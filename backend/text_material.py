"""Memecah teks tempelan guru (copy-paste dari Word, web, dll.) menjadi
halaman materi, dengan format `content` yang sama seperti hasil PDF
(lihat pdf_sections.py).

Aturan judul bagian (satu judul bagian = satu halaman):

1. Kalau ada baris berawalan "# ", hanya baris itu yang memulai halaman baru.
   "## " menjadi subjudul di dalam halaman.
2. Kalau tidak ada "# ", baris pendek yang berdiri sendiri dianggap judul
   bagian: kurang dari 60 karakter, tidak diakhiri titik, bukan butir daftar,
   dan menjadi satu paragraf sendiri. Berdiri sendiri artinya diapit baris
   kosong, atau setiap baris memang paragraf sendiri karena teksnya tidak
   punya baris kosong, atau baris itu di awal kelompok dan baris berikutnya
   memulai kalimat baru (huruf besar). Baris pendek yang diikuti huruf kecil
   adalah kalimat yang terpotong saat disalin, bukan judul.

Baris yang berurutan tanpa baris kosong di antaranya digabung menjadi satu
paragraf, karena teks salinan sering terpotong di tengah kalimat. Kalau
teksnya sama sekali tidak punya baris kosong, setiap baris dianggap satu
paragraf. Butir daftar ("-", "•", "1.") selalu satu baris sendiri.

Teks sebelum judul pertama masuk ke halaman berjudul sama dengan judul
materi. Judul yang langsung diikuti judul lain (halamannya belum berisi apa
pun) membuat judul kedua menjadi subjudul di halaman yang sama.
"""

import re

from pdf_sections import (
    BULLET_RE,
    NUMBERED_ITEM_RE,
    SUBHEADING_PREFIX,
    Section,
    normalize_content,
)

MAX_TEXT_LENGTH = 100_000
MAX_PAGES = 200
HEADING_MAX_LENGTH = 60

PAGE_PREFIX = "# "


def _is_item(line: str) -> bool:
    return bool(
        line.startswith("- ") or BULLET_RE.match(line) or NUMBERED_ITEM_RE.match(line)
    )


def looks_like_heading(line: str) -> bool:
    """Baris pendek tanpa titik di akhir yang bukan butir daftar."""
    text = line.strip()
    return (
        0 < len(text) < HEADING_MAX_LENGTH
        and not text.endswith(".")
        and not _is_item(text)
    )


def _clean_lines(text: str) -> list[str]:
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", " ")
    # Spasi tak terlihat dari Word dan web.
    text = text.replace(" ", " ").replace("​", "")
    return [" ".join(line.split()) for line in text.split("\n")]


def _has_blank_lines(lines: list[str]) -> bool:
    """Ada baris kosong di antara isi (bukan hanya di awal atau akhir)."""
    filled = [i for i, line in enumerate(lines) if line]
    if not filled:
        return False
    return not all(lines[filled[0] : filled[-1] + 1])


def _blocks(lines: list[str]) -> list[list[str]]:
    """Kelompok baris yang dipisah baris kosong. Kalau tidak ada baris kosong
    di antara isi, setiap baris satu kelompok."""
    if not _has_blank_lines(lines):
        return [[line] for line in lines if line]
    blocks, current = [], []
    for line in lines:
        if line:
            current.append(line)
        elif current:
            blocks.append(current)
            current = []
    if current:
        blocks.append(current)
    return blocks


def _paragraphs(block: list[str]) -> list[str]:
    """Baris biasa yang berurutan digabung, butir daftar tetap sendiri."""
    out, pending = [], []
    for line in block:
        if _is_item(line):
            if pending:
                out.append(" ".join(pending))
                pending = []
            out.append(line)
        else:
            pending.append(line)
    if pending:
        out.append(" ".join(pending))
    return out


def _explicit_lines(lines: list[str]) -> list[tuple[str, str]]:
    """Mode "#": (jenis, teks) dengan jenis "page", "sub", atau "text"."""
    marked = []
    for line in lines:
        if line.startswith(PAGE_PREFIX):
            marked.append(("page", line[len(PAGE_PREFIX) :].strip()))
        elif line.startswith(SUBHEADING_PREFIX):
            marked.append(("sub", line[len(SUBHEADING_PREFIX) :].strip()))
        else:
            marked.append(("text", line))
    join = _has_blank_lines(lines)
    out, block = [], []

    def flush():
        paragraphs = _paragraphs(block) if join else list(block)
        out.extend(("text", p) for p in paragraphs)
        block.clear()

    for kind, value in marked:
        if kind == "text" and value:
            block.append(value)
            continue
        flush()
        if kind != "text" and value:
            out.append((kind, value))
    flush()
    return out


def _starts_new_sentence(line: str) -> bool:
    first = line[:1]
    return first.isupper() or first.isdigit() or _is_item(line)


def _auto_lines(lines: list[str]) -> list[tuple[str, str]]:
    out = []
    for block in _blocks(lines):
        if len(block) == 1 and looks_like_heading(block[0]):
            out.append(("page", block[0]))
            continue
        # Judul yang langsung diikuti paragraf tanpa baris kosong: baris
        # berikutnya memulai kalimat baru. Kalau diawali huruf kecil, baris
        # pendek itu potongan kalimat yang terpotong saat disalin.
        if (
            len(block) > 1
            and looks_like_heading(block[0])
            and not block[0].endswith((",", ":", ";"))
            and _starts_new_sentence(block[1])
        ):
            out.append(("page", block[0]))
            block = block[1:]
        out.extend(("text", p) for p in _paragraphs(block))
    return out


def split_pasted_text(text: str, material_title: str) -> list[Section]:
    """Halaman-halaman dari teks tempelan. Kosong kalau teksnya kosong."""
    lines = _clean_lines(text)
    explicit = any(line.startswith(PAGE_PREFIX) for line in lines)
    items = _explicit_lines(lines) if explicit else _auto_lines(lines)

    pages: list[tuple[str, list[str]]] = []
    for kind, value in items:
        if kind == "page":
            if pages and not pages[-1][1]:
                # Halaman sebelumnya belum berisi: judul ini jadi subjudulnya.
                pages[-1][1].append(SUBHEADING_PREFIX + value)
            else:
                pages.append((value, []))
            continue
        if not pages:
            pages.append((material_title.strip(), []))
        line = SUBHEADING_PREFIX + value if kind == "sub" else value
        pages[-1][1].append(line)

    sections = []
    for number, (title, content_lines) in enumerate(pages, start=1):
        content = normalize_content("\n".join(content_lines))
        sections.append(
            Section(
                title=title,
                page_start=number,
                page_end=number,
                content=content,
            )
        )
    return sections


def preview_of(section: Section) -> dict:
    """Ringkasan satu halaman untuk pratinjau sebelum disimpan."""
    lines = [line for line in section.content.split("\n") if line.strip()]
    subheadings = sum(1 for line in lines if line.startswith(SUBHEADING_PREFIX))
    items = sum(1 for line in lines if _is_item(line))
    return {
        "title": section.title,
        "content": section.content,
        "paragraph_count": len(lines) - subheadings - items,
        "subheading_count": subheadings,
        "list_item_count": items,
        "word_count": len(re.findall(r"\w+", section.content)),
    }
