"""Konverter dari format lain ke halaman materi.

Semua konverter menghasilkan `Converted`: halaman dengan `content` yang sama
formatnya seperti hasil PDF (lihat pdf_sections.py), ditambah gambar yang
perlu disimpan. Jadi layar baca siswa, editor guru, pencarian, dan AI soal
tidak perlu tahu file aslinya.
"""

import re
from dataclasses import dataclass, field
from io import BytesIO

from PIL import Image, UnidentifiedImageError

from pdf_sections import (
    LIST_ITEM_PREFIX,
    SUBHEADING_PREFIX,
    Section,
    image_marker,
    normalize_content,
    table_marker,
)

# Gambar sekecil ini (piksel) dianggap ikon hiasan.
DECORATIVE_MAX_PIXELS = 48
# Sisi terpanjang gambar yang disimpan. Foto kamera HP (4000 px) diperkecil
# supaya hemat memori, penyimpanan, dan kuota Gemini.
MAX_IMAGE_SIDE = 2000
# Batas tabel per halaman: satu sheet raksasa tidak boleh menghabiskan memori.
MAX_TABLE_ROWS = 1000
MAX_TABLE_COLUMNS = 30


FILENAME_ALT_RE = re.compile(
    r"^[\w\- .()]*\.(png|jpe?g|gif|bmp|tiff?|emf|wmf|svg|webp)$", re.IGNORECASE
)


class ConversionError(ValueError):
    """Isi file tidak bisa diubah. Pesannya ditampilkan ke guru."""


@dataclass
class ExtractedImage:
    key: str
    data: bytes
    extension: str
    content_type: str
    page_number: int
    decorative: bool = False
    # Teks alternatif dari dokumen asli, atau deskripsi dari Gemini. Gambar
    # yang sudah punya deskripsi tidak dikirim ke job deskripsi lagi.
    description: str | None = None


@dataclass
class Converted:
    sections: list[Section]
    images: list[ExtractedImage] = field(default_factory=list)
    # Catatan untuk guru, misalnya "2 gambar EMF dilewati".
    notes: list[str] = field(default_factory=list)


def clean_text(text: str) -> str:
    return " ".join((text or "").replace(" ", " ").replace("​", "").split())


def prepare_image(data: bytes) -> tuple[bytes, str, str, int, int] | None:
    """(data, ekstensi, content_type, lebar, tinggi) yang aman disimpan, atau
    None kalau bukan gambar yang bisa dibaca (EMF, WMF, SVG, rusak).

    JPEG dan PNG yang tidak terlalu besar disimpan apa adanya. Format lain
    (GIF, BMP, TIFF, WebP) dan gambar raksasa diubah ke PNG atau JPEG."""
    try:
        with Image.open(BytesIO(data)) as image:
            image.load()
            width, height = image.size
            kind = image.format
            if kind in ("JPEG", "PNG") and max(width, height) <= MAX_IMAGE_SIDE:
                content_type = "image/jpeg" if kind == "JPEG" else "image/png"
                return data, "jpg" if kind == "JPEG" else "png", content_type, width, height
            image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
            out = BytesIO()
            if kind == "JPEG" or image.mode in ("RGB", "CMYK", "YCbCr"):
                image.convert("RGB").save(out, "JPEG", quality=85)
                return out.getvalue(), "jpg", "image/jpeg", *image.size
            image.save(out, "PNG", optimize=True)
            return out.getvalue(), "png", "image/png", *image.size
    except (UnidentifiedImageError, OSError, ValueError):
        return None


def table_rows_to_marker(rows: list[list[str]], title: str) -> str | None:
    """Tabel dengan baris pertama yang berisi sebagai nama kolom. Kolom kosong
    di kanan dibuang; nama kolom kosong diganti "Kolom N"."""
    rows = [[clean_cell(cell) for cell in row] for row in rows]
    rows = [row for row in rows if any(row)]
    if not rows:
        return None
    width = max(
        (max((i + 1 for i, cell in enumerate(row) if cell), default=0) for row in rows),
        default=0,
    )
    width = min(width, MAX_TABLE_COLUMNS)
    if width == 0:
        return None
    rows = [(row + [""] * width)[:width] for row in rows]
    header, body = rows[0], rows[1 : MAX_TABLE_ROWS + 1]
    columns = [name or f"Kolom {i + 1}" for i, name in enumerate(header)]
    return table_marker({"title": title, "columns": columns, "rows": body})


def clean_cell(value) -> str:
    if value is None:
        return ""
    lines = [clean_text(line) for line in str(value).replace("\r", "\n").split("\n")]
    return "\n".join(line for line in lines if line)


class PageBuilder:
    """Menyusun halaman satu per satu dalam urutan baca."""

    def __init__(self, fallback_title: str):
        self.fallback_title = fallback_title.strip() or "Materi"
        self.pages: list[tuple[str, list[str]]] = []
        self.images: list[ExtractedImage] = []
        self.notes: list[str] = []
        self._image_count = 0
        self._table_count = 0

    @property
    def page_number(self) -> int:
        return max(len(self.pages), 1)

    def new_page(self, title: str = "") -> None:
        title = clean_text(title)
        # Halaman yang belum berisi apa pun dipakai ulang, supaya judul
        # berturut-turut atau page break di awal tidak membuat halaman kosong.
        if self.pages and not self.pages[-1][1]:
            old_title = self.pages[-1][0]
            if old_title and title:
                self.pages[-1][1].append(SUBHEADING_PREFIX + title)
            else:
                self.pages[-1] = (old_title or title, [])
            return
        self.pages.append((title, []))

    def _lines(self) -> list[str]:
        if not self.pages:
            self.pages.append((self.fallback_title, []))
        return self.pages[-1][1]

    def paragraph(self, text: str) -> None:
        text = clean_text(text)
        if text:
            self._lines().append(text)

    def subheading(self, text: str) -> None:
        text = clean_text(text)
        if text:
            self._lines().append(SUBHEADING_PREFIX + text)

    def item(self, text: str) -> None:
        text = clean_text(text)
        if text:
            self._lines().append(LIST_ITEM_PREFIX + text)

    def table(self, rows: list[list[str]], title: str | None = None) -> None:
        self._table_count += 1
        marker = table_rows_to_marker(rows, title or f"Tabel {self._table_count}")
        if marker:
            self._lines().append(marker)

    def image(self, data: bytes, prefix: str, alt: str | None = None) -> None:
        prepared = prepare_image(data)
        if prepared is None:
            self.notes.append("unsupported-image")
            return
        stored, extension, content_type, width, height = prepared
        self._image_count += 1
        key = f"{prefix}-{self._image_count}"
        lines = self._lines()
        lines.append(image_marker(key))
        alt = clean_text(alt or "")
        # Office mengisi teks alternatif dengan nama file ("image.png") kalau
        # penulisnya tidak menulis apa pun. Itu bukan deskripsi.
        if FILENAME_ALT_RE.match(alt):
            alt = ""
        self.images.append(
            ExtractedImage(
                key=key,
                data=stored,
                extension=extension,
                content_type=content_type,
                page_number=len(self.pages),
                decorative=max(width, height) <= DECORATIVE_MAX_PIXELS,
                description=alt or None,
            )
        )

    def build(self) -> Converted:
        sections = []
        renumber = {}
        for index, (title, lines) in enumerate(self.pages, start=1):
            if not lines and not title:
                continue
            number = len(sections) + 1
            renumber[index] = number
            sections.append(
                Section(
                    title=title,
                    page_start=number,
                    page_end=number,
                    content=normalize_content("\n".join(lines)),
                    image_count=sum(1 for line in lines if line.startswith("[[gambar:")),
                )
            )
        # Nomor halaman gambar mengikuti halaman yang benar-benar disimpan.
        for image in self.images:
            image.page_number = renumber.get(image.page_number, image.page_number)
        notes = []
        skipped = self.notes.count("unsupported-image")
        if skipped:
            notes.append(
                f"{skipped} gambar dengan format yang tidak bisa dibaca (misalnya EMF "
                "atau SVG) dilewati."
            )
        return Converted(sections=sections, images=self.images, notes=notes)


def require_content(converted: Converted) -> Converted:
    if not any(s.content.strip() for s in converted.sections):
        raise ConversionError("File tidak berisi teks, tabel, atau gambar yang bisa dibaca.")
    return converted
