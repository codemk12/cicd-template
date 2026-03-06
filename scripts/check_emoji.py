#!/usr/bin/env python3
"""Scan source files for emoji characters and fail if any are found."""
import re
import sys
from pathlib import Path

EMOJI_PATTERN = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F680-\U0001F6FF"  # transport & map
    "\U0001F1E0-\U0001F1FF"  # flags
    "\U00002702-\U000027B0"  # dingbats
    "\U0000FE00-\U0000FE0F"  # variation selectors
    "\U0001F900-\U0001F9FF"  # supplemental symbols
    "\U0001FA00-\U0001FA6F"  # chess symbols
    "\U0001FA70-\U0001FAFF"  # symbols extended-A
    "\U00002600-\U000026FF"  # misc symbols
    "\U0000200D"             # zero width joiner
    "\U00002B50-\U00002B55"  # stars
    "]"
)

SCAN_EXTENSIONS = {".py", ".tf", ".yml", ".yaml", ".txt", ".md", ".json"}
SKIP_DIRS = {".git", "venv", ".terraform", "__pycache__", "node_modules"}


def scan_file(path):
    findings = []
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return findings
    for line_no, line in enumerate(text.splitlines(), 1):
        emojis = EMOJI_PATTERN.findall(line)
        if emojis:
            findings.append((path, line_no, emojis, line.strip()))
    return findings


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    all_findings = []
    for path in sorted(root.rglob("*")):
        if any(skip in path.parts for skip in SKIP_DIRS):
            continue
        if path.is_file() and path.suffix in SCAN_EXTENSIONS:
            all_findings.extend(scan_file(path))

    if all_findings:
        print(f"FAIL: Found emojis in {len(all_findings)} location(s):\n")
        for path, line_no, emojis, line in all_findings:
            print(f"  {path}:{line_no}  {''.join(emojis)}")
            print(f"    {line}\n")
        sys.exit(1)
    else:
        print("OK: No emojis found in source files.")


if __name__ == "__main__":
    main()
