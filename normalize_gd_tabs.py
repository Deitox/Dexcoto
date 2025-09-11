# normalize_gd_tabs.py
import pathlib, re, sys

TAB_WIDTH = 4
root = pathlib.Path(".")

for p in root.rglob("*.gd"):
    text = p.read_text(encoding="utf-8")
    lines = text.splitlines(True)

    def convert(line: str) -> str:
        m = re.match(r'^( +)', line)
        if not m:
            return line
        spaces = len(m.group(1))
        tabs = spaces // TAB_WIDTH
        remainder = spaces % TAB_WIDTH
        return ("\t" * tabs) + (" " * remainder) + line[spaces:]

    new = "".join(convert(ln) for ln in lines)
    if new != text:
        p.write_text(new, encoding="utf-8")
        print(f"fixed {p}")

print("Done.")
