import re
from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

import main
from schemas.ai_output import AIOutput

NOW = datetime(2026, 10, 25, 12, tzinfo=timezone.utc)


def schedule(start_hours, end_hours):
    return {
        "available_from": (NOW + timedelta(hours=start_hours)).isoformat(),
        "deadline_at": (NOW + timedelta(hours=end_hours)).isoformat(),
    }


def test_kode_akses_enam_huruf_kapital():
    for _ in range(50):
        assert re.fullmatch(r"[A-Z]{6}", main.generate_access_code())


def test_kode_dari_siswa_dinormalisasi():
    assert main.normalize_access_code(" kxp-rta ") == "KXPRTA"


@pytest.mark.parametrize(
    "start, end, status",
    [(1, 2, "upcoming"), (-1, 1, "open"), (-2, -1, "closed"), (0, 1, "open"), (-1, 0, "closed")],
)
def test_status_kuis(start, end, status):
    assert main.quiz_status(schedule(start, end), NOW) == status


def test_status_kuis_tanpa_jadwal():
    assert main.quiz_status({"available_from": None, "deadline_at": None}) == "unscheduled"


def test_pembahasan_terbuka_tepat_saat_tenggat():
    assert not main.discussion_available(schedule(-2, 1), NOW)
    assert main.discussion_available(schedule(-2, 0), NOW)
    assert not main.discussion_available({"deadline_at": None}, NOW)


def test_pilihan_ganda_harus_satu_jawaban_benar():
    question = {
        "type": "multiple_choice",
        "question": "Ibu kota Indonesia?",
        "explanation": "Jakarta adalah ibu kota.",
        "options": [
            {"text": "Jakarta", "is_correct": True},
            {"text": "Bandung", "is_correct": True},
        ],
    }
    with pytest.raises(ValidationError):
        AIOutput(questions=[question])
    question["options"][1]["is_correct"] = False
    parsed = AIOutput(questions=[question])
    assert parsed.questions[0].explanation == "Jakarta adalah ibu kota."


@pytest.mark.parametrize(
    "origin, allowed",
    [
        ("http://localhost:5173", True),
        ("http://127.0.0.1:8000", True),
        ("http://192.168.1.20:3000", True),
        ("http://10.0.2.2:8000", True),
        ("http://172.20.5.1", True),
        ("http://172.32.0.1", False),
        ("https://example.com", False),
        ("http://localhost.evil.com", False),
    ],
)
def test_cors_hanya_jaringan_lokal(origin, allowed):
    assert bool(re.fullmatch(main.LOCAL_ORIGIN_REGEX, origin)) is allowed
