from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form
from schemas.ai_output import AIOutput
from dotenv import load_dotenv
import os
from supabase import create_client, ClientOptions
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import random
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone
from uuid import uuid4

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
supabase_admin = create_client(SUPABASE_URL, os.getenv("SUPABASE_SERVICE_KEY"))

app = FastAPI()


class SubmittedAnswer(BaseModel):
    question_id: str
    selected_option_ids: Optional[list[str]] = None
    boolean_value: Optional[bool] = None
    text_value: Optional[str] = None
    ordered_item_ids: Optional[list[str]] = None


class SubmittedAnswersRequest(BaseModel):
    answers: list[SubmittedAnswer]


security = HTTPBearer()


@app.get("/")
def root():
    return {"message": "Hello World"}


@app.get("/test-supabase")
def test_supabase():
    response = supabase.table("materials").select("*").limit(1).execute()
    return {"data": response.data}


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    access_token = credentials.credentials

    try:
        response = supabase.auth.get_user(access_token)
        user = response.user
        if user is None:
            raise HTTPException(status_code=401, detail="Token tidak valid")
        return {"user": user, "access_token": access_token}
    except Exception:
        raise HTTPException(
            status_code=401, detail="Token tidak valid atau sudah kadaluwarsa"
        )


@app.get("/test-auth")
def test_auth(auth=Depends(get_current_user)):
    user = auth["user"]
    return {"message": "Token valid", "user_id": user.id}


@app.get("/debug-auth")
def debug_auth(auth=Depends(get_current_user)):
    user = auth["user"]
    access_token = auth["access_token"]
    user_supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {access_token}"}),
    )
    response = (
        user_supabase.table("quizzes")
        .select("id", "teacher_id")
        .eq("id", "fe14572e-34c3-4629-8d42-4fb60b176b14")
        .execute()
    )
    return {"fastapi_user_id": user.id, "quiz_data": response.data}


@app.get("/debug-policy")
def debug_policy(auth=Depends(get_current_user)):
    access_token = auth["access_token"]

    user_supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {access_token}"}),
    )

    response = (
        user_supabase.table("quizzes")
        .select("id, teacher_id")
        .eq("id", "fe14572e-34c3-4629-8d42-4fb60b176b14")
        .eq("teacher_id", auth["user"].id)
        .execute()
    )

    return {"user_id": auth["user"].id, "matching_quiz": response.data}


@app.post("/test-login")
def test_login():
    response = supabase.auth.sign_in_with_password(
        {"email": "guru.test@aprevo.local", "password": "pwsementara"}
    )
    return {"access_token": response.session.access_token}


@app.post("/quizzes/{quiz_id}/ai-output")
def save_ai_output(quiz_id: str, data: AIOutput, auth=Depends(get_current_user)):
    user = auth["user"]
    access_token = auth["access_token"]
    user_supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {access_token}"}),
    )
    quiz_response = (
        user_supabase.table("quizzes")
        .select("teacher_id")
        .eq("id", quiz_id)
        .single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None:
        raise HTTPException(status_code=404, detail="Quiz tidak ditemukan")
    if quiz["teacher_id"] != user.id:
        raise HTTPException(status_code=403, detail="Anda bukan pemilik quiz ini")

    saved_questions = []

    for question in data.questions:
        question_data = {
            "quiz_id": quiz_id,
            "type": question.type,
            "question": question.question,
        }
        question_response = (
            supabase_admin.table("questions").insert(question_data).execute()
        )
        saved_question = question_response.data[0]
        if question.type == "multiple_choice":
            options_data = [
                {
                    "question_id": saved_question["id"],
                    "text": option.text,
                    "is_correct": option.is_correct,
                }
                for option in question.options
            ]
            supabase_admin.table("question_options").insert(options_data).execute()
        elif question.type == "true_false":
            supabase_admin.table("questions").update(
                {"correct_answer": question.correct_answer}
            ).eq("id", saved_question["id"]).execute()
            saved_question["correct_answer"] = question.correct_answer
        elif question.type == "text":
            answers_data = [
                {"question_id": saved_question["id"], "answer": answer.answer}
                for answer in question.answers
            ]
            supabase_admin.table("question_answers").insert(answers_data).execute()
        elif question.type == "ordering":
            items_data = [
                {
                    "question_id": saved_question["id"],
                    "text": item.text,
                    "correct_order": item.correct_order,
                }
                for item in question.items
            ]
            supabase_admin.table("question_items").insert(items_data).execute()
        saved_questions.append(saved_question)

    return {"message": "Questions berhasil disimpan!", "questions": saved_questions}


@app.get("/quizzes/{quiz_id}")
def get_quiz(quiz_id: str, auth=Depends(get_current_user)):
    user = auth["user"]
    access_token = auth["access_token"]
    user_supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {access_token}"}),
    )
    quiz_response = (
        user_supabase.table("quizzes")
        .select("id, title, material_id, teacher_id, attempt_limit, created_at")
        .eq("id", quiz_id)
        .eq("teacher_id", user.id)
        .is_("deleted_at", "null")
        .single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None:
        raise HTTPException(status_code=404, detail="Quiz tidak ditemukan")
    questions_response = (
        supabase_admin.table("questions")
        .select("id, type, question, correct_answer")
        .eq("quiz_id", quiz_id)
        .execute()
    )
    questions = questions_response.data

    for question in questions:
        question_id = question["id"]
        if question["type"] == "multiple_choice":
            response = (
                supabase_admin.table("question_options")
                .select("id, text, is_correct")
                .eq("question_id", question_id)
                .execute()
            )
            question["options"] = response.data
        elif question["type"] == "text":
            response = (
                supabase_admin.table("question_answers")
                .select("id, answer")
                .eq("question_id", question_id)
                .execute()
            )
            question["answer"] = response.data
        elif question["type"] == "ordering":
            response = (
                supabase_admin.table("question_items")
                .select("id, text, correct_order")
                .eq("question_id", question_id)
                .order("correct_order")
                .execute()
            )
            question["items"] = response.data

    return {"quiz": quiz, "questions": questions}


@app.get("/student/materials")
def get_student_materials(auth=Depends(get_current_user)):
    user_id = str(auth["user"].id)
    profile_response = (
        supabase_admin.table("users")
        .select("id, role")
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat emngakses daftar maetri"
        )
    access_response = (
        supabase_admin.table("material_access")
        .select("material_id")
        .eq("student_id", user_id)
        .execute()
    )
    material_ids = [row["material_id"] for row in (access_response.data or [])]
    if not material_ids:
        return {"materials": []}
    materials_response = (
        supabase_admin.table("materials")
        .select("id, title, is_published")
        .in_("id", material_ids)
        .eq("is_published", True)
        .execute()
    )
    return {"materials": materials_response.data or []}


@app.get("/student/quizzes/{quiz_id}")
def get_student_quiz(quiz_id: str, auth=Depends(get_current_user)):
    user = auth["user"]
    user_id = str(user.id)

    profile_response = (
        supabase_admin.table("users")
        .select("id, role")
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat mengakses kuis"
        )

    quiz_response = (
        supabase_admin.table("quizzes")
        .select("id, title, material_id, attempt_limit, deleted_at")
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    material_id = quiz["material_id"]

    material_response = (
        supabase_admin.table("materials")
        .select("id, is_published")
        .eq("id", material_id)
        .maybe_single()
        .execute()
    )
    material = material_response.data
    if material is None or not material["is_published"]:
        raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")

    access_response = (
        supabase_admin.table("material_access")
        .select("id")
        .eq("material_id", material_id)
        .eq("student_id", user_id)
        .limit(1)
        .execute()
    )
    if not access_response.data:
        raise HTTPException(
            status_code=403, detail="Anda tidak memiliki akses ke materi ini"
        )

    questions_response = (
        supabase_admin.table("questions")
        .select("id, type, question")
        .eq("quiz_id", quiz_id)
        .execute()
    )
    questions = questions_response.data or []
    if not questions:
        raise HTTPException(status_code=400, detail="Kuis belum memiliki soal")

    for question in questions:
        question_id = question["id"]
        question_type = question["type"]
        if question_type == "multiple_choice":
            options_response = (
                supabase_admin.table("question_options")
                .select("id, text")
                .eq("question_id", question_id)
                .execute()
            )
            options = options_response.data or []
            random.shuffle(options)
            question["options"] = options
        elif question_type == "true_false":
            pass
        elif question_type == "text":
            pass
        elif question_type == "ordering":
            items_response = (
                supabase_admin.table("question_items")
                .select("id, text")
                .eq("question_id", question_id)
                .execute()
            )
            items = items_response.data or []
            random.shuffle(items)
            question["items"] = items

    return {
        "quiz": {
            "id": quiz["id"],
            "title": quiz["title"],
            "attempt_limit": quiz["attempt_limit"],
        },
        "questions": questions,
    }


@app.post("/quizzes/{quiz_id}/attempts")
def start_quiz_attempt(quiz_id: str, auth=Depends(get_current_user)):
    user = auth["user"]
    profile_supabase = (
        supabase_admin.table("users")
        .select("id, role")
        .eq("id", str(user.id))
        .maybe_single()
        .execute()
    )
    profile = profile_supabase.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat memulai kuis"
        )
    quiz_response = (
        supabase_admin.table("quizzes")
        .select("id, material_id, attempt_limit, deleted_at")
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    material_id = quiz["material_id"]
    material_response = (
        supabase_admin.table("materials")
        .select("id,is_published")
        .eq("id", material_id)
        .maybe_single()
        .execute()
    )
    material = material_response.data
    if material is None or not material["is_published"]:
        raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")
    access_response = (
        supabase_admin.table("material_access")
        .select("id")
        .eq("material_id", material_id)
        .eq("student_id", str(user.id))
        .limit(1)
        .execute()
    )
    if not access_response.data:
        raise HTTPException(
            status_code=403, detail="Anda tidak memiliki akses ke materi ini"
        )
    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .select("id, submitted_at")
        .eq("quiz_id", quiz_id)
        .eq("student_id", str(user.id))
        .execute()
    )
    previous_attempts = attempt_response.data or []
    unfinished_attempt = next(
        (attempt for attempt in previous_attempts if attempt["submitted"] is None), None
    )
    if unfinished_attempt is not None:
        return {
            "message": "Melanjutkan percobaan kuius yang belum selesai",
            "attempt": unfinished_attempt,
        }
    attempt_limit = quiz["attempt_limit"]
    if attempt_limit is not None and len(previous_attempts) >= attempt_limit:
        raise HTTPException(
            status_code=403, detail="Batas percobaan kuis sudah tercapai"
        )

    questions_response = (
        supabase_admin.table("questions").select("id").eq("quiz_id", quiz_id).execute()
    )
    total_questions = len(questions_response.data)
    if total_questions == 0:
        raise HTTPException(status_code=400, detail="Kuis belum memiliki soal")
    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .insert(
            {
                "quiz_id": quiz_id,
                "student_id": str(user.id),
                "total_questions": total_questions,
            }
        )
        .execute()
    )
    attempt = attempt_response.data
    return {"message": "Percobaan kuis berhasil dimulai", "attempt": attempt}


@app.post("/student/attempts/{attempt_id}/submit")
def submit_quiz_answers(
    attempt_id: str, data: SubmittedAnswersRequest, auth=Depends(get_current_user)
):
    user_id = str(auth["user"].id)

    profile_response = (
        supabase_admin.table("users")
        .select("id, role")
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat mengiirm jawaban"
        )

    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .select("id, quiz_id, student_id, submitted_at, total_questions")
        .eq("id", attempt_id)
        .eq("student_id", user_id)
        .maybe_single()
        .execute()
    )
    attempt = attempt_response.data
    if attempt is None:
        raise HTTPException(status_code=409, detail="Percobaan kuis tidak ditemukan")
    if attempt["submitted_at"] is not None:
        raise HTTPException(status_code=409, detail="Percobaan kuis sudah dikumpulkan")
    quiz_id = attempt["quiz_id"]

    questions_response = (
        supabase_admin.table("questions")
        .select("id, type, correct_answer")
        .eq("quiz_id", quiz_id)
        .execute()
    )
    questions = questions_response.data or []
    question_map = {q["id"]: q for q in questions}
    if not questions:
        raise HTTPException(status_code=400, detail="Kuis belum memiliki soal")

    submitted_ids = [a.question_id for a in data.answers]
    if len(submitted_ids) != len(set(submitted_ids)) or set(submitted_ids) != set(
        question_map.keys()
    ):
        raise HTTPException(
            status_code=400, detail="Jawaban harus mencakup setiap soal tepat satu kali"
        )
    correct_count = 0

    for submitted in data.answers:
        question = question_map[submitted.question_id]
        question_id = submitted.question_id
        question_type = question["type"]

        # hanya satu jawaban yg boleh diisi
        provided_values = [
            submitted.selected_option_ids is not None,
            submitted.boolean_value is not None,
            submitted.text_value is not None,
            submitted.ordered_item_ids is not None,
        ]
        if sum(provided_values) != 1:
            raise HTTPException(
                status_code=400,
                detail=f"Format jawaban tidak valid untuk soal {question_id}",
            )
        answer_id_response = (
            supabase_admin.table("answers")
            .insert({"attempt_id": attempt_id, "question_id": question_id})
            .execute()
        )
        answer_id = answer_id_response.data[0]["id"]
        is_correct = False
        if question_type == "multiple_choice":
            selected_ids = submitted.selected_option_ids
            if not selected_ids:
                raise HTTPException(
                    status_code=400,
                    detail="Pilih minimal satu opsi untuk soal pilihan ganda",
                )
            if len(selected_ids) != len(set(selected_ids)):
                raise HTTPException(
                    status_code=400,
                    detail="Opsi yang sama tidak boleh dipilih lebih dari sekali",
                )
            option_response = (
                supabase_admin.table("question_options")
                .select("id, is_correct")
                .eq("question_id", question_id)
                .execute()
            )
            options = option_response.data or []
            option_map = {option["id"]: option for option in options}
            if any(option_id not in option_map for option_id in selected_ids):
                raise HTTPException(
                    status_code=400,
                    detail="Terdapat opsi yang tidak valid untuk soal ini",
                )
            answer_option_rows = [
                {"answer_id": answer_id, "option_id": option_id}
                for option_id in selected_ids
            ]
            supabase_admin.table("answer_options").insert(answer_option_rows).execute()
            correct_ids = {
                option["id"] for option in options if option["is_correct"] is True
            }
            is_correct = set(selected_ids) == correct_ids
        elif question_type == "true_false":
            if (
                submitted.selected_option_ids is not None
                or submitted.boolean_value is None
                or submitted.text_value is not None
                or submitted.ordered_item_ids is not None
            ):
                raise HTTPException(
                    status_code=400, detail="Jawaban harus berupa true atau false"
                )
            supabase_admin.table("answer_boolean").insert(
                {"answer_id": answer_id, "value": submitted.boolean_value}
            ).execute()
            is_correct = submitted.boolean_value == question["correct_answer"]
        elif question_type == "text":
            if (
                submitted.selected_option_ids is not None
                or submitted.boolean_value is not None
                or submitted.text_value is None
                or submitted.ordered_item_ids is not None
            ):
                raise HTTPException(status_code=400, detail="Jawaban harus berupa teks")
            supabase_admin.table("answer_text").insert(
                {"answer_id": answer_id, "value": submitted.text_value}
            ).execute()
            accepted_response = (
                supabase_admin.table("question_answers")
                .select("answer")
                .eq("question_id", question_id)
                .execute()
            )
            accepted_answers = accepted_response.data or []
            normalize = lambda value: " ".join(value.strip().casefold().split())
            is_correct = any(
                normalize(submitted.text_value) == normalize(item["answer"])
                for item in accepted_answers
            )
        elif question_type == "ordering":
            if (
                submitted.selected_option_ids is not None
                or submitted.boolean_value is not None
                or submitted.text_value is not None
                or submitted.ordered_item_ids is None
            ):
                raise HTTPException(
                    status_code=400, detail="Jawaban harus berupa urutan item"
                )
            items_response = (
                supabase_admin.table("question_items")
                .select("id, correct_order")
                .eq("question_id", question_id)
                .execute()
            )
            items = items_response.data or []
            item_ids = [item["id"] for item in items]
            if len(submitted.ordered_item_ids) != len(
                set(submitted.ordered_item_ids)
            ) or set(submitted.ordered_item_ids) != set(item_ids):
                raise HTTPException(
                    status_code=400,
                    detail="Urutan harus memuat semua item tepat satu kali",
                )
            order_rows = [
                {"answer_id": answer_id, "item_id": item_id, "selected_order": position}
                for position, item_id in enumerate(submitted.ordered_item_ids, start=1)
            ]
            if order_rows:
                supabase_admin.table("answer_order_items").insert(order_rows).execute()
            expected_order = [
                item["id"]
                for item in sorted(items, key=lambda item: item["correct_order"])
            ]
            is_correct = submitted.ordered_item_ids == expected_order
        else:
            raise HTTPException(
                status_code=400, detail=f"Tipe soal tidak dikenal: {question_type}"
            )

        if is_correct:
            correct_count += 1

    supabase_admin.table("quiz_attempts").update(
        {
            "correct_count": correct_count,
            "total_questions": len(questions),
            "submitted_at": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", attempt_id).eq("student_id", user_id).execute()

    return {
        "message": "Jawaban berhasil dikumpulkan",
        "attempt_id": attempt_id,
        "correct_count": correct_count,
        "total_questions": len(questions),
    }


@app.post("/validate-ai")
def validate_ai(data: AIOutput):
    return {"message": "Output AI valid!", "data": data}


@app.post("/teacher/materials/upload")
async def upload_material_pdf(
    title: str = Form(...),
    file: UploadFile = File(...),
    current_user=Depends(get_current_user),
):
    user = current_user["user"]
    user_data = (
        supabase_admin.table("users")
        .select("role")
        .eq("id", str(user.id))
        .single()
        .execute()
    )
    if not user_data.data or user_data.data["role"] != "teacher":
        raise HTTPException(
            status_code=403, detail="Hanya guru yang boleh mengunggah materi."
        )

    if file.content_type != "application/pdf":
        raise HTTPException(status_code=400, detail="File harus berformat PDF.")
    file_bytes = await file.read()
    if not file_bytes.startswith(b"%PDF-"):
        raise HTTPException(status_code=400, detail="Isi file bukan pdf yang valid.")
    max_size = 20 * 1024 * 1024
    if len(file_bytes) > max_size:
        raise HTTPException(status_code=413, detail="Ukuran PDF maksimal 20 MB.")

    teacher_id = str(user.id)
    file_path = f"{teacher_id}/{uuid4()}.pdf"
    try:
        supabase_admin.storage.from_("materials-pdf").upload(
            path=file_path,
            file=file_bytes,
            file_options={"content-type": "application/pdf", "upsert": "false"},
        )
    except Exception as e:
        print("ERROR SUPABASE STORAGE:", repr(e))
        raise HTTPException(
            status_code=500, 
            detail="Gagal mengunggah PDF ke penyimpanan."
        )

    try:
        result = (
            supabase_admin.table("materials")
            .insert(
                {
                    "title": title,
                    "file_url": file_path,
                    "teacher_id": teacher_id,
                    "is_published": False,
                }
            )
            .execute()
        )
        return {"message": "PDF berhasil diunggah.", "material": result.data[0]}
    except Exception:
        try:
            supabase_admin.storage.from_("materials-pdf").remove([file_path])
        except Exception:
            pass
        raise HTTPException(
            status_code=500,
            detail="PDF tersimpan, tetapi metadata materi gagal disimpan.",
        )
