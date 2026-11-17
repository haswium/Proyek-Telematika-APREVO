"""Gemini untuk foto (membaca teks dan mendeskripsikan gambar) dan audio
(transkrip). Modelnya sama dengan fitur AI lain (`gemini_model`).

Audio tidak pernah dimuat utuh ke memori atau dikirim inline: file diunggah
dari disk lewat Files API Gemini, dirujuk di prompt, lalu dihapus dari Gemini
setelah selesai (berhasil maupun gagal).
"""

import json
import logging
import time
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

from PIL import Image

from ai_client import gemini_client, gemini_model

logger = logging.getLogger(__name__)

# Gemini memproses file audio dulu sebelum bisa dirujuk.
FILE_READY_TIMEOUT_SECONDS = 180
FILE_POLL_SECONDS = 2

PHOTO_PROMPT = """Ini foto materi pelajaran, misalnya halaman buku, lembar kerja, atau
papan tulis. Hasilnya dibacakan screen reader untuk siswa tunanetra.

Kembalikan JSON dengan kunci:
- "title": judul yang tertulis di foto, atau judul singkat yang menggambarkan isinya
  (maksimal 8 kata).
- "lines": daftar baris teks yang tertulis di foto, urut seperti dibaca (atas ke bawah,
  kiri ke kanan). Satu paragraf satu baris. Subjudul diawali "## ". Butir daftar diawali
  "- ". Tulis persis seperti di foto, perbaiki hanya huruf yang jelas salah baca.
  Kosongkan kalau tidak ada tulisan.
- "description": deskripsi bagian visual yang penting untuk pelajaran (gambar, diagram,
  grafik, tabel, rumus yang digambar), singkat dan jelas, dalam bahasa Indonesia, tanpa
  menyebut warna. Jangan mengulang teks yang sudah ada di "lines". Isi "" kalau fotonya
  hanya tulisan.
"""

AUDIO_PROMPT = """Buat transkrip lengkap rekaman ini untuk siswa tunanetra yang
membacanya dengan screen reader.

- Tulis kata demi kata dalam bahasa aslinya. Jangan meringkas, jangan menerjemahkan.
- Pisahkan paragraf dengan satu baris kosong setiap kali topik atau pembicara berganti.
- Kalau ada lebih dari satu pembicara, awali paragraf dengan "Pembicara 1:",
  "Pembicara 2:", dan seterusnya. Kalau hanya satu, jangan diberi label.
- Tanpa cap waktu, tanpa catatan tambahan, tanpa judul.
- Bunyi penting yang bukan ucapan boleh ditulis dalam kurung, misalnya (tepuk tangan).
- Kalau rekamannya tidak berisi ucapan, tulis persis: (tidak ada ucapan)
"""


@dataclass
class PhotoReading:
    title: str
    lines: list[str]
    description: str


def _image_for_gemini(image_bytes: bytes):
    with Image.open(BytesIO(image_bytes)) as image:
        image.load()
        copy = image.convert("RGB") if image.mode not in ("RGB", "L") else image.copy()
    copy.thumbnail((2000, 2000))
    return copy


def read_photo(image_bytes: bytes) -> PhotoReading:
    """Teks di foto dan deskripsi bagian visualnya."""
    response = gemini_client().models.generate_content(
        model=gemini_model(),
        contents=[PHOTO_PROMPT, _image_for_gemini(image_bytes)],
        config={"response_mime_type": "application/json"},
    )
    try:
        data = json.loads(response.text or "")
    except json.JSONDecodeError as error:
        raise ValueError("Jawaban Gemini untuk foto bukan JSON") from error
    if not isinstance(data, dict):
        raise ValueError("Jawaban Gemini untuk foto tidak sesuai format")
    lines = data.get("lines") or []
    if not isinstance(lines, list):
        lines = [str(lines)]
    return PhotoReading(
        title=str(data.get("title") or "").strip(),
        lines=[str(line).strip() for line in lines if str(line).strip()],
        description=str(data.get("description") or "").strip(),
    )


def _wait_until_active(client, uploaded):
    deadline = time.monotonic() + FILE_READY_TIMEOUT_SECONDS
    current = uploaded
    while True:
        state = getattr(getattr(current, "state", None), "name", None) or str(
            getattr(current, "state", "")
        )
        if state in ("ACTIVE", "", "None", "STATE_UNSPECIFIED"):
            return current
        if state == "FAILED":
            raise ValueError("Gemini gagal memproses file audio")
        if time.monotonic() > deadline:
            raise TimeoutError("Gemini terlalu lama memproses file audio")
        time.sleep(FILE_POLL_SECONDS)
        current = client.files.get(name=uploaded.name)


def transcribe_audio(path: Path, mime_type: str) -> str:
    """Transkrip audio di [path]. File di Gemini selalu dihapus setelahnya."""
    client = gemini_client()
    uploaded = client.files.upload(
        file=str(path),
        config={"mime_type": mime_type, "display_name": "aprevo-audio"},
    )
    try:
        ready = _wait_until_active(client, uploaded)
        response = client.models.generate_content(
            model=gemini_model(),
            contents=[ready, AUDIO_PROMPT],
        )
        text = (response.text or "").strip()
        if not text:
            raise ValueError("Gemini tidak menghasilkan transkrip")
        return text
    finally:
        try:
            client.files.delete(name=uploaded.name)
        except Exception:
            # Gemini juga menghapus file sendiri setelah 48 jam.
            logger.warning("File audio %s gagal dihapus dari Gemini", uploaded.name)
