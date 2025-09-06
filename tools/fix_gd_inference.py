#!/usr/bin/env python3
"""
fix_gd_inference.py

Purpose:
- Find GDScript variable declarations that use type inference with ":=" and replace it with
  an explicit dynamic declaration "=". This avoids Godot's warning:
  "The variable type is being inferred from a Variant value, so it will be typed as Variant."
  which can be treated as an error when warnings-as-errors are enabled.

Caveat:
- This script favors reliability over preserving static typing. Replacing ":=" with "="
  suppresses the warning by declaring the variable dynamically. If you prefer to add
  explicit type annotations instead, you can run in --report mode to see candidates and
  update them manually.

Usage:
  - Dry run (show matches):
      python tools/fix_gd_inference.py --report
  - Apply changes in place:
      python tools/fix_gd_inference.py --write
  - Limit to a subfolder:
      python tools/fix_gd_inference.py --write path/to/dir

Notes:
  - Creates no backup files; use version control to review diffs.
  - Skips non-.gd files.
  - Handles optional decorators like @onready before var.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple


# Matches lines like:
#   var x := expr
#   var x: float := expr
#   @onready var x := expr
#   @tool @onready var x: PackedScene := preload(...)
# and replaces only the ":=" with "=" while preserving all spacing around.
PATTERN = re.compile(
    r"^(?P<indent>\s*)"
    r"(?P<decorators>(?:@[-\w\.]+\s+)*)"
    r"var\s+"
    r"(?P<lhs>[^=]+?)\s*"
    r":=\s*"
    r"(?P<rhs>.+)$"
)


def process_line(line: str) -> Tuple[str, bool]:
    m = PATTERN.match(line)
    if not m:
        return line, False
    indent = m.group("indent")
    decorators = m.group("decorators") or ""
    lhs = m.group("lhs").rstrip()
    rhs = m.group("rhs").rstrip()
    new_line = f"{indent}{decorators}var {lhs} = {rhs}\n"
    return new_line, True


def process_file(path: str) -> Tuple[int, int, List[int]]:
    changed = 0
    total = 0
    changed_lines: List[int] = []
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    out_lines: List[str] = []
    for i, line in enumerate(lines):
        total += 1
        # Leave commented lines untouched
        stripped = line.lstrip()
        if stripped.startswith("#"):
            out_lines.append(line)
            continue
        new_line, hit = process_line(line.rstrip("\n"))
        if hit:
            changed += 1
            changed_lines.append(i + 1)
            out_lines.append(new_line)
        else:
            out_lines.append(line)
    if changed:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.writelines(out_lines)
    return changed, total, changed_lines


def scan(root: str, write: bool, report: bool) -> int:
    gd_files: List[str] = []
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".gd"):
                gd_files.append(os.path.join(dirpath, name))
    gd_files.sort()
    total_changed = 0
    total_hits = 0
    for fp in gd_files:
        with open(fp, "r", encoding="utf-8") as f:
            text = f.read()
        # Quick filter to skip files without ":=" tokens
        if ":=" not in text:
            continue
        # If reporting only, just list matching lines
        if report and not write:
            with open(fp, "r", encoding="utf-8") as f:
                for idx, line in enumerate(f, start=1):
                    if PATTERN.match(line):
                        print(f"{fp}:{idx}: {line.rstrip()}")
                        total_hits += 1
            continue
        # Apply changes
        changed, _total, changed_lines = process_file(fp)
        if changed:
            total_changed += changed
            print(f"Updated {fp} ({changed} changes) lines: {changed_lines}")
    if report and not write:
        print(f"Found {total_hits} candidate lines.")
    return 0


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="Fix GDScript inference warnings by replacing := with = in var declarations.")
    ap.add_argument("path", nargs="?", default=".", help="Root path to scan (default: current directory)")
    ap.add_argument("--write", action="store_true", help="Apply changes in place")
    ap.add_argument("--report", action="store_true", help="List candidate lines without modifying files")
    args = ap.parse_args(argv)
    if not os.path.isdir(args.path):
        print(f"Not a directory: {args.path}", file=sys.stderr)
        return 2
    return scan(args.path, write=args.write, report=args.report)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

