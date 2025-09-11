#!/usr/bin/env python3
"""
fix_gd_inference_strict.py

Conservative, CI-friendly fixer for Godot GDScript ':=' inference warnings.

Short take:
- Only rewrites single-line declarations that look like:  var name := expr
- Acts only when the RHS is likely to infer Variant (node lookups, dynamic calls,
  resource loads, timers/tweens, OS/Input/ProjectSettings, etc.).
- Skips typed declarations by default (var x: T := ...), unless --include-typed.
- Does NOT chase multiline constructs. It is intentionally conservative.
- Preserves file line endings, trailing whitespace/comments, and UTF-8 BOM.

Workflow:
  1) Commit/stash your repo
  2) Dry-run:  python tools/fix_gd_inference_strict.py --report
  3) Apply on a subtree:  python tools/fix_gd_inference_strict.py --write path/to/dir
  4) Build/test, then broaden scope

Extras:
- Exclude directories via --exclude (repeatable)
- Git-scoped modes: --git-tracked | --staged | --changed-only (mutually exclusive)
- Extra suspicious tokens via --extra-token (repeatable)
- Optional .bak backups and per-file confirmation prompts
- --dry-run is an alias for --report
- --report returns exit code 1 if fixable lines are found (useful for CI gating)
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from typing import Iterable, List, Sequence, Tuple


# Match: optional decorators, optional 'static', then 'var ... := ...' on one line.
# Decorators allow tokens with parentheses, e.g. @export_range(0, 100)
PATTERN = re.compile(
    r"^(?P<indent>\s*)"
    r"(?P<decorators>(?:@[^ \t]+\s+)*)"     # @onready @tool @export_range(0,1)
    r"(?P<static>static\s+)?"               # optional 'static'
    r"var\s+"
    r"(?P<lhs>[^=]+?)\s*"
    r":=\s*"
    r"(?P<rhs>.+)$"
)

# Stricter detection of typed LHS (e.g., "name : Type", allowing dotted types and [] )
TYPED_LHS = re.compile(r"""\b[a-zA-Z_]\w*\s*:\s*[\w\.]+(\[\])?\s*$""")


# Keep mathy built-ins out by default; focus on dynamic sources of Variant
DEFAULT_GLOBALS: Tuple[str, ...] = tuple()
DEFAULT_SUBSTRINGS: Tuple[str, ...] = (
    ".get(", ".get_", ".call(", ".call_deferred(", ".duplicate(", ".instantiate(",
    "get_node(", ".get_node(", "get_tree(", ".get_tree(", "get_viewport(",
    "get_world_2d(", "create_timer(", ".create_timer(", "create_tween(",
    "load(", "preload(", "ResourceLoader.", "OS.", "Input.", "ProjectSettings.",
)

# --- Helpers to avoid false positives from strings/comments ------------------

# Replace quoted strings with spaces (preserves positions)
_QUOTED = re.compile(r'("([^"\\]|\\.)*"|\'([^\'\\]|\\.)*\')')

def _strip_strings(s: str) -> str:
    return _QUOTED.sub(lambda m: ' ' * (m.end() - m.start()), s)

def _strip_trailing_comment(s: str) -> str:
    """
    Remove trailing comment starting at an unquoted '#' (simple but effective).
    We assume GDScript treats '#' as line comment when not inside quotes.
    """
    out = []
    in_sq = in_dq = False
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and (in_sq or in_dq) and i + 1 < len(s):
            # Keep escaped char inside strings
            out.append(c)
            out.append(s[i + 1])
            i += 2
            continue
        if not in_sq and not in_dq and c == '#':
            break
        if c == '"' and not in_sq:
            in_dq = not in_dq
        elif c == "'" and not in_dq:
            in_sq = not in_sq
        out.append(c)
        i += 1
    return ''.join(out)

def _rhs_scan_text(rhs: str) -> str:
    # Normalize RHS for token scanning: drop strings and trailing comment.
    return _strip_strings(_strip_trailing_comment(rhs.strip()))

# -----------------------------------------------------------------------------


def rhs_is_suspicious(rhs: str, extra: Iterable[str]) -> bool:
    text = _rhs_scan_text(rhs)
    for token in DEFAULT_SUBSTRINGS:
        if token in text:
            return True
    for token in DEFAULT_GLOBALS:
        if token in text:
            return True
    for token in extra:
        if token and token in text:
            return True
    return False


def split_lines_keepends(raw: bytes) -> List[bytes]:
    # Preserve original line endings and trailing whitespace/comments
    text = raw.decode("utf-8", errors="replace")
    return [s.encode("utf-8") for s in text.splitlines(keepends=True)]


def process_line(line: bytes, include_typed: bool, extra_tokens: Iterable[str]) -> Tuple[bytes, bool]:
    # Work on the textual part without the trailing newline (already included)
    s = line.decode("utf-8", errors="replace")
    # Remove trailing newline for regex, but keep it to append back
    if s.endswith("\r\n"):
        s_body, eol = s[:-2], "\r\n"
    elif s.endswith("\n"):
        s_body, eol = s[:-1], "\n"
    else:
        s_body, eol = s, ""
    m = PATTERN.match(s_body)
    if not m:
        return line, False

    lhs = m.group("lhs").rstrip()
    rhs = m.group("rhs")

    # Skip typed declarations unless requested
    if not include_typed and TYPED_LHS.search(lhs):
        return line, False

    if not rhs_is_suspicious(rhs, extra_tokens):
        return line, False

    indent = m.group("indent")
    decorators = m.group("decorators") or ""
    static_kw = m.group("static") or ""

    new_text = f"{indent}{decorators}{static_kw}var {lhs} = {rhs}{eol}"
    return new_text.encode("utf-8"), True


def should_exclude(path: str, excludes: Sequence[str]) -> bool:
    lp = path.replace("\\", "/")
    for ex in excludes:
        if ex and ex in lp:
            return True
    return False


def git_list_files(mode: str) -> List[str]:
    # mode: tracked | staged | changed
    cmds = {
        "tracked": ["git", "ls-files"],
        "staged": ["git", "diff", "--name-only", "--cached"],
        "changed": ["git", "diff", "--name-only", "HEAD"],
    }
    cmd = cmds[mode]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, text=True)
    except Exception:
        return []
    if res.returncode != 0:
        return []
    return [ln.strip() for ln in res.stdout.splitlines() if ln.strip().endswith(".gd")]


def collect_gd_files(root: str, excludes: Sequence[str], scope: str | None) -> List[str]:
    if scope in ("tracked", "staged", "changed"):
        files = git_list_files(scope)
        if not files:
            return []
        if root != ".":
            rp = os.path.abspath(root)
            out = []
            for f in files:
                af = os.path.abspath(f)
                if af.startswith(rp):
                    out.append(f)
            files = out
        files = [f for f in files if not should_exclude(f, excludes)]
        return files

    gd_files: List[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        if should_exclude(dirpath, excludes):
            continue
        dirnames[:] = [d for d in dirnames if not should_exclude(os.path.join(dirpath, d), excludes)]
        for name in filenames:
            if name.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, name))
    gd_files.sort()
    return gd_files


def scan(
    paths: List[str],
    write: bool,
    report: bool,
    include_typed: bool,
    extra_tokens: List[str],
    backup: bool,
    confirm: bool
) -> Tuple[int, int]:
    total_hits = 0
    total_changes = 0
    for fp in paths:
        try:
            with open(fp, "rb") as f:
                raw = f.read()
        except Exception:
            continue

        if b":=" not in raw:
            continue

        has_bom = raw.startswith(b"\xef\xbb\xbf")
        body = raw[3:] if has_bom else raw

        lines = split_lines_keepends(body)
        new_lines: List[bytes] = []
        changed_lines: List[int] = []
        file_hits = 0

        for idx, line in enumerate(lines, start=1):
            new_line, hit = process_line(line, include_typed, extra_tokens)
            if hit:
                file_hits += 1
                changed_lines.append(idx)
            new_lines.append(new_line)

        if report and file_hits:
            for ln in changed_lines:
                try:
                    orig = lines[ln - 1].decode("utf-8", errors="replace").rstrip("\r\n")
                except Exception:
                    orig = "(binary decode error)"
                print(f"{fp}:{ln}: {orig}")

        if write and file_hits:
            apply = True
            if confirm:
                ans = input(f"Apply {file_hits} change(s) to {fp}? [y/N] ").strip().lower()
                apply = ans == "y"
            if apply:
                if backup:
                    try:
                        with open(fp + ".bak", "wb") as b:
                            b.write(raw)
                    except Exception:
                        pass
                try:
                    with open(fp, "wb") as out:
                        if has_bom:
                            out.write(b"\xef\xbb\xbf")
                        out.writelines(new_lines)
                    print(f"Updated {fp} ({file_hits} changes) lines: {changed_lines}")
                except Exception as exc:
                    print(f"Failed to write {fp}: {exc}")
                    continue
                total_changes += file_hits

        total_hits += file_hits

    return total_hits, total_changes


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="Conservative fixer for GDScript ':=' Variant inference (strict mode)")
    ap.add_argument("path", nargs="?", default=".", help="Root directory to scan (default: .)")
    ap.add_argument("--write", action="store_true", help="Apply changes in place")
    ap.add_argument("--report", action="store_true", help="List candidate lines (no changes)")
    ap.add_argument("--dry-run", action="store_true", help="Alias for --report")
    ap.add_argument("--include-typed", action="store_true", help="Also rewrite typed declarations (var x: T := ...)")
    ap.add_argument("--extra-token", action="append", default=[], help="Additional suspicious substring (repeatable)")
    ap.add_argument("--list-patterns", action="store_true", help="Print built-in suspicious tokens and exit")
    ap.add_argument("--exclude", action="append", default=["/.git/", "/.godot/", "/addons/", "/vendor/", "/build/"], help="Dir substrings to skip (repeatable)")
    scope = ap.add_mutually_exclusive_group()
    scope.add_argument("--git-tracked", action="store_true", help="Limit to git tracked .gd files")
    scope.add_argument("--staged", action="store_true", help="Limit to staged .gd files")
    scope.add_argument("--changed-only", action="store_true", help="Limit to changed .gd files vs HEAD")
    ap.add_argument("--backup", action="store_true", help="Write a .bak alongside modified files")
    ap.add_argument("--confirm", action="store_true", help="Prompt before modifying each file")
    args = ap.parse_args(argv)

    if args.list_patterns:
        print("DEFAULT_SUBSTRINGS:")
        for t in DEFAULT_SUBSTRINGS:
            print("  ", t)
        if DEFAULT_GLOBALS:
            print("DEFAULT_GLOBALS:")
            for t in DEFAULT_GLOBALS:
                print("  ", t)
        return 0

    report = args.report or args.dry_run

    # Determine scope
    scope_mode: str | None = None
    if args.git_tracked:
        scope_mode = "tracked"
    elif args.staged:
        scope_mode = "staged"
    elif args.changed_only:
        scope_mode = "changed"

    if scope_mode is not None:
        files = collect_gd_files(args.path, args.exclude, scope_mode)
    else:
        if not os.path.isdir(args.path):
            print(f"Not a directory: {args.path}", file=sys.stderr)
            return 2
        files = collect_gd_files(args.path, args.exclude, None)

    hits, changes = scan(
        files,
        write=args.write,
        report=report,
        include_typed=args.include_typed,
        extra_tokens=args.extra_token,
        backup=args.backup,
        confirm=args.confirm
    )

    if report:
        # Non-zero exit when hits found to help CI gate
        return 1 if hits > 0 else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
