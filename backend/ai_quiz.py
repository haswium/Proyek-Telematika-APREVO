from ai_client import gemini_client
from schemas.ai_output import AIOutput

type_rules = {
    "multiple_choice": """
    Setiap soal wajib memiliki:
    - type: "multiple_choice"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban
    - options: daftar objek dengan field text dan is_correct
    - Tepat satu opsi memiliki is_correct bernilai true.
    """,
        "true_false": """
    Setiap soal wajib memiliki:
    - type: "true_false"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban
    - correct_answer: boolean true atau false
    """,
        "text": """
    Setiap soal wajib memiliki:
    - type: "text"
    - question: teks pertanyaan
    - explanation: penjelasan jawaban
    - answers: daftar objek dengan field answer berisi jawaban yang diterima
    """,
        "ordering": """
    Setiap soal wajib memiliki:
    - type: "ordering"
    - question: instruksi mengurutkan
    - explanation: penjelasan urutan
    - items: daftar objek dengan field text dan correct_order
    - correct_order dimulai dari 1 tanpa nomor duplikat atau terlewat.
    """
}

def generate_quiz(
        materi: str,
        total_questions: int,
         quiz_type: str
) -> AIOutput:
    """Menghasilkan dan memvalidasi draf soal dari materi."""
    if not materi.strip():
        raise ValueError("Materi tidak boleh koosng.")
    if total_questions < 1:
        raise ValueError("Jumlah soal minimal 1.")
    if quiz_type not in type_rules:
        raise ValueError(f"Tipe soal tidak valid: {quiz_type}")

    prompt = f"""
    Buat {total_questions} soal kuis berdasarkan materi berikut untuk siswa sekolah.

    Materi: {materi}
    Tipe Kuis: {quiz_type}

    Aturan:
    - Semua soal harus menggunakan tipe "{quiz_type}".
    - Jangan mencampurkan tipe soal lain.
    - Ikuti struktur field berikut: {type_rules[quiz_type]}
    - Soal dan jawaban harus sesuai materi.
    - Gunakan bahasa indonesia yang jelas dan mudah dipahami.
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
    return result