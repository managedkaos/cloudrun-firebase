import os

import pytest
import requests


@pytest.fixture(scope="session")
def base_url():
    return os.getenv("API_BASE_URL", "http://localhost:8080").rstrip("/")


@pytest.fixture(scope="session")
def http_session():
    session = requests.Session()
    session.headers.update({"User-Agent": "cloudrun-firebase-smoke-tests"})
    yield session
    session.close()


@pytest.fixture(scope="session")
def api_key():
    return os.getenv("API_KEY", "default-apikey")


@pytest.fixture(scope="session")
def auth_email():
    return os.getenv("AUTH_EMAIL", "test@example.com")


@pytest.fixture(scope="session")
def auth_password():
    return os.getenv("AUTH_PASSWORD", "default-password")


@pytest.fixture(scope="session")
def auth_emulator_host():
    return os.getenv("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099")


@pytest.fixture(scope="session")
def firebase_web_api_key():
    return os.getenv("FIREBASE_WEB_API_KEY", "fake-api-key")


@pytest.fixture(scope="session")
def auth_id_token(http_session, auth_email, auth_password, auth_emulator_host, firebase_web_api_key):
    url = (
        f"http://{auth_emulator_host}/identitytoolkit.googleapis.com/v1/"
        f"accounts:signInWithPassword?key={firebase_web_api_key}"
    )
    payload = {
        "email": auth_email,
        "password": auth_password,
        "returnSecureToken": True,
    }
    response = http_session.post(url, json=payload, timeout=10)
    response.raise_for_status()
    data = response.json()
    return data["idToken"]


def require_env(value, name):
    if not value:
        pytest.skip(f"Missing {name}; set it to run this test.")
