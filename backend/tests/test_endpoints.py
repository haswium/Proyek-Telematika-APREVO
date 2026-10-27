from datetime import datetime, timedelta, timezone

import main


def iso(hours):
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).isoformat()


def setup_subject(client, login, fake_db):
    teacher_id = login("teacher", "Bu Rina")
    subject = client.post("/teacher/subjects", json={"name": "IPA"}).json()["subject"]
    material = {
        "id": "m1",
        "title": "Tumbuhan",
        "teacher_id": teacher_id,
        "subject_id": subject["id"],
        "is_published": True,
        "file_url": "x.pdf",
        "created_at": "2026-10-01",
    }
    fake_db.setdefault("materials", []).append(material)
    return teacher_id, subject, material


def add_quiz(fake_db, quiz_id, kind, start, end, teacher_id):
    fake_db.setdefault("quizzes", []).append(
        {
            "id": quiz_id,
            "title": kind,
            "material_id": "m1",
            "teacher_id": teacher_id,
            "kind": kind,
            "attempt_limit": None,
            "available_from": iso(start),
            "deadline_at": iso(end),
            "deleted_at": None,
        }
    )
    fake_db.setdefault("questions", []).append(
        {
            "id": f"{quiz_id}-q1",
            "quiz_id": quiz_id,
            "type": "true_false",
            "question": "Daun berwarna hijau?",
            "correct_answer": True,
            "explanation": "Daun mengandung klorofil.",
        }
    )


def test_tanpa_profil_ditolak(client, fake_db):
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": type("U", (), {"id": "tanpa-profil"})(),
        "access_token": "t",
    }
    response = client.get("/teacher/subjects")
    assert response.status_code == 403
    # Endpoint lama juga 403, bukan 500, untuk akun tanpa profil.
    assert client.get("/student/materials").status_code == 403


def test_peran_diperiksa(client, login, fake_db):
    login("student")
    assert client.post("/teacher/subjects", json={"name": "IPA"}).status_code == 403
    login("teacher")
    assert client.post("/student/subjects/join", json={"code": "ABCDEF"}).status_code == 403


def test_guru_buat_dan_siswa_gabung(client, login, fake_db):
    _, subject, _ = setup_subject(client, login, fake_db)
    assert len(subject["access_code"]) == 6

    login("student", "Andi")
    code = subject["access_code"].lower()
    first = client.post("/student/subjects/join", json={"code": code})
    assert first.status_code == 200
    assert first.json()["already_joined"] is False
    again = client.post("/student/subjects/join", json={"code": code})
    assert again.json()["already_joined"] is True
    assert len(fake_db["subject_students"]) == 1

    subjects = client.get("/student/subjects").json()["subjects"]
    assert subjects[0]["teacher_name"] == "Bu Rina"
    assert subjects[0]["material_count"] == 1

    assert client.post("/student/subjects/join", json={"code": "ZZZZZZ"}).status_code == 404
    assert client.post("/student/subjects/join", json={"code": "AB1"}).status_code == 400


def test_kode_bentrok_dicoba_ulang(client, login, fake_db, monkeypatch):
    login("teacher")
    codes = iter(["AAAAAA", "AAAAAA", "BBBBBB"])
    monkeypatch.setattr(main, "generate_access_code", lambda: next(codes))
    assert client.post("/teacher/subjects", json={"name": "A"}).json()["subject"]["access_code"] == "AAAAAA"
    assert client.post("/teacher/subjects", json={"name": "B"}).json()["subject"]["access_code"] == "BBBBBB"


def test_post_test_terkunci_sampai_pre_test_dikumpulkan(client, login, fake_db):
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    add_quiz(fake_db, "pre", "pre", -1, 2, teacher_id)
    add_quiz(fake_db, "post", "post", -1, 2, teacher_id)
    student_id = login("student")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})

    materials = client.get(f"/student/subjects/{subject['id']}/materials").json()["materials"]
    quizzes = {quiz["kind"]: quiz for quiz in materials[0]["quizzes"]}
    assert quizzes["post"]["locked"] is True
    assert quizzes["pre"]["status"] == "open"
    assert client.post("/quizzes/post/attempts").status_code == 403
    assert client.get("/student/quizzes/post").status_code == 403

    fake_db.setdefault("quiz_attempts", []).append(
        {"id": "a1", "quiz_id": "pre", "student_id": student_id,
         "submitted_at": iso(0), "correct_count": 1, "total_questions": 1,
         "started_at": iso(-1)}
    )
    materials = client.get(f"/student/subjects/{subject['id']}/materials").json()["materials"]
    post = next(quiz for quiz in materials[0]["quizzes"] if quiz["kind"] == "post")
    assert post["locked"] is False
    assert client.post("/quizzes/post/attempts").status_code == 200


def test_soal_tidak_bisa_dibaca_sebelum_kuis_dibuka(client, login, fake_db):
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    add_quiz(fake_db, "pre", "pre", 1, 2, teacher_id)
    login("student")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    response = client.get("/student/quizzes/pre")
    assert response.status_code == 403
    assert response.json()["detail"] == "Kuis belum tersedia"


def test_jawab_review_dan_pembahasan(client, login, fake_db):
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    add_quiz(fake_db, "pre", "pre", -1, 2, teacher_id)
    login("student")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})

    attempt = client.post("/quizzes/pre/attempts").json()["attempt"]
    answer = client.put(
        f"/student/attempts/{attempt['id']}/answers/pre-q1",
        json={"question_id": "pre-q1", "boolean_value": False},
    ).json()
    assert answer["is_correct"] is False
    assert "correct_answer" not in answer and "explanation" not in answer

    client.post(f"/student/attempts/{attempt['id']}/submit")
    result = client.get(f"/student/attempts/{attempt['id']}/result").json()
    item = result["review"][0]
    assert item["answer"] is False and item["is_correct"] is False
    assert "correct_answer" not in item and "explanation" not in item
    assert result["discussion_available"] is False

    locked = client.get(f"/student/attempts/{attempt['id']}/discussion")
    assert locked.status_code == 403

    fake_db["quizzes"][0]["deadline_at"] = iso(-0.01)
    discussion = client.get(f"/student/attempts/{attempt['id']}/discussion").json()
    item = discussion["review"][0]
    assert item["correct_answer"] is True
    assert item["explanation"] == "Daun mengandung klorofil."


def test_sub_bab_hanya_untuk_yang_berhak(client, login, fake_db):
    teacher_id, subject, material = setup_subject(client, login, fake_db)
    fake_db["material_sections"] = [
        {"id": "s2", "material_id": "m1", "position": 2, "title": "Akar", "content": "b"},
        {"id": "s1", "material_id": "m1", "position": 1, "title": "Daun", "content": "a"},
    ]
    sections = client.get("/materials/m1/sections").json()["sections"]
    assert [s["title"] for s in sections] == ["Daun", "Akar"]

    login("student")
    assert client.get("/materials/m1/sections").status_code == 403
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    assert client.get("/materials/m1/sections").status_code == 200
    material["is_published"] = False
    assert client.get("/materials/m1/sections").status_code == 403


def test_hasil_per_kelas(client, login, fake_db):
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    add_quiz(fake_db, "pre", "pre", -2, -1, teacher_id)
    andi = login("student", "Andi")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    login("student", "Budi")
    client.post("/student/subjects/join", json={"code": subject["access_code"]})
    fake_db["quiz_attempts"] = [
        {"id": "a1", "quiz_id": "pre", "student_id": andi, "correct_count": 1,
         "total_questions": 2, "submitted_at": iso(-1.5)},
    ]
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": type("U", (), {"id": teacher_id})(), "access_token": "t"
    }
    results = client.get(f"/teacher/subjects/{subject['id']}/results").json()
    quiz = results["materials"][0]["quizzes"][0]
    assert results["student_count"] == 2
    assert quiz["average_percent"] == 50.0
    rows = {row["name"]: row for row in quiz["students"]}
    assert rows["Andi"]["latest_attempt"]["correct_count"] == 1
    assert rows["Budi"]["latest_attempt"] is None


def test_buat_kuis_dan_jadwal(client, login, fake_db):
    teacher_id, _, _ = setup_subject(client, login, fake_db)
    bad = client.post("/teacher/materials/m1/quizzes", json={"kind": "pre", "available_from": iso(2), "deadline_at": iso(1)})
    assert bad.status_code == 400
    created = client.post("/teacher/materials/m1/quizzes", json={"kind": "pre", "available_from": iso(1), "deadline_at": iso(2)})
    assert created.status_code == 200
    assert created.json()["quiz"]["title"] == "Pre-test"
    quiz_id = created.json()["quiz"]["id"]
    moved = client.patch(f"/teacher/quizzes/{quiz_id}/schedule", json={"available_from": iso(3), "deadline_at": iso(4)})
    assert moved.status_code == 200


def test_endpoint_debug_mati_secara_bawaan(client, fake_db):
    assert client.post("/test-login").status_code == 404
    assert client.get("/test-supabase").status_code == 404
