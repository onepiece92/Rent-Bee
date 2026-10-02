#!/usr/bin/env python3
"""Render a repo Markdown doc (plan.md, buglog.md) as a readable PDF.

Usage:  python3 tool/md2pdf.py <input.md> [output.pdf]
Needs:  reportlab  (pip install reportlab)

Handles the Markdown subset these docs use: #/##/### headings, pipe tables,
bullet and checkbox lists, bold, inline code, horizontal rules. Emoji and
non-WinAnsi symbols are mapped to text so ReportLab's built-in fonts never
render black boxes. The .md files remain the canonical source — PDFs are
disposable exports; regenerate after edits.
"""
import re
import sys
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (HRFlowable, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

# Symbols the built-in Helvetica/Courier fonts can't draw.
SYMBOLS = {
    "✅": "[done]", "\U0001f527": "[in progress]", "⏳": "[queued]",
    "⏸": "[deferred]", "ℹ️": "[note]", "ℹ": "[note]",
    "️": "", "→": "->", "←": "<-", "−": "-",
    "·": "·",  # middle dot is fine in WinAnsi — keep
    "\U0001f389": "", "✓": "[x]", "❌": "[failed]",
}

def clean(s: str) -> str:
    for k, v in SYMBOLS.items():
        s = s.replace(k, v)
    # ReportLab's built-in fonts cover WinAnsi (cp1252) — em dashes, curly
    # quotes and ellipses included. Anything beyond that becomes '?' rather
    # than a black box.
    return s.encode("cp1252", "replace").decode("cp1252")

def inline(s: str) -> str:
    s = (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\*(.+?)\*", r"<i>\1</i>", s)
    s = re.sub(r"`([^`]+)`", r'<font face="Courier" size="9">\1</font>', s)
    # Markdown links: keep the text, drop the target noise.
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    return clean(s)

def build(md_path: Path, pdf_path: Path) -> None:
    base = getSampleStyleSheet()
    body = ParagraphStyle("Body", parent=base["Normal"], fontSize=10,
                          leading=14, spaceAfter=4)
    bullet = ParagraphStyle("Bul", parent=body, leftIndent=14,
                            bulletIndent=4, spaceAfter=2)
    h1 = ParagraphStyle("H1", parent=base["Title"], fontSize=20,
                        leading=24, spaceAfter=10, alignment=0)
    h2 = ParagraphStyle("H2", parent=base["Heading1"], fontSize=14,
                        leading=18, spaceBefore=14, spaceAfter=6)
    h3 = ParagraphStyle("H3", parent=base["Heading2"], fontSize=11.5,
                        leading=15, spaceBefore=10, spaceAfter=4)
    cell = ParagraphStyle("Cell", parent=body, fontSize=9, leading=12,
                          spaceAfter=0)
    head = ParagraphStyle("Head", parent=cell, fontName="Helvetica-Bold")

    story, table_buf = [], []

    def flush_table():
        if not table_buf:
            return
        rows = [[Paragraph(inline(c), head if i == 0 else cell)
                 for c in r] for i, r in enumerate(table_buf)]
        ncols = max(len(r) for r in rows)
        for r in rows:
            r += [Paragraph("", cell)] * (ncols - len(r))
        first_wide = ncols >= 3  # ID/status tables read best with a wide last col
        widths = None
        if first_wide:
            widths = [18 * mm, 26 * mm, None]
            widths += [None] * (ncols - 3)
        t = Table(rows, colWidths=widths, repeatRows=1, hAlign="LEFT")
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F2F2F7")),
            ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#C7C7CC")),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 5),
            ("RIGHTPADDING", (0, 0), (-1, -1), 5),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ]))
        story.append(t)
        story.append(Spacer(1, 6))
        table_buf.clear()

    for raw in md_path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if re.match(r"^\s*\|", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                table_buf.append(cells)
            continue
        flush_table()
        if not line.strip():
            story.append(Spacer(1, 4))
        elif line.startswith("### "):
            story.append(Paragraph(inline(line[4:]), h3))
        elif line.startswith("## "):
            story.append(Paragraph(inline(line[3:]), h2))
        elif line.startswith("# "):
            story.append(Paragraph(inline(line[2:]), h1))
        elif re.fullmatch(r"-{3,}", line.strip()):
            story.append(HRFlowable(width="100%", thickness=0.6,
                                    color=colors.HexColor("#C7C7CC"),
                                    spaceBefore=8, spaceAfter=8))
        elif re.match(r"^\s*- \[[ xX]\] ", line):
            mark = "[x]" if line.strip()[3].lower() == "x" else "[ ]"
            text = re.sub(r"^\s*- \[[ xX]\] ", "", line)
            story.append(Paragraph(f"<b>{mark}</b> {inline(text)}", bullet,
                                   bulletText="•"))
        elif re.match(r"^\s*[-*] ", line):
            story.append(Paragraph(inline(re.sub(r"^\s*[-*] ", "", line)),
                                   bullet, bulletText="•"))
        else:
            story.append(Paragraph(inline(line), body))
    flush_table()

    SimpleDocTemplate(
        str(pdf_path), pagesize=A4,
        leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=16 * mm, bottomMargin=16 * mm,
        title=md_path.stem, author="Rent Bee",
    ).build(story)
    print(f"{pdf_path} written")

if __name__ == "__main__":
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".pdf")
    build(src, dst)
