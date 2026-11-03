"""Daftar anggota kelas dan mengeluarkan siswa."""

from types import SimpleNamespace

import pytest

import main
from test_endpoints import iso, setup_subject


class FakeAdmin:
    """Supabase Auth tiruan: email tiap siswa, atau error kalau tidak ada."""

    def __init__(self, emails):
        self.emails = emails

    def get_user_by_id(self, user_id):
        if user_id not in self.emails:
            raise RuntimeError("Auth gagal")
        return SimpleNamespace(user=SimpleNamespace(email=self.emails[user_id]))


@pytest.fixture
def kelas(client, login, fake_db, monkeypatch):
    """Kelas dengan tiga siswa. Yang aktif sesudahnya: akun guru pemilik."""
    teacher_id, subject, material = setup_subject(client, login, fake_db)
    owner = main.app.dependency_overrides[main.get_current_user]
    students = {}
    for name in ("Citra", "andi", "Budi"):
        student_id = login("student", name)
        students[name] = student_id
        fake_db.setdefault("subject_students", []).append(
            {
                "subject_id": subject["id"],
                "student_id": student_id,
                "joined_at": "2026-11-03T02:00:00+00:00",
            }
        )
    admin = FakeAdmin(
        {
            students["Citra"]: "citra@contoh.test",
            students["andi"]: "andi@contoh.test",
        }
    )
    monkeypatch.setattr(
        main.supabase_admin, "auth", SimpleNamespace(admin=admin), raising=False
    )
    main.app.dependency_overrides[main.get_current_user] = owner
    return SimpleNamespace(
        id=subject["id"],
        material=material,
        students=students,
        owner=owner,
        act_as=lambda name: main.app.dependency_overrides.__setitem__(
            main.get_current_user,
            lambda: {
                "user": SimpleNamespace(id=students[name]),
                "access_token": "token",
            },
        ),
    )


def members_url(kelas):
    return f"/teacher/subjects/{kelas.id}/members"


def test_guru_melihat_daftar_urut_nama_dengan_email(client, kelas):
    response = client.get(members_url(kelas))
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["student_count"] == 3
    assert [s["name"] for s in data["students"]] == ["andi", "Budi", "Citra"]
    assert data["students"][0] == {
        "id": kelas.students["andi"],
        "name": "andi",
        "email": "andi@contoh.test",
        "joined_at": "2026-11-03T02:00:00+00:00",
    }


def test_email_gagal_diambil_daftar_tetap_tampil(client, kelas):
    data = client.get(members_url(kelas)).json()
    budi = next(s for s in data["students"] if s["name"] == "Budi")
    assert budi["email"] is None


def test_kelas_kosong(client, login, fake_db):
    _, subject, _ = setup_subject(client, login, fake_db)
    data = client.get(f"/teacher/subjects/{subject['id']}/members").json()
    assert data["student_count"] == 0
    assert data["students"] == []


def test_guru_lain_tidak_bisa_melihat_atau_mengeluarkan(client, kelas, login, fake_db):
    login("teacher", "Guru Lain")
    assert client.get(members_url(kelas)).status_code == 404
    response = client.delete(f"{members_url(kelas)}/{kelas.students['Budi']}")
    assert response.status_code == 404
    assert len(fake_db["subject_students"]) == 3


def test_siswa_tidak_bisa_memakai_endpoint_guru(client, kelas, fake_db):
    kelas.act_as("Budi")
    assert client.get(members_url(kelas)).status_code == 403
    response = client.delete(f"{members_url(kelas)}/{kelas.students['andi']}")
    assert response.status_code == 403
    assert len(fake_db["subject_students"]) == 3


def test_tanpa_login_ditolak(client, kelas):
    main.app.dependency_overrides.pop(main.get_current_user)
    assert client.get(members_url(kelas)).status_code in (401, 403)
    response = client.delete(f"{members_url(kelas)}/{kelas.students['andi']}")
    assert response.status_code in (401, 403)


def test_mengeluarkan_siswa_mencabut_semua_akses_tetapi_nilai_tetap(
    client, kelas, fake_db
):
    budi = kelas.students["Budi"]
    fake_db["material_access"] = [
        {"id": "a1", "material_id": "m1", "student_id": budi},
        {"id": "a2", "material_id": "lain", "student_id": budi},
        {"id": "a3", "material_id": "m1", "student_id": kelas.students["andi"]},
    ]
    fake_db["quiz_attempts"] = [
        {"id": "n1", "quiz_id": "q1", "student_id": budi, "correct_count": 3}
    ]

    response = client.delete(f"{members_url(kelas)}/{budi}")
    assert response.status_code == 200, response.text
    assert response.json()["student_count"] == 2
    assert budi not in [r["student_id"] for r in fake_db["subject_students"]]
    # Akses materi kelas ini dicabut; akses materi lain dan siswa lain tetap.
    assert [r["id"] for r in fake_db["material_access"]] == ["a2", "a3"]
    assert fake_db["quiz_attempts"][0]["correct_count"] == 3

    kelas.act_as("Budi")
    assert client.get(f"/student/subjects/{kelas.id}/materials").status_code == 403
    assert client.get("/materials/m1/sections").status_code == 403


def test_mengeluarkan_dua_kali_atau_bukan_anggota(client, kelas, login):
    budi = kelas.students["Budi"]
    assert client.delete(f"{members_url(kelas)}/{budi}").status_code == 200
    response = client.delete(f"{members_url(kelas)}/{budi}")
    assert response.status_code == 404
    assert response.json()["detail"] == "Siswa bukan anggota kelas ini"


def test_siswa_yang_dikeluarkan_bisa_bergabung_lagi(client, kelas, fake_db):
    budi = kelas.students["Budi"]
    code = fake_db["subjects"][0]["access_code"]
    client.delete(f"{members_url(kelas)}/{budi}")
    kelas.act_as("Budi")
    response = client.post("/student/subjects/join", json={"code": code})
    assert response.status_code == 200, response.text
    assert response.json()["already_joined"] is False
    assert client.get(f"/student/subjects/{kelas.id}/materials").status_code == 200


def test_siswa_melihat_guru_dan_nama_teman_saja(client, kelas):
    kelas.act_as("Budi")
    response = client.get(f"/student/subjects/{kelas.id}/members")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["teacher_name"] == "Bu Rina"
    assert data["student_count"] == 3
    assert data["classmates"] == [
        {"name": "andi", "is_me": False},
        {"name": "Budi", "is_me": True},
        {"name": "Citra", "is_me": False},
    ]
    # Tidak boleh ada data pribadi di mana pun dalam respons.
    assert "email" not in response.text
    assert "contoh.test" not in response.text
    assert "joined_at" not in response.text
    assert kelas.students["andi"] not in response.text


def test_bukan_anggota_tidak_bisa_melihat_teman(client, kelas, login):
    login("student", "Orang Luar")
    response = client.get(f"/student/subjects/{kelas.id}/members")
    assert response.status_code == 403
    assert "andi" not in response.text


def test_guru_tidak_bisa_memakai_endpoint_siswa(client, kelas):
    assert client.get(f"/student/subjects/{kelas.id}/members").status_code == 403


def test_siswa_yang_dikeluarkan_hilang_dari_hasil(client, kelas):
    budi = kelas.students["Budi"]
    client.post(
        "/teacher/materials/m1/quizzes",
        json={"kind": "pre", "available_from": iso(-1), "deadline_at": iso(48)},
    )

    def names():
        data = client.get(f"/teacher/subjects/{kelas.id}/results").json()
        return data["student_count"]

    assert names() == 3
    client.delete(f"{members_url(kelas)}/{budi}")
    assert names() == 2
