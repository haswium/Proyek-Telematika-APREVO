"""Memecah teks PDF menjadi sub-bab.

Urutan cara mencari judul sub-bab:
1. Daftar isi (bookmark) PDF, level 1 dan 2.
2. Baris yang hurufnya lebih besar dari teks biasa, baris tebal yang pendek,
   atau baris berpola "BAB 1" / "1.2 Judul".
3. Kalau tidak ada judul sama sekali, satu sub-bab per halaman.
"""

import re
from collections import Counter
from dataclasses import dataclass

import pymupdf

MAX_HEADING_LENGTH = 80
HEADING_SIZE_RATIO = 1.15
BAB_RE = re.compile(r"^(bab|chapter)\s+([0-9]+|[ivxlc]+)\b", re.IGNORECASE)
SUBNUMBER_RE = re.compile(r"^\d+(\.\d+)+\.?\s+\S")
NUMBER_RE = re.compile(r"^\d+\.?\s+\S")


@dataclass
class Line:
    page: int
    y: float
    block: int
    text: str
    size: float
    bold: bool


@dataclass
class Section:
    title: str
    page_start: int
    page_end: int
    content: str = ""
    image_count: int = 0
    start_y: float = -1.0

    def as_row(self, material_id: str, position: int) -> dict:
        return {
            "material_id": material_id,
            "position": position,
            "title": self.title,
            "content": self.content,
            "image_description": None,
            "image_count": self.image_count,
            "page_start": self.page_start,
            "page_end": self.page_end,
        }


def normalize(text: str) -> str:
    return " ".join(text.casefold().split())


def extract_lines(doc) -> list[Line]:
    lines = []
    for page_index, page in enumerate(doc):
        data = page.get_text("dict", sort=True)
        for block_index, block in enumerate(data["blocks"]):
            if block.get("type") != 0:
                continue
            for raw_line in block["lines"]:
                spans = [span for span in raw_line["spans"] if span["text"].strip()]
                if not spans:
                    continue
                text = " ".join("".join(span["text"] for span in spans).split())
                lines.append(
                    Line(
                        page=page_index + 1,
                        y=raw_line["bbox"][1],
                        block=block_index,
                        text=text,
                        size=round(max(span["size"] for span in spans), 1),
                        bold=all(
                            span["flags"] & 16 or "bold" in span["font"].casefold()
                            for span in spans
                        ),
                    )
                )
    return lines


def body_font_size(lines: list[Line]) -> float:
    sizes = Counter()
    for line in lines:
        sizes[line.size] += len(line.text)
    return sizes.most_common(1)[0][0]


def is_styled(line: Line, body_size: float) -> bool:
    return line.bold or line.size >= body_size * HEADING_SIZE_RATIO


def looks_like_heading(line: Line, body_size: float) -> bool:
    text = line.text
    if len(text) > MAX_HEADING_LENGTH or text.endswith((",", ";")):
        return False
    if BAB_RE.match(text):
        return True
    if line.size >= body_size * HEADING_SIZE_RATIO:
        return True
    if text.endswith("."):
        return False
    if SUBNUMBER_RE.match(text):
        return True
    return line.bold and (NUMBER_RE.match(text) is not None or len(text) <= 60)


def continues_heading(previous: Line, line: Line) -> bool:
    return (
        previous.page == line.page
        and previous.block == line.block
        and previous.size == line.size
        and previous.bold == line.bold
    )


def headings_from_toc(doc, lines: list[Line]) -> list[int]:
    indexes = set()
    for level, title, page in doc.get_toc(simple=True):
        if level > 2:
            continue
        wanted = normalize(title)
        page_lines = [i for i, line in enumerate(lines) if line.page == page]
        if not page_lines or not wanted:
            continue
        match = next(
            (i for i in page_lines if normalize(lines[i].text).startswith(wanted)),
            page_lines[0],
        )
        indexes.add(match)
    return sorted(indexes)


def headings_from_layout(lines: list[Line], body_size: float) -> list[int]:
    indexes = []
    for i, line in enumerate(lines):
        if not looks_like_heading(line, body_size):
            continue
        # Judul yang terbagi dua baris dihitung satu judul.
        if indexes and indexes[-1] == i - 1 and continues_heading(lines[i - 1], line):
            continue
        indexes.append(i)
    return indexes


def heading_title(
    lines: list[Line], start: int, end: int, body_size: float
) -> tuple[str, int]:
    """Mengembalikan judul dan indeks baris pertama isi sub-bab."""
    parts = [lines[start].text]
    body_start = start + 1
    if is_styled(lines[start], body_size):
        while (
            body_start < end
            and continues_heading(lines[body_start - 1], lines[body_start])
            and len(" ".join(parts + [lines[body_start].text])) <= MAX_HEADING_LENGTH
        ):
            parts.append(lines[body_start].text)
            body_start += 1
    return " ".join(parts), body_start


def join_text(lines: list[Line]) -> str:
    paragraphs = []
    current = ""
    previous = None
    for line in lines:
        if previous is None or (line.page, line.block) != (previous.page, previous.block):
            if current:
                paragraphs.append(current)
            current = line.text
        elif current.endswith("-") and line.text[:1].islower():
            current = current[:-1] + line.text
        else:
            current = f"{current} {line.text}"
        previous = line
    if current:
        paragraphs.append(current)
    return "\n".join(paragraphs)


def count_images(doc, sections: list[Section]):
    starts = [(section.page_start, section.start_y) for section in sections]
    for page_index, page in enumerate(doc):
        for image in page.get_image_info():
            position = (page_index + 1, image["bbox"][1])
            owner = 0
            for i, start in enumerate(starts):
                if start <= position:
                    owner = i
            sections[owner].image_count += 1


def page_sections(doc, lines: list[Line]) -> list[Section]:
    sections = []
    for page in range(1, len(doc) + 1):
        page_lines = [line for line in lines if line.page == page]
        sections.append(
            Section(
                title=f"Halaman {page}",
                page_start=page,
                page_end=page,
                content=join_text(page_lines),
            )
        )
    return sections


def split_sections(doc) -> list[Section]:
    lines = extract_lines(doc)
    if not lines:
        sections = page_sections(doc, lines)
        count_images(doc, sections)
        return sections

    body_size = body_font_size(lines)
    heading_indexes = headings_from_toc(doc, lines) or headings_from_layout(
        lines, body_size
    )
    if not heading_indexes:
        sections = page_sections(doc, lines)
        count_images(doc, sections)
        return sections

    sections = []
    if heading_indexes[0] > 0:
        intro = lines[: heading_indexes[0]]
        sections.append(
            Section(
                title="Pendahuluan",
                page_start=intro[0].page,
                page_end=intro[-1].page,
                content=join_text(intro),
            )
        )
    bounds = heading_indexes + [len(lines)]
    for start, end in zip(bounds, bounds[1:]):
        title, body_start = heading_title(lines, start, end, body_size)
        sections.append(
            Section(
                title=title,
                page_start=lines[start].page,
                page_end=lines[end - 1].page,
                content=join_text(lines[body_start:end]),
                start_y=lines[start].y,
            )
        )
    count_images(doc, sections)
    return sections


def split_pdf_bytes(file_bytes: bytes) -> list[Section]:
    with pymupdf.open(stream=file_bytes, filetype="pdf") as doc:
        return split_sections(doc)
