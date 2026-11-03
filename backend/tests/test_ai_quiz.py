"""Aturan generate_quiz. Gemini diganti tiruan yang mengembalikan JSON tetap."""

import json
from types import SimpleNamespace

import pytest

import ai_quiz


def options(count=4, correct=1):
    return [
        {"text": f"Pilihan {i}", "is_correct": i < correct}
        for i in range(count)
    ]


def mc(**changes):
    return {
        "type": "multiple_choice",
        "question": "Apa warna amplop?",
        "explanation": "Amplopnya coklat muda.",
        "options": options(),
        **changes,
    }


@pytest.fixture
def gemini(monkeypatch):
    """Memasang jawaban Gemini tiruan. Mengembalikan daftar prompt yang dikirim."""
    prompts = []

    def install(questions):
        def generate_content(model, contents, config):
            prompts.append(contents)
            return SimpleNamespace(text=json.dumps({"questions": questions}))

        client = SimpleNamespace(
            models=SimpleNamespace(generate_content=generate_content)
        )
        monkeypatch.setattr(ai_quiz, "gemini_client", lambda: client)
        return prompts

    return install


def test_soal_yang_valid_diterima(gemini):
    gemini([mc()])
    result = ai_quiz.generate_quiz("Materi", 1, "multiple_choice")
    assert result.questions[0].question == "Apa warna amplop?"


@pytest.mark.parametrize(
    "question, message",
    [
        (mc(explanation=None), "penjelasan"),
        (mc(explanation="   "), "penjelasan"),
        (mc(question="  "), "Teks soal"),
        (mc(options=options(count=5)), "maksimal 4"),
        (mc(options=options(correct=2)), "tepat 1 jawaban benar"),
        (mc(options=options(correct=0)), "tepat 1 jawaban benar"),
        (
            {
                "type": "text",
                "question": "Warna?",
                "explanation": "Coklat.",
                "answers": [{"answer": " "}],
            },
            "tidak boleh kosong",
        ),
    ],
)
def test_soal_yang_melanggar_aturan_ditolak(gemini, question, message):
    gemini([question])
    quiz_type = question["type"]
    with pytest.raises(ValueError, match=message):
        ai_quiz.generate_quiz("Materi", 1, quiz_type)


def test_urutan_lebih_dari_4_langkah_ditolak(gemini):
    gemini(
        [
            {
                "type": "ordering",
                "question": "Urutkan",
                "explanation": "Sesuai langkah.",
                "items": [{"text": f"L{i}", "correct_order": i} for i in range(1, 6)],
            }
        ]
    )
    with pytest.raises(ValueError, match="maksimal 4"):
        ai_quiz.generate_quiz("Materi", 1, "ordering")


def test_isian_boleh_punya_lebih_dari_4_jawaban(gemini):
    gemini(
        [
            {
                "type": "text",
                "question": "Sebutkan warna",
                "explanation": "Ada banyak warna.",
                "answers": [{"answer": f"Warna {i}"} for i in range(6)],
            }
        ]
    )
    assert len(ai_quiz.generate_quiz("Materi", 1, "text").questions[0].answers) == 6


def test_jenis_soal_yang_berbeda_dari_permintaan_ditolak(gemini):
    gemini([mc()])
    with pytest.raises(ValueError, match="tipe soal"):
        ai_quiz.generate_quiz("Materi", 1, "true_false")


def test_jumlah_soal_harus_sesuai_permintaan(gemini):
    gemini([mc()])
    with pytest.raises(ValueError, match="meminta 2 soal"):
        ai_quiz.generate_quiz("Materi", 2, "multiple_choice")


def test_prompt_memuat_aturan_dan_soal_yang_dihindari(gemini):
    prompts = gemini([mc()])
    ai_quiz.generate_quiz("Materi", 1, "multiple_choice")
    assert "2 sampai 4 opsi" in prompts[0]
    assert "wajib punya penjelasan" in prompts[0]
    assert "Jangan mengulang" not in prompts[0]

    ai_quiz.generate_quiz(
        "Materi", 1, "multiple_choice", avoid_questions=["Siapa pengirimnya?"]
    )
    assert "Jangan mengulang" in prompts[1]
    assert "Siapa pengirimnya?" in prompts[1]
