"""XLSX (openpyxl) dan CSV ke halaman materi.

Satu sheet satu halaman berjudul nama sheet (CSV: judul materi). Isinya satu
tabel dengan baris pertama yang berisi sebagai nama kolom, jadi siswa
mendengar "Baris 1. Nama: Andi. Nilai: 80." per baris.

XLSX dibuka read_only (baris dibaca bertahap, hemat memori) dan data_only
(nilai hasil rumus yang tersimpan, bukan rumusnya). Sheet tersembunyi dan
kosong dilewati. Tabel dipotong di MAX_TABLE_ROWS baris dan MAX_TABLE_COLUMNS
kolom, dengan keterangan.
"""

import csv
import io
import zipfile
from datetime import date, datetime, time
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils.exceptions import InvalidFileException

from converters import (
    MAX_TABLE_COLUMNS,
    MAX_TABLE_ROWS,
    ConversionError,
    Converted,
    PageBuilder,
    require_content,
)

MONTHS = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni",
    "Juli", "Agustus", "September", "Oktober", "November", "Desember",
]


def cell_text(value) -> str:
    """Nilai sel sebagai teks yang enak dibaca TalkBack."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "Ya" if value else "Tidak"
    if isinstance(value, float):
        # Koma desimal, seperti kebiasaan di Indonesia: "7,5".
        return str(int(value)) if value.is_integer() else f"{value:g}".replace(".", ",")
    if isinstance(value, datetime):
        text = f"{value.day} {MONTHS[value.month - 1]} {value.year}"
        if value.time() != time(0, 0):
            text += f" pukul {value:%H.%M}"
        return text
    if isinstance(value, date):
        return f"{value.day} {MONTHS[value.month - 1]} {value.year}"
    if isinstance(value, time):
        return f"{value:%H.%M}"
    return str(value)


def _add_sheet(builder: PageBuilder, title: str, rows_iter) -> bool:
    """Menambah satu halaman tabel. False kalau sheet kosong."""
    rows, total, too_wide = [], 0, False
    for raw in rows_iter:
        values = [cell_text(value) for value in raw]
        if not any(value.strip() for value in values):
            continue
        total += 1
        if len(values) > MAX_TABLE_COLUMNS and any(v.strip() for v in values[MAX_TABLE_COLUMNS:]):
            too_wide = True
        # Satu baris nama kolom ditambah MAX_TABLE_ROWS baris isi.
        if len(rows) <= MAX_TABLE_ROWS:
            rows.append(values[:MAX_TABLE_COLUMNS])
    if not rows:
        return False
    builder.new_page(title)
    body_total = total - 1
    if body_total > MAX_TABLE_ROWS:
        builder.paragraph(
            f"Tabel ini dipotong: menampilkan {MAX_TABLE_ROWS} dari {body_total} baris."
        )
    if too_wide:
        builder.paragraph(f"Hanya {MAX_TABLE_COLUMNS} kolom pertama yang ditampilkan.")
    builder.table(rows, title=title)
    return True


def convert_xlsx(path: Path, title: str) -> Converted:
    builder = PageBuilder(title)
    # File object, bukan path: openpyxl menolak nama file yang tidak berakhiran
    # .xlsx, sedangkan file sementara unggahan berakhiran .upload. Mode
    # read_only membaca baris bertahap selama file terbuka.
    with open(path, "rb") as handle:
        try:
            workbook = load_workbook(handle, read_only=True, data_only=True)
        except (zipfile.BadZipFile, InvalidFileException, KeyError, ValueError, OSError) as error:
            raise ConversionError(
                "File Excel tidak bisa dibaca. Pastikan file tidak rusak, lalu "
                "simpan ulang sebagai .xlsx."
            ) from error
        try:
            for sheet in workbook.worksheets:
                if getattr(sheet, "sheet_state", "visible") != "visible":
                    continue
                _add_sheet(builder, sheet.title, sheet.iter_rows(values_only=True))
        finally:
            workbook.close()
    return require_content(builder.build())


def read_text_file(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def convert_csv(path: Path, title: str) -> Converted:
    text = read_text_file(path)
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t|")
    except csv.Error:
        dialect = csv.excel
    reader = csv.reader(io.StringIO(text), dialect)
    builder = PageBuilder(title)
    if not _add_sheet(builder, title.strip() or "Tabel", reader):
        raise ConversionError("File CSV kosong.")
    return require_content(builder.build())
