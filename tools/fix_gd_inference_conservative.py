#!/usr/bin/env python3
"""
fix_gd_inference_conservative.py

Purpose (stricter mode):
- Only rewrite GDScript var declarations that are most likely to infer Variant
  at declaration time, causing warnings-as-errors in strict projects.

Behavior:
- Scans for lines like:  var name := expr   (optionally with decorators)
- Skips lines that already have an explicit type annotation (e.g., var x: float := ...),
  unless --include-typed is specified.
- Applies a conservative heuristic: only rewrites when the RHS contains suspicious
  calls/globals that are commonly Variant-typed (e.g., .get(, .call(, get_node(, load(),
  max(), min(), clamp(), etc.). You can customize patterns via CLI.
- Rewrites by replacing ':=' with '=' to avoid the Variant inference warning without
  attempting to guess concrete types.

Usage:
  - Dry run (report):
      python tools/fix_gd_inference_conservative.py --report
  - Apply fixes:
      python tools/fix_gd_inference_conservative.py --write
  - Limit to a folder:
      python tools/fix_gd_inference_conservative.py --write path/to/dir
  - Show current patterns:
      python tools/fix_gd_inference_conservative.py --list-patterns

Notes:
  - Uses UTF-8 read/write. Review changes in version control.
  - For a broad sweep regardless of RHS, use tools/fix_gd_inference.py instead.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Iterable, List, Tuple


# Regex for matching var declarations using := (with optional decorators)
PATTERN = re.compile(
    r"^(?P<indent>\s*)"
    r"(?P<decorators>(?:@[-\w\.]+\s+)*)"
    r"var\s+"
    r"(?P<lhs>[^=]+?)\s*"
    r":=\s*"
    r"(?P<rhs>.+)$"
)


# Default heuristic patterns
DEFAULT_GLOBALS: Tuple[str, ...] = (
    "max(", "min(", "clamp(", "lerp(", "move_toward(", "snapped(",
    "pow(", "abs(", "ceil(", "floor(", "round(", "randf", "randi",
    "deg_to_rad(", "rad_to_deg("
)
DEFAULT_SUBSTRINGS: Tuple[str, ...] = (
    ".get(", ".get_", ".call(", ".call_deferred(", ".duplicate(", ".instantiate(",
    "get_node(", ".get_node(", "get_tree(", ".get_tree(", "get_viewport(",
    "get_world_2d(", "create_timer(", ".create_timer(", "create_tween(",
    "load(", "ResourceLoader.", "OS.", "Input.", "ProjectSettings."
)


def rhs_is_suspicious(rhs: str, extra: Iterable[str]) -> bool:
    text = rhs.strip()
    # Quick accept: any of our default substrings/globals
    hay = text
    for token in DEFAULT_GLOBALS:
        if token in hay:
            return True
    for token in DEFAULT_SUBSTRINGS:
        if token in hay:
            return True
    for token in extra:
        if token and token in hay:
            return True
    return False


def process_line(line: str, include_typed: bool, extra_tokens: Iterable[str]) -> Tuple[str, bool]:
    m = PATTERN.match(line)
    if not m:
        return line, False
    lhs = m.group("lhs").rstrip()
    rhs = m.group("rhs").rstrip()
    # Skip typed declarations unless explicitly requested
    if not include_typed and ":" in lhs:
        return line, False
    if not rhs_is_suspicious(rhs, extra_tokens):
        return line, False
    indent = m.group("indent")
    decorators = m.group("decorators") or ""
    new_line = f"{indent}{decorators}var {lhs} = {rhs}\n"
    return new_line, True


def process_file(path: str, include_typed: bool, extra_tokens: Iterable[str]) -> Tuple[int, List[int]]:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    changed = 0
    changed_lines: List[int] = []
    out: List[str] = []
    for idx, line in enumerate(lines, start=1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            out.append(line)
            continue
        new_line, hit = process_line(line.rstrip("\n"), include_typed, extra_tokens)
        if hit:
            changed += 1
            changed_lines.append(idx)
            out.append(new_line)
        else:
            out.append(line)
    if changed:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.writelines(out)
    return changed, changed_lines


def scan(root: str, write: bool, report: bool, include_typed: bool, extra_tokens: List[str]) -> int:
    gd_files: List[str] = []
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, name))
    gd_files.sort()
    total_hits = 0
    total_changed = 0
    for fp in gd_files:
        # Quick filter to skip files without ':='
        try:
            with open(fp, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception:
            continue
        if ":=" not in content:
            continue
        # Per-line scan to count/report candidates
        if report and not write:
            with open(fp, "r", encoding="utf-8") as f:
                for idx, line in enumerate(f, start=1):
                    m = PATTERN.match(line)
                    if not m:
                        continue
                    lhs = m.group("lhs").rstrip()
                    rhs = m.group("rhs").rstrip()
                    if (include_typed or ":" not in lhs) and rhs_is_suspicious(rhs, extra_tokens):
                        print(f"{fp}:{idx}: {line.rstrip()}")
                        total_hits += 1
            continue
        # Apply changes
        changed, lines = process_file(fp, include_typed, extra_tokens)
        if changed:
            total_changed += changed
            print(f"Updated {fp} ({changed} changes) lines: {lines}")
    if report and not write:
        print(f"Found {total_hits} candidate lines.")
    return 0


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="Conservatively fix GDScript ':=' inference for likely-Variant RHS.")
    ap.add_argument("path", nargs="?", default=".", help="Root directory to scan (default: .)")
    ap.add_argument("--write", action="store_true", help="Apply changes in place")
    ap.add_argument("--report", action="store_true", help="List candidate lines (no changes)")
    ap.add_argument("--include-typed", action="store_true", help="Also rewrite typed declarations (var x: T := ...)")
    ap.add_argument("--extra-token", action="append", default=[], help="Additional substring to treat as suspicious (can be repeated)")
    ap.add_argument("--list-patterns", action="store_true", help="Print built-in suspicious tokens and exit")
    args = ap.parse_args(argv)

    if args.list_patterns:
        print("Globals:", ", ".join(DEFAULT_GLOBALS))
        print("Substrings:", ", ".join(DEFAULT_SUBSTRINGS))
        return 0
    root = args.path
    if not os.path.isdir(root):
        print(f"Not a directory: {root}", file=sys.stderr)
        return 2
    return scan(root, write=args.write, report=args.report, include_typed=args.include_typed, extra_tokens=args.extra_token)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

