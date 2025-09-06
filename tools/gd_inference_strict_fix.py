#!/usr/bin/env python3
"""
fix_gd_inference_strict.py

Conservative, CI-friendly fixer for Godot GDScript ':=' inference warnings.

Key points:
- Rewrites only single-line 'var name := expr' (no multiline).
- Catches Godot 3–style prefixes (onready/export/remote/etc.) and Godot 4 decorators (@...).
- Defaults to explicit Variant annotation:  var name: Variant = expr
  (prevents "cannot infer" and "typed as Variant" in strict mode).
- Skips already-typed LHS unless --include-typed.
- Preserves UTF-8 BOM, original line endings, whitespace, and comments.
- Ignores tokens inside strings or after inline comments.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from typing import Iterable, List, Sequence, Tuple

# --------------------------- Patterns & Heuristics ---------------------------

# Optional decorators (@onready etc.), then any number of legacy prefixes
# (static|onready|export(...)|remote|remotesync|puppet|puppetmaster|master|sync)
# in ANY order, then 'var ... := ...' on one line.
PREFIX = r"(?:static|onready|export(?:\([^)]*\))?|remote|remotesync|puppet|puppetmaster|master|sync)"
PATTERN = re.compile(
    r"^(?P<indent>\s*)"
    r"(?P<decorators>(?:@[^ \t]+\s+)*)"     # Godot 4 style decorators
    r"(?P<prefixes>(?:" + PREFIX + r"\s+)*)"  # Godot 3 style modifiers (or static) in any order
    r"var\s+"
    r"(?P<lhs>[^=]+?)\s*"
    r":=\s*"
    r"(?P<rhs>.+)$"
)

# LHS already typed? (e.g., "foo : int")
TYPED_LHS = re.compile(r"""\b[a-zA-Z_]\w*\s*:\s*[\w\.]+(\[\])?\s*$""")

# Variant-y sources that commonly break inference
DEFAULT_SUBSTRINGS: Tuple[str, ...] = (
    ".get(", ".get_", ".call(", ".call_deferred(", ".duplicate(", ".instantiate(",
    "get_node(", ".get_node(", "get_node_or_null(", "get_parent(",
    "get_tree(", ".get_tree(", "get_viewport(", "get_world_2d(",
    "create_timer(", ".create_timer(", "create_tween(", "yield(",
    "load(", "preload(", "ResourceLoader.", "OS.", "Input.", "ProjectSettings.",
)
DEFAULT_GLOBALS: Tuple[str, ...] = tuple()

# RHS that have *no* static type by themselves and trigger "cannot infer" in strict mode
EMPTY_RHS_RE = re.compile(
    r"""^\s*(?:null|\[\s*\]|\{\s*\}|Array\s*\(\s*\)|Dictionary\s*\(\s*\))\s*$"""
)

# String/Comment handling
_QUOTED = re.compile(r'("([^"\\]|\\.)*"|\'([^\'\\]|\\.)*\')')

def _strip_strings(s: str) -> str:
    return _QUOTED.sub(lambda m: ' ' * (m.end() - m.start()), s)

def _strip_trailing_comment(s: str) -> str:
    out = []
    in_sq = in_dq = False
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and (in_sq or in_dq) and i + 1 < len(s):
            out.append(c); out.append(s[i + 1]); i += 2; continue
        if not in_sq and not in_dq and c == '#':
            break
        if c == '"' and not in_sq:
            in_dq = not in_dq
        elif c == "'" and not in_dq:
            in_sq = not in_sq
        out.append(c); i += 1
    return ''.join(out)

def _rhs_scan_text(rhs: str) -> str:
    return _strip_strings(_strip_trailing_comment(rhs.strip()))

def rhs_is_suspicious(rhs: str, extra: Iterable[str]) -> bool:
    # First: obvious "no set type" RHS
    if EMPTY_RHS_RE.match(rhs.strip()):
        return True
    # Then: dynamic sources
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

# --------------------------- IO helpers (safe) -------------------------------

def split_lines_keepends(raw: bytes) -> List[bytes]:
    text = raw.decode("utf-8", errors="replace")
    return [s.encode("utf-8") for s in text.splitlines(keepends=True)]

def should_exclude(path: str, excludes: Sequence[str]) -> bool:
    lp = path.replace("\\", "/")
    for ex in excludes:
        if ex and ex in lp:
            return True
    return False

def git_list_files(mode: str) -> List[str]:
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
            files = [f for f in files if os.path.abspath(f).startswith(rp)]
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

# --------------------------- Core processing ---------------------------------

def process_line(
    line: bytes,
    include_typed: bool,
    extra_tokens: Iterable[str],
    mode: str  # "variant" (default) or "equals"
) -> Tuple[bytes, bool]:
    s = line.decode("utf-8", errors="replace")
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

    # Skip already-typed LHS unless requested
    if not include_typed and TYPED_LHS.search(lhs):
        return line, False

    if not rhs_is_suspicious(rhs, extra_tokens):
        return line, False

    indent = m.group("indent")
    decorators = m.group("decorators") or ""
    prefixes = m.group("prefixes") or ""  # keep original order/spacing

    if mode == "equals":
        new_text = f"{indent}{decorators}{prefixes}var {lhs} = {rhs}{eol}"
    else:
        new_text = f"{indent}{decorators}{prefixes}var {lhs}: Variant = {rhs}{eol}"  # strict-safe

    return new_text.encode("utf-8"), True

def scan(
    paths: List[str],
    write: bool,
    report: bool,
    include_typed: bool,
    extra_tokens: List[str],
    backup: bool,
    confirm: bool,
    mode: str
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
            new_line, hit = process_line(line, include_typed, extra_tokens, mode)
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

# --------------------------- CLI --------------------------------------------

def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Conservative fixer for GDScript ':=' Variant inference (strict mode)")
    ap.add_argument("path", nargs="?", default=".", help="Root directory to scan (default: .)")
    ap.add_argument("--write", action="store_true", help="Apply changes in place")
    ap.add_argument("--report", action="store_true", help="List candidate lines (no changes)")
    ap.add_argument("--dry-run", action="store_true", help="Alias for --report")
    ap.add_argument("--include-typed", action="store_true", help="Also rewrite typed declarations (var x: T := ...)")
    ap.add_argument("--extra-token", action="append", default=[], help="Additional suspicious substring (repeatable)")
    ap.add_argument("--list-patterns", action="store_true", help="Print built-in suspicious tokens and exit")
    ap.add_argument("--exclude", action="append",
                    default=["/.git/", "/.godot/", "/addons/", "/vendor/", "/build/"],
                    help="Dir substrings to skip (repeatable)")
    scope = ap.add_mutually_exclusive_group()
    scope.add_argument("--git-tracked", action="store_true", help="Limit to git tracked .gd files")
    scope.add_argument("--staged", action="store_true", help="Limit to staged .gd files")
    scope.add_argument("--changed-only", action="store_true", help="Limit to changed .gd files vs HEAD")
    ap.add_argument("--backup", action="store_true", help="Write a .bak alongside modified files")
    ap.add_argument("--confirm", action="store_true", help="Prompt before modifying each file")
    ap.add_argument("--mode", choices=["variant", "equals"], default="variant",
                    help="Rewrite style: 'variant' -> ': Variant =' (default, strict-safe) or 'equals' -> '=' (legacy).")
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

    hits, _ = scan(
        files,
        write=args.write,
        report=report,
        include_typed=args.include_typed,
        extra_tokens=args.extra_token,
        backup=args.backup,
        confirm=args.confirm,
        mode=args.mode
    )

    if report:
        return 1 if hits > 0 else 0
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
