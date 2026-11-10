"""Verifikasi token dan pemeriksaan variabel Supabase.

Di Render, token yang diterima backend lokal ditolak dengan "Token tidak valid".
Penyebabnya variabel lingkungan, tetapi dulu semua error ditelan menjadi 401
yang sama. Tes ini menjaga supaya salah konfigurasi terlihat (log dan
/health/config) tanpa membocorkan token atau kunci.
"""

import base64
import json
import logging
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from supabase_auth.errors import AuthApiError

import main

URL = "https://abcdproject.supabase.co"
TOKEN = "eyJhbGciOiJFUzI1NiJ9.rahasia-token-siswa.tandatangan"


def fake_key(role, ref="abcdproject"):
    def part(data):
        raw = base64.urlsafe_b64encode(json.dumps(data).encode()).decode()
        return raw.rstrip("=")

    return f"{part({'alg': 'HS256'})}.{part({'role': role, 'ref': ref})}.sig"


ANON = fake_key("anon")
SERVICE = fake_key("service_role")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("  nilai \n", "nilai"),
        ('"nilai"', "nilai"),
        ("'nilai' ", "nilai"),
        ("", None),
        ("   ", None),
    ],
)
def test_env_value_membersihkan_salinan_dashboard(monkeypatch, raw, expected):
    monkeypatch.setenv("CONTOH_VAR", raw)
    assert main.env_value("CONTOH_VAR") == expected


def test_env_value_tanpa_variabel(monkeypatch):
    monkeypatch.delenv("CONTOH_VAR", raising=False)
    assert main.env_value("CONTOH_VAR") is None


def test_konfigurasi_benar_tanpa_masalah():
    assert main.supabase_config_problems(URL, ANON, SERVICE) == []
    # Format kunci baru Supabase juga diterima.
    assert (
        main.supabase_config_problems(URL, "sb_publishable_x", "sb_secret_y") == []
    )


@pytest.mark.parametrize(
    ("url", "key", "service", "problem"),
    [
        (None, ANON, SERVICE, "SUPABASE_URL kosong"),
        ("http://abcdproject.supabase.co", ANON, SERVICE, "harus diawali https://"),
        ("https://contoh.com", ANON, SERVICE, "bukan alamat proyek"),
        (URL, None, SERVICE, "SUPABASE_KEY kosong"),
        (URL, SERVICE, SERVICE, "SUPABASE_KEY adalah kunci service_role"),
        (URL, fake_key("anon", "proyeklain"), SERVICE, "SUPABASE_KEY milik proyek"),
        (URL, "bukan-kunci", SERVICE, "SUPABASE_KEY bukan kunci Supabase"),
        (URL, ANON, ANON, "SUPABASE_SERVICE_KEY adalah kunci anon"),
        (URL, ANON, None, "SUPABASE_SERVICE_KEY kosong"),
    ],
)
def test_masalah_konfigurasi_disebut_tanpa_nilai(url, key, service, problem):
    problems = main.supabase_config_problems(url, key, service)
    assert any(problem in item for item in problems), problems
    for item in problems:
        for secret in (ANON, SERVICE):
            assert secret not in item


def test_health_config(client, monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_CONFIG_PROBLEMS", [])
    assert client.get("/health/config").json() == {"ok": True, "problems": []}
    monkeypatch.setattr(main, "SUPABASE_CONFIG_PROBLEMS", ["SUPABASE_KEY kosong"])
    assert client.get("/health/config").json() == {
        "ok": False,
        "problems": ["SUPABASE_KEY kosong"],
    }


class FakeAuth:
    def __init__(self, result):
        self.result = result

    def get_user(self, token):
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


@pytest.fixture
def verify(monkeypatch):
    """verify(hasil get_user) memanggil get_current_user dengan token uji."""
    monkeypatch.setattr(main, "SUPABASE_URL", URL)
    monkeypatch.setattr(main, "SUPABASE_KEY", ANON)

    def _verify(result):
        monkeypatch.setattr(main, "supabase", SimpleNamespace(auth=FakeAuth(result)))
        return main.get_current_user(
            HTTPAuthorizationCredentials(scheme="Bearer", credentials=TOKEN)
        )

    return _verify


def status_of(verify, result):
    with pytest.raises(HTTPException) as caught:
        verify(result)
    return caught.value.status_code, caught.value.detail


def test_token_benar(verify):
    user = SimpleNamespace(id="u1")
    assert verify(SimpleNamespace(user=user)) == {"user": user, "access_token": TOKEN}


def test_token_ditolak_supabase_401_dan_alasan_dicatat(verify, caplog):
    error = AuthApiError(
        f"invalid JWT: unable to parse or verify signature {TOKEN}", 403, "bad_jwt"
    )
    with caplog.at_level(logging.WARNING, logger="main"):
        assert status_of(verify, error) == (401, main.TOKEN_INVALID)
    assert "bad_jwt" in caplog.text
    assert "unable to parse or verify signature" in caplog.text
    # Token tidak pernah masuk log.
    assert TOKEN not in caplog.text
    assert "rahasia-token-siswa" not in caplog.text


def test_user_kosong_401(verify, caplog):
    with caplog.at_level(logging.WARNING, logger="main"):
        assert status_of(verify, SimpleNamespace(user=None)) == (
            401,
            main.TOKEN_INVALID,
        )
    assert "tidak mengembalikan user" in caplog.text


def test_kunci_anon_salah_503_bukan_401(verify, caplog):
    error = AuthApiError("Invalid API key", 401, "no_api_key")
    with caplog.at_level(logging.WARNING, logger="main"):
        assert status_of(verify, error) == (503, main.AUTH_MISCONFIGURED)
    assert "SUPABASE_KEY ditolak" in caplog.text


def test_supabase_error_server_503(verify):
    error = AuthApiError("internal", 500, None)
    assert status_of(verify, error) == (503, main.AUTH_UNAVAILABLE)


def test_supabase_tidak_bisa_dihubungi_503(verify, caplog):
    with caplog.at_level(logging.WARNING, logger="main"):
        assert status_of(verify, ConnectionError("nama host tidak dikenal")) == (
            503,
            main.AUTH_UNAVAILABLE,
        )
    assert "ConnectionError" in caplog.text


def test_variabel_kosong_503_tanpa_memanggil_supabase(monkeypatch, caplog):
    monkeypatch.setattr(main, "SUPABASE_KEY", None)
    monkeypatch.setattr(
        main, "supabase", SimpleNamespace(auth=FakeAuth(AssertionError("dipanggil")))
    )
    with caplog.at_level(logging.ERROR, logger="main"):
        with pytest.raises(HTTPException) as caught:
            main.get_current_user(
                HTTPAuthorizationCredentials(scheme="Bearer", credentials=TOKEN)
            )
    assert caught.value.status_code == 503
    assert "tidak bisa dijalankan" in caplog.text


def test_lewat_endpoint_kunci_salah_dijawab_json_503(client, monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_URL", URL)
    monkeypatch.setattr(main, "SUPABASE_KEY", ANON)
    monkeypatch.setattr(
        main,
        "supabase",
        SimpleNamespace(auth=FakeAuth(AuthApiError("Invalid API key", 401, None))),
    )
    response = client.get(
        "/teacher/subjects", headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert response.status_code == 503
    assert response.headers["content-type"].startswith("application/json")
    assert response.json()["detail"] == main.AUTH_MISCONFIGURED
