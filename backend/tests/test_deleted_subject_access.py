"""Setelah `deleted_at` terisi, kelas langsung tertutup.

Baris anggota dan isi kelas sengaja dibiarkan ada: itu keadaan di jeda sebelum
penghapusan selesai, atau kalau penghapusan berhenti di tengah.
"""

import copy
from types import SimpleNamespace

import pytest

import main
from test_endpoints import add_quiz, iso, setup_subject, table_section
from test_images import FakeStorage

GONE = "Kelas ini sudah dihapus guru"
SCHEDULE = {"available_from": iso(1), "deadline_at": iso(2)}
AI_QUESTIONS = {
    "questions": [
        {
            "type": "true_false",
            "question": "Daun berwarna hijau?",
            "correct_answer": True,
            "explanation": "Daun mengandung klorofil.",
        }
    ]
}

# (metode, alamat, isi). Status yang diharapkan: siswa 410, guru 404.
STUDENT_CASES = [
    ("GET", "/student/subjects/{subject}/materials", None),
    ("GET", "/student/subjects/{subject}/members", None),
    ("POST", "/student/subjects/join", {"code": "{code}"}),
    ("GET", "/materials/m1/sections", None),
    ("GET", "/materials/m1/search?q=daun", None),
    ("GET", "/student/quizzes/pre", None),
    ("POST", "/quizzes/pre/attempts", None),
    (
        "PUT",
        "/student/attempts/{attempt}/answers/pre-q1",
        {"question_id": "pre-q1", "boolean_value": True},
    ),
    ("POST", "/student/attempts/{attempt}/submit", None),
    ("GET", "/student/attempts/{attempt}/result", None),
    ("GET", "/student/attempts/{attempt}/discussion", None),
    ("GET", "/student/subjects/{subject}/attendance", None),
]
TEACHER_CASES = [
    ("GET", "/teacher/subjects/{subject}/materials", None),
    ("GET", "/teacher/subjects/{subject}/results", None),
    ("GET", "/teacher/subjects/{subject}/members", None),
    ("DELETE", "/teacher/subjects/{subject}/members/{student}", None),
    ("GET", "/teacher/subjects/{subject}/attendance/sessions", None),
    (
        "POST",
        "/teacher/subjects/{subject}/attendance/sessions",
        {"title": "Pertemuan 1", "close_preset": "15m"},
    ),
    ("GET", "/teacher/subjects/{subject}/attendance/summary", None),
    ("GET", "/teacher/subjects/{subject}/progress", None),
    ("GET", "/teacher/subjects/{subject}/students/{student}/progress", None),
    ("GET", "/teacher/subjects/{subject}/delete-summary", None),
    ("GET", "/materials/m1/sections", None),
    ("GET", "/materials/m1/search?q=daun", None),
    ("PATCH", "/teacher/materials/m1", {"title": "Baru"}),
    ("POST", "/teacher/materials/m1/quizzes", {"kind": "post", **SCHEDULE}),
    (
        "POST",
        "/teacher/materials/m1/generate-quiz",
        {"total_questions": 1, "quiz_type": "true_false"},
    ),
    (
        "POST",
        "/teacher/materials/m1/generate-questions",
        {"test_kind": "pre", "quiz_type": "true_false", "total_questions": 1},
    ),
    ("GET", "/teacher/materials/m1/generate-questions?test_kind=pre", None),
    ("DELETE", "/teacher/materials/m1/generate-questions?test_kind=pre", None),
    ("POST", "/teacher/materials/m1/generate-image-description", None),
    ("GET", "/teacher/materials/m1/image-description", None),
    ("POST", "/teacher/materials/m1/images/g1/describe", None),
    ("GET", "/teacher/materials/m1/images", None),
    ("PATCH", "/teacher/materials/m1/images/g1", {"description": "Daun"}),
    (
        "PATCH",
        "/teacher/materials/m1/sections/s1/tables/0",
        {"title": "", "columns": ["A", "B"], "rows": [["1", "2"]]},
    ),
    ("PATCH", "/teacher/quizzes/pre/schedule", SCHEDULE),
    ("GET", "/quizzes/pre", None),
    ("POST", "/quizzes/pre/questions", AI_QUESTIONS),
]
# Endpoint yang sengaja tetap terbuka: guru harus bisa melanjutkan penghapusan
# yang berhenti di tengah. Unggah diuji sendiri karena isinya multipart.
EXEMPT = {
    ("DELETE", "/teacher/subjects/{subject_id}"),
    ("POST", "/teacher/materials/upload"),
}


@pytest.fixture
def kelas(client, login, fake_db, monkeypatch):
    """Kelas yang utuh dengan siswa yang sudah mengumpulkan pre-test."""

    def no_ai(*_args, **_kwargs):
        raise RuntimeError("Tes tidak memanggil Gemini")

    monkeypatch.setattr(main, "generate_quiz", no_ai)
    monkeypatch.setattr(main, "describe_image", no_ai)
    monkeypatch.setattr(main.supabase_admin, "storage", FakeStorage(), raising=False)
    # Dua endpoint kuis guru membuat klien dengan token pengguna.
    monkeypatch.setattr(main, "create_client", lambda *_a, **_k: main.supabase_admin)

    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    owner = main.app.dependency_overrides[main.get_current_user]
    add_quiz(fake_db, "pre", "pre", -1, 2, teacher_id)
    table_section(fake_db)
    fake_db["material_images"] = [
        {
            "id": "g1",
            "material_id": "m1",
            "image_key": "xref-1",
            "image_url": "g1.png",
            "description": None,
            "is_decorative": False,
        }
    ]
    student_id = login("student", "Budi")
    student = main.app.dependency_overrides[main.get_current_user]
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    attempt = client.post("/quizzes/pre/attempts").json()["attempt"]
    return SimpleNamespace(
        id=subject["id"],
        code=subject["access_code"],
        attempt=attempt["id"],
        student_id=student_id,
        as_student=lambda: main.app.dependency_overrides.__setitem__(
            main.get_current_user, student
        ),
        as_teacher=lambda: main.app.dependency_overrides.__setitem__(
            main.get_current_user, owner
        ),
    )


def fill(value, kelas):
    replace = {
        "{subject}": kelas.id,
        "{attempt}": kelas.attempt,
        "{student}": kelas.student_id,
        "{code}": kelas.code,
    }
    if isinstance(value, dict):
        return {key: fill(item, kelas) for key, item in value.items()}
    if isinstance(value, str):
        for mark, real in replace.items():
            value = value.replace(mark, real)
    return value


def send(client, kelas, method, url, body):
    return client.request(method, fill(url, kelas), json=fill(body, kelas))


def mark_deleted(fake_db):
    assert len(fake_db["subjects"]) == 1
    fake_db["subjects"][0]["deleted_at"] = iso(-0.01)


def test_daftar_kasus_mencakup_semua_endpoint_kelas():
    """Endpoint baru yang menyentuh kelas harus ditambahkan ke daftar di sini."""
    marks = ("{subject_id}", "{material_id}", "{quiz_id}", "{attempt_id}")
    routes = {
        (method, route.path)
        for route in main.app.routes
        if any(mark in getattr(route, "path", "") for mark in marks)
        or getattr(route, "path", "") in ("/student/subjects/join", "/teacher/materials/upload")
        for method in getattr(route, "methods", None) or ()
    }
    routes = {route for route in routes if route[0] != "HEAD"}

    covered = set()
    for method, path in routes:
        for case_method, url, _ in STUDENT_CASES + TEACHER_CASES:
            if case_method == method and matches(path, url):
                covered.add((method, path))
    assert routes - covered == EXEMPT


def matches(path, url):
    path_parts = path.split("/")
    url_parts = url.split("?")[0].split("/")
    return len(path_parts) == len(url_parts) and all(
        pattern.startswith("{") or pattern == part
        for pattern, part in zip(path_parts, url_parts)
    )


@pytest.mark.parametrize(
    "method,url,body", STUDENT_CASES, ids=[f"{c[0]} {c[1]}" for c in STUDENT_CASES]
)
def test_siswa_yang_masih_anggota_ditolak(client, kelas, fake_db, method, url, body):
    kelas.as_student()
    mark_deleted(fake_db)
    assert fake_db["subject_students"], "baris anggota harus masih ada"
    before = copy.deepcopy(fake_db)

    response = send(client, kelas, method, url, body)

    assert response.status_code == 410, response.text
    assert response.json()["detail"] == GONE
    assert fake_db == before


@pytest.mark.parametrize(
    "method,url,body", STUDENT_CASES, ids=[f"{c[0]} {c[1]}" for c in STUDENT_CASES]
)
def test_siswa_tidak_ditolak_kalau_kelas_masih_ada(
    client, kelas, method, url, body
):
    """Pembanding: membuktikan penolakan di atas memang karena `deleted_at`."""
    kelas.as_student()
    response = send(client, kelas, method, url, body)
    assert response.status_code not in (404, 410, 500), response.text


@pytest.mark.parametrize(
    "method,url,body", TEACHER_CASES, ids=[f"{c[0]} {c[1]}" for c in TEACHER_CASES]
)
def test_guru_pemilik_ditolak(client, kelas, fake_db, method, url, body):
    kelas.as_teacher()
    mark_deleted(fake_db)
    before = copy.deepcopy(fake_db)

    response = send(client, kelas, method, url, body)

    assert response.status_code == 404, response.text
    assert fake_db == before


@pytest.mark.parametrize(
    "method,url,body", TEACHER_CASES, ids=[f"{c[0]} {c[1]}" for c in TEACHER_CASES]
)
def test_guru_tidak_ditolak_kalau_kelas_masih_ada(
    client, kelas, method, url, body
):
    """Pembanding untuk guru."""
    kelas.as_teacher()
    response = send(client, kelas, method, url, body)
    assert response.status_code not in (404, 410, 500), response.text


def test_percobaan_yang_sudah_dikumpulkan_tetap_dijawab_410(client, kelas, fake_db):
    """Bukan 409, supaya layar kuis menampilkan alasan yang benar."""
    kelas.as_student()
    client.put(
        f"/student/attempts/{kelas.attempt}/answers/pre-q1",
        json={"question_id": "pre-q1", "boolean_value": True},
    )
    assert client.post(f"/student/attempts/{kelas.attempt}/submit").status_code == 200
    mark_deleted(fake_db)
    for method, url in (
        ("POST", f"/student/attempts/{kelas.attempt}/submit"),
        ("PUT", f"/student/attempts/{kelas.attempt}/answers/pre-q1"),
    ):
        body = {"question_id": "pre-q1", "boolean_value": True}
        response = client.request(method, url, json=body)
        assert response.status_code == 410, response.text


def test_daftar_kelas_dan_materi_siswa_tidak_memuat_kelas_terhapus(
    client, kelas, fake_db
):
    kelas.as_student()
    assert [m["id"] for m in client.get("/student/materials").json()["materials"]] == [
        "m1"
    ]
    assert len(client.get("/student/subjects").json()["subjects"]) == 1

    mark_deleted(fake_db)

    assert client.get("/student/subjects").json()["subjects"] == []
    assert client.get("/student/materials").json()["materials"] == []


def test_akses_material_lama_juga_tertutup(client, kelas, fake_db):
    """Akses lewat `material_access` tidak bergantung pada keanggotaan kelas."""
    kelas.as_student()
    fake_db["subject_students"].clear()
    fake_db["material_access"] = [
        {"id": "a1", "material_id": "m1", "student_id": kelas.student_id}
    ]
    assert client.get("/materials/m1/sections").status_code == 200
    assert [m["id"] for m in client.get("/student/materials").json()["materials"]] == [
        "m1"
    ]

    mark_deleted(fake_db)

    assert client.get("/materials/m1/sections").status_code == 410
    assert client.get("/student/quizzes/pre").status_code == 410
    assert client.get("/student/materials").json()["materials"] == []


def test_materi_tanpa_kelas_tidak_terpengaruh(client, kelas, fake_db):
    kelas.as_teacher()
    mark_deleted(fake_db)
    fake_db["materials"][0]["subject_id"] = None
    assert client.get("/materials/m1/sections").status_code == 200
    assert client.get("/teacher/materials/m1/images").status_code == 200


def test_guru_tidak_bisa_mengunggah_ke_kelas_terhapus(client, kelas, fake_db):
    kelas.as_teacher()
    mark_deleted(fake_db)
    before = copy.deepcopy(fake_db)
    response = client.post(
        "/teacher/materials/upload",
        data={"title": "Baru", "subject_id": kelas.id},
        files={"file": ("a.pdf", b"%PDF-1.4", "application/pdf")},
    )
    assert response.status_code == 404, response.text
    assert fake_db == before


def test_guru_lain_tidak_tahu_kelasnya_dihapus(client, kelas, login, fake_db):
    mark_deleted(fake_db)
    login("teacher", "Guru Lain")
    response = client.get("/materials/m1/sections")
    assert response.status_code == 404
    assert GONE not in response.text


def test_penghapusan_tetap_bisa_dilanjutkan(client, kelas, fake_db):
    kelas.as_teacher()
    mark_deleted(fake_db)
    response = client.delete(f"/teacher/subjects/{kelas.id}")
    assert response.status_code == 200, response.text
    assert fake_db["subject_students"] == []
    assert fake_db["materials"] == []
