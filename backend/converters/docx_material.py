"""DOCX ke halaman materi (python-docx).

- Heading 1 (atau gaya "Title") dan page break memulai halaman baru. Judul
  halaman dari teks heading; halaman dari page break tanpa judul.
- Heading 2 ke bawah menjadi subjudul.
- Paragraf berpenomoran atau berbutir (numPr, atau gaya "List ...") menjadi
  butir daftar.
- Tabel menjadi [[tabel]] dengan baris pertama sebagai nama kolom. Sel yang
  digabung hanya dihitung sekali.
- Gambar inline disimpan di posisinya. Teks alternatif dari Word dipakai
  sebagai deskripsi awal; sisanya dideskripsikan AI.

Isi dibaca langsung dari XML body supaya urutan paragraf dan tabel benar.
"""

import re
from pathlib import Path

from docx import Document
from docx.opc.exceptions import PackageNotFoundError
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph

from converters import ConversionError, Converted, PageBuilder, clean_text, require_content

# Namespace VML (gambar Word 2003) tidak ada di daftar python-docx.
VML_IMAGEDATA = "{urn:schemas-microsoft-com:vml}imagedata"
HEADING_RE = re.compile(r"^(heading|judul)\s*(\d)$", re.IGNORECASE)


def _heading_level(paragraph: Paragraph) -> int | None:
    style = paragraph.style
    for name in (getattr(style, "name", None), getattr(style, "style_id", None)):
        if not name:
            continue
        if name.lower() == "title":
            return 1
        match = HEADING_RE.match(name)
        if match:
            return int(match.group(2))
    # Gaya buatan sendiri yang ditandai level outline di Word.
    ppr = paragraph._p.pPr
    if ppr is not None:
        outline = ppr.find(qn("w:outlineLvl"))
        if outline is not None:
            try:
                return int(outline.get(qn("w:val"))) + 1
            except (TypeError, ValueError):
                return None
    return None


def _is_list(paragraph: Paragraph) -> bool:
    ppr = paragraph._p.pPr
    if ppr is not None and ppr.find(qn("w:numPr")) is not None:
        return True
    name = getattr(paragraph.style, "name", "") or ""
    return name.lower().startswith(("list", "daftar"))


def _page_break_before(paragraph: Paragraph) -> bool:
    ppr = paragraph._p.pPr
    if ppr is None:
        return False
    flag = ppr.find(qn("w:pageBreakBefore"))
    return flag is not None and flag.get(qn("w:val"), "true") not in ("0", "false")


def _image_alt(drawing) -> str | None:
    for tag in ("wp:docPr",):
        for element in drawing.iter(qn(tag)):
            return element.get("descr") or element.get("title")
    return None


class _DocxReader:
    def __init__(self, document, builder: PageBuilder):
        self.document = document
        self.part = document.part
        self.out = builder

    def run(self):
        for child in self.document.element.body.iterchildren():
            if child.tag == qn("w:p"):
                self.paragraph(Paragraph(child, self.document))
            elif child.tag == qn("w:tbl"):
                self.table(Table(child, self.document))

    def _blob(self, rel_id):
        part = self.part.related_parts.get(rel_id)
        return getattr(part, "blob", None)

    def paragraph(self, paragraph: Paragraph):
        if _page_break_before(paragraph):
            self.out.new_page()
        level = _heading_level(paragraph)
        if level is not None and clean_text(paragraph.text):
            if level == 1:
                self.out.new_page(paragraph.text)
            else:
                self.out.subheading(paragraph.text)
            return
        add = self.out.item if _is_list(paragraph) else self.out.paragraph
        # Run demi run, supaya gambar dan page break di tengah paragraf
        # berada di posisi yang benar.
        text = []
        for element in paragraph._p.iter():
            if element.tag == qn("w:t"):
                text.append(element.text or "")
            elif element.tag == qn("w:tab"):
                text.append(" ")
            elif element.tag == qn("w:br") and element.get(qn("w:type")) == "page":
                add("".join(text))
                text = []
                self.out.new_page()
            elif element.tag == qn("w:drawing"):
                add("".join(text))
                text = []
                for blip in element.iter(qn("a:blip")):
                    blob = self._blob(blip.get(qn("r:embed")))
                    if blob:
                        self.out.image(blob, "docx", _image_alt(element))
            elif element.tag == VML_IMAGEDATA:
                # Gambar format lama (VML) dari dokumen Word 2003.
                add("".join(text))
                text = []
                blob = self._blob(element.get(qn("r:id")))
                if blob:
                    self.out.image(blob, "docx")
        add("".join(text))

    def table(self, table: Table):
        rows = []
        for row in table.rows:
            cells, seen = [], set()
            for cell in row.cells:
                # Sel gabungan muncul berulang dengan objek _tc yang sama.
                if id(cell._tc) in seen:
                    continue
                seen.add(id(cell._tc))
                cells.append(cell.text)
            rows.append(cells)
        self.out.table(rows)


def convert_docx(path: Path, title: str) -> Converted:
    try:
        document = Document(str(path))
    except (PackageNotFoundError, KeyError, ValueError) as error:
        raise ConversionError(
            "Dokumen Word tidak bisa dibaca. Pastikan file tidak rusak, lalu "
            "simpan ulang sebagai .docx."
        ) from error
    # Judul cadangan dari guru, bukan properti dokumen (sering berisi
    # "Microsoft Word - ..." atau kosong).
    builder = PageBuilder(title)
    _DocxReader(document, builder).run()
    return require_content(builder.build())
