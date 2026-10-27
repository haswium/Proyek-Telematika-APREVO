"""Klien Gemini bersama untuk ai_quiz dan ai_image.

Kunci GEMINI_API_KEY baru diperiksa saat fungsi AI dipanggil, bukan saat
modul diimpor. Jadi backend tetap menyala tanpa kunci, dan hanya endpoint AI
yang menolak dengan pesan jelas.
"""

import os

from dotenv import load_dotenv
from google import genai

load_dotenv()


class GeminiKeyMissing(RuntimeError):
    """GEMINI_API_KEY belum diatur di backend/.env."""


_client = None
_client_key = None


def gemini_client() -> genai.Client:
    global _client, _client_key
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise GeminiKeyMissing("GEMINI_API_KEY belum diatur di backend/.env")
    if _client is None or _client_key != api_key:
        _client = genai.Client(api_key=api_key)
        _client_key = api_key
    return _client
