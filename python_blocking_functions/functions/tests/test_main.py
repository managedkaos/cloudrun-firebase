import importlib
import os
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch


def _load_main():
    functions_dir = Path(__file__).resolve().parents[1]
    if str(functions_dir) not in sys.path:
        sys.path.insert(0, str(functions_dir))

    sys.modules.pop("main", None)
    with patch("firebase_admin.initialize_app"):
        return importlib.import_module("main")


class TestValidateEmail(TestCase):
    def test_requires_email(self):
        main = _load_main()
        event = SimpleNamespace(data=None)

        with patch.dict(os.environ, {"AUTH_ALLOWED_EMAILS": "user@example.com"}):
            with self.assertRaises(main.https_fn.HttpsError):
                main._validate_email(event)

    def test_requires_allowed_emails_config(self):
        main = _load_main()
        event = SimpleNamespace(data={"email": "user@example.com"})

        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(main.https_fn.HttpsError):
                main._validate_email(event)

    def test_blocks_unauthorized_email(self):
        main = _load_main()
        event = SimpleNamespace(data={"email": "blocked@example.com"})

        with patch.dict(os.environ, {"AUTH_ALLOWED_EMAILS": "allowed@example.com"}):
            with self.assertRaises(main.https_fn.HttpsError):
                main._validate_email(event)

    def test_allows_case_insensitive_match(self):
        main = _load_main()
        event = SimpleNamespace(data={"email": "ALLOWED@EXAMPLE.COM"})

        with patch.dict(
            os.environ,
            {"AUTH_ALLOWED_EMAILS": "allowed@example.com, other@example.com"},
        ):
            main._validate_email(event)


class TestBlockingHandlers(TestCase):
    def _call_handler(self, handler, event):
        raw_handler = getattr(handler, "__wrapped__", handler)
        return raw_handler(event)

    def test_before_create_calls_validate(self):
        main = _load_main()
        event = SimpleNamespace(data={"email": "user@example.com"})

        with patch.object(main, "_validate_email") as validate_mock:
            result = self._call_handler(main.before_create, event)

        validate_mock.assert_called_once_with(event)
        self.assertIsInstance(result, dict)
        self.assertEqual(result, {})

    def test_before_sign_in_calls_validate(self):
        main = _load_main()
        event = SimpleNamespace(data={"email": "user@example.com"})

        with patch.object(main, "_validate_email") as validate_mock:
            result = self._call_handler(main.before_sign_in, event)

        validate_mock.assert_called_once_with(event)
        self.assertIsInstance(result, dict)
        self.assertEqual(result, {})
