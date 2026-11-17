"""TXT dan MD ke halaman materi, dengan aturan tempel teks
(text_material.split_pasted_text).

Markdown dirapikan dulu supaya cocok dengan aturan itu:
- `#` tetap judul halaman, `##` sampai `######` menjadi subjudul,
- butir `*` dan `+` menjadi `-`,
- **tebal**, *miring*, `kode`, dan tautan [teks](alamat) menjadi teks biasa,
- tabel Markdown (`| a | b |` dengan baris `|---|`) menjadi [[tabel]],
- gambar ![alt](alamat) dilewati, karena alamatnya tidak bisa diambil;
  teks alternatifnya ditulis sebagai paragraf "Gambar tidak disertakan: ...",
- pagar kode ``` dibuang, isinya tetap.
"""

import re
from pathlib import Path

from converters import ConversionError, Converted, table_rows_to_marker
from converters.sheet_material import read_text_file
from text_material import split_pasted_text

SUBHEADING_RE = re.compile(r"^#{2,6}\s+(.*?)\s*#*\s*$")
PAGE_HEADING_RE = re.compile(r"^#\s+(.*?)\s*#*\s*$")
STAR_ITEM_RE = re.compile(r"^(\s*)[*+]\s+")
IMAGE_RE = re.compile(r"!\[([^\]]*)\]\([^)]*\)")
LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")
BOLD_RE = re.compile(r"(\*\*|__)(.+?)\1")
ITALIC_RE = re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])")
CODE_RE = re.compile(r"`([^`]+)`")
TABLE_SEPARATOR_RE = re.compile(r"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$")


def _inline(text: str) -> str:
    text = IMAGE_RE.sub(
        lambda m: f"Gambar tidak disertakan: {m.group(1)}." if m.group(1) else "", text
    )
    text = LINK_RE.sub(r"\1", text)
    text = BOLD_RE.sub(r"\2", text)
    text = ITALIC_RE.sub(r"\1", text)
    return CODE_RE.sub(r"\1", text)


def _cells(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [_inline(cell.strip()) for cell in line.split("|")]


def markdown_to_plain(text: str) -> str:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out = []
    i = 0
    table_count = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            i += 1
            continue
        # Tabel: baris berpipa diikuti baris pemisah ---.
        if (
            stripped.startswith("|")
            and i + 1 < len(lines)
            and TABLE_SEPARATOR_RE.match(lines[i + 1].strip())
        ):
            rows = [_cells(stripped)]
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(_cells(lines[i]))
                i += 1
            table_count += 1
            marker = table_rows_to_marker(rows, f"Tabel {table_count}")
            if marker:
                # Baris kosong di sekelilingnya: penanda tidak digabung dengan
                # paragraf lain oleh aturan tempel teks.
                out.extend(["", marker, ""])
            continue
        match = PAGE_HEADING_RE.match(stripped)
        if match:
            out.append("# " + _inline(match.group(1)))
        elif (match := SUBHEADING_RE.match(stripped)) is not None:
            out.append("## " + _inline(match.group(1)))
        elif STAR_ITEM_RE.match(line) and stripped not in ("***", "* * *"):
            out.append("- " + _inline(STAR_ITEM_RE.sub("", line, count=1)))
        elif re.fullmatch(r"[-*_]{3,}", stripped):
            out.append("")  # garis pemisah
        else:
            out.append(_inline(line))
        i += 1
    return "\n".join(out)


def convert_text_file(path: Path, title: str, markdown: bool) -> Converted:
    text = read_text_file(path)
    if markdown:
        text = markdown_to_plain(text)
    sections = split_pasted_text(text, title)
    if not sections or not any(s.content.strip() for s in sections):
        raise ConversionError("File teks kosong.")
    return Converted(sections=sections)
