"""Memecah PDF menjadi satu bagian per halaman, berisi teks terstruktur.

Teks disusun dari posisi tiap huruf, bukan dari karakter spasi di PDF.
PDF buatan Canva dan sejenisnya sering tidak menyimpan spasi, dan jarak antar
katanya terlalu rapat untuk dikenali MuPDF, sehingga kata menempel
("Budimengeluarkanamplop"). Di sini spasi disisipkan kalau jarak dua huruf
jelas lebih lebar dari jarak huruf biasa di baris yang sama.

Isi halaman disimpan sebagai baris-baris di `content`:
- baris biasa adalah satu paragraf utuh,
- baris berawalan "## " adalah subjudul,
- baris berawalan "- " adalah satu butir daftar (tanda butir aslinya, seperti
  "●" atau "•", dibuang); butir berurutan membentuk satu daftar,
- baris "[[gambar:xref-12]]" adalah gambar di posisi itu dalam urutan baca.
  Deskripsinya ada di tabel material_images dengan image_key yang sama, jadi
  gambar yang dipakai di beberapa halaman cukup dideskripsikan sekali.
Judul halaman (huruf terbesar di halaman) disimpan di `title`, atau kosong
kalau halaman tidak punya judul.
"""

import re
import statistics
from collections import Counter
from dataclasses import dataclass, field

import pymupdf

SUBHEADING_PREFIX = "## "
LIST_ITEM_PREFIX = "- "
# Tanda butir simbol boleh langsung menempel ke teks ("●Mengenal").
# , , , , : butir dari huruf Symbol/Wingdings
# (PDF hasil Word).
SYMBOL_BULLETS = "●•▪◦‣∙○■□◆◇➢➤►▸✓✔"
# Tanda butir yang juga dipakai dalam kalimat ("-5 derajat") hanya dihitung
# butir kalau diikuti spasi.
DASH_BULLETS = "-–—*·"
BULLET_RE = re.compile(rf"^(?:[{SYMBOL_BULLETS}]\s*|[{re.escape(DASH_BULLETS)}]\s+)")
BULLET_ONLY_RE = re.compile(rf"^[{SYMBOL_BULLETS}{re.escape(DASH_BULLETS)}]$")
HEADING_SIZE_RATIO = 1.15
MAX_HEADING_LENGTH = 80
MAX_BOLD_SUBHEADING_LENGTH = 60
# Spasi disisipkan kalau jarak dua huruf melebihi jarak huruf biasa
# ditambah sekian kali ukuran huruf.
WORD_GAP_RATIO = 0.05
# Baris yang sejajar dan berjarak kurang dari ini (kali ukuran huruf)
# dianggap satu baris yang terpotong oleh PDF.
SAME_ROW_GAP_RATIO = 1.0
# Jarak vertikal maksimal antar baris dalam satu paragraf.
PARAGRAPH_GAP_RATIO = 0.7
# Karakter tak terlihat yang sering ada di PDF Canva.
INVISIBLE = {"\u200b", "\u200c", "\u200d", "\u2060", "\ufeff", "\u00ad"}
IMAGE_MARKER_RE = re.compile(r"^\[\[gambar:([\w-]+)\]\]$")
# Gambar sekecil ini (dalam poin, 72 poin = 1 inci) dianggap ikon hiasan.
DECORATIVE_MAX_SIDE = 40
# Gambar yang menutupi hampir seluruh halaman dianggap latar.
BACKGROUND_AREA_RATIO = 0.9
# Celah tengah minimal (poin) untuk mengenali dua kolom.
MIN_GUTTER = 18
CREDIT_RE = re.compile(r"^(sumber|source|foto|kredit|credit)\s*:", re.IGNORECASE)


@dataclass
class Line:
    text: str
    size: float
    bold: bool
    x0: float
    y0: float
    x1: float
    y1: float
    baseline: float
    bullet: bool = False
    # Kunci urutan baca, diisi assign_reading_order.
    order: tuple = ()


@dataclass
class Block:
    kind: str  # "heading", "subheading", "paragraph", "item", atau "image"
    text: str  # untuk "image": image_key
    size: float
    order: tuple = ()


@dataclass
class PageImage:
    key: str
    xref: int
    page: int
    y: float
    decorative: bool
    x0: float = 0.0
    x1: float = 0.0
    y1: float = 0.0
    order: tuple = ()

    @property
    def y0(self) -> float:
        return self.y


@dataclass
class Section:
    title: str
    page_start: int
    page_end: int
    content: str = ""
    image_count: int = 0
    blocks: list[Block] = field(default_factory=list)

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


def is_bold(span: dict) -> bool:
    return bool(span["flags"] & 16) or "bold" in span["font"].casefold()


def line_text(chars: list[dict]) -> str:
    """Menyusun teks satu baris dari posisi huruf."""
    chars = [char for char in chars if char["c"] not in INVISIBLE]
    gaps = []
    for previous, char in zip(chars, chars[1:]):
        if previous["c"].isspace() or char["c"].isspace():
            continue
        gaps.append(char["bbox"][0] - previous["bbox"][2])
    # Kebanyakan jarak adalah jarak antar huruf dalam kata.
    letter_gap = statistics.median(gaps) if gaps else 0.0

    text = ""
    previous = None
    for char in chars:
        c = char["c"]
        if c.isspace():
            if text and not text.endswith(" "):
                text += " "
        else:
            if previous is not None and not previous["c"].isspace():
                gap = char["bbox"][0] - previous["bbox"][2]
                if gap - letter_gap > WORD_GAP_RATIO * char["size"]:
                    text += " "
            text += c
        previous = char
    text = " ".join(text.split())
    # Spasi sebelum tanda baca ("CodeJR .", "belajar :") dibuang.
    text = re.sub(r"\s+([.,;:!?)\]])", r"\1", text)
    return re.sub(r"([(\[])\s+", r"\1", text)


def page_lines(page) -> list[Line]:
    lines = []
    data = page.get_text("rawdict", sort=True)
    for block in data["blocks"]:
        if block.get("type") != 0:
            continue
        for raw_line in block["lines"]:
            chars = []
            sizes = Counter()
            bold = Counter()
            for span in raw_line["spans"]:
                for char in span["chars"]:
                    chars.append({**char, "size": span["size"]})
                    if not char["c"].isspace():
                        sizes[round(span["size"], 1)] += 1
                        bold[is_bold(span)] += 1
            text = line_text(chars)
            if not text:
                continue
            x0, y0, x1, y1 = raw_line["bbox"]
            letters = [c for c in chars if not c["c"].isspace()]
            lines.append(
                Line(
                    text=text,
                    size=sizes.most_common(1)[0][0],
                    bold=bold.most_common(1)[0][0],
                    x0=x0,
                    y0=y0,
                    x1=x1,
                    y1=y1,
                    baseline=letters[0]["origin"][1],
                )
            )
    return mark_bullets(merge_rows(lines))


def same_style(a: Line, b: Line) -> bool:
    return abs(a.size - b.size) < 0.5 and a.bold == b.bold


def merge_rows(lines: list[Line]) -> list[Line]:
    """Menyatukan potongan baris yang sejajar dan bersebelahan."""
    merged: list[Line] = []
    for line in lines:
        previous = merged[-1] if merged else None
        if (
            previous is not None
            and same_style(previous, line)
            and abs(previous.baseline - line.baseline) < 0.25 * line.size
            and 0 <= line.x0 - previous.x1 < SAME_ROW_GAP_RATIO * line.size
        ):
            previous.text = f"{previous.text} {line.text}"
            previous.x1 = line.x1
            previous.y0 = min(previous.y0, line.y0)
            previous.y1 = max(previous.y1, line.y1)
            continue
        merged.append(line)
    return merged


def mark_bullets(lines: list[Line]) -> list[Line]:
    """Menandai baris butir dan membuang tanda butirnya.

    Tanda butir bisa menempel di awal baris, atau menjadi baris sendiri
    (ukuran atau huruf berbeda) yang sejajar dengan teks butirnya.
    """
    result: list[Line] = []
    pending: Line | None = None
    for line in lines:
        if BULLET_ONLY_RE.match(line.text):
            pending = line
            continue
        if (
            pending is not None
            and abs(pending.baseline - line.baseline) < 0.5 * line.size
            and line.x0 >= pending.x0
        ):
            line.bullet = True
            line.x0 = pending.x0
        pending = None
        match = BULLET_RE.match(line.text)
        if match and line.text[match.end() :].strip():
            line.text = line.text[match.end() :].strip()
            line.bullet = True
        result.append(line)
    return result


def body_font_size(lines: list[Line]) -> float:
    sizes = Counter()
    for line in lines:
        sizes[line.size] += len(line.text)
    return sizes.most_common(1)[0][0] if sizes else 0.0


def is_noise(line: Line) -> bool:
    """Keterangan sumber gambar dan nomor halaman tidak dibacakan."""
    return bool(CREDIT_RE.match(line.text)) or line.text.isdigit()


def continues_paragraph(previous: Line, line: Line) -> bool:
    return (
        same_style(previous, line)
        and line.y0 > previous.y0
        and line.y0 - previous.y1 < PARAGRAPH_GAP_RATIO * line.size
    )


def continues_item(first: Line, line: Line) -> bool:
    """Lanjutan butir menjorok ke kanan dari tanda butirnya. Baris yang
    sejajar tanda butir sudah paragraf baru setelah daftar."""
    return not first.bullet or line.x0 > first.x0 + 0.3 * line.size


def join_lines(texts: list[str]) -> str:
    text = texts[0]
    for part in texts[1:]:
        # Kata yang dipenggal di akhir baris disambung lagi.
        if text.endswith("-") and part[:1].islower():
            text = text[:-1] + part
        else:
            text = f"{text} {part}"
    return text


def classify(text: str, line: Line, body_size: float) -> str:
    if len(text) <= MAX_HEADING_LENGTH and line.size >= body_size * HEADING_SIZE_RATIO:
        return "heading"
    if (
        line.bold
        and len(text) <= MAX_BOLD_SUBHEADING_LENGTH
        and not text.endswith((".", ",", ";", ":"))
    ):
        return "subheading"
    return "paragraph"


def group_blocks(lines: list[Line], body_size: float) -> list[Block]:
    groups: list[list[Line]] = []
    for line in lines:
        if is_noise(line):
            # Keterangan juga memutus paragraf di sekitarnya.
            groups.append([])
            continue
        # Butir selalu mulai blok baru, jadi tidak menempel ke kalimat
        # pengantarnya ("Hari ini kamu akan belajar:").
        if (
            not line.bullet
            and groups
            and groups[-1]
            and continues_paragraph(groups[-1][-1], line)
            and continues_item(groups[-1][0], line)
        ):
            groups[-1].append(line)
        else:
            groups.append([line])
    blocks = []
    for group in groups:
        if not group:
            continue
        text = join_lines([line.text for line in group])
        kind = "item" if group[0].bullet else classify(text, group[0], body_size)
        blocks.append(Block(kind, text, group[0].size, group[0].order))
    return blocks


def bands(items: list) -> list[list]:
    """Mengelompokkan baris dan gambar menjadi pita horizontal: benda yang
    tumpang tindih secara vertikal masuk pita yang sama."""
    result: list[list] = []
    bottom = 0.0
    for item in sorted(items, key=lambda i: (i.y0, i.x0)):
        if result and item.y0 < bottom - 1:
            result[-1].append(item)
            bottom = max(bottom, item.y1)
        else:
            result.append([item])
            bottom = item.y1
    return result


def gutter(band: list) -> tuple[float, float] | None:
    """Celah kosong vertikal terlebar di pita, dengan benda di kedua sisi."""
    spans = sorted((item.x0, item.x1) for item in band)
    best = None
    reach = spans[0][1]
    for x0, x1 in spans[1:]:
        if x0 - reach >= MIN_GUTTER and (best is None or x0 - reach > best[1] - best[0]):
            best = (reach, x0)
        reach = max(reach, x1)
    return best


def is_left(item, gap: tuple[float, float]) -> bool:
    return (item.x0 + item.x1) / 2 < (gap[0] + gap[1]) / 2


def narrow(gap: tuple[float, float], band: list) -> tuple[float, float] | None:
    """Celah yang tersisa setelah pita ini ikut, atau None kalau celahnya
    tertutup (misalnya paragraf selebar halaman)."""
    left, right = gap
    for item in band:
        if is_left(item, gap):
            left = max(left, item.x1)
        else:
            right = min(right, item.x0)
    return (left, right) if right - left >= MIN_GUTTER else None


def flows(columns: list[list]) -> bool:
    """Kedua kolom berisi teks, dan teksnya mengalir sebagai paragraf (ada
    baris lanjutan). Tabel yang selnya satu baris, atau tabel gambar |
    keterangan, tidak dianggap kolom, jadi tetap dibaca per baris."""
    if not all(any(isinstance(i, Line) for i in column) for column in columns):
        return False
    for column in columns:
        lines = sorted((i for i in column if isinstance(i, Line)), key=lambda i: i.y0)
        if any(continues_paragraph(a, b) for a, b in zip(lines, lines[1:])):
            return True
    return False


def assign_reading_order(lines: list[Line], images: list[PageImage]):
    """Mengisi `order` setiap baris dan gambar.

    Biasanya urut dari atas ke bawah. Bagian dua kolom (pita-pita berurutan
    dengan celah tengah yang sama dan teks yang mengalir) dibaca kolom kiri
    sampai habis, baru kolom kanan, supaya kalimat kedua kolom tidak
    saling menyelang.
    """
    page_bands = bands([*lines, *images])
    segment = 0
    i = 0
    while i < len(page_bands):
        gap = gutter(page_bands[i])
        if gap is not None:
            j = i + 1
            while j < len(page_bands):
                band = page_bands[j]
                narrowed = narrow(gap, band)
                if narrowed is None:
                    break
                # Pita yang hanya berisi satu sisi ikut kolom hanya kalau
                # rapat dengan pita sebelumnya (lanjutan baris kolom). Kalau
                # berjarak, itu paragraf baru di bawah bagian dua kolom.
                one_sided = len({is_left(item, gap) for item in band}) == 1
                top = min(item.y0 for item in band)
                height = max(item.y1 for item in band) - top
                previous_bottom = max(item.y1 for item in page_bands[j - 1])
                if one_sided and top - previous_bottom > height:
                    break
                gap = narrowed
                j += 1
            region = [item for band in page_bands[i:j] for item in band]
            columns = [
                [item for item in region if is_left(item, gap)],
                [item for item in region if not is_left(item, gap)],
            ]
            if j - i > 1 and flows(columns):
                for column_index, column in enumerate(columns):
                    for item in column:
                        item.order = (segment, column_index, item.y0, item.x0)
                segment += 1
                i = j
                continue
        for item in page_bands[i]:
            item.order = (segment, 0, item.y0, item.x0)
        segment += 1
        i += 1


def image_marker(key: str) -> str:
    return f"[[gambar:{key}]]"


def page_images(page, number: int) -> list[PageImage]:
    """Gambar di halaman, urut dari atas. Gambar inline tanpa xref dilewati
    karena berkasnya tidak bisa diambil untuk dideskripsikan."""
    page_area = page.rect.width * page.rect.height
    images = []
    for info in page.get_image_info(xrefs=True):
        xref = info.get("xref") or 0
        if not xref:
            continue
        rect = pymupdf.Rect(info["bbox"]) & page.rect
        if rect.is_empty:
            continue
        decorative = (
            min(rect.width, rect.height) < DECORATIVE_MAX_SIDE
            or rect.width * rect.height >= BACKGROUND_AREA_RATIO * page_area
        )
        images.append(
            PageImage(
                f"xref-{xref}",
                xref,
                number,
                rect.y0,
                decorative,
                x0=rect.x0,
                x1=rect.x1,
                y1=rect.y1,
            )
        )
    images.sort(key=lambda image: image.y)
    return images


def content_line(block: Block) -> str:
    if block.kind == "image":
        return image_marker(block.text)
    if block.kind == "paragraph":
        return block.text
    if block.kind == "item":
        return LIST_ITEM_PREFIX + block.text
    return SUBHEADING_PREFIX + block.text


def image_keys(content: str) -> list[str]:
    """Kunci gambar yang dirujuk isi halaman, urut dan tanpa duplikat."""
    keys = []
    for line in content.split("\n"):
        match = IMAGE_MARKER_RE.match(line.strip())
        if match and match.group(1) not in keys:
            keys.append(match.group(1))
    return keys


def plain_text(content: str) -> str:
    """Isi halaman tanpa penanda gambar dan awalan subjudul, untuk AI soal."""
    lines = []
    for line in content.split("\n"):
        if IMAGE_MARKER_RE.match(line.strip()):
            continue
        lines.append(line.removeprefix(SUBHEADING_PREFIX))
    return "\n".join(line for line in lines if line.strip())


def build_page(number: int, blocks: list[Block], images: list[PageImage]) -> Section:
    headings = [b for b in blocks if b.kind == "heading"]
    title = ""
    if headings:
        biggest = max(b.size for b in headings)
        title_block = next(b for b in headings if b.size == biggest)
        title = title_block.text
        blocks = [b for b in blocks if b is not title_block]
    # Gambar disisipkan di antara teks menurut urutan baca. Gambar yang
    # sama dua kali di satu halaman cukup sekali.
    seen = set()
    for image in images:
        if image.key in seen:
            continue
        seen.add(image.key)
        blocks.append(Block("image", image.key, 0.0, image.order))
    blocks.sort(key=lambda block: block.order)
    content = "\n".join(content_line(b) for b in blocks)
    return Section(
        title=title,
        page_start=number,
        page_end=number,
        content=content,
        image_count=len(seen),
        blocks=blocks,
    )


def split_sections(doc) -> list[Section]:
    pages = [page_lines(page) for page in doc]
    body_size = body_font_size([line for lines in pages for line in lines])
    sections = []
    for number, (page, lines) in enumerate(zip(doc, pages), start=1):
        images = page_images(page, number)
        assign_reading_order(lines, images)
        lines.sort(key=lambda line: line.order)
        sections.append(build_page(number, group_blocks(lines, body_size), images))
    return sections


def split_pdf_bytes(file_bytes: bytes) -> list[Section]:
    with pymupdf.open(stream=file_bytes, filetype="pdf") as doc:
        return split_sections(doc)
