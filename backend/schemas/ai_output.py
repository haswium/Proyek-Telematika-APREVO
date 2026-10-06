from typing import Annotated, Literal, Union
from pydantic import BaseModel, Field, StrictBool, field_validator, model_validator


class MultipleChoiceOption(BaseModel):
    text: str
    is_correct: StrictBool


class MultipleChoiceQuestion(BaseModel):
    type: Literal["multiple_choice"]
    question: str
    options: list[MultipleChoiceOption]

    @model_validator(mode="after")
    def validate_correct_answer(self):
        correct_count = sum(option.is_correct for option in self.options)
        if correct_count != 1:
            raise ValueError("Multiple choice harus memiliki tepat 1 jawaban benar.")

        return self


class TrueFalseQuestion(BaseModel):
    type: Literal["true_false"]
    question: str
    correct_answer: StrictBool


class TextAnswer(BaseModel):
    answer: str

    @field_validator("answer")
    @classmethod
    def validate_answer_length(cls, value):
        word_count = len(value.split())
        if word_count > 3:
            raise ValueError("Jawaban isian singkat maksimal 3 kata.")
        return value


class TextQuestion(BaseModel):
    type: Literal["text"]
    question: str
    answers: list[TextAnswer]

    @model_validator(mode="after")
    def validate_answers(self):
        if len(self.answers) < 1:
            raise ValueError("Isian singkat harus memiliki minimal 1 jawaban.")
        return self


class OrderingItem(BaseModel):
    text: str
    correct_order: int


class OrderingQuestion(BaseModel):
    type: Literal["ordering"]
    question: str
    items: list[OrderingItem]

    @model_validator(mode="after")
    def validate_order(self):
        orders = [item.correct_order for item in self.items]
        expected = list(range(1, len(self.items) + 1))
        if sorted(orders) != expected:
            raise ValueError("Urutan harus lengkap dan dimulai dari 1 tanpa duplikat.")
        return self


Question = Annotated[
    Union[MultipleChoiceQuestion, TrueFalseQuestion, TextQuestion, OrderingQuestion],
    Field(discriminator="type"),
]


class AIOutput(BaseModel):
    questions: list[Question]
