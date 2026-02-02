import uuid


def test_health(base_url, http_session):
    response = http_session.get(f"{base_url}/health", timeout=10)
    assert response.status_code == 200
    assert response.json() == {"status": "online"}


def test_login_page(base_url, http_session):
    response = http_session.get(f"{base_url}/login", timeout=10)
    assert response.status_code == 200
    assert "Firebase" in response.text or "login" in response.text.lower()


def test_debug_db(base_url, http_session):
    response = http_session.get(f"{base_url}/debug-db", timeout=10)
    assert response.status_code == 200
    payload = response.json()
    assert "project_id" in payload
    assert "emulator_host" in payload
    assert "keys_in_db" in payload


def test_items_smoke_with_api_key(base_url, http_session, api_key):
    item_name = f"smoke-{uuid.uuid4().hex[:8]}"
    item_id = None

    try:
        create_response = http_session.post(
            f"{base_url}/item",
            headers={"X-API-KEY": api_key},
            json={"item_name": item_name},
            timeout=10,
        )
        assert create_response.status_code == 200
        item_id = create_response.json().get("id")
        assert item_id

        list_response = http_session.get(
            f"{base_url}/items",
            headers={"X-API-KEY": api_key},
            timeout=10,
        )
        assert list_response.status_code == 200
        items = list_response.json()
        assert any(item.get("id") == item_id for item in items)

        update_response = http_session.put(
            f"{base_url}/item/{item_id}",
            headers={"X-API-KEY": api_key},
            json={"tag": "smoke-updated"},
            timeout=10,
        )
        assert update_response.status_code == 200
    finally:
        if item_id:
            http_session.delete(
                f"{base_url}/item/{item_id}",
                headers={"X-API-KEY": api_key},
                timeout=10,
            )


def test_token_based_session_flow(base_url, http_session, auth_id_token):
    session_response = http_session.post(
        f"{base_url}/auth/session",
        json={"token": auth_id_token},
        timeout=10,
    )
    assert session_response.status_code == 200
    assert session_response.json() == {"status": "success"}
    assert "session=" in session_response.headers.get("set-cookie", "")

    dashboard_response = http_session.get(
        f"{base_url}/dashboard",
        timeout=10,
    )
    assert dashboard_response.status_code == 200
    assert "test@example.com" in dashboard_response.text

    item_name = f"smoke-session-{uuid.uuid4().hex[:8]}"
    item_id = None
    try:
        create_response = http_session.post(
            f"{base_url}/item",
            headers={"Authorization": f"Bearer {auth_id_token}"},
            json={"item_name": item_name},
            timeout=10,
        )
        assert create_response.status_code == 200
        item_id = create_response.json().get("id")
        assert item_id

        update_response = http_session.put(
            f"{base_url}/item/{item_id}",
            headers={"Authorization": f"Bearer {auth_id_token}"},
            json={"tag": "session-smoke"},
            timeout=10,
        )
        assert update_response.status_code == 200
    finally:
        if item_id:
            http_session.delete(
                f"{base_url}/item/{item_id}",
                headers={"Authorization": f"Bearer {auth_id_token}"},
                timeout=10,
            )
