#!/usr/bin/env python3
"""Static checks over the Swift sources that do not need a Swift toolchain.

    python3 scripts/swift_static_checks.py

These are not a substitute for compiling — see docs/REVIVAL_AUDIT.md, which is
blunt about the fact that this project has never been compiled. They are the
checks that are cheap enough to run on every push and that catch the two things
that have actually gone wrong here: a shell creeping back into the process
layer, and an unbalanced brace in a file nobody built.

Everything works on a *stripped* copy of each file, with comments and string
literals removed. The first version of the shell check was a plain
`grep -rn "bin/zsh" SentryBar/`, which failed the build on

    /// `/bin/zsh -c "<string>"` for every reading. Three problems came with that:

— the doc comment in ProcessRunner.swift explaining what it replaced. A check
that cannot tell code from prose gets switched off the first time it cries
wolf, so this one reads the language properly.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "SentryBar"
TEST_DIR = ROOT / "SentryBarTests"

#: The single file allowed to start another process.
PROCESS_OWNER = "SentryBar/Utilities/ProcessRunner.swift"


def strip_swift(text: str, keep_strings: bool = False) -> str:
    """Return *text* with comments and string literals replaced by spaces.

    Handles line comments, nested block comments, ordinary strings, multiline
    strings, raw strings with any number of leading hashes, and escapes.
    Interpolation is treated as string content: it can contain code, but
    nothing this file checks for is legal inside one.

    With `keep_strings=True` only comments are removed. That is the right view
    for the shell check: `"/bin/zsh"` in a string literal is exactly the thing
    being banned, while `/bin/zsh` in a doc comment is prose. Structural checks
    want the opposite view, so they pass `keep_strings=False`.
    """
    out: list[str] = []
    i, n = 0, len(text)

    while i < n:
        char = text[i]

        # Line comment
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue

        # Block comment, which nests in Swift
        if char == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth:
                if text.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            continue

        # Raw string: #"..."# / ##"..."## and their multiline forms
        if char == "#":
            hashes = 0
            j = i
            while j < n and text[j] == "#":
                hashes += 1
                j += 1
            if j < n and text[j] == '"':
                closing = '"' + "#" * hashes
                triple = text.startswith('"""', j)
                if triple:
                    closing = '"""' + "#" * hashes
                    j += 3
                else:
                    j += 1
                end = j
                while end < n and not text.startswith(closing, end):
                    end += 1
                end = min(end + len(closing), n)
                if keep_strings:
                    out.append(text[i:end])
                else:
                    out.append(_blank(text[i:end]))
                i = end
                continue

        # Multiline string
        if text.startswith('"""', i):
            end = i + 3
            while end < n and not text.startswith('"""', end):
                end += 2 if text[end] == "\\" and end + 1 < n else 1
            end = min(end + 3, n)
            out.append(text[i:end] if keep_strings else _blank(text[i:end]))
            i = end
            continue

        # Ordinary string
        if char == '"':
            end = i + 1
            while end < n and text[end] != '"':
                end += 2 if text[end] == "\\" and end + 1 < n else 1
            end = min(end + 1, n)
            out.append(text[i:end] if keep_strings else _blank(text[i:end]))
            i = end
            continue

        out.append(char)
        i += 1

    return "".join(out)


def _blank(chunk: str) -> str:
    """Same length, same line breaks, no content — so offsets stay honest."""
    return "".join("\n" if ch == "\n" else " " for ch in chunk)


def swift_files() -> list[Path]:
    found: list[Path] = []
    for directory in (SOURCE_DIR, TEST_DIR):
        if directory.exists():
            found.extend(sorted(directory.rglob("*.swift")))
    return found


def check_balanced(path: Path, stripped: str, failures: list[str]) -> None:
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line = 1
    for char in stripped:
        if char == "\n":
            line += 1
        elif char in "([{":
            stack.append((char, line))
        elif char in pairs:
            if not stack or stack[-1][0] != pairs[char]:
                failures.append(f"{path.relative_to(ROOT)}:{line}: unexpected '{char}'")
                return
            stack.pop()
    if stack:
        char, opened = stack[-1]
        failures.append(f"{path.relative_to(ROOT)}:{opened}: '{char}' is never closed")


#: A leading dot excludes SwiftUI's `.system(size:)`, `.systemGray` and
#: friends, which are member lookups and not the C library call.
SHELL_PATTERNS = [
    (re.compile(r"/bin/(?:sh|zsh|bash|csh|tcsh|ksh)"), "a shell binary"),
    (re.compile(r"\bNSTask\b"), "NSTask"),
    (re.compile(r"(?<![.\w])system\s*\("), "system()"),
    (re.compile(r"(?<![.\w])popen\s*\("), "popen()"),
]
PROCESS_PATTERN = re.compile(r"\bProcess\s*\(")


def check_no_shell(path: Path, code: str, code_and_strings: str, failures: list[str]) -> None:
    relative = str(path.relative_to(ROOT))

    # Shell paths are searched with strings intact: a literal "/bin/zsh" handed
    # to anything is the defect, and the only reason the old grep-based check
    # was wrong is that it also read comments.
    for index, line in enumerate(code_and_strings.splitlines(), start=1):
        for pattern, label in SHELL_PATTERNS:
            if pattern.search(line):
                failures.append(
                    f"{relative}:{index}: {label} — everything must go through ProcessRunner"
                )

    if relative == PROCESS_OWNER:
        return
    for index, line in enumerate(code.splitlines(), start=1):
        if PROCESS_PATTERN.search(line):
            failures.append(f"{relative}:{index}: Process() outside {PROCESS_OWNER}")


def main() -> int:
    files = swift_files()
    if not files:
        print("no Swift files found — is this the right directory?", file=sys.stderr)
        return 1

    failures: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        code = strip_swift(text)
        code_and_strings = strip_swift(text, keep_strings=True)
        check_balanced(path, code, failures)
        check_no_shell(path, code, code_and_strings, failures)

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        print(f"\n{len(failures)} problem(s) in {len(files)} Swift files", file=sys.stderr)
        return 1

    print(f"{len(files)} Swift files: brackets balanced, no shell outside {PROCESS_OWNER}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
