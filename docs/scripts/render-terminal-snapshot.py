#!/usr/bin/env python3
"""Render a real terminal output (text file) as a terminal-styled SVG.

Documentation helper only — takes captured command output and produces a
static SVG for docs/images/. No external dependencies, stdlib only.
The input must be *real* command output; this tool does not invent content.

Usage:
    python3 render-terminal-snapshot.py <input.txt> <output.svg> ["Window title"]

Simple coloring rules:
  - lines starting with "$ "          -> prompt (green $, bold command)
  - lines with PASSED / [ OK ] / ✔    -> green
  - lines with FAILED / ERROR / ✘     -> red
  - everything else                   -> light gray
"""

import html
import sys

FONT_SIZE = 14
CHAR_W = 8.4       # approx monospace advance at 14px
LINE_H = 21
PAD_X = 18
PAD_TOP = 52       # room for the title bar
PAD_BOTTOM = 18

BG = "#0d1117"
BAR = "#161b22"
FG = "#c9d1d9"
GREEN = "#3fb950"
RED = "#f85149"
CYAN = "#58a6ff"
DIM = "#8b949e"


def line_color(line: str) -> str:
    if any(t in line for t in ("FAILED", "ERROR", "✘")):
        return RED
    if any(t in line for t in ("PASSED", "[ OK ]", "passed", "✔", "OK:", "Synced", "valid", "syntax OK", "renders cleanly", "0 chart(s) failed")):
        return GREEN
    if line.startswith(("====", "----", "┌─")) or "[INFO]" in line:
        return DIM
    return FG


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "terminal"

    lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
    width = int(max(80, max(len(l) for l in lines)) * CHAR_W) + 2 * PAD_X
    height = PAD_TOP + len(lines) * LINE_H + PAD_BOTTOM

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" '
        f'font-size="{FONT_SIZE}px">',
        f'<rect width="{width}" height="{height}" rx="10" fill="{BG}"/>',
        f'<rect width="{width}" height="36" rx="10" fill="{BAR}"/>',
        f'<rect y="26" width="{width}" height="10" fill="{BAR}"/>',
        '<circle cx="22" cy="18" r="6" fill="#ff5f56"/>',
        '<circle cx="44" cy="18" r="6" fill="#ffbd2e"/>',
        '<circle cx="66" cy="18" r="6" fill="#27c93f"/>',
        f'<text x="{width / 2:.0f}" y="23" text-anchor="middle" fill="{DIM}">{html.escape(title)}</text>',
    ]

    y = PAD_TOP + FONT_SIZE
    for line in lines:
        esc = html.escape(line)
        if line.startswith("$ "):
            out.append(
                f'<text x="{PAD_X}" y="{y}" xml:space="preserve">'
                f'<tspan fill="{GREEN}">$ </tspan>'
                f'<tspan fill="{CYAN}" font-weight="bold">{html.escape(line[2:])}</tspan></text>'
            )
        else:
            out.append(
                f'<text x="{PAD_X}" y="{y}" xml:space="preserve" fill="{line_color(line)}">{esc}</text>'
            )
        y += LINE_H

    out.append("</svg>")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {dst} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
