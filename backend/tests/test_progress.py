"""Progres siswa: tabel nilai pre-test dan post-test per kelas dan per siswa."""

from types import SimpleNamespace

import pytest

import main
from test_endpoints import setup_subject


def as_user(user_id):
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": SimpleNamespace(id=user_id),
        "access_token": "token",
    }


def add_material(fake_db, material_id, title, teacher_id, subject_id, created):
    fake_db["materials"].append(
        {
            "id": material_id,
            "title": title,
            "teacher_id": teacher_id,
            "subject_id": subject_id,
            "is_published": True,
            "file_url": f"{material_id}.pdf",
            "created_at": created,
        }
    )


def add_quiz(fake_db, quiz_id, material_id, kind, teacher_id, deleted=False):
    fake_db.setdefault("quizzes", []).append(
        {
            "id": quiz_id,
            "title": kind,
            "material_id": material_id,
            "teacher_id": teacher_id,
            "kind": kind,
            "attempt_limit": None,
            "available_from": "2026-11-01T00:00:00+00:00",
            "deadline_at": "2026-11-30T00:00:00+00:00",
            "deleted_at": "2026-11-05T00:00:00+00:00" if deleted else None,
        }
    )


def add_attempt(fake_db, quiz_id, student_id, correct, total, day, submitted=True):
    fake_db.setdefault("quiz_attempts", []).append(
        {
            "id": f"{quiz_id}-{student_id}-{day}",
            "quiz_id": quiz_id,
            "student_id": student_id,
            "correct_count": correct,
            "total_questions": total,
            "submitted_at": f"2026-11-{day:02d}T01:00:00+00:00" if submitted else None,
        }
    )


@pytest.fixture
def kelas(client, login, fake_db):
    """Kelas IPA dengan dua materi berkuis, satu materi tanpa kuis, dan tiga
    siswa. Yang aktif sesudahnya: guru pemilik."""
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    # m1 "Tumbuhan" dari setup_subject, ditambah dua materi lain.
    add_material(fake_db, "m2", "Fotosintesis", teacher_id, subject["id"], "2026-10-02")
    add_material(fake_db, "m3", "Tanpa kuis", teacher_id, subject["id"], "2026-10-03")
    add_quiz(fake_db, "pre1", "m1", "pre", teacher_id)
    add_quiz(fake_db, "post1", "m1", "post", teacher_id)
    add_quiz(fake_db, "pre2", "m2", "pre", teacher_id)
    add_quiz(fake_db, "post2", "m2", "post", teacher_id)
    # Kuis yang dihapus tidak dihitung.
    add_quiz(fake_db, "old", "m2", "post", teacher_id, deleted=True)

    students = {}
    for name in ("Citra", "Andi", "Budi"):
        students[name] = login("student", name)
        fake_db.setdefault("subject_students", []).append(
            {
                "subject_id": subject["id"],
                "student_id": students[name],
                "joined_at": "2026-11-01T00:00:00+00:00",
            }
        )
    andi, budi, citra = students["Andi"], students["Budi"], students["Citra"]

    # Andi, Tumbuhan: pre dua kali (pertama 3/5 = 60, kedua 5/5), post dua
    # kali (pertama 4/5, terakhir 17/20 = 85). Dipakai: 60 dan 85.
    add_attempt(fake_db, "pre1", andi, 3, 5, 2)
    add_attempt(fake_db, "pre1", andi, 5, 5, 3)
    add_attempt(fake_db, "post1", andi, 17, 20, 9)
    add_attempt(fake_db, "post1", andi, 4, 5, 6)
    # Percobaan yang belum dikumpulkan tidak dihitung.
    add_attempt(fake_db, "post1", andi, 0, 5, 10, submitted=False)
    # Andi, Fotosintesis: pre 8/10 = 80, post 7/10 = 70: turun 10.
    add_attempt(fake_db, "pre2", andi, 8, 10, 4)
    add_attempt(fake_db, "post2", andi, 7, 10, 8)
    # Andi di kuis yang dihapus.
    add_attempt(fake_db, "old", andi, 0, 10, 8)
    # Budi, Tumbuhan: pre 1/8 = 12.5 dibulatkan 13, post belum.
    add_attempt(fake_db, "pre1", budi, 1, 8, 2)
    # Citra belum mengerjakan apa pun.

    main.app.dependency_overrides[main.get_current_user] = (
        lambda: {"user": SimpleNamespace(id=teacher_id), "access_token": "token"}
    )
    return SimpleNamespace(
        id=subject["id"], teacher_id=teacher_id, students=students
    )


def progress(client, kelas):
    response = client.get(f"/teacher/subjects/{kelas.id}/progress")
    assert response.status_code == 200, response.text
    return response.json()


def row_of(material, name):
    return next(row for row in material["rows"] if row["name"] == name)


def test_pre_pertama_post_terakhir_dan_kenaikan(client, kelas):
    data = progress(client, kelas)
    titles = [m["title"] for m in data["materials"]]
    # Materi tanpa kuis tidak masuk tabel.
    assert titles == ["Tumbuhan", "Fotosintesis"]

    andi = row_of(data["materials"][0], "Andi")
    assert andi["pre"]["score"] == 60
    assert andi["pre"]["attempt_count"] == 2
    assert andi["pre"]["submitted_at"] == "2026-11-02T01:00:00+00:00"
    assert andi["post"]["score"] == 85
    assert andi["post"]["attempt_count"] == 2
    assert andi["post"]["stars"] == 3
    assert andi["post"]["correct_count"] == 17
    assert andi["post"]["total_questions"] == 20
    assert andi["gain"] == 25

    assert row_of(data["materials"][1], "Andi")["gain"] == -10


def test_siswa_belum_mengerjakan_dan_pembulatan(client, kelas):
    data = progress(client, kelas)
    tumbuhan = data["materials"][0]
    budi = row_of(tumbuhan, "Budi")
    assert budi["pre"]["score"] == 13
    assert budi["pre"]["stars"] == 1
    assert budi["post"]["score"] is None
    assert budi["post"]["attempt_count"] == 0
    assert budi["gain"] is None

    citra = row_of(tumbuhan, "Citra")
    assert citra["pre"]["attempt_count"] == 0
    assert citra["pre"]["score"] is None
    assert [row["name"] for row in tumbuhan["rows"]] == ["Andi", "Budi", "Citra"]


def test_kuis_yang_dihapus_tidak_dihitung(client, kelas):
    foto = progress(client, kelas)["materials"][1]
    assert row_of(foto, "Andi")["post"]["quiz_id"] == "post2"


def test_materi_tanpa_post_test(client, kelas, fake_db):
    fake_db["quizzes"] = [q for q in fake_db["quizzes"] if q["id"] != "post2"]
    foto = progress(client, kelas)["materials"][1]
    assert foto["has_pre"] is True
    assert foto["has_post"] is False
    andi = row_of(foto, "Andi")
    assert andi["post"] is None
    assert andi["gain"] is None


def test_ringkasan_kelas(client, kelas):
    data = progress(client, kelas)
    assert data["subject"]["name"] == "IPA"
    assert data["summary"] == {
        "student_count": 3,
        "material_count": 2,
        # pre: 60, 80, 13
        "average_pre": 51.0,
        # post: 85, 70
        "average_post": 77.5,
        # 25 dan -10
        "average_gain": 7.5,
        "complete_count": 2,
        # Andi rata-rata 7.5: naik. Budi dan Citra tanpa pasangan lengkap.
        "improved": 1,
        "same": 0,
        "declined": 0,
    }
    tumbuhan = data["materials"][0]
    assert tumbuhan["average_pre"] == 36.5
    assert tumbuhan["average_post"] == 85.0
    assert tumbuhan["average_gain"] == 25.0


def test_kelas_tanpa_siswa(client, login, fake_db):
    setup_subject(client, login, fake_db)
    subject_id = fake_db["subjects"][0]["id"]
    data = client.get(f"/teacher/subjects/{subject_id}/progress").json()
    assert data["summary"]["student_count"] == 0
    assert data["summary"]["average_pre"] is None
    assert data["materials"] == []


def test_progres_per_siswa(client, kelas):
    andi = kelas.students["Andi"]
    response = client.get(f"/teacher/subjects/{kelas.id}/students/{andi}/progress")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["student"]["name"] == "Andi"
    assert data["average_gain"] == 7.5
    assert data["complete_count"] == 2
    assert [m["title"] for m in data["materials"]] == ["Tumbuhan", "Fotosintesis"]
    first = data["materials"][0]
    assert first["pre"]["score"] == 60
    assert first["post"]["score"] == 85
    assert first["gain"] == 25

    citra = kelas.students["Citra"]
    data = client.get(f"/teacher/subjects/{kelas.id}/students/{citra}/progress").json()
    assert data["average_gain"] is None
    assert data["complete_count"] == 0


def test_hanya_guru_pemilik(client, kelas, login):
    andi = kelas.students["Andi"]
    paths = [
        f"/teacher/subjects/{kelas.id}/progress",
        f"/teacher/subjects/{kelas.id}/students/{andi}/progress",
    ]
    login("teacher", "Guru lain")
    for path in paths:
        assert client.get(path).status_code == 404, path
    as_user(andi)
    for path in paths:
        assert client.get(path).status_code == 403, path


def test_siswa_bukan_anggota(client, kelas, login, fake_db):
    outsider = login("student", "Luar")
    as_user(kelas.teacher_id)
    response = client.get(
        f"/teacher/subjects/{kelas.id}/students/{outsider}/progress"
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "Siswa bukan anggota kelas ini"

    # Siswa yang dikeluarkan tidak lagi muncul di tabel.
    fake_db["subject_students"] = [
        row
        for row in fake_db["subject_students"]
        if row["student_id"] != kelas.students["Budi"]
    ]
    rows = progress(client, kelas)["materials"][0]["rows"]
    assert [row["name"] for row in rows] == ["Andi", "Citra"]


def test_kelas_dihapus_ditolak(client, kelas, fake_db):
    fake_db["subjects"][0]["deleted_at"] = "2026-11-09T00:00:00+00:00"
    andi = kelas.students["Andi"]
    assert client.get(f"/teacher/subjects/{kelas.id}/progress").status_code == 404
    assert (
        client.get(
            f"/teacher/subjects/{kelas.id}/students/{andi}/progress"
        ).status_code
        == 404
    )


@pytest.mark.parametrize(
    ("correct", "total", "score", "stars"),
    [(0, 5, 0, 0), (1, 2, 50, 1), (3, 5, 60, 2), (17, 20, 85, 3), (0, 0, None, 0)],
)
def test_nilai_dan_bintang(correct, total, score, stars):
    assert main.score_percent(correct, total) == score
    assert main.stars_for(correct, total) == stars
