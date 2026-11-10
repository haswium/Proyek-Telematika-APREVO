from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from schemas.ai_output import AIOutput
from dotenv import load_dotenv
import os
import threading
import time
from dataclasses import dataclass, field
from supabase import create_client, ClientOptions
from postgrest.exceptions import APIError
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import random
import re
import secrets
import string
from pydantic import BaseModel, Field
from typing import Literal, Optional
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import uuid4
import pymupdf
import logging
from pdf_sections import (
    image_keys,
    normalize_content,
    page_images,
    plain_text,
    replace_table,
    plain_words,
    search_content,
    search_snippet,
    split_pdf_bytes,
)
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
class ThreadLocalSupabase:
    """Klien Supabase tersendiri untuk setiap thread.

    Klien Supabase memakai satu koneksi HTTP/2 (httpx) yang tidak aman dipakai
    bersamaan oleh beberapa thread. Endpoint sinkron FastAPI berjalan di
    thread pool, dan deskripsi gambar berjalan di latar belakang, jadi satu
    klien bersama sesekali gagal dengan RemoteProtocolError ("Server
    disconnected") saat polling bertabrakan dengan penulisan. Dengan klien per
    thread, setiap thread memakai koneksinya sendiri.
    """

    def __init__(self, key):
        self._key = key
        self._local = threading.local()

    def _client(self):
        client = getattr(self._local, "client", None)
        if client is None:
            client = create_client(SUPABASE_URL, self._key)
            self._local.client = client
        return client

    def __getattr__(self, name):
        return getattr(self._client(), name)


supabase = ThreadLocalSupabase(SUPABASE_KEY)
supabase_admin = ThreadLocalSupabase(os.getenv("SUPABASE_SERVICE_KEY"))
TEST_LOGIN_EMAIL = os.getenv("TEST_LOGIN_EMAIL")
TEST_LOGIN_PASSWORD = os.getenv("TEST_LOGIN_PASSWORD")


def debug_endpoints_enabled():
    """Render selalu mengisi RENDER. Di sana endpoint debug tetap mati, walau
    variabelnya diisi 1 di dashboard."""
    return os.getenv("ENABLE_DEBUG_ENDPOINTS") == "1" and not os.getenv("RENDER")


ENABLE_DEBUG_ENDPOINTS = debug_endpoints_enabled()

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
    except Exception as error:
        logger.exception(server_error_log(request, error))
        return JSONResponse(status_code=500, content={"detail": SERVER_ERROR_DETAIL})


def server_error_log(request, error):
    """Satu baris yang mudah dicari di log: cari "SERVER_ERROR". Endpoint
    ditulis sebagai pola rute supaya error di materi berbeda terkumpul."""
    route = request.scope.get("route")
    endpoint = getattr(route, "path", None) or request.url.path
    kind = type(error)
    message = " ".join(str(error).split())[:500] or "-"
    return (
        f"SERVER_ERROR endpoint={request.method} {endpoint} "
        f"path={request.url.path} "
        f"error={kind.__module__}.{kind.__qualname__} "
        f"pesan={message}"
    )


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


@app.get("/health")
def health():
    """Untuk health check Render dan membangunkan server. Tanpa database, supaya
    gangguan Supabase tidak membuat Render memulai ulang layanan."""
    return {"status": "ok"}


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


def read_profile(user_id: str):
    return (
        supabase_admin.table("users")
        .select("id, name, role")
        .eq("id", user_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data


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


SUBJECT_DELETED_DETAIL = "Kelas ini sudah dihapus guru"


def deleted_subject_ids(subject_ids):
    """Yang `deleted_at`-nya terisi. Ini yang menentukan, bukan baris anggota:
    baris itu baru terhapus beberapa saat setelah `deleted_at` diisi."""
    ids = list({subject_id for subject_id in subject_ids if subject_id})
    if not ids:
        return set()
    response = (
        supabase_admin.table("subjects")
        .select("id")
        .in_("id", ids)
        .not_.is_("deleted_at", "null")
        .execute()
    )
    return {row["id"] for row in (response.data or [])}


def subject_is_deleted(subject_id):
    return bool(deleted_subject_ids([subject_id]))


def quiz_subject_is_deleted(quiz_id):
    quiz = (
        supabase_admin.table("quizzes")
        .select("material_id")
        .eq("id", quiz_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    if quiz is None:
        return False
    material = (
        supabase_admin.table("materials")
        .select("subject_id")
        .eq("id", quiz["material_id"])
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    return material is not None and subject_is_deleted(material.get("subject_id"))


def reject_deleted_quiz_subject(quiz_id):
    """Untuk siswa: 410 supaya layar kuis tahu alasannya. Guru mendapat 404,
    sama seperti `get_owned_subject`."""
    if quiz_subject_is_deleted(quiz_id):
        raise HTTPException(status_code=410, detail=SUBJECT_DELETED_DETAIL)


def get_member_subject(subject_id, student_id):
    """Kelas yang boleh dibuka siswa. Kelas yang dihapus guru dijawab 410, bukan
    403: keanggotaannya ikut terhapus, tetapi siswa perlu tahu alasannya."""
    subject = (
        supabase_admin.table("subjects")
        .select("id, name, teacher_id, deleted_at")
        .eq("id", subject_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    if subject is not None and subject.get("deleted_at"):
        raise HTTPException(status_code=410, detail=SUBJECT_DELETED_DETAIL)
    if not is_subject_member(subject_id, student_id):
        raise HTTPException(
            status_code=403, detail="Kamu belum bergabung di kelas ini"
        )
    if subject is None:
        raise HTTPException(status_code=404, detail="Kelas tidak ditemukan")
    return subject


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
    if material is None or subject_is_deleted(material.get("subject_id")):
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
    if quiz is None or quiz_subject_is_deleted(quiz_id):
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
    if quiz is None or quiz_subject_is_deleted(quiz_id):
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
            .select("id, title, is_published, subject_id")
            .in_("id", material_ids)
            .eq("is_published", True)
            .execute()
        )
        materials.extend(materials_response.data or [])
    if subject_ids:
        subject_materials_response = (
            supabase_admin.table("materials")
            .select("id, title, is_published, subject_id")
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
    deleted = deleted_subject_ids(material.get("subject_id") for material in materials)
    return {
        "materials": [
            {key: material[key] for key in ("id", "title", "is_published")}
            for material in materials
            if material.get("subject_id") not in deleted
        ]
    }


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
    reject_deleted_quiz_subject(quiz_id)
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
    reject_deleted_quiz_subject(quiz_id)
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
    reject_deleted_quiz_subject(attempt["quiz_id"])
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
        reject_deleted_quiz_subject(attempt["quiz_id"])
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
    reject_deleted_quiz_subject(attempt["quiz_id"])
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


class ChooseRoleRequest(BaseModel):
    role: Literal["teacher", "student"]


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


class GenerateQuestionsRequest(GenerateQuizRequest):
    test_kind: Literal["pre", "post"]


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


@app.post("/me/role")
def choose_role(data: ChooseRoleRequest, auth=Depends(get_current_user)):
    """Peran akun Google yang baru pertama kali masuk. Hanya tersimpan sekali: kalau
    baris akun sudah ada, peran lamanya yang dikembalikan."""
    user = auth["user"]
    user_id = str(user.id)
    profile = read_profile(user_id)
    if profile is None:
        metadata = user.user_metadata or {}
        name = str(metadata.get("name") or metadata.get("full_name") or "").strip()
        try:
            supabase_admin.table("users").insert(
                {
                    "id": user_id,
                    "name": name or (user.email or "").split("@")[0] or "Pengguna",
                    "role": data.role,
                }
            ).execute()
        except APIError as error:
            # 23505: permintaan lain baru saja menyimpan peran akun ini.
            if error.code != "23505":
                raise
        profile = read_profile(user_id)
    return {"name": profile["name"], "role": profile["role"]}


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
    deleted = (
        supabase_admin.table("subjects")
        .select("id, name")
        .eq("teacher_id", auth["user_id"])
        .not_.is_("deleted_at", "null")
        .execute()
    ).data or []
    leftovers = subjects_with_leftovers([row["id"] for row in deleted])
    return {
        "subjects": [
            {
                **subject,
                "student_count": student_counts[subject["id"]],
                "material_count": material_counts[subject["id"]],
            }
            for subject in subjects
        ],
        # Penghapusan yang berhenti di tengah, untuk dilanjutkan guru.
        "unfinished_deletions": [row for row in deleted if row["id"] in leftovers],
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
                "hidden_image_count": (
                    hidden_image_count(material["id"]) if material["is_published"] else 0
                ),
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


def material_plain_text(material_id):
    """Teks seluruh halaman materi hasil konversi, untuk AI soal."""
    sections_result = (
        supabase_admin.table("material_sections")
        .select("position, content")
        .eq("material_id", material_id)
        .order("position")
        .execute()
    )
    return "\n\n".join(
        plain_text(section.get("content") or "") for section in sections_result.data or []
    ).strip()


@app.post("/teacher/materials/{material_id}/generate-quiz")
def generate_material_quiz(
    material_id: str, data: GenerateQuizRequest, auth=Depends(require_teacher)
):
    get_owned_material(material_id, auth["user_id"])
    require_gemini()
    materi = material_plain_text(material_id)
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


def store_page_images(
    pdf, material_id, teacher_id, known_keys, uploaded_paths, stopped=None
):
    """Menyimpan gambar PDF yang belum punya baris di material_images.

    Gambar baru belum punya deskripsi. Ikon kecil dan latar penuh langsung
    ditandai dekoratif sehingga tidak perlu dideskripsikan.
    """
    for page_number, page in enumerate(pdf, start=1):
        for image in page_images(page, page_number):
            if image.key in known_keys:
                continue
            if stopped is not None and stopped():
                raise AiJobCancelled
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
    Semua baris gambar dihitung, sama dengan daftar yang dilihat guru. Gambar
    di isi halaman yang belum punya baris sama sekali juga dihitung."""
    rows = material_image_rows(material_id)
    pages = [row.get("page_number") for row in rows if needs_description(row)]
    known = {row["image_key"] for row in rows}
    pages += [None for key in material_content_image_keys(material_id) if key not in known]
    return pages


def hidden_image_count(material_id):
    """Gambar di isi halaman yang disembunyikan dari siswa karena belum punya
    deskripsi. Terjadi di materi yang terbit sebelum syarat terbit berlaku."""
    rows = {row["image_key"]: row for row in material_image_rows(material_id)}
    return sum(
        1
        for key in material_content_image_keys(material_id)
        if key not in rows or needs_description(rows[key])
    )


# Jeda antar panggilan Gemini. Versi gratis membatasi jumlah permintaan per
# menit, jadi gambar dideskripsikan satu per satu dengan jeda.
GEMINI_DELAY_SECONDS = float(os.getenv("GEMINI_DELAY_SECONDS") or "4")
# Jeda tambahan setelah Gemini menjawab "batas pemakaian tercapai".
GEMINI_RATE_LIMIT_PAUSE_SECONDS = float(
    os.getenv("GEMINI_RATE_LIMIT_PAUSE_SECONDS") or "30"
)


@dataclass
class DescribeJob:
    """Progres pembuatan deskripsi gambar satu materi.

    Disimpan di memori proses backend. Kalau backend dimulai ulang, progresnya
    hilang, tetapi deskripsi yang sudah dibuat tetap tersimpan di database
    dan gambar sisanya bisa diproses lagi.
    """

    total: int = 0
    done: int = 0
    running: bool = True
    error: Optional[str] = None
    # image_id -> pesan kegagalan, untuk dicoba ulang satu per satu.
    failed: dict = field(default_factory=dict)
    subject_id: Optional[str] = None
    cancelled: bool = False


DESCRIBE_JOBS: dict[str, DescribeJob] = {}
DESCRIBE_JOBS_LOCK = threading.Lock()


class AiJobCancelled(Exception):
    """Kelasnya dihapus selama proses AI berjalan. Hasilnya dibuang."""


def job_stopped(job) -> bool:
    """`deleted_at` ikut diperiksa untuk proses yang terdaftar tepat setelah
    `cancel_ai_jobs` berjalan, atau yang berjalan di proses backend lain."""
    return job.cancelled or (
        job.subject_id is not None and subject_is_deleted(job.subject_id)
    )


def is_rate_limited(error: Exception) -> bool:
    text = str(error)
    return "429" in text or "RESOURCE_EXHAUSTED" in text or "quota" in text.lower()


def describe_failure_message(error: Exception) -> str:
    if isinstance(error, GeminiKeyMissing):
        return GEMINI_KEY_MISSING_DETAIL
    if is_rate_limited(error):
        return "Batas pemakaian Gemini tercapai. Coba lagi beberapa menit lagi"
    return "AI gagal mendeskripsikan gambar ini. Coba lagi"


def describe_one(row, stopped=None):
    """Mendeskripsikan satu gambar dan menyimpannya. Melempar error asli
    kalau gagal, supaya pemanggil bisa menilai jenis kegagalannya.

    Panggilan Gemini yang sudah berjalan tidak bisa diputus, jadi `stopped`
    diperiksa setelahnya, dan hasilnya dibuang kalau kelasnya sudah dihapus."""
    image_bytes = supabase_admin.storage.from_("material-images").download(
        row["image_url"]
    )
    description = describe_image(image_bytes).strip()
    if not description:
        raise ValueError("Deskripsi kosong")
    if stopped is not None and stopped():
        raise AiJobCancelled
    # Hanya mengisi yang masih kosong: kalau guru menulis deskripsi selama
    # Gemini bekerja, tulisan guru yang dipertahankan.
    response = (
        supabase_admin.table("material_images")
        .update({"description": description})
        .eq("id", row["id"])
        .is_("description", "null")
        .execute()
    )
    if response.data:
        return response.data[0]
    return fresh_image_row(row["id"]) or {**row, "description": description}


def fresh_image_row(image_id):
    """Keadaan terbaru satu gambar, karena guru bisa mengubahnya selama
    proses deskripsi berjalan."""
    response = (
        supabase_admin.table("material_images")
        .select("id, image_key, page_number, image_url, description, is_decorative")
        .eq("id", image_id)
        .execute()
    )
    return (response.data or [None])[0]


def prepare_image_rows(material, teacher_id, stopped=None):
    """Materi lama yang gambarnya belum tersimpan diproses dari PDF-nya. Kalau
    kelasnya dihapus di tengah proses, berkas yang baru disimpan ikut dihapus,
    karena penghapusan kelas tidak tahu soal berkas itu."""
    material_id = material["id"]
    known_keys = {row["image_key"] for row in material_image_rows(material_id)}
    missing = set(material_content_image_keys(material_id)) - known_keys
    if missing and material.get("file_url"):
        pdf_bytes = supabase_admin.storage.from_("materials-pdf").download(
            material["file_url"]
        )
        uploaded = []
        try:
            with pymupdf.open(stream=pdf_bytes, filetype="pdf") as pdf:
                store_page_images(
                    pdf, material_id, teacher_id, known_keys, uploaded, stopped
                )
            if stopped is not None and stopped():
                raise AiJobCancelled
        except Exception:
            if stopped is None or not stopped():
                raise
            remove_from_storage("material-images", uploaded)
            delete_rows("material_images", "image_url", uploaded, ())
            raise AiJobCancelled from None


def run_describe_job(job: DescribeJob, material, teacher_id):
    """Dijalankan di latar belakang setelah endpoint menjawab."""
    stopped = lambda: job_stopped(job)
    try:
        if stopped():
            return
        prepare_image_rows(material, teacher_id, stopped)
        rows = [
            row for row in ordered_image_rows(material["id"]) if needs_description(row)
        ]
        job.total = len(rows)
        called = False
        for row in rows:
            # Guru mungkin sudah menulis deskripsi atau menandai dekoratif
            # sejak proses dimulai; gambar itu tidak perlu Gemini lagi.
            current = fresh_image_row(row["id"])
            if current is None or not needs_description(current):
                job.done += 1
                continue
            if called:
                time.sleep(GEMINI_DELAY_SECONDS)
            called = True
            if stopped():
                return
            try:
                describe_one(current, stopped)
                job.done += 1
            except AiJobCancelled:
                return
            except Exception as error:
                logger.exception("Gagal mendeskripsikan %s", row["image_key"])
                job.failed[str(row["id"])] = describe_failure_message(error)
                # Gambar lain tetap diproses; setelah kena batas pemakaian,
                # tunggu lebih lama sebelum lanjut.
                if is_rate_limited(error):
                    time.sleep(GEMINI_RATE_LIMIT_PAUSE_SECONDS)
    except AiJobCancelled:
        logger.info("Deskripsi gambar materi %s dihentikan", material["id"])
    except Exception:
        logger.exception("Proses deskripsi gambar materi %s berhenti", material["id"])
        job.error = "Proses deskripsi berhenti karena kesalahan server. Coba lagi"
    finally:
        job.running = False


def describe_status(material_id):
    rows = {str(row["id"]): row for row in material_image_rows(material_id)}
    job = DESCRIBE_JOBS.get(material_id)
    failed = []
    if job is not None:
        for image_id, message in job.failed.items():
            row = rows.get(image_id)
            # Gambar yang sudah berhasil dicoba ulang tidak lagi gagal.
            if row is not None and needs_description(row):
                failed.append(
                    {
                        "image_id": image_id,
                        "page_number": row.get("page_number"),
                        "message": message,
                    }
                )
    return {
        "material_id": material_id,
        "running": bool(job and job.running),
        "total": job.total if job else 0,
        "done": job.done if job else 0,
        "failed": failed,
        "error": job.error if job else None,
        "pending": sum(needs_description(row) for row in rows.values()),
    }


@app.post(
    "/teacher/materials/{material_id}/generate-image-description",
    status_code=202,
)
def generate_material_image_description(
    material_id: str,
    background_tasks: BackgroundTasks,
    auth=Depends(require_teacher),
):
    """Memulai pembuatan deskripsi gambar di latar belakang.

    Langsung menjawab dengan status awal. Progresnya dibaca lewat
    GET .../image-description. Gambar yang sudah berdeskripsi atau dekoratif
    dilewati, jadi aman dipanggil ulang.
    """
    material = get_owned_material(material_id, auth["user_id"])
    require_gemini()
    # Diperiksa dan dibuat di bawah kunci: dua klik yang hampir bersamaan
    # tidak boleh memulai dua proses untuk materi yang sama.
    with DESCRIBE_JOBS_LOCK:
        job = DESCRIBE_JOBS.get(material_id)
        start_new = job is None or not job.running
        if start_new:
            job = DescribeJob(subject_id=material.get("subject_id"))
            DESCRIBE_JOBS[material_id] = job
    if start_new:
        pending = [row for row in material_image_rows(material_id) if needs_description(row)]
        job.total = len(pending)
        background_tasks.add_task(run_describe_job, job, material, auth["user_id"])
    return describe_status(material_id)


@app.get("/teacher/materials/{material_id}/image-description")
def get_image_description_status(material_id: str, auth=Depends(require_teacher)):
    """Progres pembuatan deskripsi, misalnya 3 dari 12 gambar selesai."""
    get_owned_material(material_id, auth["user_id"])
    return describe_status(material_id)


# Satu panggilan Gemini membuat paling banyak sebanyak ini soal.
QUESTION_BATCH_SIZE = 10
# Panggilan gagal berturut-turut sebelum proses menyerah.
QUESTION_MAX_FAILURES = 2


@dataclass
class QuestionDraftJob:
    """Pembuatan draf soal satu kuis.

    Hasilnya disimpan di memori proses backend sampai diambil aplikasi. Kalau
    backend dimulai ulang sebelum diambil, hasilnya hilang dan harus dibuat
    ulang.
    """

    job_id: str
    quiz_type: str
    total: int
    questions: list = field(default_factory=list)
    running: bool = True
    error: Optional[str] = None
    subject_id: Optional[str] = None
    cancelled: bool = False


QUESTION_JOBS: dict[tuple[str, str], QuestionDraftJob] = {}
QUESTION_JOBS_LOCK = threading.Lock()


def cancel_ai_jobs(material_ids):
    """Menghentikan proses AI materi ini dan membuang hasilnya. Prosesnya berhenti
    sendiri sebelum panggilan Gemini berikutnya."""
    wanted = set(material_ids)
    with DESCRIBE_JOBS_LOCK:
        for material_id in wanted:
            job = DESCRIBE_JOBS.pop(material_id, None)
            if job is not None:
                job.cancelled = True
    with QUESTION_JOBS_LOCK:
        for key in [key for key in QUESTION_JOBS if key[0] in wanted]:
            QUESTION_JOBS.pop(key).cancelled = True


def question_failure_message(error: Exception) -> str:
    if isinstance(error, GeminiKeyMissing):
        return GEMINI_KEY_MISSING_DETAIL
    if is_rate_limited(error):
        return "Batas pemakaian Gemini tercapai. Coba lagi beberapa menit lagi"
    return "AI gagal membuat soal. Coba lagi"


def run_question_job(job: QuestionDraftJob, materi: str):
    """Dijalankan di latar belakang setelah endpoint menjawab. Soal yang sudah
    jadi tetap disimpan kalau panggilan berikutnya gagal."""
    seen = set()
    failures = 0
    called = False
    try:
        while len(job.questions) < job.total:
            if called:
                time.sleep(GEMINI_DELAY_SECONDS)
            called = True
            if job_stopped(job):
                return
            try:
                result = generate_quiz(
                    materi=materi,
                    total_questions=min(
                        job.total - len(job.questions), QUESTION_BATCH_SIZE
                    ),
                    quiz_type=job.quiz_type,
                    avoid_questions=[q["question"] for q in job.questions],
                )
            except Exception as error:
                logger.exception("Gagal membuat soal dengan Gemini")
                failures += 1
                if isinstance(error, GeminiKeyMissing) or failures >= QUESTION_MAX_FAILURES:
                    job.error = question_failure_message(error)
                    return
                if is_rate_limited(error):
                    time.sleep(GEMINI_RATE_LIMIT_PAUSE_SECONDS)
                continue
            added = 0
            for question in result.questions:
                key = question.question.strip().casefold()
                if key not in seen:
                    seen.add(key)
                    job.questions.append(question.model_dump())
                    added += 1
            # Semua soal kembar: panggilan ini tidak menghasilkan apa-apa.
            failures = 0 if added else failures + 1
            if failures >= QUESTION_MAX_FAILURES:
                job.error = "AI hanya membuat soal yang sama. Coba lagi"
                return
    except Exception:
        logger.exception("Proses pembuatan soal berhenti")
        job.error = "Proses pembuatan soal berhenti karena kesalahan server. Coba lagi"
    finally:
        job.running = False


def question_job_status(material_id, test_kind):
    job = QUESTION_JOBS.get((material_id, test_kind))
    if job is None:
        return {
            "job_id": None,
            "test_kind": test_kind,
            "running": False,
            "total": 0,
            "done": 0,
            "quiz_type": None,
            "questions": [],
            "error": None,
        }
    return {
        "job_id": job.job_id,
        "test_kind": test_kind,
        "running": job.running,
        "total": job.total,
        "done": len(job.questions),
        "quiz_type": job.quiz_type,
        # Soal baru dikirim setelah selesai, supaya tidak terbaca setengah jadi.
        "questions": [] if job.running else job.questions,
        "error": job.error,
    }


def check_question_request(material_id, data: GenerateQuestionsRequest):
    """Kuis harus sudah punya jadwal, dan satu materi memakai satu jenis soal."""
    quizzes = quizzes_by_material([material_id])[material_id]
    if not any(quiz["kind"] == data.test_kind for quiz in quizzes):
        label = "pre-test" if data.test_kind == "pre" else "post-test"
        raise HTTPException(
            status_code=409, detail=f"Atur dulu jadwal {label} materi ini"
        )
    saved = (
        supabase_admin.table("questions")
        .select("type")
        .in_("quiz_id", [quiz["id"] for quiz in quizzes])
        .execute()
    ).data or []
    if any(row["type"] != data.quiz_type for row in saved):
        raise HTTPException(
            status_code=409, detail="Materi ini sudah memakai jenis soal lain"
        )
    for kind in ("pre", "post"):
        other = QUESTION_JOBS.get((material_id, kind))
        if other and other.running and other.quiz_type != data.quiz_type:
            raise HTTPException(
                status_code=409, detail="Materi ini sedang dibuatkan jenis soal lain"
            )


@app.post("/teacher/materials/{material_id}/generate-questions")
def start_generate_questions(
    material_id: str,
    data: GenerateQuestionsRequest,
    background_tasks: BackgroundTasks,
    auth=Depends(require_teacher),
):
    """Memulai pembuatan draf soal di latar belakang. Status dan hasilnya dibaca
    lewat GET di alamat yang sama. Hasil lama kuis ini yang belum diambil diganti."""
    material = get_owned_material(material_id, auth["user_id"])
    require_gemini()
    check_question_request(material_id, data)
    materi = material_plain_text(material_id)
    if not materi:
        raise HTTPException(
            status_code=422, detail="Materi belum memiliki teks yang dapat digunakan."
        )
    key = (material_id, data.test_kind)
    with QUESTION_JOBS_LOCK:
        job = QUESTION_JOBS.get(key)
        started = job is None or not job.running
        if started:
            job = QuestionDraftJob(
                job_id=str(uuid4()),
                quiz_type=data.quiz_type,
                total=data.total_questions,
                subject_id=material.get("subject_id"),
            )
            QUESTION_JOBS[key] = job
    if started:
        background_tasks.add_task(run_question_job, job, materi)
    # Status dibaca sebelum proses berjalan: jawaban selalu "sedang berjalan".
    return question_job_status(material_id, data.test_kind)


@app.get("/teacher/materials/{material_id}/generate-questions")
def generate_questions_status(
    material_id: str,
    test_kind: Literal["pre", "post"],
    auth=Depends(require_teacher),
):
    get_owned_material(material_id, auth["user_id"])
    return question_job_status(material_id, test_kind)


@app.delete("/teacher/materials/{material_id}/generate-questions")
def clear_generated_questions(
    material_id: str,
    test_kind: Literal["pre", "post"],
    auth=Depends(require_teacher),
):
    """Aplikasi sudah mengambil hasilnya sebagai draf."""
    get_owned_material(material_id, auth["user_id"])
    key = (material_id, test_kind)
    with QUESTION_JOBS_LOCK:
        job = QUESTION_JOBS.get(key)
        if job is not None and job.running:
            raise HTTPException(status_code=409, detail="Soal masih dibuat")
        QUESTION_JOBS.pop(key, None)
    return {"message": "Hasil dihapus"}


@app.post("/teacher/materials/{material_id}/images/{image_id}/describe")
def describe_single_image(material_id: str, image_id: str, auth=Depends(require_teacher)):
    """Mencoba ulang deskripsi satu gambar. Cukup satu panggilan Gemini,
    jadi dijawab langsung tanpa proses latar belakang."""
    material = get_owned_material(material_id, auth["user_id"])
    require_gemini()
    job = DESCRIBE_JOBS.get(material_id)
    if job is not None and job.running:
        raise HTTPException(
            status_code=409,
            detail="Deskripsi gambar lain sedang dibuat. Tunggu sampai selesai",
        )
    row = next(
        (r for r in material_image_rows(material_id) if str(r["id"]) == image_id),
        None,
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Gambar tidak ditemukan")
    try:
        saved = describe_one(
            row, lambda: subject_is_deleted(material.get("subject_id"))
        )
    except AiJobCancelled as error:
        raise HTTPException(status_code=404, detail="Materi tidak ditemukan") from error
    except Exception as error:
        logger.exception("Gagal mendeskripsikan ulang %s", row["image_key"])
        message = describe_failure_message(error)
        if job is not None:
            job.failed[image_id] = message
        status = 429 if is_rate_limited(error) else 502
        raise HTTPException(status_code=status, detail=message) from error
    if job is not None:
        job.failed.pop(image_id, None)
    return {"message": "Deskripsi gambar dibuat", "image": public_image(saved)}


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


class MaterialTableUpdateRequest(BaseModel):
    title: str = Field(default="", max_length=200)
    columns: list[str]
    rows: list[list[str]]


@app.patch("/teacher/materials/{material_id}/sections/{section_id}/tables/{table_index}")
def update_material_table(
    material_id: str,
    section_id: str,
    table_index: int,
    data: MaterialTableUpdateRequest,
    auth=Depends(require_teacher),
):
    """Guru memperbaiki isi tabel hasil PDF."""
    get_owned_material(material_id, auth["user_id"])
    columns = [name.strip() for name in data.columns]
    rows = [[cell.strip() for cell in row] for row in data.rows]
    if len(columns) < 2 or not all(columns):
        raise HTTPException(status_code=400, detail="Semua kolom tabel harus punya nama.")
    if any(len(row) != len(columns) for row in rows):
        raise HTTPException(
            status_code=400, detail="Jumlah sel tiap baris harus sama dengan jumlah kolom."
        )
    if not any(any(row) for row in rows):
        raise HTTPException(status_code=400, detail="Tabel harus punya isi.")
    if any(len(cell) > 2000 for cell in [*columns, *(c for row in rows for c in row)]):
        raise HTTPException(status_code=400, detail="Isi sel tabel terlalu panjang.")
    sections = (
        supabase_admin.table("material_sections")
        .select("id, content")
        .eq("material_id", material_id)
        .execute()
    ).data or []
    section = next((row for row in sections if str(row["id"]) == section_id), None)
    if section is None:
        raise HTTPException(status_code=404, detail="Halaman tidak ditemukan")
    table = {"title": data.title.strip(), "columns": columns, "rows": rows}
    content = replace_table(section.get("content") or "", table_index, table)
    if content is None:
        raise HTTPException(status_code=404, detail="Tabel tidak ditemukan")
    supabase_admin.table("material_sections").update({"content": content}).eq(
        "id", section["id"]
    ).execute()
    return {"message": "Tabel disimpan", "table": table}


@app.patch("/teacher/quizzes/{quiz_id}/schedule")
def update_quiz_schedule(
    quiz_id: str, data: QuizScheduleRequest, auth=Depends(require_teacher)
):
    validate_schedule(data)
    if quiz_subject_is_deleted(quiz_id):
        raise HTTPException(status_code=404, detail="Kuis tidak ditemukan")
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


def subject_member_rows(subject_id):
    """Anggota kelas beserta namanya, urut nama."""
    members = (
        supabase_admin.table("subject_students")
        .select("student_id, joined_at")
        .eq("subject_id", subject_id)
        .execute()
    ).data or []
    if not members:
        return []
    users = (
        supabase_admin.table("users")
        .select("id, name")
        .in_("id", [row["student_id"] for row in members])
        .execute()
    ).data or []
    names = {row["id"]: row["name"] for row in users}
    rows = [
        {
            "id": row["student_id"],
            "name": names.get(row["student_id"], "Tanpa nama"),
            "joined_at": row.get("joined_at"),
        }
        for row in members
    ]
    return sorted(rows, key=lambda row: row["name"].casefold())


def student_email(student_id):
    """Email ada di Supabase Auth, bukan di tabel users. Kalau gagal diambil,
    daftar anggota tetap tampil tanpa email siswa itu."""
    try:
        return supabase_admin.auth.admin.get_user_by_id(student_id).user.email
    except Exception:
        logger.exception("Gagal mengambil email siswa %s", student_id)
        return None


@app.get("/teacher/subjects/{subject_id}/members")
def list_subject_members(subject_id: str, auth=Depends(require_teacher)):
    subject = get_owned_subject(subject_id, auth["user_id"])
    rows = subject_member_rows(subject_id)
    # Satu permintaan per siswa: dibuat bersamaan supaya kelas besar tidak lama.
    with ThreadPoolExecutor(max_workers=8) as pool:
        emails = list(pool.map(student_email, [row["id"] for row in rows]))
    return {
        "subject": {"id": subject["id"], "name": subject["name"]},
        "student_count": len(rows),
        "students": [{**row, "email": email} for row, email in zip(rows, emails)],
    }


@app.delete("/teacher/subjects/{subject_id}/members/{student_id}")
def remove_subject_member(
    subject_id: str, student_id: str, auth=Depends(require_teacher)
):
    """Mengeluarkan siswa dari kelas. Nilainya tetap tersimpan, dan muncul lagi
    kalau siswa bergabung kembali dengan kode akses."""
    get_owned_subject(subject_id, auth["user_id"])
    if not is_subject_member(subject_id, student_id):
        raise HTTPException(status_code=404, detail="Siswa bukan anggota kelas ini")
    materials = (
        supabase_admin.table("materials")
        .select("id")
        .eq("subject_id", subject_id)
        .execute()
    ).data or []
    # material_access lama juga memberi akses, jadi ikut dicabut.
    if materials:
        supabase_admin.table("material_access").delete().eq(
            "student_id", student_id
        ).in_("material_id", [row["id"] for row in materials]).execute()
    supabase_admin.table("subject_students").delete().eq("subject_id", subject_id).eq(
        "student_id", student_id
    ).execute()
    return {
        "message": "Siswa dikeluarkan dari kelas",
        "student_count": len(subject_member_rows(subject_id)),
    }


# Isi satu materi dalam urutan aman untuk foreign key: anak dihapus sebelum
# induknya, dan jawaban sebelum soal yang dirujuknya. Bentuk tiap baris:
# (tabel, kolom yang menunjuk ke induk, anak-anaknya). material_images dan
# materials tidak ada di sini: keduanya menyimpan alamat berkas Storage, jadi
# dihapus paling akhir.
MATERIAL_CHILD_TABLES = (
    ("material_access", "material_id", ()),
    (
        "quizzes",
        "material_id",
        (
            (
                "quiz_attempts",
                "quiz_id",
                (
                    (
                        "answers",
                        "attempt_id",
                        (
                            ("answer_options", "answer_id", ()),
                            ("answer_boolean", "answer_id", ()),
                            ("answer_text", "answer_id", ()),
                            ("answer_order_items", "answer_id", ()),
                        ),
                    ),
                ),
            ),
            (
                "questions",
                "quiz_id",
                (
                    ("question_options", "question_id", ()),
                    ("question_answers", "question_id", ()),
                    ("question_items", "question_id", ()),
                ),
            ),
        ),
    ),
    ("material_sections", "material_id", ()),
)
# Alamat permintaan punya batas panjang, dan select dibatasi 1000 baris.
DELETE_CHUNK_SIZE = 100
DELETE_PAGE_SIZE = 500


def chunks(values, size=DELETE_CHUNK_SIZE):
    return [values[i : i + size] for i in range(0, len(values), size)]


def delete_rows(table, column, values, children):
    """Menghapus baris yang `column`-nya ada di `values`, anak-anaknya lebih
    dulu. Baris tanpa anak dihapus langsung, karena sebagian tabel jawaban
    tidak punya kolom id."""
    for chunk in chunks(values):
        if not children:
            supabase_admin.table(table).delete().in_(column, chunk).execute()
            continue
        while True:
            rows = (
                supabase_admin.table(table)
                .select("id")
                .in_(column, chunk)
                .limit(DELETE_PAGE_SIZE)
                .execute()
            ).data or []
            if not rows:
                break
            ids = [row["id"] for row in rows]
            for child_table, child_column, grandchildren in children:
                delete_rows(child_table, child_column, ids, grandchildren)
            supabase_admin.table(table).delete().in_("id", ids).execute()


def subject_material_rows(subject_id):
    return (
        supabase_admin.table("materials")
        .select("id, file_url")
        .eq("subject_id", subject_id)
        .execute()
    ).data or []


def remove_from_storage(bucket, paths):
    for chunk in chunks(paths):
        supabase_admin.storage.from_(bucket).remove(chunk)


@app.get("/teacher/subjects/{subject_id}/delete-summary")
def subject_delete_summary(subject_id: str, auth=Depends(require_teacher)):
    """Apa saja yang ikut terhapus, untuk dialog konfirmasi guru."""
    get_owned_subject(subject_id, auth["user_id"])
    material_ids = [row["id"] for row in subject_material_rows(subject_id)]
    quizzes = quizzes_by_material(material_ids)
    return {
        "material_count": len(material_ids),
        "quiz_count": sum(len(group) for group in quizzes.values()),
        "student_count": len(subject_member_rows(subject_id)),
    }


def subjects_with_leftovers(subject_ids):
    """Kelas terhapus yang isinya belum habis. Baris materials dan anggota
    hanya tersisa kalau penghapusan berhenti di tengah."""
    if not subject_ids:
        return set()
    left = set()
    for table in ("materials", "subject_students", "attendance_sessions"):
        rows = (
            supabase_admin.table(table)
            .select("subject_id")
            .in_("subject_id", subject_ids)
            .execute()
        ).data or []
        left |= {row["subject_id"] for row in rows}
    return left


@app.delete("/teacher/subjects/{subject_id}")
def delete_subject(subject_id: str, auth=Depends(require_teacher)):
    """Menghapus kelas beserta seluruh isinya, dan melanjutkan penghapusan yang
    berhenti di tengah.

    Urutannya: tandai `deleted_at` supaya kelas langsung hilang dari guru dan
    siswa, hapus data, hapus berkas Storage, lalu hapus material_images dan
    materials. Dua tabel itu terakhir karena hanya di sanalah alamat berkas
    tersimpan: kalau Storage gagal, alamatnya masih ada untuk diulang. Baris kelas
    tetap ada, tanpa isi apa pun, supaya siswa yang membuka kelas ini mendapat
    penjelasan.
    """
    subject = (
        supabase_admin.table("subjects")
        .select("id, name, teacher_id, deleted_at")
        .eq("id", subject_id)
        .eq("teacher_id", auth["user_id"])
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    if subject is None or (
        subject.get("deleted_at") and subject_id not in subjects_with_leftovers([subject_id])
    ):
        raise HTTPException(status_code=404, detail="Kelas tidak ditemukan")
    try:
        if not subject.get("deleted_at"):
            supabase_admin.table("subjects").update(
                {"deleted_at": datetime.now(timezone.utc).isoformat()}
            ).eq("id", subject_id).execute()
        # Anggota lebih dulu supaya siswa langsung kehilangan akses.
        supabase_admin.table("subject_students").delete().eq(
            "subject_id", subject_id
        ).execute()
        # Catatan dulu, lalu sesinya. Kalau berhenti di tengah, sesi yang
        # tersisa membuat penghapusan bisa dilanjutkan.
        session_ids = [row["id"] for row in subject_sessions(subject_id)]
        delete_rows("attendance_records", "session_id", session_ids, ())
        delete_rows("attendance_sessions", "id", session_ids, ())
        materials = subject_material_rows(subject_id)
        material_ids = [row["id"] for row in materials]
        cancel_ai_jobs(material_ids)
        for table, column, children in MATERIAL_CHILD_TABLES:
            delete_rows(table, column, material_ids, children)
        remove_from_storage(
            "material-images",
            [
                row["image_url"]
                for material_id in material_ids
                for row in material_image_rows(material_id)
                if row.get("image_url")
            ],
        )
        remove_from_storage(
            "materials-pdf",
            [row["file_url"] for row in materials if row.get("file_url")],
        )
        delete_rows("material_images", "material_id", material_ids, ())
        delete_rows("materials", "id", material_ids, ())
    except Exception as error:
        logger.exception("Gagal menghapus kelas %s", subject_id)
        raise HTTPException(
            status_code=500, detail="Kelas belum terhapus sepenuhnya. Coba lagi"
        ) from error
    # Sekali lagi untuk proses yang terdaftar selagi kelas dihapus.
    cancel_ai_jobs(material_ids)
    return {
        "message": "Kelas dihapus",
        "subject": {"id": subject["id"], "name": subject["name"]},
    }


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


# ---- Progres siswa
#
# Nilai = persen benar, dibulatkan ke bilangan bulat terdekat (setengah ke atas).
# Pre-test memakai percobaan PERTAMA yang dikumpulkan (kemampuan awal),
# post-test memakai percobaan TERAKHIR. Jumlah percobaan tetap dilaporkan.
# Kenaikan = post-test - pre-test, hanya kalau keduanya ada.


def score_percent(correct, total):
    if not total:
        return None
    return (correct * 200 + total) // (2 * total)


def stars_for(correct, total):
    """Sama dengan `starsFor` di aplikasi."""
    if not total or correct <= 0:
        return 0
    ratio = correct / total
    if ratio >= 0.85:
        return 3
    if ratio >= 0.6:
        return 2
    return 1


def average_of(values):
    values = [value for value in values if value is not None]
    return round(sum(values) / len(values), 1) if values else None


def subject_quiz_materials(subject_id):
    """Materi kelas yang punya minimal satu kuis, urut waktu dibuat, beserta
    kuisnya per materi."""
    materials = (
        supabase_admin.table("materials")
        .select("id, title, is_published, created_at")
        .eq("subject_id", subject_id)
        .order("created_at")
        .execute()
    ).data or []
    quizzes = quizzes_by_material([row["id"] for row in materials])
    return [row for row in materials if quizzes.get(row["id"])], quizzes


def submitted_attempts(quiz_ids, student_ids):
    """Percobaan yang sudah dikumpulkan per (kuis, siswa), urut waktu kumpul."""
    grouped = {}
    if not quiz_ids or not student_ids:
        return grouped
    for quiz_chunk in chunks(list(quiz_ids)):
        for student_chunk in chunks(list(student_ids)):
            rows = (
                supabase_admin.table("quiz_attempts")
                .select(
                    "id, quiz_id, student_id, correct_count, total_questions, "
                    "submitted_at"
                )
                .in_("quiz_id", quiz_chunk)
                .in_("student_id", student_chunk)
                .not_.is_("submitted_at", "null")
                .execute()
            ).data or []
            for row in rows:
                key = (row["quiz_id"], row["student_id"])
                grouped.setdefault(key, []).append(row)
    for attempts in grouped.values():
        attempts.sort(key=lambda row: parse_time(row["submitted_at"]))
    return grouped


def quiz_progress(quiz, attempts):
    """Nilai satu siswa di satu kuis. `None` kalau kuisnya belum dibuat;
    `score` `None` kalau belum dikerjakan."""
    if quiz is None:
        return None
    attempts = attempts or []
    base = {
        "quiz_id": quiz["id"],
        "kind": quiz["kind"],
        "attempt_count": len(attempts),
    }
    if not attempts:
        return {
            **base,
            "attempt_id": None,
            "score": None,
            "correct_count": None,
            "total_questions": None,
            "stars": None,
            "submitted_at": None,
        }
    chosen = attempts[0] if quiz["kind"] == "pre" else attempts[-1]
    correct = chosen["correct_count"] or 0
    total = chosen["total_questions"] or 0
    return {
        **base,
        "attempt_id": chosen["id"],
        "score": score_percent(correct, total),
        "correct_count": correct,
        "total_questions": total,
        "stars": stars_for(correct, total),
        "submitted_at": chosen["submitted_at"],
    }


def progress_gain(pre, post):
    if pre is None or post is None:
        return None
    if pre["score"] is None or post["score"] is None:
        return None
    return post["score"] - pre["score"]


def material_progress(quizzes, student_id, attempts):
    """Pre-test, post-test, dan kenaikan satu siswa di satu materi."""
    by_kind = {quiz["kind"]: quiz for quiz in quizzes}
    result = {}
    for kind in ("pre", "post"):
        quiz = by_kind.get(kind)
        result[kind] = quiz_progress(
            quiz, attempts.get((quiz["id"], student_id)) if quiz else None
        )
    result["gain"] = progress_gain(result["pre"], result["post"])
    return result


def gain_direction_counts(gains_per_student):
    """Berapa siswa naik, tetap, atau turun menurut rata-rata kenaikannya."""
    counts = {"improved": 0, "same": 0, "declined": 0}
    for gains in gains_per_student:
        average = average_of(gains)
        if average is None:
            continue
        if average > 0:
            counts["improved"] += 1
        elif average < 0:
            counts["declined"] += 1
        else:
            counts["same"] += 1
    return counts


def quiz_ids_of(materials, quizzes):
    return [quiz["id"] for row in materials for quiz in quizzes[row["id"]]]


@app.get("/teacher/subjects/{subject_id}/progress")
def get_subject_progress(subject_id: str, auth=Depends(require_teacher)):
    """Tabel nilai tiap siswa di tiap materi: pre-test, post-test, kenaikan,
    beserta ringkasan kelas."""
    subject = get_owned_subject(subject_id, auth["user_id"])
    students = subject_member_rows(subject_id)
    materials, quizzes = subject_quiz_materials(subject_id)
    attempts = submitted_attempts(
        quiz_ids_of(materials, quizzes), [student["id"] for student in students]
    )
    gains_per_student = {student["id"]: [] for student in students}
    all_pre, all_post, all_gain = [], [], []
    result_materials = []
    for material in materials:
        rows = []
        pre_scores, post_scores, gains = [], [], []
        for student in students:
            row = material_progress(quizzes[material["id"]], student["id"], attempts)
            if row["pre"] and row["pre"]["score"] is not None:
                pre_scores.append(row["pre"]["score"])
            if row["post"] and row["post"]["score"] is not None:
                post_scores.append(row["post"]["score"])
            if row["gain"] is not None:
                gains.append(row["gain"])
                gains_per_student[student["id"]].append(row["gain"])
            rows.append({"student_id": student["id"], "name": student["name"], **row})
        all_pre += pre_scores
        all_post += post_scores
        all_gain += gains
        kinds = {quiz["kind"] for quiz in quizzes[material["id"]]}
        result_materials.append(
            {
                "id": material["id"],
                "title": material["title"],
                "is_published": material["is_published"],
                "has_pre": "pre" in kinds,
                "has_post": "post" in kinds,
                "average_pre": average_of(pre_scores),
                "average_post": average_of(post_scores),
                "average_gain": average_of(gains),
                "rows": rows,
            }
        )
    return {
        "subject": {"id": subject["id"], "name": subject["name"]},
        "summary": {
            "student_count": len(students),
            "material_count": len(materials),
            "average_pre": average_of(all_pre),
            "average_post": average_of(all_post),
            "average_gain": average_of(all_gain),
            "complete_count": len(all_gain),
            **gain_direction_counts(gains_per_student.values()),
        },
        "materials": result_materials,
    }


@app.get("/teacher/subjects/{subject_id}/students/{student_id}/progress")
def get_student_progress(
    subject_id: str, student_id: str, auth=Depends(require_teacher)
):
    """Progres satu siswa di kelas ini: nilai, bintang, waktu mengerjakan, dan
    jumlah percobaan tiap kuis, serta rata-rata kenaikannya."""
    subject = get_owned_subject(subject_id, auth["user_id"])
    student = next(
        (row for row in subject_member_rows(subject_id) if row["id"] == student_id),
        None,
    )
    if student is None:
        raise HTTPException(status_code=404, detail="Siswa bukan anggota kelas ini")
    materials, quizzes = subject_quiz_materials(subject_id)
    attempts = submitted_attempts(quiz_ids_of(materials, quizzes), [student_id])
    result_materials = []
    gains = []
    for material in materials:
        row = material_progress(quizzes[material["id"]], student_id, attempts)
        if row["gain"] is not None:
            gains.append(row["gain"])
        result_materials.append({"id": material["id"], "title": material["title"], **row})
    return {
        "subject": {"id": subject["id"], "name": subject["name"]},
        "student": {
            "id": student["id"],
            "name": student["name"],
            "joined_at": student["joined_at"],
        },
        "average_gain": average_of(gains),
        "complete_count": len(gains),
        "materials": result_materials,
    }


@app.post("/student/subjects/join")
def join_subject(data: JoinSubjectRequest, auth=Depends(require_student)):
    code = normalize_access_code(data.code)
    if not ACCESS_CODE_RE.match(code):
        raise HTTPException(status_code=400, detail="Kode akses harus 6 huruf")
    subject_response = (
        supabase_admin.table("subjects")
        .select("id, name, teacher_id, deleted_at")
        .eq("access_code", code)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    )
    subject = subject_response.data
    if subject is None:
        raise HTTPException(status_code=404, detail="Kode akses tidak ditemukan")
    if subject.get("deleted_at"):
        raise HTTPException(status_code=410, detail=SUBJECT_DELETED_DETAIL)
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


@app.get("/student/subjects/{subject_id}/members")
def list_subject_classmates(subject_id: str, auth=Depends(require_student)):
    """Nama guru dan nama teman sekelas. Sengaja tanpa id, email, dan tanggal
    bergabung: siswa hanya perlu tahu namanya."""
    student_id = auth["user_id"]
    subject = get_member_subject(subject_id, student_id)
    teacher = (
        supabase_admin.table("users")
        .select("name")
        .eq("id", subject["teacher_id"])
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    rows = subject_member_rows(subject_id)
    return {
        "subject": {"id": subject["id"], "name": subject["name"]},
        "teacher_name": (teacher or {}).get("name"),
        "student_count": len(rows),
        "classmates": [
            {"name": row["name"], "is_me": str(row["id"]) == str(student_id)}
            for row in rows
        ],
    }


@app.get("/student/subjects/{subject_id}/materials")
def list_student_subject_materials(subject_id: str, auth=Depends(require_student)):
    student_id = auth["user_id"]
    subject = get_member_subject(subject_id, student_id)
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


def get_readable_material(material_id, auth):
    """Materi yang boleh dibaca: milik guru ini, atau terbit dan bisa diakses siswa."""
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
        if material["teacher_id"] != auth["user_id"] or subject_is_deleted(
            material.get("subject_id")
        ):
            raise HTTPException(status_code=404, detail="Materi tidak ditemukan")
    else:
        if subject_is_deleted(material.get("subject_id")):
            raise HTTPException(status_code=410, detail=SUBJECT_DELETED_DETAIL)
        if not material["is_published"]:
            raise HTTPException(status_code=403, detail="Materi belum dipublikasikan")
        if not student_can_access_material(material, auth["user_id"]):
            raise HTTPException(
                status_code=403, detail="Anda tidak memiliki akses ke materi ini"
            )
    return material


@app.get("/materials/{material_id}/sections")
def get_material_sections(material_id: str, auth=Depends(get_current_profile)):
    material = get_readable_material(material_id, auth)
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
    sections = sections_response.data or []
    # Materi lama dan teks ketikan guru bisa masih memuat tanda butir.
    for section in sections:
        section["content"] = normalize_content(section.get("content") or "")
    return {
        "material": {"id": material["id"], "title": material["title"]},
        "sections": sections,
        # Deskripsi untuk penanda [[gambar:...]] di isi halaman.
        "images": [public_image(row) for row in material_image_rows(material_id)],
    }


SEARCH_MIN_LENGTH = 2
SEARCH_MAX_LENGTH = 100


@app.get("/materials/{material_id}/search")
def search_material(material_id: str, q: str = "", auth=Depends(get_current_profile)):
    """Halaman yang memuat kata `q`. Satu hasil per halaman, di blok pertama yang
    cocok. Judul halaman hanya dipakai kalau isinya tidak cocok."""
    get_readable_material(material_id, auth)
    query = plain_words(q)
    needle = query.lower()
    if not SEARCH_MIN_LENGTH <= len(needle) <= SEARCH_MAX_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Kata pencarian harus {SEARCH_MIN_LENGTH} sampai "
                f"{SEARCH_MAX_LENGTH} huruf"
            ),
        )
    sections_response = (
        supabase_admin.table("material_sections")
        .select("id, position, title, content")
        .eq("material_id", material_id)
        .order("position")
        .execute()
    )
    descriptions = {
        row["image_key"]: row.get("description")
        for row in material_image_rows(material_id)
        if not row.get("is_decorative")
    }
    results = []
    # Nomor mengikuti urutan layar baca, dan `line` menunjuk baris di isi yang
    # sama dengan jawaban GET .../sections.
    for page_index, section in enumerate(sections_response.data or []):
        title = section.get("title") or ""
        found = search_content(
            normalize_content(section.get("content") or ""), descriptions, needle
        )
        if found is None and needle in plain_words(title).lower():
            found = {
                "line": None,
                "row": None,
                "snippet": search_snippet(title, needle),
            }
        if found is not None:
            results.append(
                {
                    "section_id": section["id"],
                    "page_index": page_index,
                    "title": title,
                    **found,
                }
            )
    return {"query": query, "results": results}


# ---- Presensi
#
# Status sesi (belum dibuka, terbuka, ditutup) selalu dihitung dengan jam
# server, bukan jam HP. Alpa tidak disimpan oleh tugas terjadwal karena server
# Render bisa tidur: siswa tanpa catatan di sesi yang sudah tutup dihitung alpa
# saat data dibaca.

# Asia/Jakarta tidak memakai waktu musim panas, jadi selisih tetap cukup dan
# tidak bergantung pada data zona waktu sistem (Windows tidak punya).
JAKARTA = timezone(timedelta(hours=7), "WIB")
ATTENDANCE_STATUSES = ("hadir", "izin", "sakit", "alpa")
# Pilihan cepat waktu tutup, dihitung dari jam server saat sesi dibuat.
CLOSE_PRESET_MINUTES = {"15m": 15, "30m": 30, "1h": 60}
ClosePreset = Literal["15m", "30m", "1h", "end_of_day"]
SESSION_COLUMNS = "id, subject_id, title, opens_at, closes_at, created_at"
SESSION_NOT_FOUND = "Sesi presensi tidak ditemukan"


def server_now():
    """Jam server. Diganti di tes."""
    return datetime.now(timezone.utc)


def end_of_day(moment):
    """Pukul 23.59.59 WIB pada hari yang sama dengan `moment`."""
    return moment.astimezone(JAKARTA).replace(
        hour=23, minute=59, second=59, microsecond=0
    )


def as_aware(value):
    """Waktu tanpa zona dianggap WIB, zona sekolah."""
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=JAKARTA)


def session_state(session, now):
    if now < parse_time(session["opens_at"]):
        return "upcoming"
    if now >= parse_time(session["closes_at"]):
        return "closed"
    return "open"


def public_session(session, now):
    opens_at = parse_time(session["opens_at"])
    closes_at = parse_time(session["closes_at"])
    state = session_state(session, now)
    return {
        "id": session["id"],
        "subject_id": session["subject_id"],
        "title": session["title"],
        "opens_at": opens_at.isoformat(),
        "closes_at": closes_at.isoformat(),
        "state": state,
        # Aplikasi memuat ulang setelah detik-detik ini, tanpa membaca jam HP.
        "seconds_until_open": (
            max(0, int((opens_at - now).total_seconds()))
            if state == "upcoming"
            else None
        ),
        "seconds_until_close": (
            max(0, int((closes_at - now).total_seconds()))
            if state != "closed"
            else None
        ),
    }


def expected_in_session(member, session):
    """Siswa hanya dihitung di sesi yang tutup setelah ia bergabung."""
    joined = parse_time(member.get("joined_at"))
    return joined is None or joined < parse_time(session["closes_at"])


def effective_status(session, record, now):
    """Status catatan, atau alpa kalau sesi sudah tutup tanpa catatan. None
    berarti belum presensi di sesi yang belum tutup."""
    if record is not None:
        return record["status"]
    return "alpa" if session_state(session, now) == "closed" else None


def empty_counts():
    return {status: 0 for status in ATTENDANCE_STATUSES}


def subject_sessions(subject_id):
    """Sesi kelas, yang terbaru dibuka lebih dulu."""
    rows = (
        supabase_admin.table("attendance_sessions")
        .select(SESSION_COLUMNS)
        .eq("subject_id", subject_id)
        .execute()
    ).data or []
    return sorted(rows, key=lambda row: parse_time(row["opens_at"]), reverse=True)


def session_records(session_ids, student_id=None):
    """Catatan presensi menurut (session_id, student_id)."""
    records = {}
    for chunk in chunks(list(session_ids)):
        query = (
            supabase_admin.table("attendance_records")
            .select("session_id, student_id, status, source, marked_at")
            .in_("session_id", chunk)
        )
        if student_id is not None:
            query = query.eq("student_id", student_id)
        for row in query.execute().data or []:
            records[(row["session_id"], row["student_id"])] = row
    return records


def member_status(session, member, records, now):
    """(dihitung, status) seorang anggota di satu sesi."""
    record = records.get((session["id"], member["id"]))
    if record is None and not expected_in_session(member, session):
        return False, None
    return True, effective_status(session, record, now)


def session_counts(session, members, records, now):
    counts = {**empty_counts(), "belum": 0}
    for member in members:
        counted, status = member_status(session, member, records, now)
        if counted:
            counts[status or "belum"] += 1
    return counts


def find_session(session_id):
    session = (
        supabase_admin.table("attendance_sessions")
        .select(SESSION_COLUMNS)
        .eq("id", session_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    if session is None:
        raise HTTPException(status_code=404, detail=SESSION_NOT_FOUND)
    return session


def get_owned_session(session_id, teacher_id):
    """Sesi di kelas milik guru ini. Kelas yang dihapus dijawab 404."""
    session = find_session(session_id)
    try:
        get_owned_subject(session["subject_id"], teacher_id)
    except HTTPException:
        raise HTTPException(status_code=404, detail=SESSION_NOT_FOUND) from None
    return session


def get_member_session(session_id, student_id):
    """Sesi di kelas yang diikuti siswa ini. Kelas yang dihapus dijawab 410."""
    session = find_session(session_id)
    get_member_subject(session["subject_id"], student_id)
    return session


def validate_session_times(opens_at, closes_at, now):
    if closes_at <= opens_at:
        raise HTTPException(
            status_code=422, detail="Waktu tutup harus setelah waktu buka"
        )
    if closes_at <= now:
        raise HTTPException(
            status_code=422, detail="Waktu tutup sudah lewat. Pilih waktu lain"
        )


def clean_title(title):
    title = " ".join(title.split())
    if not title:
        raise HTTPException(status_code=422, detail="Judul sesi wajib diisi")
    return title


def preset_close(preset, opens_at, now):
    """Waktu tutup dari pilihan cepat, dihitung dari waktu buka atau jam
    server, mana yang lebih akhir."""
    start = max(opens_at, now)
    if preset == "end_of_day":
        return end_of_day(start)
    return start + timedelta(minutes=CLOSE_PRESET_MINUTES[preset])


class AttendanceSessionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    # Kosong berarti dibuka sekarang (jam server).
    opens_at: Optional[datetime] = None
    # Isi salah satu: waktu tutup sendiri, atau pilihan cepat.
    closes_at: Optional[datetime] = None
    close_preset: Optional[ClosePreset] = None


class AttendanceSessionUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=100)
    opens_at: Optional[datetime] = None
    closes_at: Optional[datetime] = None
    close_preset: Optional[ClosePreset] = None
    close_now: bool = False


class AttendanceStatusUpdate(BaseModel):
    status: Literal["hadir", "izin", "sakit", "alpa"]


@app.post("/teacher/subjects/{subject_id}/attendance/sessions")
def create_attendance_session(
    subject_id: str, data: AttendanceSessionCreate, auth=Depends(require_teacher)
):
    get_owned_subject(subject_id, auth["user_id"])
    now = server_now()
    title = clean_title(data.title)
    if (data.closes_at is None) == (data.close_preset is None):
        raise HTTPException(
            status_code=422,
            detail="Pilih waktu tutup: pilihan cepat atau atur sendiri",
        )
    opens_at = as_aware(data.opens_at) or now
    closes_at = (
        preset_close(data.close_preset, opens_at, now)
        if data.close_preset
        else as_aware(data.closes_at)
    )
    validate_session_times(opens_at, closes_at, now)
    row = (
        supabase_admin.table("attendance_sessions")
        .insert(
            {
                "subject_id": subject_id,
                "title": title,
                "opens_at": opens_at.isoformat(),
                "closes_at": closes_at.isoformat(),
                "created_by": auth["user_id"],
            }
        )
        .execute()
    ).data[0]
    return {"session": public_session(row, now)}


@app.get("/teacher/subjects/{subject_id}/attendance/sessions")
def list_attendance_sessions(subject_id: str, auth=Depends(require_teacher)):
    get_owned_subject(subject_id, auth["user_id"])
    now = server_now()
    sessions = subject_sessions(subject_id)
    members = subject_member_rows(subject_id)
    records = session_records([row["id"] for row in sessions])
    return {
        "server_time": now.isoformat(),
        "sessions": [
            {
                **public_session(row, now),
                "counts": session_counts(row, members, records, now),
            }
            for row in sessions
        ],
    }


@app.get("/teacher/attendance/sessions/{session_id}")
def get_attendance_session(session_id: str, auth=Depends(require_teacher)):
    """Rekap satu sesi: status tiap siswa."""
    session = get_owned_session(session_id, auth["user_id"])
    now = server_now()
    members = subject_member_rows(session["subject_id"])
    records = session_records([session_id])
    students = []
    for member in members:
        counted, status = member_status(session, member, records, now)
        if not counted:
            continue
        record = records.get((session_id, member["id"]))
        students.append(
            {
                "student_id": member["id"],
                "name": member["name"],
                "status": status,
                "source": record["source"] if record else None,
                "marked_at": record["marked_at"] if record else None,
            }
        )
    return {
        "session": {
            **public_session(session, now),
            "counts": session_counts(session, members, records, now),
        },
        "students": students,
    }


@app.patch("/teacher/attendance/sessions/{session_id}")
def update_attendance_session(
    session_id: str, data: AttendanceSessionUpdate, auth=Depends(require_teacher)
):
    session = get_owned_session(session_id, auth["user_id"])
    now = server_now()
    changes = {}
    if data.title is not None:
        changes["title"] = clean_title(data.title)
    old_opens = parse_time(session["opens_at"])
    old_closes = parse_time(session["closes_at"])
    opens_at = as_aware(data.opens_at) or old_opens
    closes_at = old_closes
    if data.close_now:
        state = session_state(session, now)
        if state == "upcoming":
            raise HTTPException(
                status_code=409,
                detail="Sesi belum dibuka. Hapus sesi kalau tidak jadi dipakai",
            )
        if state == "closed":
            raise HTTPException(status_code=409, detail="Sesi sudah ditutup")
        closes_at = now
    else:
        if data.close_preset is not None:
            closes_at = preset_close(data.close_preset, opens_at, now)
        elif data.closes_at is not None:
            closes_at = as_aware(data.closes_at)
        if opens_at != old_opens or closes_at != old_closes:
            validate_session_times(opens_at, closes_at, now)
    if opens_at != old_opens:
        changes["opens_at"] = opens_at.isoformat()
    if closes_at != old_closes:
        changes["closes_at"] = closes_at.isoformat()
    if changes:
        changes["updated_at"] = now.isoformat()
        session = (
            supabase_admin.table("attendance_sessions")
            .update(changes)
            .eq("id", session_id)
            .execute()
        ).data[0]
    return {"session": public_session(session, now)}


@app.delete("/teacher/attendance/sessions/{session_id}")
def delete_attendance_session(session_id: str, auth=Depends(require_teacher)):
    session = get_owned_session(session_id, auth["user_id"])
    supabase_admin.table("attendance_records").delete().eq(
        "session_id", session_id
    ).execute()
    supabase_admin.table("attendance_sessions").delete().eq(
        "id", session_id
    ).execute()
    return {"message": "Sesi presensi dihapus", "session_id": session["id"]}


@app.put("/teacher/attendance/sessions/{session_id}/students/{student_id}")
def set_attendance_status(
    session_id: str,
    student_id: str,
    data: AttendanceStatusUpdate,
    auth=Depends(require_teacher),
):
    session = get_owned_session(session_id, auth["user_id"])
    member = next(
        (
            row
            for row in subject_member_rows(session["subject_id"])
            if row["id"] == student_id
        ),
        None,
    )
    if member is None:
        raise HTTPException(status_code=404, detail="Siswa bukan anggota kelas ini")
    now = server_now()
    record = (
        supabase_admin.table("attendance_records")
        .upsert(
            {
                "session_id": session_id,
                "student_id": student_id,
                "status": data.status,
                "source": "guru",
                "updated_by": auth["user_id"],
                "marked_at": now.isoformat(),
            },
            on_conflict="session_id,student_id",
        )
        .execute()
    ).data[0]
    return {
        "student": {
            "student_id": student_id,
            "name": member["name"],
            "status": record["status"],
            "source": record["source"],
            "marked_at": record["marked_at"],
        }
    }


@app.get("/teacher/subjects/{subject_id}/attendance/summary")
def attendance_summary(subject_id: str, auth=Depends(require_teacher)):
    """Rekap per siswa: jumlah tiap status di semua sesi kelas. Sesi yang
    belum tutup hanya dihitung kalau sudah ada catatannya."""
    get_owned_subject(subject_id, auth["user_id"])
    now = server_now()
    sessions = subject_sessions(subject_id)
    members = subject_member_rows(subject_id)
    records = session_records([row["id"] for row in sessions])
    students = []
    for member in members:
        counts = empty_counts()
        for session in sessions:
            _, status = member_status(session, member, records, now)
            if status is not None:
                counts[status] += 1
        students.append(
            {"student_id": member["id"], "name": member["name"], "counts": counts}
        )
    return {"session_count": len(sessions), "students": students}


def member_joined_at(subject_id, student_id):
    row = (
        supabase_admin.table("subject_students")
        .select("joined_at")
        .eq("subject_id", subject_id)
        .eq("student_id", student_id)
        .maybe_single()
        .execute()
        or EMPTY_RESPONSE
    ).data
    return (row or {}).get("joined_at")


@app.get("/student/subjects/{subject_id}/attendance")
def student_attendance(subject_id: str, auth=Depends(require_student)):
    """Sesi presensi kelas beserta status siswa ini, dan rekapnya."""
    student_id = auth["user_id"]
    get_member_subject(subject_id, student_id)
    now = server_now()
    me = {"id": student_id, "joined_at": member_joined_at(subject_id, student_id)}
    sessions = subject_sessions(subject_id)
    records = session_records([row["id"] for row in sessions], student_id)
    counts = empty_counts()
    items = []
    for session in sessions:
        counted, status = member_status(session, me, records, now)
        if not counted:
            continue
        if status is not None:
            counts[status] += 1
        record = records.get((session["id"], student_id))
        items.append(
            {
                **public_session(session, now),
                "status": status,
                "source": record["source"] if record else None,
                "marked_at": record["marked_at"] if record else None,
            }
        )
    return {"server_time": now.isoformat(), "counts": counts, "sessions": items}


def already_marked(session, record):
    who = " oleh guru" if record["source"] == "guru" else ""
    return HTTPException(
        status_code=409,
        detail=f"Kamu sudah tercatat {record['status']}{who} di {session['title']}",
    )


@app.post("/student/attendance/sessions/{session_id}/present")
def mark_present(session_id: str, auth=Depends(require_student)):
    student_id = auth["user_id"]
    session = get_member_session(session_id, student_id)
    now = server_now()
    state = session_state(session, now)
    if state == "upcoming":
        raise HTTPException(status_code=409, detail="Sesi presensi belum dibuka")
    if state == "closed":
        raise HTTPException(status_code=409, detail="Sesi presensi sudah ditutup")
    key = (session_id, student_id)
    existing = session_records([session_id], student_id).get(key)
    if existing is not None:
        raise already_marked(session, existing)
    try:
        record = (
            supabase_admin.table("attendance_records")
            .insert(
                {
                    "session_id": session_id,
                    "student_id": student_id,
                    "status": "hadir",
                    "source": "siswa",
                    "updated_by": student_id,
                    "marked_at": now.isoformat(),
                }
            )
            .execute()
        ).data[0]
    except APIError as error:
        # Dua ketukan bersamaan: yang kedua kena primary key.
        if getattr(error, "code", None) != "23505":
            raise
        existing = session_records([session_id], student_id).get(key)
        raise already_marked(
            session, existing or {"status": "hadir", "source": "siswa"}
        ) from None
    return {
        "session": {
            **public_session(session, now),
            "status": record["status"],
            "source": record["source"],
            "marked_at": record["marked_at"],
        }
    }
