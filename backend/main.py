from fastapi import FastAPI, Depends, HTTPException
from schemas.ai_output import AIOutput
from dotenv import load_dotenv
import os
from supabase import create_client, ClientOptions
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
supabase_admin = create_client(SUPABASE_URL, os.getenv("SUPABASE_SERVICE_KEY"))

app = FastAPI()

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
        .is_("deleted_at", "null").single().execute()
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


@app.post("/validate-ai")
def validate_ai(data: AIOutput):
    return {"message": "Output AI valid!", "data": data}
