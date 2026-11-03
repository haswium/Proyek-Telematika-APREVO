"""Kesiapan deploy ke Render."""

import re
from pathlib import Path

import main

ROOT = Path(__file__).resolve().parent.parent.parent


def test_health_tanpa_login_dan_tanpa_database(client, monkeypatch):
    def no_database(*_args):
        raise AssertionError("Health check tidak boleh menyentuh database")

    monkeypatch.setattr(main.supabase_admin, "table", no_database, raising=False)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_endpoint_debug_mati_di_render_walau_diisi_1(monkeypatch):
    monkeypatch.setenv("ENABLE_DEBUG_ENDPOINTS", "1")
    monkeypatch.setenv("RENDER", "true")
    assert main.debug_endpoints_enabled() is False


def test_endpoint_debug_bisa_dinyalakan_di_luar_render(monkeypatch):
    monkeypatch.setenv("ENABLE_DEBUG_ENDPOINTS", "1")
    monkeypatch.delenv("RENDER", raising=False)
    assert main.debug_endpoints_enabled() is True


def test_endpoint_debug_mati_secara_bawaan(monkeypatch):
    monkeypatch.delenv("ENABLE_DEBUG_ENDPOINTS", raising=False)
    monkeypatch.delenv("RENDER", raising=False)
    assert main.debug_endpoints_enabled() is False


def render_yaml():
    return (ROOT / "render.yaml").read_text(encoding="utf-8")


def test_render_yaml_sesuai_kebutuhan():
    text = render_yaml()
    assert "rootDir: backend" in text
    assert "startCommand: uvicorn main:app --host 0.0.0.0 --port $PORT" in text
    assert "healthCheckPath: /health" in text
    assert re.search(r'key: ENABLE_DEBUG_ENDPOINTS\s+value: "0"', text)


def test_rahasia_tidak_ditulis_di_render_yaml():
    text = render_yaml()
    for name in (
        "SUPABASE_URL",
        "SUPABASE_KEY",
        "SUPABASE_SERVICE_KEY",
        "GEMINI_API_KEY",
    ):
        assert re.search(rf"key: {name}\s+sync: false", text), name


def test_variabel_yang_dibaca_kode_tercatat_di_panduan():
    guide = (ROOT / "docs" / "deploy.md").read_text(encoding="utf-8")
    backend = ROOT / "backend"
    names = set()
    for path in (backend / "main.py", backend / "ai_client.py"):
        names |= set(
            re.findall(r'os\.getenv\(\s*"([A-Z_]+)"', path.read_text(encoding="utf-8"))
        )
    assert "SUPABASE_SERVICE_KEY" in names
    missing = [name for name in sorted(names) if f"`{name}`" not in guide]
    assert missing == []


def test_file_rahasia_diabaikan_git():
    root = (ROOT / ".gitignore").read_text(encoding="utf-8")
    backend = (ROOT / "backend" / ".gitignore").read_text(encoding="utf-8")
    assert ".env" in backend.splitlines()
    for pattern in ("key.properties", "*.jks", "*.keystore"):
        assert pattern in root.splitlines(), pattern
