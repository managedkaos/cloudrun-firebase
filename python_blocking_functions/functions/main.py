import os

from firebase_functions import https_fn, identity_fn
from firebase_functions.options import set_global_options
from firebase_admin import initialize_app

# For cost control, you can set the maximum number of containers that can be
# running at the same time. This helps mitigate the impact of unexpected
# traffic spikes by instead downgrading performance. This limit is a per-function
# limit. You can override the limit for each function using the max_instances
# parameter in the decorator, e.g. @https_fn.on_request(max_instances=5).
set_global_options(max_instances=10)

initialize_app()


def _validate_email(event: identity_fn.AuthBlockingEvent) -> None:
    email = None
    if event.data is not None:
        email = event.data.get("email")
    if email:
        email = email.lower()

    raw_allowed_emails = os.getenv("AUTH_ALLOWED_EMAILS")

    if not email:
        raise https_fn.HttpsError("invalid-argument", "Email is required.")

    if not raw_allowed_emails:
        raise https_fn.HttpsError("internal", "Configuration error.")

    allowed_emails = [entry.strip().lower() for entry in raw_allowed_emails.split(",")]

    if email not in allowed_emails:
        print(f"{email} is unauthorized. Access is denied.")
        raise https_fn.HttpsError(
            "permission-denied",
            "The email address is not authorized.",
        )


@identity_fn.before_user_created(secrets=["auth-allowed-emails"])
def before_create(event: identity_fn.AuthBlockingEvent) -> identity_fn.BeforeCreateResponse:
    _validate_email(event)
    return identity_fn.BeforeCreateResponse()


@identity_fn.before_user_signed_in(secrets=["auth-allowed-emails"])
def before_sign_in(event: identity_fn.AuthBlockingEvent) -> identity_fn.BeforeSignInResponse:
    _validate_email(event)
    return identity_fn.BeforeSignInResponse()
