from pathlib import Path
import pymupdf
from backend.ai_quiz import generate_quiz

pdf_path = Path(__file__).with_name("Mengirim_Pesan_Rahasia.pdf")
with pymupdf.open(pdf_path) as pdf:
    materi = "\n".join(page.get_text("text") for page in pdf)
if not materi.strip():
    raise ValueError(
        "Teks PDF kosong. PDF mungkin berupa hasil scan yang memerlukan OCR."
    )

total_questions = 1
quiz_type = "multiple_choice"

result = generate_quiz(
    materi=materi,
    total_questions=total_questions,
    quiz_type=quiz_type
)

print(f"Berhasil: {len(result.questions)} soal valid.\n")
print(result.model_dump_json(indent=2))
