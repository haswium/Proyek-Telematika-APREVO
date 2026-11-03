"""Pembuatan draf soal di latar belakang. generate_quiz selalu tiruan."""

import pytest

import main
from schemas.ai_output import AIOutput
from test_endpoints import iso, setup_subject

URL = "/teacher/materials/m1/generate-questions"


def question(text):
    return {
        "type": "true_false",
        "question": text,
        "explanation": f"Penjelasan {text}",
        "correct_answer": True,
    }


class FakeGemini:
    """Membuat soal bernomor urut. `script` mengatur tiap panggilan: Exception
    untuk gagal, atau daftar teks soal."""

    def __init__(self, script=()):
        self.script = list(script)
        self.calls = []
        self.number = 0

    def __call__(self, materi, total_questions, quiz_type, avoid_questions=()):
        self.calls.append(
            {
                "materi": materi,
                "total": total_questions,
                "type": quiz_type,
                "avoid": list(avoid_questions),
            }
        )
        step = self.script.pop(0) if self.script else None
        if isinstance(step, Exception):
            raise step
        if step is None:
            step = []
            for _ in range(total_questions):
                self.number += 1
                step.append(f"Soal {self.number}")
        return AIOutput(questions=[question(text) for text in step])


@pytest.fixture
def gemini(monkeypatch):
    def install(script=()):
        fake = FakeGemini(script)
        monkeypatch.setattr(main, "generate_quiz", fake)
        return fake

    return install


@pytest.fixture
def ready(client, login, fake_db, monkeypatch):
    """Materi m1 berteks dengan pre-test yang sudah berjadwal."""
    monkeypatch.setenv("GEMINI_API_KEY", "kunci-tes")
    setup_subject(client, login, fake_db)
    fake_db["material_sections"] = [
        {
            "id": "s1",
            "material_id": "m1",
            "position": 1,
            "title": "Hal",
            "content": "## Judul\nBudi menabung.\n[[gambar:xref-1]]",
        }
    ]
    response = client.post(
        "/teacher/materials/m1/quizzes",
        json={"kind": "pre", "available_from": iso(1), "deadline_at": iso(48)},
    )
    assert response.status_code == 200, response.text
    return client


def start(client, total=3, kind="pre", quiz_type="true_false"):
    return client.post(
        URL,
        json={"test_kind": kind, "quiz_type": quiz_type, "total_questions": total},
    )


def status(client, kind="pre"):
    return client.get(URL, params={"test_kind": kind}).json()


def test_satu_panggilan_gemini_untuk_sampai_10_soal(ready, gemini):
    fake = gemini()
    response = start(ready, total=10)
    assert response.status_code == 200, response.text
    # Jawaban POST dibuat sebelum proses berjalan.
    assert response.json()["running"] is True
    assert response.json()["questions"] == []

    result = status(ready)
    assert result["running"] is False
    assert result["done"] == result["total"] == 10
    assert result["error"] is None
    assert result["quiz_type"] == "true_false"
    assert [q["question"] for q in result["questions"]][:2] == ["Soal 1", "Soal 2"]
    assert all(q["explanation"] for q in result["questions"])
    assert len(fake.calls) == 1
    assert fake.calls[0]["total"] == 10
    # Teks hasil konversi, tanpa penanda gambar dan awalan subjudul.
    assert fake.calls[0]["materi"] == "Judul\nBudi menabung."


def test_lebih_dari_10_soal_dipecah_per_10_tanpa_mengulang(ready, gemini):
    fake = gemini()
    start(ready, total=25)
    assert [call["total"] for call in fake.calls] == [10, 10, 5]
    assert fake.calls[0]["avoid"] == []
    assert fake.calls[1]["avoid"] == [f"Soal {i}" for i in range(1, 11)]
    assert len(fake.calls[2]["avoid"]) == 20
    assert status(ready)["done"] == 25


def test_soal_kembar_dibuang_dan_kekurangannya_diminta_lagi(ready, gemini):
    fake = gemini([["Soal A", "soal a ", "Soal B"], ["Soal C"]])
    start(ready, total=3)
    result = status(ready)
    assert [q["question"] for q in result["questions"]] == ["Soal A", "Soal B", "Soal C"]
    assert [call["total"] for call in fake.calls] == [3, 1]


def test_jawaban_ai_tidak_valid_dicoba_sekali_lagi(ready, gemini):
    fake = gemini([ValueError("tanpa penjelasan")])
    start(ready, total=2)
    result = status(ready)
    assert result["done"] == 2
    assert result["error"] is None
    assert len(fake.calls) == 2


def test_gagal_dua_kali_melaporkan_error(ready, gemini):
    gemini([ValueError("rusak"), ValueError("rusak")])
    start(ready, total=2)
    result = status(ready)
    assert result["running"] is False
    assert result["questions"] == []
    assert result["error"] == "AI gagal membuat soal. Coba lagi"


def test_batas_pemakaian_dijelaskan(ready, gemini):
    error = RuntimeError("429 RESOURCE_EXHAUSTED")
    gemini([error, error])
    start(ready, total=2)
    assert status(ready)["error"] == (
        "Batas pemakaian Gemini tercapai. Coba lagi beberapa menit lagi"
    )


def test_gagal_di_tengah_soal_yang_sudah_jadi_tetap_ada(ready, gemini):
    error = RuntimeError("putus")
    gemini([None, error, error])
    start(ready, total=15)
    result = status(ready)
    assert result["done"] == 10
    assert result["total"] == 15
    assert len(result["questions"]) == 10
    assert result["error"] == "AI gagal membuat soal. Coba lagi"


def test_ai_terus_mengulang_soal_berhenti_dengan_error(ready, gemini):
    fake = gemini([["Sama"], ["Sama"], ["Sama"]])
    start(ready, total=2)
    result = status(ready)
    assert result["done"] == 1
    assert result["error"] == "AI hanya membuat soal yang sama. Coba lagi"
    assert len(fake.calls) == 3


def test_kunci_hilang_saat_proses_tidak_dicoba_ulang(ready, gemini):
    fake = gemini([main.GeminiKeyMissing("kosong")])
    start(ready, total=2)
    assert status(ready)["error"] == main.GEMINI_KEY_MISSING_DETAIL
    assert len(fake.calls) == 1


def test_proses_yang_berjalan_tidak_dimulai_dua_kali(ready, gemini):
    fake = gemini()
    job = main.QuestionDraftJob(job_id="j1", quiz_type="true_false", total=5)
    main.QUESTION_JOBS[("m1", "pre")] = job
    response = start(ready, total=9)
    assert response.json()["job_id"] == "j1"
    assert response.json()["total"] == 5
    assert fake.calls == []


def test_soal_belum_dikirim_selama_berjalan(ready, gemini):
    job = main.QuestionDraftJob(job_id="j1", quiz_type="true_false", total=5)
    job.questions.append(question("Setengah jadi"))
    main.QUESTION_JOBS[("m1", "pre")] = job
    result = status(ready)
    assert result["running"] is True
    assert result["done"] == 1
    assert result["questions"] == []


def test_hasil_dihapus_setelah_diambil(ready, gemini):
    gemini()
    start(ready, total=1)
    assert status(ready)["done"] == 1
    response = ready.delete(URL, params={"test_kind": "pre"})
    assert response.status_code == 200
    assert status(ready)["job_id"] is None
    # Menghapus dua kali tidak apa-apa.
    assert ready.delete(URL, params={"test_kind": "pre"}).status_code == 200


def test_hasil_tidak_bisa_dihapus_selama_berjalan(ready, gemini):
    main.QUESTION_JOBS[("m1", "pre")] = main.QuestionDraftJob(
        job_id="j1", quiz_type="true_false", total=5
    )
    assert ready.delete(URL, params={"test_kind": "pre"}).status_code == 409


def test_kuis_tanpa_jadwal_ditolak(ready, gemini):
    fake = gemini()
    response = start(ready, kind="post")
    assert response.status_code == 409
    assert response.json()["detail"] == "Atur dulu jadwal post-test materi ini"
    assert fake.calls == []


def test_jenis_soal_lain_ditolak_kalau_sudah_ada_soal(ready, gemini, fake_db):
    fake = gemini()
    quiz = fake_db["quizzes"][0]
    fake_db["questions"] = [{"id": "q1", "quiz_id": quiz["id"], "type": "multiple_choice"}]
    response = start(ready, quiz_type="true_false")
    assert response.status_code == 409
    assert response.json()["detail"] == "Materi ini sudah memakai jenis soal lain"
    assert fake.calls == []
    assert start(ready, quiz_type="multiple_choice").status_code == 200


def test_jenis_soal_lain_ditolak_selama_kuis_satunya_berjalan(ready, gemini):
    gemini()
    main.QUESTION_JOBS[("m1", "post")] = main.QuestionDraftJob(
        job_id="j1", quiz_type="multiple_choice", total=5
    )
    response = start(ready, quiz_type="true_false")
    assert response.status_code == 409
    assert response.json()["detail"] == "Materi ini sedang dibuatkan jenis soal lain"


def test_materi_tanpa_teks_ditolak(ready, gemini, fake_db):
    fake = gemini()
    fake_db["material_sections"][0]["content"] = "[[gambar:xref-1]]"
    response = start(ready)
    assert response.status_code == 422
    assert fake.calls == []


@pytest.mark.parametrize("total", [0, 31])
def test_jumlah_soal_di_luar_batas_ditolak(ready, gemini, total):
    assert start(ready, total=total).status_code == 422


def test_kunci_belum_diatur_ditolak(ready, gemini, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "")
    assert start(ready).status_code == 503


def test_guru_lain_tidak_bisa_memakai(ready, gemini, login):
    fake = gemini()
    start(ready, total=1)
    login("teacher", "Guru Lain")
    assert start(ready, total=1).status_code in (403, 404)
    assert ready.get(URL, params={"test_kind": "pre"}).status_code in (403, 404)
    assert ready.delete(URL, params={"test_kind": "pre"}).status_code in (403, 404)
    assert len(fake.calls) == 1
