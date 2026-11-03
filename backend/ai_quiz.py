from collections.abc import Sequence

from ai_client import gemini_client
from schemas.ai_output import AIOutput

# Form soal guru hanya punya empat kolom pilihan atau langkah.
MAX_CHOICES = 4

type_rules = {
    "multiple_choice": """
    Setiap soal wajib memiliki:
    - type: "multiple_choice"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban, wajib diisi
    - options: daftar objek dengan field text dan is_correct, 2 sampai 4 opsi
    - Tepat satu opsi memiliki is_correct bernilai true.
    """,
        "true_false": """
    Setiap soal wajib memiliki:
    - type: "true_false"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban, wajib diisi
    - correct_answer: boolean true atau false
    """,
        "text": """
    Setiap soal wajib memiliki:
    - type: "text"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban, wajib diisi
    - answers: daftar objek dengan field answer berisi jawaban yang diterima
    """,
        "ordering": """
    Setiap soal wajib memiliki:
    - type: "ordering"
    - question: instruksi mengurutkan
    - explanation: penjelasan urutan, wajib diisi
    - items: daftar objek dengan field text dan correct_order, 2 sampai 4 item
    - correct_order dimulai dari 1 tanpa nomor duplikat atau terlewat.
    """
}

def validate_draft(question) -> None:
    """Syarat draf soal AI yang lebih ketat dari skema AIOutput. Skema itu juga
    dipakai untuk menyimpan soal ketikan guru, yang penjelasannya boleh kosong."""
    if not question.question.strip():
        raise ValueError("Teks soal tidak boleh kosong.")
    if not (question.explanation or "").strip():
        raise ValueError("Setiap soal harus punya penjelasan.")
    if question.type == "multiple_choice":
        choices = [option.text for option in question.options]
    elif question.type == "ordering":
        choices = [item.text for item in question.items]
    elif question.type == "text":
        choices = [answer.answer for answer in question.answers]
    else:
        return
    if question.type != "text" and len(choices) > MAX_CHOICES:
        raise ValueError(f"Pilihan atau langkah maksimal {MAX_CHOICES}.")
    if any(not choice.strip() for choice in choices):
        raise ValueError("Pilihan, langkah, atau jawaban tidak boleh kosong.")


def generate_quiz(
        materi: str,
        total_questions: int,
         quiz_type: str,
         avoid_questions: Sequence[str] = (),
) -> AIOutput:
    """Menghasilkan dan memvalidasi draf soal dari materi.

    `avoid_questions` berisi soal yang sudah dibuat di panggilan sebelumnya,
    supaya tidak terulang kalau soal dibuat beberapa kali panggilan.
    """
    if not materi.strip():
        raise ValueError("Materi tidak boleh koosng.")
    if total_questions < 1:
        raise ValueError("Jumlah soal minimal 1.")
    if quiz_type not in type_rules:
        raise ValueError(f"Tipe soal tidak valid: {quiz_type}")

    avoid_rule = ""
    if avoid_questions:
        daftar = "\n".join(f"    * {question}" for question in avoid_questions)
        avoid_rule = f"- Jangan mengulang atau memirip-miripkan soal berikut:\n{daftar}"

    prompt = f"""
    Buat {total_questions} soal kuis berdasarkan materi berikut untuk siswa sekolah.

    Materi: {materi}
    Tipe Kuis: {quiz_type}

    Aturan:
    - Semua soal harus menggunakan tipe "{quiz_type}".
    - Jangan mencampurkan tipe soal lain.
    - Ikuti struktur field berikut: {type_rules[quiz_type]}
    - Soal dan jawaban harus sesuai materi.
    - Setiap soal wajib punya penjelasan yang membantu siswa memahami jawabannya.
    - Gunakan bahasa indonesia yang jelas dan mudah dipahami.
    {avoid_rule}
    - Keluarkan JSON valid saja, tanpa markdown.
    - Struktur utama: {{"questions": [...]}}
    """

    response = gemini_client().models.generate_content(
        model="gemini-3.5-flash-lite",
        contents=prompt,
        config={"response_mime_type": "application/json"},
    )

    if not response.text:
        raise ValueError("Gemini tidak menghasilkan respons teks.")

    result = AIOutput.model_validate_json(response.text)
    if len(result.questions) != total_questions:
        raise ValueError(
            f"Guru meminta {total_questions} soal, tetapi Gemini menghasilkan {len(result.questions)} soal."
            )
    for question in result.questions:
        if question.type != quiz_type:
            raise ValueError(f"Gemini menghasilkan tipe soal {question.type}.")
        validate_draft(question)
    return result
