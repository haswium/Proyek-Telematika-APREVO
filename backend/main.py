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
import pymupdf
import logging

print("DEBUG: MAIN.PY TERLOAD", flush=True)

logging.basicConfig(level=logging.INFO)

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
supabase_admin = create_client(SUPABASE_URL, os.getenv("SUPABASE_SERVICE_KEY"))
TEST_LOGIN_EMAIL = os.getenv("TEST_LOGIN_EMAIL")
TEST_LOGIN_PASSWORD = os.getenv("TEST_LOGIN_PASSWORD")

app = FastAPI()


@app.middleware("http")
async def debug_request(request, call_next):
    print(f">>> REQUEST MASUK: {request.method} {request.url.path}", flush=True)
    try:
        response = await call_next(request)
        print(f">>> RESPONSE: {response.status_code}", flush=True)
        return response
    except Exception as exc:
        import traceback

        traceback.print_exc()
        raise

class SubmittedAnswer(BaseModel):
    question_id: str
    selected_option_ids: Optional[list[str]] = None
    boolean_value: Optional[bool] = None
    text_value: Optional[str] = None
    ordered_item_ids: Optional[list[str]] = None


class AutosaveAnswerRequest(BaseModel):
    selected_option_ids: Optional[list[str]] = None
    boolean_value: Optional[bool] = None
    text_value: Optional[str] = None
    ordered_item_ids: Optional[list[str]] = None


class SubmittedAnswersRequest(BaseModel):
    answers: list[SubmittedAnswer]


def check_quiz_schedule(quiz):
    available_from = quiz["available_from"]
    deadline_at = quiz["deadline_at"]
    if available_from is None or deadline_at is None:
        raise HTTPException(
            status_code=500, detail="Jadwal kuis belum dikonfigurasi dengan benar"
        )
    start_time = datetime.fromisoformat(available_from.replace("Z", "+00:00"))
    deadline = datetime.fromisoformat(deadline_at.replace("Z", "+00:00"))
    if deadline <= start_time:
        raise HTTPException(status_code=500, detail="Jadwal kuis tidak valid")
    now = datetime.now(timezone.utc)
    if now < start_time:
        raise HTTPException(status_code=403, detail="Kuis belum tersedia")
    if now >= deadline:
        raise HTTPException(status_code=403, detail="Deadline kuis telah lewat")
    return deadline


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
    if not TEST_LOGIN_EMAIL or not TEST_LOGIN_PASSWORD:
        raise HTTPException(
            status_code=500,
            detail="Kredensial pengujian belum dikonfigurasi",
        )

    try:
        response = supabase.auth.sign_in_with_password(
            {
                "email": TEST_LOGIN_EMAIL,
                "password": TEST_LOGIN_PASSWORD,
            }
        )
    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Login pengujian gagal",
        )

    if not response.session:
        raise HTTPException(
            status_code=401,
            detail="Sesi login tidak tersedia",
        )

    return {"access_token": response.session.access_token}


@app.post("/quizzes/{quiz_id}/questions")
def save_ai_output(quiz_id: str, data: AIOutput, auth=Depends(get_current_user)):
    user = auth["user"]
    access_token = auth["access_token"]
    profile_response = (
        supabase_admin.table("users")
        .select("role")
        .eq("id", str(user.id))
        .maybe_single()
        .execute()
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "teacher":
        raise HTTPException(
            status_code=403, detail="Hanya guru yang boleh mengakses endpoint ini"
        )
    user_supabase = create_client(
        SUPABASE_URL,
        SUPABASE_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {access_token}"}),
    )
    quiz_response = (
        user_supabase.table("quizzes")
        .select("teacher_id")
        .eq("id", quiz_id)
        .maybe_single()
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
    profile_response = (
        supabase_admin.table("users")
        .select("role")
        .eq("id", str(user.id))
        .maybe_single()
        .execute()
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "teacher":
        raise HTTPException(
            status_code=403, detail="Hanya guru yang boleh mengakses endpoint ini"
        )
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
        .maybe_single()
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
    questions = questions_response.data or []

    for question in questions:
        question_id = question["id"]
        if question["type"] == "multiple_choice":
            response = (
                supabase_admin.table("question_options")
                .select("id, text, is_correct")
                .eq("question_id", question_id)
                .execute()
            )
            question["options"] = response.data or []
        elif question["type"] == "text":
            response = (
                supabase_admin.table("question_answers")
                .select("id, answer")
                .eq("question_id", question_id)
                .execute()
            )
            question["answer"] = response.data or []
        elif question["type"] == "ordering":
            response = (
                supabase_admin.table("question_items")
                .select("id, text, correct_order")
                .eq("question_id", question_id)
                .order("correct_order")
                .execute()
            )
            question["items"] = response.data or []

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
        .select(
            "id, material_id, attempt_limit, deleted_at, available_from, deadline_at"
        )
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    check_quiz_schedule(quiz)
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
        (attempt for attempt in previous_attempts if attempt["submitted_at"] is None),
        None,
    )
    if unfinished_attempt is not None:
        return {
            "message": "Melanjutkan percobaan kuis yang belum selesai",
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
    attempt = attempt_response.data[0]
    return {"message": "Percobaan kuis berhasil dimulai", "attempt": attempt}


@app.put("/student/attempts/{attempt_id}/answers/{question_id}")
def autosave_quiz_answer(
    attempt_id: str,
    question_id: str,
    data: SubmittedAnswer,
    auth=Depends(get_current_user),
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
            status_code=403, detail="Hanya siswa yang dapat menyimpan jawaban"
        )
    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .select("id, quiz_id, student_id, submitted_at")
        .eq("id", attempt_id)
        .eq("student_id", user_id)
        .maybe_single()
        .execute()
    )
    attempt = attempt_response.data
    if attempt is None:
        raise HTTPException(status_code=404, detail="Percobaan kuis tidak ditemukan")
    if attempt["submitted_at"] is not None:
        raise HTTPException(status_code=409, detail="Percobaan kuis sudah selesai")
    quiz_response = (
        supabase_admin.table("quizzes")
        .select("id, available_from, deadline_at, deleted_at")
        .eq("id", attempt["quiz_id"])
        .maybe_single()
        .execute()
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    check_quiz_schedule(quiz)
    if str(data.question_id) != question_id:
        raise HTTPException(
            status_code=400, detail="ID soal pada URL dan body tidak sama"
        )
    question_response = (
        supabase_admin.table("questions")
        .select("id, type, correct_answer")
        .eq("id", question_id)
        .eq("quiz_id", attempt["quiz_id"])
        .maybe_single()
        .execute()
    )
    question = question_response.data
    if question is None:
        raise HTTPException(
            status_code=404, detail="Soal tidak ditemukan dalam kuis ini"
        )
    provided_values = [
        data.selected_option_ids is not None,
        data.boolean_value is not None,
        data.text_value is not None,
        data.ordered_item_ids is not None,
    ]
    if sum(provided_values) != 1:
        raise HTTPException(status_code=400, detail="Kirim tepat satu format jawaban")
    question_type = question["type"]
    is_correct = False
    answer_options = []
    answer_boolean = None
    answer_text = None
    answer_order_items = []
    if question_type == "multiple_choice":
        selected_ids = data.selected_option_ids
        if selected_ids is None or len(selected_ids) != 1:
            raise HTTPException(
                status_code=400,
                detail="Pilih tepat satu opsi",
            )
        if len(selected_ids) != len(set(selected_ids)):
            raise HTTPException(
                status_code=400, detail="Opsi yang sama tidak boleh dipilih berulang"
            )
        options_response = (
            supabase_admin.table("question_options")
            .select("id, is_correct")
            .eq("question_id", question_id)
            .execute()
        )
        options = options_response.data or []
        option_map = {str(option["id"]): option for option in options}
        selected_id = selected_ids[0]
        if selected_id not in option_map:
            raise HTTPException(
                status_code=400,
                detail="Opsi tidak valid untuk soal ini",
            )
        correct_ids = {
            str(option["id"]) for option in options if option["is_correct"] is True
        }
        if len(correct_ids) != 1:
            raise HTTPException(
                status_code=400,
                detail="Soal harus memiliki tepat satu opsi benar",
            )
        is_correct = selected_id in correct_ids
        answer_options = [{"option_id": selected_id}]
    elif question_type == "true_false":
        if data.boolean_value is None:
            raise HTTPException(
                status_code=400, detail="Jawaban harus berupa true atau false"
            )
        if not isinstance(question["correct_answer"], bool):
            raise HTTPException(
                status_code=500, detail="Kunci jawaban beanr/salah belum valid"
            )
        is_correct = data.boolean_value == question["correct_answer"]
        answer_boolean = {"value": data.boolean_value}
    elif question_type == "text":
        if data.text_value is None:
            raise HTTPException(status_code=400, detail="Jawaban harus berupa teks")
        accepted_response = (
            supabase_admin.table("question_answers")
            .select("answer")
            .eq("question_id", question_id)
            .execute()
        )
        accepted_answers = accepted_response.data or []
        normalize = lambda value: " ".join(value.strip().casefold().split())
        is_correct = any(
            normalize(data.text_value) == normalize(item["answer"])
            for item in accepted_answers
        )
        answer_text = {"value": data.text_value}
    elif question_type == "ordering":
        ordered_ids = data.ordered_item_ids
        if ordered_ids is None:
            raise HTTPException(
                staus_code=400, detail="Jawaban harus berupa urutan item"
            )
        if len(ordered_ids) != len(set(ordered_ids)):
            raise HTTPException(
                status_code=400, detail="Item yang sama tidak boleh muncul berulang"
            )
        items_response = (
            supabase_admin.table("question_items")
            .select("id, correct_order")
            .eq("question_id", question_id)
            .execute()
        )
        items = items_response.data or []
        item_map = {str(item["id"]): item for item in items}
        valid_item_ids = set(item_map.keys())
        if set(ordered_ids) != valid_item_ids:
            raise HTTPException(
                status_code=400, detail="Urutan harus memuat semua item tepat satu kali"
            )
        expected_order = [
            str(item["id"])
            for item in sorted(items, key=lambda item: item["correct_order"])
        ]
        is_correct = ordered_ids == expected_order
        answer_order_items = [
            {"item_id": item_id, "selected_order": position}
            for position, item_id in enumerate(ordered_ids, start=1)
        ]
    else:
        raise HTTPException(
            status_code=400, detail=f"Tipe soal tidak dikenal: {question_type}"
        )
    answer_response = (
        supabase_admin.table("answers")
        .upsert(
            {
                "attempt_id": attempt_id,
                "question_id": question_id,
            },
            on_conflict="attempt_id,question_id",
        )
        .execute()
    )
    if not answer_response.data:
        raise HTTPException(status_code=500, detail="Jawaban gagal disimpan")
    answer_id = answer_response.data[0]["id"]
    supabase_admin.table("answer_options").delete().eq("answer_id", answer_id).execute()
    supabase_admin.table("answer_boolean").delete().eq("answer_id", answer_id).execute()
    supabase_admin.table("answer_text").delete().eq("answer_id", answer_id).execute()
    supabase_admin.table("answer_order_items").delete().eq(
        "answer_id", answer_id
    ).execute()
    if answer_options:
        supabase_admin.table("answer_options").insert(
            [
                {"answer_id": answer_id, "option_id": item["option_id"]}
                for item in answer_options
            ]
        ).execute()
    elif answer_boolean is not None:
        supabase_admin.table("answer_boolean").insert(
            {"answer_id": answer_id, "value": answer_boolean["value"]}
        ).execute()
    elif answer_text is not None:
        supabase_admin.table("answer_text").insert(
            {"answer_id": answer_id, "value": answer_text["value"]}
        ).execute()
    elif answer_order_items:
        supabase_admin.table("answer_order_items").insert(
            [
                {
                    "answer_id": answer_id,
                    "item_id": item["item_id"],
                    "selected_order": item["selected_order"],
                }
                for item in answer_order_items
            ]
        ).execute()
    return {
        "message": "Jawaban berhasil disimpan",
        "attempt_id": attempt_id,
        "question_id": question_id,
        "is_correct": is_correct,
    }


@app.post("/student/attempts/{attempt_id}/submit")
def submit_quiz_answers(attempt_id: str, auth=Depends(get_current_user)):
    print("DEBUG: ENDPOINT SUBMIT TERPANGGIL", flush=True)
    try:
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
                status_code=403, detail="Hanya siswa yang dapat mengumpulkan jawaban"
            )

        attempt_response = (
            supabase_admin.table("quiz_attempts")
            .select("id, quiz_id, student_id, submitted_at")
            .eq("id", attempt_id)
            .eq("student_id", user_id)
            .maybe_single()
            .execute()
        )
        attempt = attempt_response.data
        if attempt is None:
            raise HTTPException(
                status_code=409, detail="Percobaan kuis tidak ditemukan"
            )
        if attempt["submitted_at"] is not None:
            raise HTTPException(
                status_code=409, detail="Percobaan kuis sudah dikumpulkan"
            )
        quiz_response = (
            supabase_admin.table("quizzes")
            .select("id, deadline_at, deleted_at")
            .eq("id", attempt["quiz_id"])
            .maybe_single()
            .execute()
        )
        quiz = quiz_response.data
        if quiz is None or quiz["deleted_at"] is not None:
            raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
        if quiz["deadline_at"] is None:
            raise HTTPException(
                status_code=500, detail="Jadwal kuis belum dikonfigurasi dnegan benar"
            )
        deadline = datetime.fromisoformat(quiz["deadline_at"].replace("Z", "+00:00"))
        if deadline.tzinfo is None:
            deadline = deadline.replace(tzinfo=timezone.utc)
        submitted_at = datetime.now(timezone.utc)
        questions_response = (
            supabase_admin.table("questions")
            .select("id, type, correct_answer")
            .eq("quiz_id", attempt["quiz_id"])
            .execute()
        )
        questions = questions_response.data or []
        if not questions:
            raise HTTPException(status_code=400, detail="Kuis belum memiliki soal")
        question_ids = [question["id"] for question in questions]
        answer_response = (
            supabase_admin.table("answers")
            .select("id, question_id")
            .eq("attempt_id", attempt_id)
            .execute()
        )
        saved_answers = answer_response.data or []
        answer_map = {answer["question_id"]: answer["id"] for answer in saved_answers}
        if any(question_id not in question_ids for question_id in answer_map):
            raise HTTPException(
                status_code=500, detail="Terdapat jawaban yang tidak sesuai dengan kuis"
            )
        correct_count = 0
        for question in questions:
            question_id = question["id"]
            question_type = question["type"]
            answer_id = answer_map.get(question_id)
            if answer_id is None:
                continue
            is_correct = False
            if question_type == "multiple_choice":
                selected_response = (
                    supabase_admin.table("answer_options")
                    .select("option_id")
                    .eq("answer_id", answer_id)
                    .execute()
                )
                selected_ids = {
                    row["option_id"] for row in (selected_response.data or [])
                }
                options_response = (
                    supabase_admin.table("question_options")
                    .select("id, is_correct")
                    .eq("question_id", question_id)
                    .execute()
                )
                options = options_response.data or []
                correct_ids = {
                    option["id"] for option in options if option["is_correct"] is True
                }
                is_correct = len(correct_ids) == 1 and selected_ids == correct_ids
            elif question_type == "true_false":
                boolean_response = (
                    supabase_admin.table("answer_boolean")
                    .select("value")
                    .eq("answer_id", answer_id)
                    .maybe_single()
                    .execute()
                )
                boolean_answer = boolean_response.data
                is_correct = (
                    boolean_answer is not None
                    and boolean_answer["value"] == question["correct_answer"]
                )
            elif question_type == "text":
                text_response = (
                    supabase_admin.table("answer_text")
                    .select("value")
                    .eq("answer_id", answer_id)
                    .maybe_single()
                    .execute()
                )
                text_answer = text_response.data
                accepted_response = (
                    supabase_admin.table("question_answers")
                    .select("answer")
                    .eq("question_id", question_id)
                    .execute()
                )
                accepted_answers = accepted_response.data or []
                if text_answer is not None:
                    normalize = lambda value: " ".join(value.strip().casefold().split())
                    is_correct = any(
                        normalize(text_answer["value"]) == normalize(item["answer"])
                        for item in accepted_answers
                    )
            elif question_type == "ordering":
                order_response = (
                    supabase_admin.table("answer_order_items")
                    .select("item_id, selected_order")
                    .eq("answer_id", answer_id)
                    .execute()
                )
                selected_items = order_response.data or []
                items_response = (
                    supabase_admin.table("question_items")
                    .select("id, correct_order")
                    .eq("question_id", question_id)
                    .execute()
                )
                items = items_response.data or []
                selected_order = [
                    row["item_id"]
                    for row in sorted(
                        selected_items, key=lambda row: row["selected_order"]
                    )
                ]
                expected_order = [
                    item["id"]
                    for item in sorted(items, key=lambda item: item["correct_order"])
                ]
                is_correct = (
                    len(selected_order) == len(expected_order)
                    and selected_order == expected_order
                )
            else:
                raise HTTPException(
                    status_code=400, detail=f"Tipe soal tidak dikenal: {question_type}"
                )
            if is_correct:
                correct_count += 1
        update_response = (
            supabase_admin.table("quiz_attempts")
            .update(
                {
                    "correct_count": correct_count,
                    "total_questions": len(questions),
                    "submitted_at": submitted_at.isoformat(),
                }
            )
            .eq("id", attempt_id)
            .eq("student_id", user_id)
            .is_("submitted_at", "null")
            .execute()
        )
        if not update_response.data:
            raise HTTPException(
                status_code=409, detail="Percobaan kuis sudah dikumpulkan"
            )
        return {
            "message": "Jawaban berhasil dikumpulkan",
            "attempt_id": attempt_id,
            "correct_count": correct_count,
            "total_questions": len(questions),
            "submitted_at": submitted_at.isoformat(),
            "deadline_passed": submitted_at >= deadline,
        }
    except HTTPException:
        raise
    except Exception:
        logging.exception("Error saat submit kuis")
        raise


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

    try:
        with fitz.open(stream=file_bytes, filetype="pdf") as pdf:
            extracted_text = "\n".join(page.get_text() for page in pdf)
            total_pages = len(pdf)
            total_images = sum(len(page.get_images(full=True)) for page in pdf)
    except Exception as e:
        print("ERROR EKSTRAKSI PDF:", repr(e))
        raise HTTPException(
            status_code=400, detail="PDF tidak dapat diproses: {str(e)}"
        )

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
            status_code=500, detail="Gagal mengunggah PDF ke penyimpanan."
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
        return {
            "message": "PDF berhasil diunggah dan diekstraksi.",
            "material": result.data[0],
            "extraction": {
                "total_pages": total_pages,
                "total_images": total_images,
                "extracted_text": extracted_text,
            },
        }
    except Exception:
        try:
            supabase_admin.storage.from_("materials-pdf").remove([file_path])
        except Exception:
            pass
        raise HTTPException(
            status_code=500,
            detail="PDF tersimpan, tetapi metadata materi gagal disimpan.",
        )
