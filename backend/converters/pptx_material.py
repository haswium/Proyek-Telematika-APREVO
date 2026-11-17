"""PPTX ke halaman materi (python-pptx). Satu slide satu halaman.

- Judul slide menjadi judul halaman ("Slide 3" kalau tidak ada judul).
- Shape dibaca dari atas ke bawah, lalu kiri ke kanan, termasuk isi grup.
- Teks di placeholder isi (bullet) dan paragraf berlevel menjadi butir daftar;
  kotak teks biasa menjadi paragraf.
- Tabel menjadi [[tabel]]. Grafik menjadi tabel kategori x seri.
- Gambar disimpan di posisinya, dengan teks alternatif sebagai deskripsi awal.
- Catatan pembicara masuk di akhir halaman dengan subjudul
  "Catatan pembicara".
"""

from pathlib import Path

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE, PP_PLACEHOLDER
from pptx.exc import PackageNotFoundError

from converters import ConversionError, Converted, PageBuilder, clean_text, require_content

BULLET_PLACEHOLDERS = {
    PP_PLACEHOLDER.BODY,
    PP_PLACEHOLDER.OBJECT,
    PP_PLACEHOLDER.VERTICAL_BODY,
    PP_PLACEHOLDER.VERTICAL_OBJECT,
}
TITLE_PLACEHOLDERS = {
    PP_PLACEHOLDER.TITLE,
    PP_PLACEHOLDER.CENTER_TITLE,
    PP_PLACEHOLDER.VERTICAL_TITLE,
}
SKIPPED_PLACEHOLDERS = {
    PP_PLACEHOLDER.SLIDE_NUMBER,
    PP_PLACEHOLDER.FOOTER,
    PP_PLACEHOLDER.DATE,
    PP_PLACEHOLDER.HEADER,
}


def _placeholder_type(shape):
    if not shape.is_placeholder:
        return None
    try:
        return shape.placeholder_format.type
    except ValueError:
        return None


def _reading_order(shapes):
    return sorted(shapes, key=lambda s: ((s.top or 0) // 20000, s.left or 0))


def _alt_text(shape) -> str | None:
    try:
        props = shape._element._nvXxPr.cNvPr
    except AttributeError:
        return None
    return props.get("descr") or None


class _SlideReader:
    def __init__(self, builder: PageBuilder):
        self.out = builder

    def shapes(self, shapes, title_shape):
        for shape in _reading_order(shapes):
            if shape is title_shape or shape.shape_id == getattr(title_shape, "shape_id", None):
                continue
            kind = _placeholder_type(shape)
            if kind in TITLE_PLACEHOLDERS or kind in SKIPPED_PLACEHOLDERS:
                continue
            if shape.shape_type == MSO_SHAPE_TYPE.GROUP:
                self.shapes(shape.shapes, title_shape)
            elif getattr(shape, "has_table", False) and shape.has_table:
                self.table(shape.table)
            elif getattr(shape, "has_chart", False) and shape.has_chart:
                self.chart(shape.chart)
            elif hasattr(shape, "image"):
                try:
                    blob = shape.image.blob
                except (AttributeError, ValueError, KeyError):
                    blob = None
                if blob:
                    self.out.image(blob, f"pptx-s{self.out.page_number}", _alt_text(shape))
            elif getattr(shape, "has_text_frame", False) and shape.has_text_frame:
                self.text(shape.text_frame, bullets=kind in BULLET_PLACEHOLDERS)

    def text(self, frame, bullets: bool):
        for paragraph in frame.paragraphs:
            text = clean_text("".join(run.text for run in paragraph.runs) or paragraph.text)
            if not text:
                continue
            if bullets or paragraph.level > 0:
                self.out.item(text)
            else:
                self.out.paragraph(text)

    def table(self, table):
        rows = [[cell.text for cell in row.cells] for row in table.rows]
        self.out.table(rows)

    def chart(self, chart):
        title = "Grafik"
        try:
            if chart.has_title and chart.chart_title.has_text_frame:
                title = clean_text(chart.chart_title.text_frame.text) or title
        except (AttributeError, ValueError):
            pass
        try:
            plot = chart.plots[0]
            categories = [str(c) for c in plot.categories]
            series = list(plot.series)
        except (IndexError, AttributeError, ValueError):
            self.out.paragraph(f"{title}.")
            return
        rows = [["Kategori", *[s.name or f"Seri {i + 1}" for i, s in enumerate(series)]]]
        for index, category in enumerate(categories):
            row = [category]
            for item in series:
                values = list(item.values)
                value = values[index] if index < len(values) else None
                row.append("" if value is None else f"{value:g}")
            rows.append(row)
        self.out.table(rows, title=title)


def convert_pptx(path: Path, title: str) -> Converted:
    try:
        presentation = Presentation(str(path))
    except (PackageNotFoundError, KeyError, ValueError) as error:
        raise ConversionError(
            "Presentasi PowerPoint tidak bisa dibaca. Pastikan file tidak rusak, "
            "lalu simpan ulang sebagai .pptx."
        ) from error
    builder = PageBuilder(title)
    reader = _SlideReader(builder)
    for number, slide in enumerate(presentation.slides, start=1):
        title_shape = slide.shapes.title
        slide_title = clean_text(title_shape.text) if title_shape is not None else ""
        # Satu slide selalu satu halaman, termasuk slide berjudul sama.
        builder.pages.append((slide_title or f"Slide {number}", []))
        reader.shapes(slide.shapes, title_shape)
        if slide.has_notes_slide:
            notes = slide.notes_slide.notes_text_frame
            lines = [clean_text(p.text) for p in notes.paragraphs] if notes else []
            lines = [line for line in lines if line]
            if lines:
                builder.subheading("Catatan pembicara")
                for line in lines:
                    builder.paragraph(line)
    converted = builder.build()
    if not converted.sections:
        raise ConversionError("Presentasi tidak berisi slide.")
    return require_content(converted)
