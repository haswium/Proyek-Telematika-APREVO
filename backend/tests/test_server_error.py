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
