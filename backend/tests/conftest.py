"""Tes berjalan tanpa Supabase asli.

Variabel lingkungan palsu dipasang sebelum main diimpor. load_dotenv() tidak
menimpa variabel yang sudah ada, jadi nilai di .env tidak dipakai di sini.
"""

import os
import sys
from pathlib import Path
from uuid import uuid4

import pytest

os.environ["SUPABASE_URL"] = "http://localhost:54321"
os.environ["SUPABASE_KEY"] = "test-anon-key"
os.environ["SUPABASE_SERVICE_KEY"] = "test-service-key"
os.environ["ENABLE_DEBUG_ENDPOINTS"] = "0"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from postgrest.exceptions import APIError  # noqa: E402

import main  # noqa: E402

UNIQUE_KEYS = {
    "subjects": [("access_code",)],
    "subject_students": [("subject_id", "student_id")],
    "answers": [("attempt_id", "question_id")],
}


# Nilai bawaan kolom seperti di database.
DEFAULTS = {
    "subjects": {"deleted_at": None, "created_at": "2026-10-01T00:00:00+00:00"},
    "subject_students": {"joined_at": "2026-10-01T00:00:00+00:00"},
    "quiz_attempts": {
        "submitted_at": None,
        "correct_count": None,
        "started_at": "2026-10-01T00:00:00+00:00",
    },
    "quizzes": {"deleted_at": None},
}


class Result:
    def __init__(self, data):
        self.data = data


class Query:
    def __init__(self, db, table):
        self.db = db
        self.table = table
        self.filters = []
        self.action = "select"
        self.payload = None
        self.single = False
        self.order_key = None
        self.limit_count = None
        self.on_conflict = None
        self.ignore_duplicates = False
        self._negate = False

    # Pembangun query
    def select(self, *_columns):
        return self

    def _add(self, test):
        if self._negate:
            self.filters.append(lambda row: not test(row))
            self._negate = False
        else:
            self.filters.append(test)
        return self

    def eq(self, column, value):
        return self._add(lambda row: str(row.get(column)) == str(value))

    def is_(self, column, value):
        assert value == "null"
        return self._add(lambda row: row.get(column) is None)

    def in_(self, column, values):
        wanted = {str(value) for value in values}
        return self._add(lambda row: str(row.get(column)) in wanted)

    @property
    def not_(self):
        self._negate = True
        return self

    def order(self, column, desc=False):
        self.order_key = column
        return self

    def limit(self, count):
        self.limit_count = count
        return self

    def maybe_single(self):
        self.single = True
        return self

    def insert(self, payload):
        self.action, self.payload = "insert", payload
        return self

    def update(self, payload):
        self.action, self.payload = "update", payload
        return self

    def upsert(self, payload, on_conflict=None, ignore_duplicates=False):
        self.action, self.payload = "upsert", payload
        self.on_conflict = tuple(on_conflict.split(",")) if on_conflict else None
        self.ignore_duplicates = ignore_duplicates
        return self

    def delete(self):
        self.action = "delete"
        return self

    # Eksekusi
    def _rows(self):
        return self.db.setdefault(self.table, [])

    def _matching(self):
        return [row for row in self._rows() if all(test(row) for test in self.filters)]

    def _check_unique(self, row):
        for key in UNIQUE_KEYS.get(self.table, []):
            for other in self._rows():
                if all(other.get(column) == row.get(column) for column in key):
                    raise APIError({"message": "duplicate", "code": "23505"})

    def _insert_one(self, values):
        row = {"id": str(uuid4()), **DEFAULTS.get(self.table, {}), **values}
        self._check_unique(row)
        self._rows().append(row)
        return row

    def execute(self):
        if self.action == "select":
            rows = self._matching()
            if self.order_key:
                rows = sorted(rows, key=lambda row: str(row.get(self.order_key)))
            if self.limit_count is not None:
                rows = rows[: self.limit_count]
            rows = [dict(row) for row in rows]
            if self.single:
                return Result(rows[0]) if rows else None
            return Result(rows)
        if self.action == "insert":
            payload = self.payload if isinstance(self.payload, list) else [self.payload]
            return Result([dict(self._insert_one(values)) for values in payload])
        if self.action == "update":
            rows = self._matching()
            for row in rows:
                row.update(self.payload)
            return Result([dict(row) for row in rows])
        if self.action == "upsert":
            key = self.on_conflict
            existing = next(
                (
                    row
                    for row in self._rows()
                    if all(str(row.get(c)) == str(self.payload.get(c)) for c in key)
                ),
                None,
            )
            if existing is None:
                return Result([dict(self._insert_one(self.payload))])
            if self.ignore_duplicates:
                return Result([])
            existing.update(self.payload)
            return Result([dict(existing)])
        if self.action == "delete":
            rows = self._matching()
            self.db[self.table] = [row for row in self._rows() if row not in rows]
            return Result([dict(row) for row in rows])
        raise AssertionError(self.action)


class FakeSupabase:
    def __init__(self):
        self.db = {}

    def table(self, name):
        return Query(self.db, name)


class FakeUser:
    def __init__(self, user_id):
        self.id = user_id


@pytest.fixture
def fake_db(monkeypatch):
    fake = FakeSupabase()
    monkeypatch.setattr(main, "supabase_admin", fake)
    yield fake.db
    main.app.dependency_overrides.clear()


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    return TestClient(main.app)


@pytest.fixture
def login(fake_db):
    """login(role) membuat akun dan memakainya untuk request berikutnya."""

    def _login(role, name=None):
        user_id = str(uuid4())
        fake_db.setdefault("users", []).append(
            {"id": user_id, "name": name or role, "role": role}
        )
        main.app.dependency_overrides[main.get_current_user] = lambda: {
            "user": FakeUser(user_id),
            "access_token": "token",
        }
        return user_id

    return _login
