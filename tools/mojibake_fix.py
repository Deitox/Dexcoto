import pathlib
import argparse
import fnmatch

# Map of mojibake -> proper character
REPLACEMENTS = {
    "â€“": "–",   # en dash
    "â€”": "—",   # em dash
    "â€˜": "‘",   # left single quote
    "â€™": "’",   # right single quote
    "â€œ": "“",   # left double quote
    "â€": "”",   # right double quote
    "â€¦": "…",   # ellipsis
    "Â ": " ",   # stray non-breaking space
}

DEFAULT_EXCLUDED_DIRS = {".git", ".hg", ".svn", ".venv", "venv", "node_modules", "dist", "build", "__pycache__"}

def is_text_file(path: pathlib.Path) -> bool:
    try:
        with open(path, "rb") as f:
            chunk = f.read(2048)
        # If it decodes as UTF-8, we treat it as text.
        chunk.decode("utf-8")
        return True
    except Exception:
        return False

def should_skip(path: pathlib.Path, script_path: pathlib.Path, repo_root: pathlib.Path,
                extra_excludes: list[str], exclude_globs: list[str]) -> bool:
    # Always skip the script itself
    if path.resolve() == script_path:
        return True

    # Skip default heavy/metadata directories
    parts = set(p.name for p in path.parents) | {path.name}
    if any(d in parts for d in DEFAULT_EXCLUDED_DIRS):
        return True

    # Skip explicit paths
    for ex in extra_excludes:
        ex_path = (repo_root / ex).resolve() if not pathlib.Path(ex).is_absolute() else pathlib.Path(ex).resolve()
        try:
            if path.resolve().is_relative_to(ex_path):  # py3.9+: replace with try/except if older
                return True
        except Exception:
            # Fallback for Python <3.9: manual check
            try:
                if str(path.resolve()).startswith(str(ex_path) + str(pathlib.os.sep)):
                    return True
            except Exception:
                pass

    # Skip glob patterns
    rel = str(path.relative_to(repo_root))
    for pat in exclude_globs:
        if fnmatch.fnmatch(rel, pat):
            return True

    return False

def repair_file(path: pathlib.Path, dry_run: bool) -> bool:
    """
    Returns True if a change (or would-change in dry-run) occurred.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        new_text = text
        for bad, good in REPLACEMENTS.items():
            new_text = new_text.replace(bad, good)

        if new_text != text:
            if dry_run:
                print(f"[DRY RUN] Would fix: {path}")
            else:
                path.write_text(new_text, encoding="utf-8")
                print(f"Fixed: {path}")
            return True
    except Exception as e:
        print(f"Skipped {path} ({e})")
    return False

def main():
    parser = argparse.ArgumentParser(description="Repair mojibake artifacts in repo text files.")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without writing files")
    parser.add_argument("--exclude", action="append", default=[],
                        help="Path (file or directory) to exclude (relative to repo root or absolute). Can be used multiple times.")
    parser.add_argument("--exclude-glob", action="append", default=[],
                        help="Glob (relative to repo root) to exclude, e.g. 'assets/**' or '**/*.min.js'. Can be used multiple times.")
    args = parser.parse_args()

    script_path = pathlib.Path(__file__).resolve()
    repo_root = script_path.parent.parent.resolve()  # parent of /tools

    scanned = 0
    text_candidates = 0
    changed = 0

    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        scanned += 1

        if should_skip(p, script_path, repo_root, args.exclude, args.exclude_glob):
            continue

        if not is_text_file(p):
            continue

        text_candidates += 1
        if repair_file(p, dry_run=args.dry_run):
            changed += 1

    print("\n--- Summary ---")
    print(f"Scanned files: {scanned}")
    print(f"Text-like files: {text_candidates}")
    print(f"{'Would fix' if args.dry_run else 'Fixed'}: {changed}")

if __name__ == "__main__":
    main()
