"""Menghapus kelas beserta seluruh isinya."""

from types import SimpleNamespace

import pytest

import main
from conftest import Query
from test_endpoints import setup_subject
from test_images import FakeStorage

# Tabel anak -> (kolom, tabel induk), seperti foreign key di database. Dipakai
# untuk memastikan anak selalu dihapus sebelum induknya.
FOREIGN_KEYS = [
    ("material_images", "material_id", "materials"),
    ("material_sections", "material_id", "materials"),
    ("material_access", "material_id", "materials"),
    ("quizzes", "material_id", "materials"),
    ("questions", "quiz_id", "quizzes"),
    ("question_options", "question_id", "questions"),
    ("question_answers", "question_id", "questions"),
    ("question_items", "question_id", "questions"),
    ("quiz_attempts", "quiz_id", "quizzes"),
    ("answers", "attempt_id", "quiz_attempts"),
    ("answers", "question_id", "questions"),
    ("answer_options", "answer_id", "answers"),
    ("answer_options", "option_id", "question_options"),
    ("answer_boolean", "answer_id", "answers"),
    ("answer_text", "answer_id", "answers"),
    ("answer_order_items", "answer_id", "answers"),
    ("answer_order_items", "item_id", "question_items"),
]
ALL_CHILD_TABLES = {child for child, _, _ in FOREIGN_KEYS} | {
    "materials",
    "subject_students",
}


@pytest.fixture(autouse=True)
def foreign_keys(monkeypatch):
    """Database asli menolak menghapus baris yang masih dirujuk."""
    original = Query.execute

    def execute(self):
        if self.action == "delete":
            doomed = {str(row.get("id")) for row in self._matching()}
            for child, column, parent in FOREIGN_KEYS:
                if parent != self.table:
                    continue
                for row in self.db.get(child, []):
                    assert str(row.get(column)) not in doomed, (
                        f"{parent} dihapus sebelum {child}"
                    )
        return original(self)

    monkeypatch.setattr(Query, "execute", execute)


@pytest.fixture
def storage(fake_db, monkeypatch):
    fake = FakeStorage()
    monkeypatch.setattr(main.supabase_admin, "storage", fake, raising=False)
    return fake


def fill_material(db, storage, material_id, prefix, student_id):
    """Satu materi dengan semua jenis isi. Semua id diawali `prefix`."""
    def add(table, **row):
        db.setdefault(table, []).append({"id": f"{prefix}-{table}", **row})

    pdf = f"{prefix}.pdf"
    next(m for m in db["materials"] if m["id"] == material_id)["file_url"] = pdf
    storage.files[("materials-pdf", pdf)] = b"pdf"
    storage.files[("material-images", f"{prefix}.png")] = b"png"
    add(
        "material_images",
        material_id=material_id,
        image_key=f"{prefix}-key",
        image_url=f"{prefix}.png",
    )
    add("material_sections", material_id=material_id, position=1, content="Isi")
    add("material_access", material_id=material_id, student_id=student_id)
    add(
        "quizzes",
        material_id=material_id,
        title="Pre",
        kind="pre",
        deleted_at=None,
    )
    quiz = f"{prefix}-quizzes"
    add("questions", quiz_id=quiz, type="multiple_choice", question="Soal")
    question = f"{prefix}-questions"
    add("question_options", question_id=question, text="A")
    add("question_answers", question_id=question, answer="A")
    add("question_items", question_id=question, text="A")
    add("quiz_attempts", quiz_id=quiz, student_id=student_id, correct_count=1)
    add("answers", attempt_id=f"{prefix}-quiz_attempts", question_id=question)
    answer = f"{prefix}-answers"
    add("answer_options", answer_id=answer, option_id=f"{prefix}-question_options")
    # Tabel ini tidak punya kolom id di database.
    db.setdefault("answer_boolean", []).append({"answer_id": answer, "value": True})
    db.setdefault("answer_text", []).append({"answer_id": answer, "value": "A"})
    add("answer_order_items", answer_id=answer, item_id=f"{prefix}-question_items")


@pytest.fixture
def kelas(client, login, fake_db, storage):
    """Kelas IPA milik guru, dan kelas lain milik guru lain yang tidak boleh
    tersentuh. Yang aktif sesudahnya: guru pemilik kelas IPA."""
    other_teacher, other, _ = setup_subject(client, login, fake_db)
    other_id = other["id"]
    fake_db["materials"][0].update(id="lain", subject_id=other_id)
    student = login("student", "Budi")
    fill_material(fake_db, storage, "lain", "lain", student)
    fake_db.setdefault("subject_students", []).append(
        {"subject_id": other_id, "student_id": student, "joined_at": "2026-10-01"}
    )

    teacher, subject, _ = setup_subject(client, login, fake_db)
    fill_material(fake_db, storage, "m1", "ipa", student)
    fake_db["subject_students"].append(
        {"subject_id": subject["id"], "student_id": student, "joined_at": "2026-10-01"}
    )
    return SimpleNamespace(
        id=subject["id"],
        name=subject["name"],
        code=subject["access_code"],
        other_id=other_id,
        student=student,
        teacher=teacher,
    )


def act_as(user_id):
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": SimpleNamespace(id=user_id),
        "access_token": "token",
    }


def test_ringkasan_menyebut_jumlah_isi(client, kelas):
    response = client.get(f"/teacher/subjects/{kelas.id}/delete-summary")
    assert response.status_code == 200, response.text
    assert response.json() == {
        "material_count": 1,
        "quiz_count": 1,
        "student_count": 1,
    }


def test_semua_isi_terhapus_dan_kelas_lain_utuh(client, kelas, fake_db, storage):
    response = client.delete(f"/teacher/subjects/{kelas.id}")
    assert response.status_code == 200, response.text
    assert response.json()["subject"]["name"] == kelas.name

    for table in ALL_CHILD_TABLES:
        rows = fake_db.get(table, [])
        assert not any("ipa" in str(row.values()) for row in rows), table
    # Isi kelas lain tetap ada di semua tabel.
    for table in ALL_CHILD_TABLES - {"subject_students"}:
        assert len(fake_db[table]) == 1, table
    assert [r["subject_id"] for r in fake_db["subject_students"]] == [kelas.other_id]
    assert sorted(storage.files) == [
        ("material-images", "lain.png"),
        ("materials-pdf", "lain.pdf"),
    ]


def test_kelas_tidak_tampil_lagi_dan_tidak_bisa_dihapus_dua_kali(client, kelas):
    client.delete(f"/teacher/subjects/{kelas.id}")
    subjects = client.get("/teacher/subjects").json()["subjects"]
    assert kelas.id not in [s["id"] for s in subjects]
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 404
    assert client.get(f"/teacher/subjects/{kelas.id}/delete-summary").status_code == 404


def test_guru_lain_ditolak_dan_tidak_ada_yang_terhapus(
    client, kelas, login, fake_db, storage
):
    before = len(storage.files)
    login("teacher", "Guru Lain")
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 404
    assert client.get(f"/teacher/subjects/{kelas.id}/delete-summary").status_code == 404
    assert len(storage.files) == before
    assert len(fake_db["materials"]) == 2


def test_siswa_ditolak(client, kelas, fake_db):
    act_as(kelas.student)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 403
    assert client.get(f"/teacher/subjects/{kelas.id}/delete-summary").status_code == 403
    assert len(fake_db["materials"]) == 2


def test_tanpa_login_ditolak(client, kelas, fake_db):
    main.app.dependency_overrides.pop(main.get_current_user)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code in (401, 403)
    assert len(fake_db["materials"]) == 2


def unfinished(client):
    return client.get("/teacher/subjects").json()["unfinished_deletions"]


def test_urutan_penanda_data_storage_lalu_alamat_berkas(
    client, kelas, fake_db, storage, monkeypatch
):
    """Saat Storage dipanggil, kelas sudah ditandai dan data lain sudah habis,
    tetapi baris yang menyimpan alamat berkas masih ada."""
    seen = {}
    original = storage.from_

    def spy(bucket):
        seen.setdefault(
            bucket,
            {
                "deleted": next(
                    s for s in fake_db["subjects"] if s["id"] == kelas.id
                )["deleted_at"],
                "quizzes": [q["id"] for q in fake_db["quizzes"]],
                "materials": [m["id"] for m in fake_db["materials"]],
                "images": [i["id"] for i in fake_db["material_images"]],
            },
        )
        return original(bucket)

    monkeypatch.setattr(storage, "from_", spy)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    for bucket in ("material-images", "materials-pdf"):
        assert seen[bucket]["deleted"] is not None
        assert seen[bucket]["quizzes"] == ["lain-quizzes"]
        assert "m1" in seen[bucket]["materials"]
        assert "ipa-material_images" in seen[bucket]["images"]


def test_storage_gagal_alamat_berkas_tersisa_dan_bisa_dilanjutkan(
    client, kelas, fake_db, storage, monkeypatch
):
    original = storage.from_

    def broken(bucket):
        bucket_object = original(bucket)
        if bucket == "materials-pdf":
            def fail(_paths):
                raise RuntimeError("Storage mati")

            bucket_object.remove = fail
        return bucket_object

    monkeypatch.setattr(storage, "from_", broken)
    response = client.delete(f"/teacher/subjects/{kelas.id}")
    assert response.status_code == 500
    assert response.json()["detail"] == "Kelas belum terhapus sepenuhnya. Coba lagi"
    # Kelas sudah hilang dari daftar, data lain sudah habis, alamat berkas tersisa.
    subjects = client.get("/teacher/subjects").json()["subjects"]
    assert kelas.id not in [s["id"] for s in subjects]
    assert [row["id"] for row in unfinished(client)] == [kelas.id]
    assert any(m["id"] == "m1" for m in fake_db["materials"])
    assert not any("ipa" in q["id"] for q in fake_db["quizzes"])
    # Siswa sudah mendapat pesan yang jelas.
    teacher = main.app.dependency_overrides[main.get_current_user]
    act_as(kelas.student)
    assert client.get(f"/student/subjects/{kelas.id}/materials").status_code == 410
    main.app.dependency_overrides[main.get_current_user] = teacher

    monkeypatch.setattr(storage, "from_", original)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    assert ("materials-pdf", "ipa.pdf") not in storage.files
    assert ("material-images", "ipa.png") not in storage.files
    assert not any(m["id"] == "m1" for m in fake_db["materials"])
    assert unfinished(client) == []
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 404


def test_gagal_di_tengah_kelas_masih_ada_dan_bisa_diulang(
    client, kelas, fake_db, monkeypatch
):
    original = Query.execute
    armed = {"on": True}

    def execute(self):
        if armed["on"] and self.action == "delete" and self.table == "material_sections":
            raise RuntimeError("Database putus")
        return original(self)

    monkeypatch.setattr(Query, "execute", execute)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 500
    subject = next(s for s in fake_db["subjects"] if s["id"] == kelas.id)
    first_mark = subject["deleted_at"]
    assert first_mark is not None
    assert [row["id"] for row in unfinished(client)] == [kelas.id]

    armed["on"] = False
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    assert not any(m["id"] == "m1" for m in fake_db["materials"])
    assert not any("ipa" in str(r.get("id")) for r in fake_db["material_sections"])
    # Penanda waktu pertama tidak ditimpa, dan daftar sudah bersih.
    assert subject["deleted_at"] == first_mark
    assert unfinished(client) == []


def test_guru_lain_tidak_bisa_melanjutkan_penghapusan(
    client, kelas, login, fake_db, monkeypatch
):
    original = Query.execute

    def execute(self):
        if self.action == "delete" and self.table == "material_sections":
            raise RuntimeError("Database putus")
        return original(self)

    monkeypatch.setattr(Query, "execute", execute)
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 500
    monkeypatch.setattr(Query, "execute", original)
    login("teacher", "Guru Lain")
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 404
    assert unfinished(client) == []


def test_kelas_tanpa_isi(client, login, fake_db, storage):
    _, subject, _ = setup_subject(client, login, fake_db)
    fake_db["materials"].clear()
    assert client.delete(f"/teacher/subjects/{subject['id']}").status_code == 200


def test_data_banyak_terhapus_semua(client, kelas, fake_db):
    """Lebih banyak dari satu halaman select dan satu potongan permintaan."""
    fake_db["quiz_attempts"].extend(
        {"id": f"ipa-x{i}", "quiz_id": "ipa-quizzes", "student_id": kelas.student}
        for i in range(250)
    )
    fake_db["answers"].extend(
        {"id": f"ipa-y{i}", "attempt_id": "ipa-x0", "question_id": "ipa-questions"}
        for i in range(1200)
    )
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    assert len(fake_db["quiz_attempts"]) == 1
    assert len(fake_db["answers"]) == 1


def test_siswa_mendapat_pesan_jelas(client, kelas):
    client.delete(f"/teacher/subjects/{kelas.id}")
    act_as(kelas.student)
    for url in (
        f"/student/subjects/{kelas.id}/materials",
        f"/student/subjects/{kelas.id}/members",
    ):
        response = client.get(url)
        assert response.status_code == 410, url
        assert response.json()["detail"] == "Kelas ini sudah dihapus guru"
    response = client.post("/student/subjects/join", json={"code": kelas.code})
    assert response.status_code == 410
    assert response.json()["detail"] == "Kelas ini sudah dihapus guru"
    # Kelas itu hilang dari daftar kelas siswa.
    subjects = client.get("/student/subjects").json()["subjects"]
    assert kelas.id not in [s["id"] for s in subjects]


def test_kelas_yang_tidak_pernah_ada_tetap_bukan_410(client, kelas):
    act_as(kelas.student)
    response = client.get("/student/subjects/tidak-ada/materials")
    assert response.status_code == 403
