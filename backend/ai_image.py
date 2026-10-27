from io import BytesIO
import os
from dotenv import load_dotenv
from google import genai
from PIL import Image

load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    raise RuntimeError("GEMINI_API_KEY belum ditemukan di .env")

client = genai.Client(api_key=api_key)


def describe_image(image_bytes: bytes) -> str:
    """Menghasilkan deskripsi gambar yang sesuai untuk siswa tunanetra."""
    with Image.open(BytesIO(image_bytes)) as image:
        image.load()
        response = client.models.generate_content(
            model="gemini-3.5-flash-lite",
            contents=[
                (
                    "Deskripsikan gambar ini secara ringkas, langsung pada informasi penting pada gambar, tanpa bertele-tele untuk siswa maupun guru tunanetra mendengarkan melalui audio. Jangan menyebutkan warna atau elemen visual lain yang tidak dapat dirasakan atau didengar oleh tunanetra! Jelaskan pula hubungan antarelemen pada gambar yang penting dalam gambar ini. Untuk foto, ilustrasi, atau situasi, deskripsikan secara naratif, sehingga seolah pengguna sedang mendengarkan cerita, jelaskan objek dan posisinya, aktivitas atau hubungan yang ada pada gambar. Untuk grafik, tabel, atau diagram data, jelaskan secara tersturktur, baik pada sumbu, nilai, tren, dan perbandingannya."
                ),
                image.copy(),
            ],
        )

    description = (response.text or "").strip()
    if not description:
        raise ValueError("Gemini tidak menghasilkan deskripsi gambar.")

    return description
