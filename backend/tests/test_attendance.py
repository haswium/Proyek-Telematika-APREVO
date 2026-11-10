"""Presensi per pertemuan: sesi guru, tombol Hadir siswa, alpa otomatis, rekap."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

import main
from test_delete_subject import storage  # noqa: F401  (fixture)
from test_endpoints import setup_subject

# 10.00 WIB.
NOW = datetime(2026, 11, 10, 3, 0, tzinfo=timezone.utc)


@pytest.fixture
def clock(monkeypatch):
    """Jam server tiruan. clock.now bisa dimajukan di tengah tes."""
    state = SimpleNamespace(now=NOW)
    monkeypatch.setattr(main, "server_now", lambda: state.now)
    return state


def act_as(user_id):
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "user": SimpleNamespace(id=user_id),
        "access_token": "token",
    }


@pytest.fixture
def kelas(client, login, fake_db, clock):
    """Kelas milik Bu Rina dengan siswa Andi dan Budi. Akun aktif: guru."""
    teacher_id, subject, _ = setup_subject(client, login, fake_db)
    students = {}
    for name in ("Budi", "Andi"):
        student_id = login("student", name)
        students[name] = student_id
        fake_db.setdefault("subject_students", []).append(
            {
                "subject_id": subject["id"],
                "student_id": student_id,
                "joined_at": "2026-11-01T00:00:00+00:00",
            }
        )
    outsider = login("student", "Cici")
    act_as(teacher_id)
    return SimpleNamespace(
        id=subject["id"],
        teacher=teacher_id,
        students=students,
        outsider=outsider,
        as_teacher=lambda: act_as(teacher_id),
        as_student=lambda name: act_as(students[name]),
    )


def open_session(client, kelas, **body):
    kelas.as_teacher()
    response = client.post(
        f"/teacher/subjects/{kelas.id}/attendance/sessions",
        json={"title": "Pertemuan 3", "close_preset": "30m", **body},
    )
    assert response.status_code == 200, response.text
    return response.json()["session"]


def student_view(client, kelas, name):
    kelas.as_student(name)
    response = client.get(f"/student/subjects/{kelas.id}/attendance")
    assert response.status_code == 200, response.text
    return response.json()


# ---- Membuka sesi


@pytest.mark.parametrize(
    "preset, minutes", [("15m", 15), ("30m", 30), ("1h", 60)]
)
def test_pilihan_cepat_dihitung_dari_jam_server(client, kelas, preset, minutes):
    session = open_session(client, kelas, close_preset=preset)
    assert session["state"] == "open"
    assert datetime.fromisoformat(session["opens_at"]) == NOW
    assert datetime.fromisoformat(session["closes_at"]) == NOW + timedelta(
        minutes=minutes
    )
    assert session["seconds_until_close"] == minutes * 60
    assert session["seconds_until_open"] is None


def test_akhir_hari_memakai_zona_wib(client, kelas, clock):
    # 23.30 WIB, 9 November.
    clock.now = datetime(2026, 11, 9, 16, 30, tzinfo=timezone.utc)
    session = open_session(client, kelas, close_preset="end_of_day")
    closes = datetime.fromisoformat(session["closes_at"])
    assert closes == datetime(2026, 11, 9, 16, 59, 59, tzinfo=timezone.utc)
    assert closes.utcoffset() == timedelta(hours=7)


def test_atur_sendiri_dengan_zona_dan_tanpa_zona(client, kelas):
    session = open_session(
        client,
        kelas,
        close_preset=None,
        opens_at="2026-11-10T11:00:00+07:00",
        closes_at="2026-11-10T12:00:00+07:00",
    )
    assert session["state"] == "upcoming"
    assert session["seconds_until_open"] == 3600
    # Tanpa zona dianggap WIB.
    session = open_session(
        client, kelas, close_preset=None, closes_at="2026-11-10T10:45:00"
    )
    assert datetime.fromisoformat(session["closes_at"]) == NOW + timedelta(
        minutes=45
    )


@pytest.mark.parametrize(
    "body, detail",
    [
        ({"close_preset": None}, "Pilih waktu tutup"),
        (
            {"close_preset": "15m", "closes_at": "2026-11-10T12:00:00+07:00"},
            "Pilih waktu tutup",
        ),
        (
            {
                "close_preset": None,
                "opens_at": "2026-11-10T12:00:00+07:00",
                "closes_at": "2026-11-10T11:00:00+07:00",
            },
            "harus setelah waktu buka",
        ),
        (
            # Jam HP mungkin bilang belum lewat, tetapi jam server 10.00.
            {"close_preset": None, "opens_at": "2026-11-10T08:00:00+07:00",
             "closes_at": "2026-11-10T09:59:00+07:00"},
            "sudah lewat",
        ),
        ({"title": "   "}, "Judul sesi wajib diisi"),
    ],
)
def test_validasi_sesi(client, kelas, body, detail):
    response = client.post(
        f"/teacher/subjects/{kelas.id}/attendance/sessions",
        json={"title": "Pertemuan 3", "close_preset": "30m", **body},
    )
    assert response.status_code == 422
    assert detail in response.json()["detail"]


# ---- Otorisasi


def test_hanya_guru_pemilik_yang_mengelola(client, kelas, login):
    session = open_session(client, kelas)
    login("teacher", "Pak Lain")
    paths = [
        ("get", f"/teacher/subjects/{kelas.id}/attendance/sessions", None),
        ("post", f"/teacher/subjects/{kelas.id}/attendance/sessions",
         {"title": "X", "close_preset": "15m"}),
        ("get", f"/teacher/subjects/{kelas.id}/attendance/summary", None),
        ("get", f"/teacher/attendance/sessions/{session['id']}", None),
        ("patch", f"/teacher/attendance/sessions/{session['id']}",
         {"close_now": True}),
        ("delete", f"/teacher/attendance/sessions/{session['id']}", None),
        ("put",
         f"/teacher/attendance/sessions/{session['id']}/students/"
         f"{kelas.students['Andi']}",
         {"status": "izin"}),
    ]
    for method, path, body in paths:
        kwargs = {"json": body} if body is not None else {}
        response = getattr(client, method)(path, **kwargs)
        assert response.status_code == 404, (method, path)

    # Siswa tidak boleh memakai endpoint guru.
    kelas.as_student("Andi")
    assert (
        client.get(f"/teacher/subjects/{kelas.id}/attendance/sessions").status_code
        == 403
    )
    # Guru tidak boleh memakai endpoint siswa.
    kelas.as_teacher()
    assert (
        client.post(
            f"/student/attendance/sessions/{session['id']}/present"
        ).status_code
        == 403
    )


def test_siswa_bukan_anggota_ditolak(client, kelas):
    session = open_session(client, kelas)
    act_as(kelas.outsider)
    assert client.get(f"/student/subjects/{kelas.id}/attendance").status_code == 403
    response = client.post(f"/student/attendance/sessions/{session['id']}/present")
    assert response.status_code == 403


def test_kelas_dihapus_ditolak(client, kelas, fake_db):
    session = open_session(client, kelas)
    for subject in fake_db["subjects"]:
        subject["deleted_at"] = "2026-11-10T02:00:00+00:00"

    kelas.as_student("Andi")
    for response in (
        client.get(f"/student/subjects/{kelas.id}/attendance"),
        client.post(f"/student/attendance/sessions/{session['id']}/present"),
    ):
        assert response.status_code == 410
        assert response.json()["detail"] == main.SUBJECT_DELETED_DETAIL

    kelas.as_teacher()
    assert (
        client.get(f"/teacher/subjects/{kelas.id}/attendance/sessions").status_code
        == 404
    )
    assert (
        client.get(f"/teacher/attendance/sessions/{session['id']}").status_code
        == 404
    )


def test_menghapus_kelas_ikut_menghapus_presensi(client, kelas, fake_db, storage):
    session = open_session(client, kelas)
    kelas.as_student("Andi")
    client.post(f"/student/attendance/sessions/{session['id']}/present")
    assert fake_db["attendance_records"]

    kelas.as_teacher()
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    assert fake_db["attendance_records"] == []
    assert fake_db["attendance_sessions"] == []


def test_sesi_tersisa_membuat_penghapusan_bisa_dilanjutkan(
    client, kelas, fake_db, storage
):
    open_session(client, kelas)
    for subject in fake_db["subjects"]:
        subject["deleted_at"] = "2026-11-10T02:00:00+00:00"
    fake_db["subject_students"] = []
    assert kelas.id in main.subjects_with_leftovers([kelas.id])
    assert client.delete(f"/teacher/subjects/{kelas.id}").status_code == 200
    assert fake_db["attendance_sessions"] == []


# ---- Tombol Hadir


def test_hadir_sekali_per_sesi(client, kelas):
    session = open_session(client, kelas)
    kelas.as_student("Andi")
    path = f"/student/attendance/sessions/{session['id']}/present"

    first = client.post(path)
    assert first.status_code == 200
    assert first.json()["session"]["status"] == "hadir"
    assert first.json()["session"]["source"] == "siswa"

    second = client.post(path)
    assert second.status_code == 409
    assert second.json()["detail"] == "Kamu sudah tercatat hadir di Pertemuan 3"


def test_hadir_hanya_selama_sesi_terbuka(client, kelas, clock):
    session = open_session(
        client,
        kelas,
        close_preset=None,
        opens_at="2026-11-10T11:00:00+07:00",
        closes_at="2026-11-10T12:00:00+07:00",
    )
    kelas.as_student("Andi")
    path = f"/student/attendance/sessions/{session['id']}/present"
    response = client.post(path)
    assert response.status_code == 409
    assert response.json()["detail"] == "Sesi presensi belum dibuka"

    clock.now = datetime(2026, 11, 10, 5, 0, tzinfo=timezone.utc)  # 12.00 WIB
    response = client.post(path)
    assert response.status_code == 409
    assert response.json()["detail"] == "Sesi presensi sudah ditutup"

    clock.now = datetime(2026, 11, 10, 4, 30, tzinfo=timezone.utc)  # 11.30 WIB
    assert client.post(path).status_code == 200


def test_status_dari_guru_tidak_bisa_ditimpa_siswa(client, kelas):
    session = open_session(client, kelas)
    response = client.put(
        f"/teacher/attendance/sessions/{session['id']}/students/"
        f"{kelas.students['Andi']}",
        json={"status": "izin"},
    )
    assert response.status_code == 200
    kelas.as_student("Andi")
    response = client.post(f"/student/attendance/sessions/{session['id']}/present")
    assert response.status_code == 409
    assert response.json()["detail"] == (
        "Kamu sudah tercatat izin oleh guru di Pertemuan 3"
    )


# ---- Alpa otomatis dan rekap


def test_alpa_dihitung_saat_dibaca_setelah_sesi_tutup(client, kelas, clock, fake_db):
    session = open_session(client, kelas, close_preset="15m")
    kelas.as_student("Andi")
    client.post(f"/student/attendance/sessions/{session['id']}/present")

    # Selama sesi terbuka, Budi belum presensi, belum alpa.
    kelas.as_teacher()
    detail = client.get(f"/teacher/attendance/sessions/{session['id']}").json()
    assert {row["name"]: row["status"] for row in detail["students"]} == {
        "Andi": "hadir",
        "Budi": None,
    }
    assert detail["session"]["counts"] == {
        "hadir": 1, "izin": 0, "sakit": 0, "alpa": 0, "belum": 1,
    }
    assert student_view(client, kelas, "Budi")["counts"]["alpa"] == 0

    # Tanpa tugas terjadwal: begitu jam server lewat waktu tutup, Budi alpa.
    clock.now = NOW + timedelta(minutes=16)
    kelas.as_teacher()
    detail = client.get(f"/teacher/attendance/sessions/{session['id']}").json()
    assert detail["session"]["state"] == "closed"
    assert {row["name"]: row["status"] for row in detail["students"]} == {
        "Andi": "hadir",
        "Budi": "alpa",
    }
    assert detail["session"]["counts"]["alpa"] == 1
    assert detail["session"]["counts"]["belum"] == 0
    # Alpa tidak ditulis ke database.
    assert len(fake_db["attendance_records"]) == 1

    budi = student_view(client, kelas, "Budi")
    assert budi["counts"] == {"hadir": 0, "izin": 0, "sakit": 0, "alpa": 1}
    assert budi["sessions"][0]["status"] == "alpa"
    assert budi["sessions"][0]["state"] == "closed"


def test_siswa_baru_tidak_alpa_di_sesi_lama(client, kelas, clock, fake_db, login):
    session = open_session(client, kelas, close_preset="15m")
    clock.now = NOW + timedelta(hours=1)
    late = login("student", "Dodi")
    fake_db["subject_students"].append(
        {
            "subject_id": kelas.id,
            "student_id": late,
            "joined_at": (NOW + timedelta(minutes=30)).isoformat(),
        }
    )
    act_as(late)
    view = client.get(f"/student/subjects/{kelas.id}/attendance").json()
    assert view["sessions"] == []
    assert view["counts"]["alpa"] == 0

    kelas.as_teacher()
    detail = client.get(f"/teacher/attendance/sessions/{session['id']}").json()
    assert "Dodi" not in [row["name"] for row in detail["students"]]
    summary = client.get(f"/teacher/subjects/{kelas.id}/attendance/summary").json()
    dodi = next(row for row in summary["students"] if row["name"] == "Dodi")
    assert dodi["counts"] == {"hadir": 0, "izin": 0, "sakit": 0, "alpa": 0}


def test_guru_mengubah_status_dan_rekap_per_siswa(client, kelas, clock):
    first = open_session(client, kelas, title="Pertemuan 1", close_preset="15m")
    second = open_session(client, kelas, title="Pertemuan 2", close_preset="15m")
    kelas.as_student("Andi")
    client.post(f"/student/attendance/sessions/{first['id']}/present")
    clock.now = NOW + timedelta(minutes=20)

    kelas.as_teacher()
    andi, budi = kelas.students["Andi"], kelas.students["Budi"]
    for session, student, status in (
        (second, andi, "sakit"),
        (first, budi, "izin"),
        (first, budi, "hadir"),  # Diubah lagi: tetap satu catatan.
    ):
        response = client.put(
            f"/teacher/attendance/sessions/{session['id']}/students/{student}",
            json={"status": status},
        )
        assert response.status_code == 200
        assert response.json()["student"]["source"] == "guru"

    summary = client.get(f"/teacher/subjects/{kelas.id}/attendance/summary").json()
    assert summary["session_count"] == 2
    assert [(row["name"], row["counts"]) for row in summary["students"]] == [
        ("Andi", {"hadir": 1, "izin": 0, "sakit": 1, "alpa": 0}),
        ("Budi", {"hadir": 1, "izin": 0, "sakit": 0, "alpa": 1}),
    ]

    sessions = client.get(
        f"/teacher/subjects/{kelas.id}/attendance/sessions"
    ).json()["sessions"]
    counts = {row["title"]: row["counts"] for row in sessions}
    assert counts["Pertemuan 1"]["hadir"] == 2
    assert counts["Pertemuan 2"] == {
        "hadir": 0, "izin": 0, "sakit": 1, "alpa": 1, "belum": 0,
    }


def test_ubah_status_siswa_bukan_anggota_atau_status_salah(client, kelas):
    session = open_session(client, kelas)
    base = f"/teacher/attendance/sessions/{session['id']}/students"
    response = client.put(f"{base}/{kelas.outsider}", json={"status": "hadir"})
    assert response.status_code == 404
    response = client.put(
        f"{base}/{kelas.students['Andi']}", json={"status": "terlambat"}
    )
    assert response.status_code == 422


# ---- Mengubah dan menghapus sesi


def test_tutup_sekarang(client, kelas):
    session = open_session(client, kelas)
    path = f"/teacher/attendance/sessions/{session['id']}"
    response = client.patch(path, json={"close_now": True})
    assert response.status_code == 200
    assert response.json()["session"]["state"] == "closed"
    response = client.patch(path, json={"close_now": True})
    assert response.status_code == 409

    upcoming = open_session(
        client,
        kelas,
        close_preset=None,
        opens_at="2026-11-10T11:00:00+07:00",
        closes_at="2026-11-10T12:00:00+07:00",
    )
    response = client.patch(
        f"/teacher/attendance/sessions/{upcoming['id']}", json={"close_now": True}
    )
    assert response.status_code == 409


def test_ubah_judul_dan_perpanjang(client, kelas):
    session = open_session(client, kelas, close_preset="15m")
    path = f"/teacher/attendance/sessions/{session['id']}"
    response = client.patch(path, json={"title": " Pertemuan  4 ", "close_preset": "1h"})
    assert response.status_code == 200
    updated = response.json()["session"]
    assert updated["title"] == "Pertemuan 4"
    assert datetime.fromisoformat(updated["closes_at"]) == NOW + timedelta(hours=1)

    response = client.patch(path, json={"closes_at": "2026-11-10T09:00:00+07:00"})
    assert response.status_code == 422


def test_hapus_sesi_beserta_catatannya(client, kelas, fake_db):
    session = open_session(client, kelas)
    kelas.as_student("Andi")
    client.post(f"/student/attendance/sessions/{session['id']}/present")
    kelas.as_teacher()
    response = client.delete(f"/teacher/attendance/sessions/{session['id']}")
    assert response.status_code == 200
    assert fake_db["attendance_sessions"] == []
    assert fake_db["attendance_records"] == []
    assert student_view(client, kelas, "Andi")["sessions"] == []
