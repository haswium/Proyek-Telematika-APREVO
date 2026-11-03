"""Akun Google memilih peran sekali lewat POST /me/role."""

from types import SimpleNamespace
from uuid import uuid4

import main


def sign_in(metadata=None, email="budi@gmail.com"):
    user_id = str(uuid4())
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": SimpleNamespace(id=user_id, user_metadata=metadata, email=email),
        "access_token": "token",
    }
    return user_id


def rows_of(fake_db, user_id):
    return [row for row in fake_db.get("users", []) if row["id"] == user_id]


def test_akun_baru_tersimpan_dengan_nama_google(client, fake_db):
    user_id = sign_in({"full_name": "Budi Santoso"})

    response = client.post("/me/role", json={"role": "teacher"})

    assert response.status_code == 200, response.text
    assert response.json() == {"name": "Budi Santoso", "role": "teacher"}
    assert rows_of(fake_db, user_id)[0]["role"] == "teacher"


def test_nama_kosong_memakai_bagian_depan_email(client, fake_db):
    sign_in({"name": "  "})

    assert client.post("/me/role", json={"role": "student"}).json() == {
        "name": "budi",
        "role": "student",
    }


def test_peran_tidak_bisa_diganti(client, fake_db):
    user_id = sign_in({"name": "Budi"})
    client.post("/me/role", json={"role": "student"})

    response = client.post("/me/role", json={"role": "teacher"})

    assert response.status_code == 200, response.text
    assert response.json()["role"] == "student"
    assert [row["role"] for row in rows_of(fake_db, user_id)] == ["student"]


def test_peran_tidak_berubah_walau_metadata_diubah_pengguna(client, fake_db):
    user_id = sign_in({"name": "Budi", "role": "teacher"})
    fake_db.setdefault("users", []).append(
        {"id": user_id, "name": "Budi", "role": "student"}
    )

    assert client.post("/me/role", json={"role": "teacher"}).json()["role"] == "student"


def test_dua_permintaan_bersamaan_memakai_peran_yang_tersimpan(
    client, fake_db, monkeypatch
):
    user_id = sign_in({"name": "Budi"})
    real_read = main.read_profile
    calls = []

    def read_after_other_request(wanted_id):
        calls.append(wanted_id)
        result = real_read(wanted_id)
        if len(calls) == 1:
            fake_db.setdefault("users", []).append(
                {"id": user_id, "name": "Budi", "role": "student"}
            )
        return result

    monkeypatch.setattr(main, "read_profile", read_after_other_request)

    response = client.post("/me/role", json={"role": "teacher"})

    assert response.status_code == 200, response.text
    assert response.json()["role"] == "student"
    assert len(rows_of(fake_db, user_id)) == 1


def test_peran_lain_ditolak(client, fake_db):
    sign_in({"name": "Budi"})

    assert client.post("/me/role", json={"role": "admin"}).status_code == 422


def test_akun_tanpa_peran_belum_bisa_memakai_endpoint_guru(client, fake_db):
    sign_in({"name": "Budi"})

    assert client.get("/teacher/subjects").status_code == 403


def test_perlu_login(client, fake_db):
    assert client.post("/me/role", json={"role": "student"}).status_code in (401, 403)
