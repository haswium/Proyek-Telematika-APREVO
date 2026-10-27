from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from schemas.ai_output import AIOutput
from dotenv import load_dotenv
import os
from supabase import create_client, ClientOptions
from postgrest.exceptions import APIError
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import random
import re
import secrets
import string
from pydantic import BaseModel, Field
from typing import Literal, Optional
from datetime import datetime, timezone
from uuid import uuid4
import pymupdf
import logging
from pdf_sections import image_keys, page_images, plain_text, split_pdf_bytes
from ai_client import GeminiKeyMissing, gemini_client
from ai_quiz import generate_quiz
from PIL import UnidentifiedImageError
from ai_image import describe_image
import mimetypes

print("DEBUG: MAIN.PY TERLOAD", flush=True)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
supabase_admin = create_client(SUPABASE_URL, os.getenv("SUPABASE_SERVICE_KEY"))
TEST_LOGIN_EMAIL = os.getenv("TEST_LOGIN_EMAIL")
TEST_LOGIN_PASSWORD = os.getenv("TEST_LOGIN_PASSWORD")
ENABLE_DEBUG_ENDPOINTS = os.getenv("ENABLE_DEBUG_ENDPOINTS") == "1"

# localhost dan IP jaringan lokal (10.x, 172.16-31.x, 192.168.x) di port mana pun.
LOCAL_ORIGIN_REGEX = (
    r"^https?://(localhost|127\.0\.0\.1|\[::1\]"
    r"|10(\.\d{1,3}){3}"
    r"|172\.(1[6-9]|2\d|3[01])(\.\d{1,3}){2}"
    r"|192\.168(\.\d{1,3}){2})(:\d+)?$"
)
EXTRA_CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "").split(",")
    if origin.strip()
]

app = FastAPI()

SERVER_ERROR_DETAIL = (
    "Server mengalami kesalahan saat memproses permintaan. Coba lagi nanti, "
    "atau hubungi pengelola server kalau terus terjadi."
)


# Dipasang sebelum CORSMiddleware sehingga berada DI DALAM CORS: error yang
# tidak tertangkap tetap dijawab 500 dengan header CORS. Tanpa ini, browser
# membuang respons 500 dan aplikasi web mengira server tidak bisa dihubungi.
@app.middleware("http")
async def server_error_json(request, call_next):
    try:
        return await call_next(request)
    except Exception:
        logger.exception("Error tak tertangkap: %s %s", request.method, request.url.path)
        return JSONResponse(status_code=500, content={"detail": SERVER_ERROR_DETAIL})


app.add_middleware(
    CORSMiddleware,
    allow_origins=EXTRA_CORS_ORIGINS,
    allow_origin_regex=LOCAL_ORIGIN_REGEX,
    allow_methods=["*"],
    allow_headers=["*"],
)


class EmptyResponse:
    """Pengganti hasil maybe_single() yang bernilai None saat baris tidak ada."""

    data = None


EMPTY_RESPONSE = EmptyResponse()


def require_debug():
    if not ENABLE_DEBUG_ENDPOINTS:
        raise HTTPException(status_code=404, detail="Not Found")


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


@app.get("/test-supabase", dependencies=[Depends(require_debug)])
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


ROLE_LABELS = {"teacher": "guru", "student": "siswa"}


def get_current_profile(auth=Depends(get_current_user)):
    profile_response = (
        supabase_admin.table("users")
        .select("id, name, role")
        .eq("id", str(auth["user"].id))
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    profile = profile_response.data
    if profile is None or profile["role"] not in ROLE_LABELS:
        raise HTTPException(status_code=403, detail="Profil akun belum terdaftar")
    return {**auth, "user_id": str(auth["user"].id), "profile": profile}


def require_role(role: str):
    def dependency(auth=Depends(get_current_profile)):
        if auth["profile"]["role"] != role:
            raise HTTPException(
                status_code=403,
                detail=f"Hanya {ROLE_LABELS[role]} yang boleh mengakses endpoint ini",
            )
        return auth

    return dependency


require_teacher = require_role("teacher")
require_student = require_role("student")


def parse_time(value):
    if value is None:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def quiz_status(quiz, now=None):
    start_time = parse_time(quiz.get("available_from"))
    deadline = parse_time(quiz.get("deadline_at"))
    if start_time is None or deadline is None:
        return "unscheduled"
    now = now or datetime.now(timezone.utc)
    if now < start_time:
        return "upcoming"
    if now >= deadline:
        return "closed"
    return "open"


def discussion_available(quiz, now=None):
    deadline = parse_time(quiz.get("deadline_at"))
    if deadline is None:
        return False
    return (now or datetime.now(timezone.utc)) >= deadline


def is_subject_member(subject_id, student_id):
    if subject_id is None:
        return False
    response = (
        supabase_admin.table("subject_students")
        .select("subject_id")
        .eq("subject_id", subject_id)
        .eq("student_id", student_id)
        .limit(1)
        .execute()
    )
    return bool(response.data)


def student_can_access_material(material, student_id):
    """Akses lewat keanggotaan kelas, atau material_access lama."""
    if is_subject_member(material.get("subject_id"), student_id):
        return True
    access_response = (
        supabase_admin.table("material_access")
        .select("id")
        .eq("material_id", material["id"])
        .eq("student_id", student_id)
        .limit(1)
        .execute()
    )
    return bool(access_response.data)


def has_submitted_pre_test(material_id, student_id):
    """Post-test terkunci sampai pre-test materi yang sama dikumpulkan.

    Materi tanpa pre-test tidak mengunci post-test.
    """
    pre_response = (
        supabase_admin.table("quizzes")
        .select("id")
        .eq("material_id", material_id)
        .eq("kind", "pre")
        .is_("deleted_at", "null")
        .execute()
    )
    pre_ids = [row["id"] for row in (pre_response.data or [])]
    if not pre_ids:
        return True
    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .select("id")
        .in_("quiz_id", pre_ids)
        .eq("student_id", student_id)
        .not_.is_("submitted_at", "null")
        .limit(1)
        .execute()
    )
    return bool(attempt_response.data)


def check_post_test_unlocked(quiz, student_id):
    if quiz.get("kind") == "post" and not has_submitted_pre_test(
        quiz["material_id"], student_id
    ):
        raise HTTPException(status_code=403, detail="Kerjakan pre-test terlebih dahulu")


def get_owned_subject(subject_id, teacher_id):
    subject_response = (
        supabase_admin.table("subjects")
        .select("id, name, access_code, teacher_id, created_at")
        .eq("id", subject_id)
        .eq("teacher_id", teacher_id)
        .is_("deleted_at", "null")
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    subject = subject_response.data
    if subject is None:
        raise HTTPException(status_code=404, detail="Kelas tidak ditemukan")
    return subject


def get_owned_material(material_id, teacher_id):
    material_response = (
        supabase_admin.table("materials")
        .select("id, title, subject_id, teacher_id, is_published, created_at, file_url")
        .eq("id", material_id)
        .eq("teacher_id", teacher_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    material = material_response.data
    if material is None:
        raise HTTPException(status_code=404, detail="Materi tidak ditemukan")
    return material


@app.get("/test-auth", dependencies=[Depends(require_debug)])
def test_auth(auth=Depends(get_current_user)):
    user = auth["user"]
    return {"message": "Token valid", "user_id": user.id}


@app.get("/debug-auth", dependencies=[Depends(require_debug)])
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


@app.get("/debug-policy", dependencies=[Depends(require_debug)])
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


@app.post("/test-login", dependencies=[Depends(require_debug)])
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
        or EMPTY_RESPONSE
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
        or EMPTY_RESPONSE
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
            "explanation": question.explanation,
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
        or EMPTY_RESPONSE
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
        .select(
            "id, title, material_id, teacher_id, attempt_limit, created_at, "
            "kind, available_from, deadline_at"
        )
        .eq("id", quiz_id)
        .eq("teacher_id", user.id)
        .is_("deleted_at", "null")
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    quiz = quiz_response.data
    if quiz is None:
        raise HTTPException(status_code=404, detail="Quiz tidak ditemukan")
    questions_response = (
        supabase_admin.table("questions")
        .select("id, type, question, correct_answer, explanation")
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
        or EMPTY_RESPONSE
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat mengakses daftar materi"
        )
    access_response = (
        supabase_admin.table("material_access")
        .select("material_id")
        .eq("student_id", user_id)
        .execute()
    )
    material_ids = [row["material_id"] for row in (access_response.data or [])]
    membership_response = (
        supabase_admin.table("subject_students")
        .select("subject_id")
        .eq("student_id", user_id)
        .execute()
    )
    subject_ids = [row["subject_id"] for row in (membership_response.data or [])]
    materials = []
    if material_ids:
        materials_response = (
            supabase_admin.table("materials")
            .select("id, title, is_published")
            .in_("id", material_ids)
            .eq("is_published", True)
            .execute()
        )
        materials.extend(materials_response.data or [])
    if subject_ids:
        subject_materials_response = (
            supabase_admin.table("materials")
            .select("id, title, is_published")
            .in_("subject_id", subject_ids)
            .eq("is_published", True)
            .execute()
        )
        known_ids = {material["id"] for material in materials}
        materials.extend(
            material
            for material in (subject_materials_response.data or [])
            if material["id"] not in known_ids
        )
    return {"materials": materials}


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
        or EMPTY_RESPONSE
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat mengakses kuis"
        )

    quiz_response = (
        supabase_admin.table("quizzes")
        .select(
            "id, title, material_id, attempt_limit, deleted_at, "
            "kind, available_from, deadline_at"
        )
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    material_id = quiz["material_id"]

    material_response = (
        supabase_admin.table("materials")
        .select("id, is_published, subject_id")
        .eq("id", material_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    material = material_response.data
    if material is None or not material["is_published"]:
        raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")

    if not student_can_access_material(material, user_id):
        raise HTTPException(
            status_code=403, detail="Anda tidak memiliki akses ke materi ini"
        )
    check_quiz_schedule(quiz)
    check_post_test_unlocked(quiz, user_id)

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
        or EMPTY_RESPONSE
    )
    profile = profile_supabase.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya siswa yang dapat memulai kuis"
        )
    quiz_response = (
        supabase_admin.table("quizzes")
        .select(
            "id, material_id, attempt_limit, deleted_at, available_from, deadline_at, "
            "kind"
        )
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    quiz = quiz_response.data
    if quiz is None or quiz["deleted_at"] is not None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    check_quiz_schedule(quiz)
    material_id = quiz["material_id"]
    material_response = (
        supabase_admin.table("materials")
        .select("id,is_published,subject_id")
        .eq("id", material_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    material = material_response.data
    if material is None or not material["is_published"]:
        raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")
    if not student_can_access_material(material, str(user.id)):
        raise HTTPException(
            status_code=403, detail="Anda tidak memiliki akses ke materi ini"
        )
    check_post_test_unlocked(quiz, str(user.id))
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
        or EMPTY_RESPONSE
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
        or EMPTY_RESPONSE
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
        or EMPTY_RESPONSE
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
        or EMPTY_RESPONSE
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
                status_code=500, detail="Kunci jawaban benar/salah belum valid"
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
                status_code=400, detail="Jawaban harus berupa urutan item"
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
                "is_correct": is_correct,
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
            or EMPTY_RESPONSE
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
            or EMPTY_RESPONSE
        )
        attempt = attempt_response.data
        if attempt is None:
            raise HTTPException(
                status_code=404, detail="Percobaan kuis tidak ditemukan"
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
            or EMPTY_RESPONSE
        )
        quiz = quiz_response.data
        if quiz is None or quiz["deleted_at"] is not None:
            raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
        if quiz["deadline_at"] is None:
            raise HTTPException(
                status_code=500, detail="Jadwal kuis belum dikonfigurasi dengan benar"
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
                    or EMPTY_RESPONSE
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
                    or EMPTY_RESPONSE
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
            supabase_admin.table("answers").update({"is_correct": is_correct}).eq(
                "id", answer_id
            ).execute()
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


def build_review(attempt_id, quiz_id, include_key):
    """Soal dan jawaban siswa pada satu percobaan.

    include_key menambahkan jawaban benar dan pembahasan, hanya untuk dipakai
    setelah tenggat kuis lewat.
    """
    question_response = (
        supabase_admin.table("questions")
        .select("id, type, question, correct_answer, explanation")
        .eq("quiz_id", quiz_id)
        .execute()
    )
    questions = question_response.data or []
    answers_response = (
        supabase_admin.table("answers")
        .select("id, question_id, is_correct")
        .eq("attempt_id", attempt_id)
        .execute()
    )
    answers = answers_response.data or []
    answer_map = {str(answer["question_id"]): answer for answer in answers}
    review = []
    for question in questions:
        question_id = str(question["id"])
        answer = answer_map.get(question_id)
        answer_id = answer["id"] if answer else None
        item = {
            "question_id": question_id,
            "type": question["type"],
            "question": question["question"],
            "answer": None,
            "is_correct": answer.get("is_correct") if answer else False,
        }
        if question["type"] == "multiple_choice":
            options_response = (
                supabase_admin.table("question_options")
                .select("id, text, is_correct")
                .eq("question_id", question_id)
                .execute()
            )
            options = options_response.data or []
            selected_ids = set()
            if answer_id:
                selected_response = (
                    supabase_admin.table("answer_options")
                    .select("option_id")
                    .eq("answer_id", answer_id)
                    .execute()
                )
                selected_ids = {
                    str(row["option_id"]) for row in (selected_response.data or [])
                }
            item["options"] = []
            for option in options:
                option_item = {
                    "option_id": str(option["id"]),
                    "text": option["text"],
                    "selected": str(option["id"]) in selected_ids,
                }
                if include_key:
                    option_item["is_correct"] = option["is_correct"]
                item["options"].append(option_item)
        elif question["type"] == "true_false":
            if answer_id:
                response = (
                    supabase_admin.table("answer_boolean")
                    .select("value")
                    .eq("answer_id", answer_id)
                    .maybe_single()
                    .execute()
                    or EMPTY_RESPONSE
                )
                saved = response.data
                if saved is not None:
                    item["answer"] = saved["value"]
            if include_key:
                item["correct_answer"] = question["correct_answer"]
        elif question["type"] == "text":
            if answer_id:
                response = (
                    supabase_admin.table("answer_text")
                    .select("value")
                    .eq("answer_id", answer_id)
                    .maybe_single()
                    .execute()
                    or EMPTY_RESPONSE
                )
                saved = response.data
                if saved is not None:
                    item["answer"] = saved["value"]
            if include_key:
                accepted_response = (
                    supabase_admin.table("question_answers")
                    .select("answer")
                    .eq("question_id", question_id)
                    .execute()
                )
                item["accepted_answers"] = [
                    row["answer"] for row in (accepted_response.data or [])
                ]
        elif question["type"] == "ordering":
            items_response = (
                supabase_admin.table("question_items")
                .select("id, text, correct_order")
                .eq("question_id", question_id)
                .execute()
            )
            question_items = items_response.data or []
            selected_order_map = {}
            if answer_id:
                order_response = (
                    supabase_admin.table("answer_order_items")
                    .select("item_id, selected_order")
                    .eq("answer_id", answer_id)
                    .execute()
                )
                selected_order_map = {
                    str(row["item_id"]): row["selected_order"]
                    for row in (order_response.data or [])
                }
            item["items"] = []
            for question_item in sorted(
                question_items,
                key=lambda question_item: (
                    selected_order_map.get(str(question_item["id"])) is None,
                    selected_order_map.get(str(question_item["id"]), 0),
                ),
            ):
                order_item = {
                    "item_id": str(question_item["id"]),
                    "text": question_item["text"],
                    "selected_order": selected_order_map.get(str(question_item["id"])),
                }
                if include_key:
                    order_item["correct_order"] = question_item["correct_order"]
                item["items"].append(order_item)
        if include_key:
            item["explanation"] = question["explanation"]
        review.append(item)
    return review


def get_student_attempt(attempt_id, student_id):
    attempt_response = (
        supabase_admin.table("quiz_attempts")
        .select("id, quiz_id, student_id, submitted_at, correct_count, total_questions")
        .eq("id", attempt_id)
        .eq("student_id", student_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    attempt = attempt_response.data
    if attempt is None:
        raise HTTPException(status_code=404, detail="Percobaan kuis tidak ditemukan.")
    return attempt


def get_attempt_quiz(attempt):
    quiz_response = (
        supabase_admin.table("quizzes")
        .select("id, title, deadline_at")
        .eq("id", attempt["quiz_id"])
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    quiz = quiz_response.data
    if quiz is None:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan.")
    return quiz


@app.get("/student/attempts/{attempt_id}/result")
def get_quiz_result(attempt_id: str, auth=Depends(get_current_user)):
    user_id = str(auth["user"].id)
    profile_response = (
        supabase_admin.table("users")
        .select("id, role")
        .eq("id", user_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    profile = profile_response.data
    if profile is None or profile["role"] != "student":
        raise HTTPException(
            status_code=403, detail="Hanya murid yang boleh melihat hasil kuis."
        )
    attempt = get_student_attempt(attempt_id, user_id)
    if attempt["submitted_at"] is None:
        raise HTTPException(status_code=409, detail="Percobaan kuis belum dikumpulkan.")
    quiz = get_attempt_quiz(attempt)
    review = build_review(attempt_id, attempt["quiz_id"], include_key=False)
    return {
        "attempt_id": attempt["id"],
        "quiz_id": attempt["quiz_id"],
        "quiz_title": quiz["title"],
        "score": attempt["correct_count"],
        "total_questions": attempt["total_questions"],
        "submitted_at": attempt["submitted_at"],
        "deadline_at": quiz["deadline_at"],
        "discussion_available": discussion_available(quiz),
        "review": review,
    }


@app.get("/student/attempts/{attempt_id}/discussion")
def get_quiz_discussion(attempt_id: str, auth=Depends(require_student)):
    attempt = get_student_attempt(attempt_id, auth["user_id"])
    quiz = get_attempt_quiz(attempt)
    if not discussion_available(quiz):
        raise HTTPException(
            status_code=403,
            detail="Pembahasan baru terbuka setelah tenggat kuis lewat.",
        )
    review = build_review(attempt_id, attempt["quiz_id"], include_key=True)
    return {
        "attempt_id": attempt["id"],
        "quiz_id": attempt["quiz_id"],
        "quiz_title": quiz["title"],
        "score": attempt["correct_count"],
        "total_questions": attempt["total_questions"],
        "submitted_at": attempt["submitted_at"],
        "deadline_at": quiz["deadline_at"],
        "review": review,
    }


@app.post("/validate-ai")
def validate_ai(data: AIOutput, auth=Depends(require_teacher)):
    return {"message": "Output AI valid!", "data": data}


@app.post("/teacher/materials/upload")
async def upload_material_pdf(
    title: str = Form(...),
    file: UploadFile = File(...),
    subject_id: Optional[str] = Form(None),
    current_user=Depends(get_current_user),
):
    user = current_user["user"]
    user_data = (
        supabase_admin.table("users")
        .select("role")
        .eq("id", str(user.id))
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    if not user_data.data or user_data.data["role"] != "teacher":
        raise HTTPException(
            status_code=403, detail="Hanya guru yang boleh mengunggah materi."
        )
    teacher_id = str(user.id)
    if subject_id is not None:
        get_owned_subject(subject_id, teacher_id)

    # content_type dari klien tidak dipercaya: HP sering mengirim PDF sebagai
    # application/octet-stream. Yang diperiksa ekstensi dan isi file.
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="File harus berformat PDF.")
    file_bytes = await file.read()
    if not file_bytes.startswith(b"%PDF-"):
        raise HTTPException(status_code=400, detail="Isi file bukan PDF yang valid.")
    max_size = 20 * 1024 * 1024
    if len(file_bytes) > max_size:
        raise HTTPException(status_code=413, detail="Ukuran PDF maksimal 20 MB.")

    try:
        with pymupdf.open(stream=file_bytes, filetype="pdf") as pdf:
            extracted_text = "\n".join(page.get_text() for page in pdf)
            total_pages = len(pdf)
            total_images = sum(len(page.get_images(full=True)) for page in pdf)
        sections = split_pdf_bytes(file_bytes)
    except Exception as e:
        print("ERROR EKSTRAKSI PDF:", repr(e))
        raise HTTPException(status_code=400, detail="PDF tidak dapat diproses.")

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

    material = None
    image_paths = []
    try:
        result = (
            supabase_admin.table("materials")
            .insert(
                {
                    "title": title,
                    "file_url": file_path,
                    "teacher_id": teacher_id,
                    "subject_id": subject_id,
                    "is_published": False,
                }
            )
            .execute()
        )
        material = result.data[0]
        section_rows = [
            section.as_row(material["id"], position)
            for position, section in enumerate(sections, start=1)
        ]
        saved_sections = (
            supabase_admin.table("material_sections").insert(section_rows).execute()
        ).data or []
        # Gambar disimpan sekarang (belum dideskripsikan), supaya daftar
        # gambar dan syarat terbit langsung lengkap. Deskripsi AI dibuat lewat
        # endpoint generate-image-description, yang dipanggil aplikasi
        # setelah unggah selesai.
        with pymupdf.open(stream=file_bytes, filetype="pdf") as pdf:
            store_page_images(pdf, material["id"], teacher_id, set(), image_paths)
    except Exception as e:
        print("ERROR SIMPAN MATERI:", repr(e))
        if material is not None:
            try:
                # Tabel lama material_images tidak memakai on delete cascade.
                supabase_admin.table("material_images").delete().eq(
                    "material_id", material["id"]
                ).execute()
                supabase_admin.table("materials").delete().eq(
                    "id", material["id"]
                ).execute()
            except Exception:
                pass
        try:
            supabase_admin.storage.from_("materials-pdf").remove([file_path])
            if image_paths:
                supabase_admin.storage.from_("material-images").remove(image_paths)
        except Exception:
            pass
        raise HTTPException(
            status_code=500,
            detail="PDF tersimpan, tetapi metadata materi gagal disimpan.",
        )
    return {
        "message": "PDF berhasil diunggah dan diekstraksi.",
        "material": material,
        "extraction": {
            "total_pages": total_pages,
            "total_images": total_images,
            "extracted_text": extracted_text,
        },
        "sections": [
            {
                "id": section["id"],
                "position": section["position"],
                "title": section["title"],
                "page_start": section["page_start"],
                "page_end": section["page_end"],
                "image_count": section["image_count"],
            }
            for section in sorted(saved_sections, key=lambda row: row["position"])
        ],
    }


ACCESS_CODE_LETTERS = string.ascii_uppercase
ACCESS_CODE_RE = re.compile(r"^[A-Z]{6}$")


def generate_access_code():
    return "".join(secrets.choice(ACCESS_CODE_LETTERS) for _ in range(6))


def normalize_access_code(code: str) -> str:
    """Huruf kecil, spasi, dan strip dari input siswa diabaikan."""
    return re.sub(r"[\s-]", "", code).upper()


class SubjectCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class JoinSubjectRequest(BaseModel):
    code: str


class MaterialUpdateRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1)
    is_published: Optional[bool] = None


class QuizScheduleRequest(BaseModel):
    available_from: datetime
    deadline_at: datetime


class QuizCreateRequest(QuizScheduleRequest):
    kind: Literal["pre", "post"]
    title: Optional[str] = None
    attempt_limit: Optional[int] = Field(default=None, ge=1)


class GenerateQuizRequest(BaseModel):
    total_questions: int = Field(ge=1, le=30)
    quiz_type: Literal["multiple_choice", "true_false", "text", "ordering"]


def validate_schedule(data: QuizScheduleRequest):
    for value in (data.available_from, data.deadline_at):
        if value.tzinfo is None:
            raise HTTPException(
                status_code=400, detail="Waktu harus menyertakan zona waktu"
            )
    if data.deadline_at <= data.available_from:
        raise HTTPException(
            status_code=400, detail="Waktu tutup harus setelah waktu buka"
        )


def quizzes_by_material(material_ids):
    if not material_ids:
        return {}
    quizzes_response = (
        supabase_admin.table("quizzes")
        .select(
            "id, title, material_id, kind, attempt_limit, available_from, deadline_at"
        )
        .in_("material_id", material_ids)
        .is_("deleted_at", "null")
        .execute()
    )
    grouped = {material_id: [] for material_id in material_ids}
    for quiz in quizzes_response.data or []:
        grouped[quiz["material_id"]].append(quiz)
    for quizzes in grouped.values():
        quizzes.sort(key=lambda quiz: {"pre": 0, "post": 1}.get(quiz["kind"], 2))
    return grouped


def section_counts(material_ids):
    if not material_ids:
        return {}
    sections_response = (
        supabase_admin.table("material_sections")
        .select("material_id")
        .in_("material_id", material_ids)
        .execute()
    )
    counts = {material_id: 0 for material_id in material_ids}
    for row in sections_response.data or []:
        counts[row["material_id"]] += 1
    return counts


@app.post("/teacher/subjects")
def create_subject(data: SubjectCreateRequest, auth=Depends(require_teacher)):
    name = data.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Nama kelas wajib diisi")
    for _ in range(5):
        try:
            response = (
                supabase_admin.table("subjects")
                .insert(
                    {
                        "name": name,
                        "access_code": generate_access_code(),
                        "teacher_id": auth["user_id"],
                    }
                )
                .execute()
            )
            return {"message": "Kelas berhasil dibuat", "subject": response.data[0]}
        except APIError as error:
            # 23505: kode akses sudah dipakai, coba kode lain.
            if error.code != "23505":
                raise
    raise HTTPException(status_code=500, detail="Gagal membuat kode akses unik")


@app.get("/teacher/subjects")
def list_teacher_subjects(auth=Depends(require_teacher)):
    subjects_response = (
        supabase_admin.table("subjects")
        .select("id, name, access_code, created_at")
        .eq("teacher_id", auth["user_id"])
        .is_("deleted_at", "null")
        .order("created_at")
        .execute()
    )
    subjects = subjects_response.data or []
    subject_ids = [subject["id"] for subject in subjects]
    student_counts = {subject_id: 0 for subject_id in subject_ids}
    material_counts = {subject_id: 0 for subject_id in subject_ids}
    if subject_ids:
        members_response = (
            supabase_admin.table("subject_students")
            .select("subject_id")
            .in_("subject_id", subject_ids)
            .execute()
        )
        for row in members_response.data or []:
            student_counts[row["subject_id"]] += 1
        materials_response = (
            supabase_admin.table("materials")
            .select("subject_id")
            .in_("subject_id", subject_ids)
            .execute()
        )
        for row in materials_response.data or []:
            material_counts[row["subject_id"]] += 1
    return {
        "subjects": [
            {
                **subject,
                "student_count": student_counts[subject["id"]],
                "material_count": material_counts[subject["id"]],
            }
            for subject in subjects
        ]
    }


@app.get("/teacher/subjects/{subject_id}/materials")
def list_teacher_subject_materials(subject_id: str, auth=Depends(require_teacher)):
    subject = get_owned_subject(subject_id, auth["user_id"])
    materials_response = (
        supabase_admin.table("materials")
        .select("id, title, is_published, created_at")
        .eq("subject_id", subject_id)
        .order("created_at")
        .execute()
    )
    materials = materials_response.data or []
    material_ids = [material["id"] for material in materials]
    quizzes = quizzes_by_material(material_ids)
    counts = section_counts(material_ids)
    return {
        "subject": subject,
        "materials": [
            {
                **material,
                "section_count": counts.get(material["id"], 0),
                "quizzes": [
                    {**quiz, "status": quiz_status(quiz)}
                    for quiz in quizzes.get(material["id"], [])
                ],
            }
            for material in materials
        ],
    }


@app.patch("/teacher/materials/{material_id}")
def update_material(
    material_id: str, data: MaterialUpdateRequest, auth=Depends(require_teacher)
):
    get_owned_material(material_id, auth["user_id"])
    changes = data.model_dump(exclude_none=True)
    if not changes:
        raise HTTPException(status_code=400, detail="Tidak ada perubahan")
    if changes.get("is_published"):
        pages = undescribed_image_pages(material_id)
        if pages:
            known = sorted({page for page in pages if page})
            where = f" (halaman {', '.join(map(str, known))})" if known else ""
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Materi belum bisa diterbitkan: {len(pages)} gambar{where} "
                    "belum punya deskripsi atau tanda dekoratif. Lengkapi di "
                    "menu Gambar dan deskripsi"
                ),
            )
    response = (
        supabase_admin.table("materials")
        .update(changes)
        .eq("id", material_id)
        .execute()
    )
    return {"message": "Materi berhasil diperbarui", "material": response.data[0]}


@app.post("/teacher/materials/{material_id}/quizzes")
def create_quiz(
    material_id: str, data: QuizCreateRequest, auth=Depends(require_teacher)
):
    get_owned_material(material_id, auth["user_id"])
    validate_schedule(data)
    title = (data.title or "").strip() or (
        "Pre-test" if data.kind == "pre" else "Post-test"
    )
    try:
        response = (
            supabase_admin.table("quizzes")
            .insert(
                {
                    "title": title,
                    "material_id": material_id,
                    "teacher_id": auth["user_id"],
                    "kind": data.kind,
                    "attempt_limit": data.attempt_limit,
                    "available_from": data.available_from.isoformat(),
                    "deadline_at": data.deadline_at.isoformat(),
                }
            )
            .execute()
        )
    except APIError as error:
        if error.code == "23505":
            raise HTTPException(
                status_code=409,
                detail=f"Materi ini sudah punya {title.lower()}",
            )
        raise
    return {"message": "Kuis berhasil dibuat", "quiz": response.data[0]}


GEMINI_KEY_MISSING_DETAIL = (
    "Fitur AI belum aktif karena GEMINI_API_KEY belum diatur di backend/.env. "
    "Hubungi pengelola server."
)


def require_gemini():
    """Endpoint AI menolak dengan 503 kalau kunci Gemini belum diatur."""
    try:
        gemini_client()
    except GeminiKeyMissing as error:
        raise HTTPException(status_code=503, detail=GEMINI_KEY_MISSING_DETAIL) from error


@app.post("/teacher/materials/{material_id}/generate-quiz")
def generate_material_quiz(
    material_id: str, data: GenerateQuizRequest, auth=Depends(require_teacher)
):
    material = get_owned_material(material_id, auth["user_id"])
    require_gemini()
    sections_result = (
        supabase_admin.table("material_sections")
        .select("position, content")
        .eq("material_id", material_id)
        .order("position")
        .execute()
    )
    sections = sections_result.data or []
    materi = "\n\n".join(
        plain_text(section.get("content") or "") for section in sections
    ).strip()
    if not materi:
        raise HTTPException(
            status_code=422, detail="Materi belum memiliki teks yang dapat digunakan."
        )
    try:
        result = generate_quiz(
            materi=materi,
            total_questions=data.total_questions,
            quiz_type=data.quiz_type,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    except Exception as error:
        logger.exception("Gagal menghasilkan kuis dengan Gemini")
        raise HTTPException(
            status_code=502, detail="Gagal menghasilkan kuis. Silakan coba lagi."
        ) from error
    return {
        "material_id": material_id,
        "total_questions": len(result.questions),
        "quiz_type": data.quiz_type,
        "questions": [question.model_dump() for question in result.questions],
    }


# Format yang disimpan apa adanya. Format lain (JPEG 2000, JBIG2, TIFF, dll.)
# diubah ke PNG supaya bisa dibuka Pillow dan dikirim ke Gemini.
IMAGE_MIME_TYPES = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "jpe": "image/jpeg",
    "jfif": "image/jpeg",
    "webp": "image/webp",
    "gif": "image/gif",
    "bmp": "image/bmp",
}
IMAGE_PREVIEW_SECONDS = 60 * 60


def image_file(pdf, xref):
    """Berkas gambar dari PDF: (bytes, ekstensi, content type)."""
    extracted = pdf.extract_image(xref)
    extension = (extracted.get("ext") or "").lower().lstrip(".")
    if extension in IMAGE_MIME_TYPES:
        return extracted["image"], extension, IMAGE_MIME_TYPES[extension]
    pixmap = pymupdf.Pixmap(pdf, xref)
    if pixmap.colorspace is not None and pixmap.colorspace.n > 3:
        pixmap = pymupdf.Pixmap(pymupdf.csRGB, pixmap)
    return pixmap.tobytes("png"), "png", "image/png"


def store_page_images(pdf, material_id, teacher_id, known_keys, uploaded_paths):
    """Menyimpan gambar PDF yang belum punya baris di material_images.

    Gambar baru belum punya deskripsi. Ikon kecil dan latar penuh langsung
    ditandai dekoratif sehingga tidak perlu dideskripsikan.
    """
    for page_number, page in enumerate(pdf, start=1):
        for image in page_images(page, page_number):
            if image.key in known_keys:
                continue
            known_keys.add(image.key)
            data, extension, content_type = image_file(pdf, image.xref)
            image_path = (
                f"{teacher_id}/{material_id}/images/"
                f"page-{page_number}-{image.key}.{extension}"
            )
            supabase_admin.storage.from_("material-images").upload(
                path=image_path,
                file=data,
                file_options={"content-type": content_type, "upsert": "true"},
            )
            uploaded_paths.append(image_path)
            supabase_admin.table("material_images").insert(
                {
                    "material_id": material_id,
                    "image_key": image.key,
                    "page_number": page_number,
                    "image_url": image_path,
                    "description": None,
                    "is_decorative": image.decorative,
                    "audio_url": None,
                }
            ).execute()


def material_image_rows(material_id):
    response = (
        supabase_admin.table("material_images")
        .select("id, image_key, page_number, image_url, description, is_decorative")
        .eq("material_id", material_id)
        .execute()
    )
    rows = [row for row in (response.data or []) if row.get("image_key")]
    return sorted(rows, key=lambda row: (row.get("page_number") or 0, row["image_key"]))


def needs_description(row):
    return not row.get("is_decorative") and not (row.get("description") or "").strip()


def public_image(row):
    return {
        "id": row["id"],
        "image_key": row["image_key"],
        "page_number": row.get("page_number"),
        "description": row.get("description"),
        "is_decorative": bool(row.get("is_decorative")),
        "needs_description": needs_description(row),
    }


def material_content_image_keys(material_id):
    """Kunci gambar yang dirujuk isi halaman materi."""
    response = (
        supabase_admin.table("material_sections")
        .select("content")
        .eq("material_id", material_id)
        .execute()
    )
    keys = []
    for section in response.data or []:
        for key in image_keys(section.get("content") or ""):
            if key not in keys:
                keys.append(key)
    return keys


def ordered_image_rows(material_id):
    """Gambar materi menurut urutan baca: urutan penanda di isi halaman,
    lalu gambar yang tidak dirujuk menurut halamannya."""
    order = {key: i for i, key in enumerate(material_content_image_keys(material_id))}
    return sorted(
        material_image_rows(material_id),
        key=lambda row: (order.get(row["image_key"], len(order)), row.get("page_number") or 0),
    )


def undescribed_image_pages(material_id):
    """Halaman yang masih punya gambar tanpa deskripsi dan bukan dekoratif.
    Gambar yang belum punya baris sama sekali juga dihitung."""
    rows = {row["image_key"]: row for row in material_image_rows(material_id)}
    pages = []
    for key in material_content_image_keys(material_id):
        row = rows.get(key)
        if row is None or needs_description(row):
            pages.append((row or {}).get("page_number"))
    return pages


@app.post("/teacher/materials/{material_id}/generate-image-description")
def generate_material_image_description(
    material_id: str,
    auth=Depends(require_teacher),
):
    """Mendeskripsikan gambar materi yang belum punya deskripsi dengan Gemini.

    Aman dipanggil ulang: gambar yang sudah dideskripsikan atau dekoratif
    dilewati, jadi pemanggilan berikutnya hanya mencoba gambar yang gagal.
    Materi lama yang gambarnya belum tersimpan diproses dari PDF-nya.
    """
    material = get_owned_material(material_id, auth["user_id"])
    require_gemini()
    described = failed = 0
    try:
        rows = material_image_rows(material_id)
        known_keys = {row["image_key"] for row in rows}
        missing = set(material_content_image_keys(material_id)) - known_keys
        if missing and material.get("file_url"):
            pdf_bytes = supabase_admin.storage.from_("materials-pdf").download(
                material["file_url"]
            )
            with pymupdf.open(stream=pdf_bytes, filetype="pdf") as pdf:
                store_page_images(pdf, material_id, auth["user_id"], known_keys, [])
            rows = material_image_rows(material_id)
        for row in rows:
            if not needs_description(row):
                continue
            try:
                image_bytes = supabase_admin.storage.from_("material-images").download(
                    row["image_url"]
                )
                description = describe_image(image_bytes).strip()
            except Exception:
                logger.exception("Gagal mendeskripsikan %s", row["image_key"])
                failed += 1
                continue
            supabase_admin.table("material_images").update(
                {"description": description}
            ).eq("id", row["id"]).execute()
            described += 1
    except Exception as error:
        print(f"Error deskripsi gambar materi {material_id}:", repr(error))
        raise HTTPException(
            status_code=502,
            detail="Gagal memproses gambar atau menyimpan deskripsi. Periksa log backend",
        ) from error
    images = [public_image(row) for row in ordered_image_rows(material_id)]
    return {
        "material_id": material_id,
        "total_described": described,
        "total_failed": failed,
        "total_pending": sum(image["needs_description"] for image in images),
        "images": images,
    }


@app.get("/teacher/materials/{material_id}/images")
def list_material_images(material_id: str, auth=Depends(require_teacher)):
    """Gambar materi untuk diperiksa guru, dengan tautan pratinjau sementara."""
    get_owned_material(material_id, auth["user_id"])
    images = []
    for row in ordered_image_rows(material_id):
        preview_url = None
        try:
            signed = supabase_admin.storage.from_("material-images").create_signed_url(
                row["image_url"], IMAGE_PREVIEW_SECONDS
            )
            preview_url = signed.get("signedURL") or signed.get("signedUrl")
        except Exception as error:
            print("Gagal membuat tautan pratinjau gambar:", repr(error))
        images.append({**public_image(row), "preview_url": preview_url})
    return {"material_id": material_id, "images": images}


class MaterialImageUpdateRequest(BaseModel):
    description: Optional[str] = Field(default=None, max_length=2000)
    is_decorative: Optional[bool] = None


@app.patch("/teacher/materials/{material_id}/images/{image_id}")
def update_material_image(
    material_id: str,
    image_id: str,
    data: MaterialImageUpdateRequest,
    auth=Depends(require_teacher),
):
    """Guru memperbaiki deskripsi AI atau menandai gambar dekoratif."""
    material = get_owned_material(material_id, auth["user_id"])
    changes = {}
    if data.description is not None:
        changes["description"] = data.description.strip() or None
    if data.is_decorative is not None:
        changes["is_decorative"] = data.is_decorative
    if not changes:
        raise HTTPException(status_code=400, detail="Tidak ada perubahan.")
    current = next(
        (row for row in material_image_rows(material_id) if str(row["id"]) == image_id),
        None,
    )
    if current is None:
        raise HTTPException(status_code=404, detail="Gambar tidak ditemukan")
    # Siswa tidak boleh menemui gambar tanpa deskripsi di materi yang terbit.
    if material.get("is_published") and needs_description({**current, **changes}):
        raise HTTPException(
            status_code=409,
            detail=(
                "Materi sudah terbit, jadi gambar ini harus punya deskripsi "
                "atau ditandai dekoratif"
            ),
        )
    response = (
        supabase_admin.table("material_images")
        .update(changes)
        .eq("id", image_id)
        .eq("material_id", material_id)
        .execute()
    )
    if not response.data:
        raise HTTPException(status_code=404, detail="Gambar tidak ditemukan")
    return {"message": "Gambar disimpan", "image": public_image(response.data[0])}


@app.patch("/teacher/quizzes/{quiz_id}/schedule")
def update_quiz_schedule(
    quiz_id: str, data: QuizScheduleRequest, auth=Depends(require_teacher)
):
    validate_schedule(data)
    response = (
        supabase_admin.table("quizzes")
        .update(
            {
                "available_from": data.available_from.isoformat(),
                "deadline_at": data.deadline_at.isoformat(),
            }
        )
        .eq("id", quiz_id)
        .eq("teacher_id", auth["user_id"])
        .is_("deleted_at", "null")
        .execute()
    )
    if not response.data:
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
    return {"message": "Jadwal kuis berhasil diperbarui", "quiz": response.data[0]}


@app.get("/teacher/subjects/{subject_id}/results")
def get_subject_results(subject_id: str, auth=Depends(require_teacher)):
    subject = get_owned_subject(subject_id, auth["user_id"])
    members_response = (
        supabase_admin.table("subject_students")
        .select("student_id, joined_at")
        .eq("subject_id", subject_id)
        .execute()
    )
    student_ids = [row["student_id"] for row in (members_response.data or [])]
    students = []
    if student_ids:
        users_response = (
            supabase_admin.table("users")
            .select("id, name")
            .in_("id", student_ids)
            .execute()
        )
        students = sorted(users_response.data or [], key=lambda row: row["name"])

    materials_response = (
        supabase_admin.table("materials")
        .select("id, title, is_published, created_at")
        .eq("subject_id", subject_id)
        .order("created_at")
        .execute()
    )
    materials = materials_response.data or []
    quizzes = quizzes_by_material([material["id"] for material in materials])
    quiz_ids = [quiz["id"] for group in quizzes.values() for quiz in group]

    # Percobaan terakhir yang sudah dikumpulkan per (kuis, siswa).
    latest = {}
    attempt_counts = {}
    if quiz_ids and student_ids:
        attempts_response = (
            supabase_admin.table("quiz_attempts")
            .select(
                "id, quiz_id, student_id, correct_count, total_questions, submitted_at"
            )
            .in_("quiz_id", quiz_ids)
            .in_("student_id", student_ids)
            .not_.is_("submitted_at", "null")
            .order("submitted_at")
            .execute()
        )
        for attempt in attempts_response.data or []:
            key = (attempt["quiz_id"], attempt["student_id"])
            latest[key] = attempt
            attempt_counts[key] = attempt_counts.get(key, 0) + 1

    result_materials = []
    for material in materials:
        result_quizzes = []
        for quiz in quizzes.get(material["id"], []):
            rows = []
            percents = []
            for student in students:
                key = (quiz["id"], student["id"])
                attempt = latest.get(key)
                if attempt and attempt["total_questions"]:
                    percents.append(
                        attempt["correct_count"] / attempt["total_questions"] * 100
                    )
                rows.append(
                    {
                        "student_id": student["id"],
                        "name": student["name"],
                        "attempt_count": attempt_counts.get(key, 0),
                        "latest_attempt": (
                            {
                                "attempt_id": attempt["id"],
                                "correct_count": attempt["correct_count"],
                                "total_questions": attempt["total_questions"],
                                "submitted_at": attempt["submitted_at"],
                            }
                            if attempt
                            else None
                        ),
                    }
                )
            result_quizzes.append(
                {
                    **quiz,
                    "status": quiz_status(quiz),
                    "submitted_count": len(percents),
                    "average_percent": (
                        round(sum(percents) / len(percents), 1) if percents else None
                    ),
                    "students": rows,
                }
            )
        result_materials.append({**material, "quizzes": result_quizzes})
    return {
        "subject": subject,
        "student_count": len(students),
        "materials": result_materials,
    }


@app.post("/student/subjects/join")
def join_subject(data: JoinSubjectRequest, auth=Depends(require_student)):
    code = normalize_access_code(data.code)
    if not ACCESS_CODE_RE.match(code):
        raise HTTPException(status_code=400, detail="Kode akses harus 6 huruf")
    subject_response = (
        supabase_admin.table("subjects")
        .select("id, name, teacher_id")
        .eq("access_code", code)
        .is_("deleted_at", "null")
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    subject = subject_response.data
    if subject is None:
        raise HTTPException(status_code=404, detail="Kode akses tidak ditemukan")
    already_joined = is_subject_member(subject["id"], auth["user_id"])
    if not already_joined:
        supabase_admin.table("subject_students").upsert(
            {"subject_id": subject["id"], "student_id": auth["user_id"]},
            on_conflict="subject_id,student_id",
            ignore_duplicates=True,
        ).execute()
    return {
        "message": (
            "Kamu sudah bergabung di kelas ini"
            if already_joined
            else "Berhasil bergabung ke kelas"
        ),
        "already_joined": already_joined,
        "subject": {"id": subject["id"], "name": subject["name"]},
    }


@app.get("/student/subjects")
def list_student_subjects(auth=Depends(require_student)):
    members_response = (
        supabase_admin.table("subject_students")
        .select("subject_id, joined_at")
        .eq("student_id", auth["user_id"])
        .execute()
    )
    joined_at = {
        row["subject_id"]: row["joined_at"] for row in (members_response.data or [])
    }
    if not joined_at:
        return {"subjects": []}
    subjects_response = (
        supabase_admin.table("subjects")
        .select("id, name, teacher_id")
        .in_("id", list(joined_at))
        .is_("deleted_at", "null")
        .execute()
    )
    subjects = subjects_response.data or []
    teacher_ids = list({subject["teacher_id"] for subject in subjects})
    teacher_names = {}
    if teacher_ids:
        teachers_response = (
            supabase_admin.table("users")
            .select("id, name")
            .in_("id", teacher_ids)
            .execute()
        )
        teacher_names = {
            row["id"]: row["name"] for row in (teachers_response.data or [])
        }
    material_counts = {subject["id"]: 0 for subject in subjects}
    if subjects:
        materials_response = (
            supabase_admin.table("materials")
            .select("subject_id")
            .in_("subject_id", list(material_counts))
            .eq("is_published", True)
            .execute()
        )
        for row in materials_response.data or []:
            material_counts[row["subject_id"]] += 1
    return {
        "subjects": sorted(
            [
                {
                    "id": subject["id"],
                    "name": subject["name"],
                    "teacher_name": teacher_names.get(subject["teacher_id"]),
                    "material_count": material_counts[subject["id"]],
                    "joined_at": joined_at[subject["id"]],
                }
                for subject in subjects
            ],
            key=lambda subject: subject["joined_at"],
        )
    }


@app.get("/student/subjects/{subject_id}/materials")
def list_student_subject_materials(subject_id: str, auth=Depends(require_student)):
    student_id = auth["user_id"]
    if not is_subject_member(subject_id, student_id):
        raise HTTPException(
            status_code=403, detail="Kamu belum bergabung di kelas ini"
        )
    subject_response = (
        supabase_admin.table("subjects")
        .select("id, name")
        .eq("id", subject_id)
        .is_("deleted_at", "null")
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    subject = subject_response.data
    if subject is None:
        raise HTTPException(status_code=404, detail="Kelas tidak ditemukan")
    materials_response = (
        supabase_admin.table("materials")
        .select("id, title, created_at")
        .eq("subject_id", subject_id)
        .eq("is_published", True)
        .order("created_at")
        .execute()
    )
    materials = materials_response.data or []
    material_ids = [material["id"] for material in materials]
    quizzes = quizzes_by_material(material_ids)
    counts = section_counts(material_ids)
    quiz_ids = [quiz["id"] for group in quizzes.values() for quiz in group]
    attempts_by_quiz = {quiz_id: [] for quiz_id in quiz_ids}
    if quiz_ids:
        attempts_response = (
            supabase_admin.table("quiz_attempts")
            .select("id, quiz_id, correct_count, total_questions, submitted_at")
            .in_("quiz_id", quiz_ids)
            .eq("student_id", student_id)
            .order("started_at")
            .execute()
        )
        for attempt in attempts_response.data or []:
            attempts_by_quiz[attempt["quiz_id"]].append(attempt)

    now = datetime.now(timezone.utc)
    result = []
    for material in materials:
        material_quizzes = quizzes.get(material["id"], [])
        has_pre = any(quiz["kind"] == "pre" for quiz in material_quizzes)
        pre_submitted = any(
            attempt["submitted_at"] is not None
            for quiz in material_quizzes
            if quiz["kind"] == "pre"
            for attempt in attempts_by_quiz[quiz["id"]]
        )
        quiz_rows = []
        for quiz in material_quizzes:
            attempts = attempts_by_quiz[quiz["id"]]
            submitted = [a for a in attempts if a["submitted_at"] is not None]
            unfinished = next((a for a in attempts if a["submitted_at"] is None), None)
            latest = submitted[-1] if submitted else None
            quiz_rows.append(
                {
                    "id": quiz["id"],
                    "kind": quiz["kind"],
                    "title": quiz["title"],
                    "available_from": quiz["available_from"],
                    "deadline_at": quiz["deadline_at"],
                    "status": quiz_status(quiz, now),
                    "attempt_limit": quiz["attempt_limit"],
                    "attempts_used": len(attempts),
                    "unfinished_attempt_id": unfinished["id"] if unfinished else None,
                    "locked": quiz["kind"] == "post" and has_pre and not pre_submitted,
                    "discussion_available": discussion_available(quiz, now),
                    "latest_attempt": (
                        {
                            "attempt_id": latest["id"],
                            "correct_count": latest["correct_count"],
                            "total_questions": latest["total_questions"],
                            "submitted_at": latest["submitted_at"],
                        }
                        if latest
                        else None
                    ),
                }
            )
        result.append(
            {
                "id": material["id"],
                "title": material["title"],
                "section_count": counts.get(material["id"], 0),
                "quizzes": quiz_rows,
            }
        )
    return {"subject": subject, "materials": result}


@app.get("/materials/{material_id}/sections")
def get_material_sections(material_id: str, auth=Depends(get_current_profile)):
    material_response = (
        supabase_admin.table("materials")
        .select("id, title, subject_id, teacher_id, is_published")
        .eq("id", material_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    material = material_response.data
    if material is None:
        raise HTTPException(status_code=404, detail="Materi tidak ditemukan")
    if auth["profile"]["role"] == "teacher":
        if material["teacher_id"] != auth["user_id"]:
            raise HTTPException(status_code=404, detail="Materi tidak ditemukan")
    else:
        if not material["is_published"]:
            raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")
        if not student_can_access_material(material, auth["user_id"]):
            raise HTTPException(
                status_code=403, detail="Anda tidak memiliki akses ke materi ini"
            )
    sections_response = (
        supabase_admin.table("material_sections")
        .select(
            "id, position, title, content, image_description, image_count, "
            "page_start, page_end"
        )
        .eq("material_id", material_id)
        .order("position")
        .execute()
    )
    return {
        "material": {"id": material["id"], "title": material["title"]},
        "sections": sections_response.data or [],
        # Deskripsi untuk penanda [[gambar:...]] di isi halaman.
        "images": [public_image(row) for row in material_image_rows(material_id)],
    }
