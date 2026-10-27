import os
import subprocess
import sys
from pathlib import Path

import pytest

import main
from ai_client import GeminiKeyMissing, gemini_client
from test_endpoints import setup_subject

BACKEND = Path(__file__).resolve().parent.parent


def test_backend_tetap_menyala_tanpa_kunci_gemini():
    # Kunci kosong yang sudah ada di lingkungan tidak ditimpa oleh .env.
    env = {
        **os.environ,
        "GEMINI_API_KEY": "",
        "SUPABASE_URL": "http://localhost:54321",
        "SUPABASE_KEY": "test-anon-key",
        "SUPABASE_SERVICE_KEY": "test-service-key",
    }
    result = subprocess.run(
        [sys.executable, "-c", "import main"],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_kunci_baru_dicek_saat_fungsi_ai_dipanggil(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "")
    with pytest.raises(GeminiKeyMissing):
        gemini_client()


@pytest.mark.parametrize(
    "path, body",
    [
        (
            "/teacher/materials/m1/generate-quiz",
            {"total_questions": 1, "quiz_type": "true_false"},
        ),
        ("/teacher/materials/m1/generate-image-description", None),
    ],
)
def test_endpoint_ai_menjelaskan_kunci_belum_diatur(
    client, login, fake_db, monkeypatch, path, body
):
    setup_subject(client, login, fake_db)
    monkeypatch.setenv("GEMINI_API_KEY", "")
    response = client.post(path, json=body)
    assert response.status_code == 503
    assert response.json()["detail"] == main.GEMINI_KEY_MISSING_DETAIL
    assert "GEMINI_API_KEY" in response.json()["detail"]
