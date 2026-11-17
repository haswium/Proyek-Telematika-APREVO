"""Mengenali jenis file materi dari isinya (magic bytes), bukan dari nama.

Nama file hanya dipakai untuk dua hal: membedakan CSV dari teks biasa (isinya
sama-sama teks), dan menyebut format yang benar saat menolak format Office
lama. Kalau ekstensi dan isi tidak cocok, isi yang menang.
"""

import zipfile
from dataclasses import dataclass
from pathlib import Path

MB = 1024 * 1024

# Batas ukuran per jenis. Render gratis punya 512 MB RAM dan hanya satu
# konversi berjalan sekaligus, jadi batas ini menjaga puncak memori di bawah
# sekitar 200 MB.
MAX_BYTES = {
    "pdf": 20 * MB,
    "docx": 20 * MB,
    "pptx": 20 * MB,
    "xlsx": 10 * MB,
    "csv": 2 * MB,
    "txt": 2 * MB,
    "md": 2 * MB,
    "image": 10 * MB,
    "audio": 25 * MB,
}
# Batas saat menerima unggahan, sebelum jenisnya diketahui.
MAX_UPLOAD_BYTES = max(MAX_BYTES.values())
# Total isi ZIP (DOCX/PPTX/XLSX) setelah diekstrak, untuk menolak zip bomb.
MAX_UNZIPPED_BYTES = 150 * MB
MAX_AUDIO_SECONDS = 15 * 60

LABELS = {
    "pdf": "PDF",
    "docx": "Word (.docx)",
    "pptx": "PowerPoint (.pptx)",
    "xlsx": "Excel (.xlsx)",
    "csv": "CSV",
    "txt": "teks (.txt)",
    "md": "Markdown (.md)",
    "image": "gambar",
    "audio": "audio",
}

# Format yang didukung, untuk pesan error dan teks bantuan.
SUPPORTED_TEXT = (
    "PDF, Word (.docx), PowerPoint (.pptx), Excel (.xlsx), CSV, teks (.txt, "
    ".md), gambar (.jpg, .png), dan audio (.mp3, .m4a, .wav, .ogg)"
)

OLD_OFFICE = {
    ".doc": ".docx",
    ".ppt": ".pptx",
    ".pps": ".pptx",
    ".xls": ".xlsx",
}


class UnsupportedFile(ValueError):
    """File ditolak. Pesannya langsung ditampilkan ke guru."""

    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


@dataclass(frozen=True)
class DetectedFile:
    kind: str  # kunci di MAX_BYTES
    content_type: str
    extension: str  # untuk nama file di Storage, tanpa titik


def _zip_kind(path: Path) -> str:
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            names = {info.filename for info in infos}
            total = sum(info.file_size for info in infos)
    except zipfile.BadZipFile:
        raise UnsupportedFile("File rusak atau bukan dokumen yang bisa dibaca.")
    if total > MAX_UNZIPPED_BYTES:
        raise UnsupportedFile(
            "Isi dokumen terlalu besar untuk diproses. Pecah menjadi beberapa "
            "file lalu unggah lagi.",
            413,
        )
    if "word/document.xml" in names:
        return "docx"
    if "ppt/presentation.xml" in names:
        return "pptx"
    if "xl/workbook.xml" in names:
        return "xlsx"
    raise UnsupportedFile(f"Jenis file tidak didukung. Gunakan {SUPPORTED_TEXT}.")


def _is_mp3(head: bytes) -> bool:
    if head.startswith(b"ID3"):
        return True
    # Frame MPEG audio: 11 bit sinkron, lalu layer III.
    return len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xE6) == 0xE2


def _is_text(head: bytes) -> bool:
    if b"\x00" in head:
        return False
    try:
        head.decode("utf-8")
        return True
    except UnicodeDecodeError as error:
        # Karakter multibyte terpotong di ujung potongan awal masih teks.
        return error.start >= len(head) - 3


def _old_office_message(filename: str) -> str:
    suffix = Path(filename or "").suffix.lower()
    target = OLD_OFFICE.get(suffix)
    if target:
        return f"Format {suffix} lama tidak didukung. Simpan ulang sebagai {target} lalu unggah lagi."
    return (
        "Format Office lama tidak didukung. Simpan ulang sebagai .pptx/.docx/"
        ".xlsx lalu unggah lagi."
    )


def detect(path: Path, filename: str) -> DetectedFile:
    """Jenis file di [path]. Melempar UnsupportedFile kalau tidak didukung."""
    with open(path, "rb") as handle:
        head = handle.read(4096)
    if not head:
        raise UnsupportedFile("File kosong.")
    suffix = Path(filename or "").suffix.lower()

    if head.startswith(b"%PDF-"):
        return DetectedFile("pdf", "application/pdf", "pdf")
    if head.startswith(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"):
        raise UnsupportedFile(_old_office_message(filename))
    if head.startswith(b"PK\x03\x04"):
        kind = _zip_kind(path)
        return {
            "docx": DetectedFile(
                "docx",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "docx",
            ),
            "pptx": DetectedFile(
                "pptx",
                "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                "pptx",
            ),
            "xlsx": DetectedFile(
                "xlsx",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "xlsx",
            ),
        }[kind]
    if head.startswith(b"\xff\xd8\xff"):
        return DetectedFile("image", "image/jpeg", "jpg")
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return DetectedFile("image", "image/png", "png")
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return DetectedFile("audio", "audio/wav", "wav")
    if head.startswith(b"OggS"):
        return DetectedFile("audio", "audio/ogg", "ogg")
    if head[4:8] == b"ftyp":
        brand = head[8:12]
        # M4A/M4B pasti audio. isom/mp42/mp41 juga dipakai video MP4, jadi
        # hanya diterima kalau namanya memang .m4a.
        if brand in (b"M4A ", b"M4B ") or (
            brand in (b"mp42", b"isom", b"mp41", b"dash") and suffix == ".m4a"
        ):
            return DetectedFile("audio", "audio/mp4", "m4a")
        raise UnsupportedFile("File video tidak didukung. Unggah audionya saja (.m4a atau .mp3).")
    if _is_mp3(head):
        return DetectedFile("audio", "audio/mpeg", "mp3")
    if _is_text(head):
        if suffix == ".csv":
            return DetectedFile("csv", "text/csv", "csv")
        if suffix in (".md", ".markdown"):
            return DetectedFile("md", "text/markdown", "md")
        return DetectedFile("txt", "text/plain", "txt")
    if suffix in OLD_OFFICE:
        raise UnsupportedFile(_old_office_message(filename))
    raise UnsupportedFile(f"Jenis file tidak didukung. Gunakan {SUPPORTED_TEXT}.")


def check_size(detected: DetectedFile, size: int) -> None:
    limit = MAX_BYTES[detected.kind]
    if size > limit:
        raise UnsupportedFile(
            f"Ukuran file {LABELS[detected.kind]} maksimal {limit // MB} MB.",
            413,
        )
