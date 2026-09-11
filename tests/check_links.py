#!/usr/bin/env python3
"""Check that every relative Markdown link in the harness docs resolves.

Called by tests/test.sh. Kept as a separate file rather than inline so the test
suite does not have to nest a heredoc inside a heredoc.

Usage: check_links.py <repo-root>
Prints one "<file> -> <target>" line per broken link, nothing on success.
"""

import os
import re
import sys

DOCS = (
    "README.md",
    "README.pt-BR.md",
    "docs/GETTING_STARTED.md",
    "docs/WINDOWS.md",
)

# Link targets inside fenced code blocks are examples, not references: the
# install commands print paths that do not exist until a user runs them.
FENCE = re.compile(r"^(```|~~~)", re.M)


def strip_code_blocks(text: str) -> str:
    out = []
    inside = False
    for line in text.splitlines():
        if FENCE.match(line.strip()):
            inside = not inside
            continue
        if not inside:
            out.append(line)
    return "\n".join(out)


def main() -> int:
    repo = sys.argv[1] if len(sys.argv) > 1 else "."
    broken = []

    for name in DOCS:
        path = os.path.join(repo, name)
        if not os.path.exists(path):
            continue
        base = os.path.dirname(path)
        text = strip_code_blocks(open(path, encoding="utf-8").read())
        for target in re.findall(r"\]\(([^)#\s]+)", text):
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = os.path.normpath(os.path.join(base, target))
            if not os.path.exists(resolved):
                broken.append(f"{name} -> {target}")

    if broken:
        print("\n".join(broken))
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
