from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

import main
from test_endpoints import setup_subject

ORIGIN = "http://localhost:5555"


def test_error_tak_tertangkap_dijawab_500_dengan_header_cors(
    client, login, fake_db, monkeypatch
):
    setup_subject(client, login, fake_db)

    def missing_column(_material_id):
        # Seperti database yang belum menjalankan migrasi 005.
        raise APIError(
            {"message": "column material_images.image_key does not exist", "code": "42703"}
        )

    monkeypatch.setattr(main, "material_image_rows", missing_column)
    raw = TestClient(main.app, raise_server_exceptions=False)
    response = raw.get("/materials/m1/sections", headers={"Origin": ORIGIN})
    assert response.status_code == 500
    assert response.json() == {"detail": main.SERVER_ERROR_DETAIL}
    assert response.headers["access-control-allow-origin"] == ORIGIN
    # Detail database tidak bocor ke aplikasi.
    assert "image_key" not in response.text


def test_error_biasa_tetap_membawa_header_cors(client, login, fake_db):
    login("teacher")
    response = client.get("/materials/tidak-ada/sections", headers={"Origin": ORIGIN})
    assert response.status_code == 404
    assert response.headers["access-control-allow-origin"] == ORIGIN


def test_error_tak_tertangkap_dicatat_satu_baris_yang_mudah_dicari(
    client, login, fake_db, monkeypatch, caplog
):
    setup_subject(client, login, fake_db)

    def disconnected(_material_id):
        raise ConnectionError("Server disconnected\nwithout sending a response.")

    monkeypatch.setattr(main, "material_image_rows", disconnected)
    raw = TestClient(main.app, raise_server_exceptions=False)
    with caplog.at_level("ERROR", logger="main"):
        raw.get("/materials/m1/sections")
    lines = [r.getMessage() for r in caplog.records if "SERVER_ERROR" in r.getMessage()]
    assert lines == [
        "SERVER_ERROR endpoint=GET /materials/{material_id}/sections "
        "path=/materials/m1/sections "
        "error=builtins.ConnectionError "
        "pesan=Server disconnected without sending a response."
    ]
    # Traceback tetap ikut tercatat untuk ditelusuri.
    assert caplog.records[-1].exc_info is not None


def test_klien_supabase_terpisah_untuk_setiap_thread(monkeypatch):
    import threading

    created = []
    monkeypatch.setattr(
        main, "create_client", lambda url, key: created.append(key) or object()
    )
    proxy = main.ThreadLocalSupabase("kunci")
    same_thread = [proxy._client(), proxy._client()]
    other = []
    thread = threading.Thread(target=lambda: other.append(proxy._client()))
    thread.start()
    thread.join()
    assert same_thread[0] is same_thread[1]
    assert other[0] is not same_thread[0]
    assert created == ["kunci", "kunci"]
