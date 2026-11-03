"""Menghapus kelas menghentikan proses AI-nya dan membuang hasilnya."""

import pytest

import main
from test_endpoints import iso
from test_generate_questions import FakeGemini, gemini, ready, start  # noqa: F401
from test_images import storage, upload  # noqa: F401


def mark_deleted(fake_db):
    fake_db["subjects"][0]["deleted_at"] = iso(-0.01)


def test_endpoint_hapus_menghentikan_proses_kelas_itu_saja(
    ready, fake_db, storage  # noqa: F811
):
    subject_id = fake_db["subjects"][0]["id"]
    question = main.QuestionDraftJob(job_id="a", quiz_type="true_false", total=5)
    describe = main.DescribeJob()
    other_question = main.QuestionDraftJob(job_id="b", quiz_type="true_false", total=5)
    other_describe = main.DescribeJob()
    main.QUESTION_JOBS[("m1", "pre")] = question
    main.DESCRIBE_JOBS["m1"] = describe
    main.QUESTION_JOBS[("lain", "pre")] = other_question
    main.DESCRIBE_JOBS["lain"] = other_describe

    response = ready.delete(f"/teacher/subjects/{subject_id}")

    assert response.status_code == 200, response.text
    assert question.cancelled and describe.cancelled
    assert not other_question.cancelled and not other_describe.cancelled
    assert list(main.QUESTION_JOBS) == [("lain", "pre")]
    assert list(main.DESCRIBE_JOBS) == ["lain"]


def test_pembuatan_soal_berhenti_setelah_kelas_dihapus(
    ready, fake_db, monkeypatch  # noqa: F811
):
    fake = FakeGemini()

    def generate(**kwargs):
        result = fake(**kwargs)
        mark_deleted(fake_db)
        main.cancel_ai_jobs(["m1"])
        return result

    monkeypatch.setattr(main, "generate_quiz", generate)

    assert start(ready, total=20).status_code == 200

    # 20 soal butuh dua panggilan; yang kedua tidak pernah terjadi.
    assert len(fake.calls) == 1
    assert main.QUESTION_JOBS == {}


@pytest.mark.parametrize("by_flag", [True, False], ids=["tanda", "deleted_at"])
def test_proses_soal_tidak_memanggil_gemini_kalau_sudah_dibatalkan(
    ready, fake_db, gemini, by_flag  # noqa: F811
):
    fake = gemini()
    job = main.QuestionDraftJob(
        job_id="a",
        quiz_type="true_false",
        total=3,
        subject_id=fake_db["subjects"][0]["id"],
    )
    if by_flag:
        job.cancelled = True
    else:
        mark_deleted(fake_db)

    main.run_question_job(job, "materi")

    assert fake.calls == []
    assert job.questions == []
    assert job.error is None
    assert job.running is False


def test_deskripsi_yang_sedang_dibuat_dibuang_dan_sisanya_berhenti(
    client, login, fake_db, storage, monkeypatch  # noqa: F811
):
    material_id, _ = upload(client, login, fake_db)
    photos = [
        {
            "id": f"g{number}",
            "material_id": material_id,
            "image_key": f"xref-{number}",
            "page_number": 1,
            "image_url": f"g{number}.png",
            "description": None,
            "is_decorative": False,
        }
        for number in (1, 2, 3)
    ]
    fake_db["material_images"] = photos
    storage.files.update({("material-images", p["image_url"]): b"x" for p in photos})
    monkeypatch.setattr(main, "material_content_image_keys", lambda _id: [])
    calls = []

    def describe(_bytes):
        calls.append(1)
        mark_deleted(fake_db)
        main.cancel_ai_jobs([material_id])
        return "Hasil yang harus dibuang."

    monkeypatch.setattr(main, "describe_image", describe)

    response = client.post(
        f"/teacher/materials/{material_id}/generate-image-description"
    )

    assert response.status_code == 202, response.text
    assert len(calls) == 1
    assert [row["description"] for row in fake_db["material_images"]] == [None] * 3
    assert main.DESCRIBE_JOBS == {}


def test_coba_ulang_satu_gambar_dibuang_kalau_kelas_dihapus(
    client, login, fake_db, storage, monkeypatch  # noqa: F811
):
    material_id, _ = upload(client, login, fake_db)
    row = next(r for r in fake_db["material_images"] if not r["is_decorative"])

    def describe(_bytes):
        mark_deleted(fake_db)
        return "Hasil yang harus dibuang."

    monkeypatch.setattr(main, "describe_image", describe)

    response = client.post(
        f"/teacher/materials/{material_id}/images/{row['id']}/describe"
    )

    assert response.status_code == 404, response.text
    assert row["description"] is None


def test_berkas_materi_lama_dihapus_kalau_kelas_dihapus_saat_disiapkan(
    client, login, fake_db, storage, monkeypatch  # noqa: F811
):
    material_id, _ = upload(client, login, fake_db)
    fake_db["material_images"] = []
    for key in [key for key in storage.files if key[0] == "material-images"]:
        del storage.files[key]
    monkeypatch.setattr(
        main, "material_content_image_keys", lambda _id: ["xref-tidak-tersimpan"]
    )
    material = next(m for m in fake_db["materials"] if m["id"] == material_id)
    job = main.DescribeJob(subject_id=material["subject_id"])
    uploaded = []
    bucket_type = type(storage.from_("material-images"))
    real_upload = bucket_type.upload

    def upload_then_delete(self, path, file, file_options):
        real_upload(self, path, file, file_options)
        uploaded.append(path)
        job.cancelled = True

    monkeypatch.setattr(bucket_type, "upload", upload_then_delete)

    main.run_describe_job(job, material, material["teacher_id"])

    assert uploaded, "tes harus benar-benar mengunggah berkas"
    assert not [key for key in storage.files if key[0] == "material-images"]
    assert fake_db["material_images"] == []
    assert job.error is None
    assert job.running is False
