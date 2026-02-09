import logging
import os

from firebase_functions import https_fn, identity_fn
from firebase_functions.options import set_global_options
from firebase_functions.params import SecretParam
from firebase_admin import initialize_app


# For cost control, you can set the maximum number of containers that can be
# running at the same time. This helps mitigate the impact of unexpected
# traffic spikes by instead downgrading performance. This limit is a per-function
# limit. You can override the limit for each function using the max_instances
# parameter in the decorator, e.g. @https_fn.on_request(max_instances=5).
set_global_options(max_instances=10)

AUTH_ALLOWED_EMAILS = SecretParam("AUTH_ALLOWED_EMAILS")

initialize_app()



def _validate_email(event: identity_fn.AuthBlockingEvent) -> None:
    data = event.data
    raw_email = getattr(data, "email", None)
    email = raw_email.lower() if isinstance(raw_email, str) else None
    log_details = {
        "uid": getattr(data, "uid", None),
        "email": raw_email,
        "normalized_email": email,
        "email_verified": getattr(data, "email_verified", None),
        "display_name": getattr(data, "display_name", None),
        "phone_number": getattr(data, "phone_number", None),
        "provider_id": getattr(data, "provider_id", None),
        "photo_url": getattr(data, "photo_url", None),
        "tenant_id": getattr(data, "tenant_id", None),
        "custom_claims": getattr(data, "custom_claims", None),
        "event_type": getattr(event, "event_type", None),
        "event_id": getattr(event, "event_id", None),
        "timestamp": getattr(event, "timestamp", None),
        "app_id": getattr(getattr(event, "app_info", None), "app_id", None),
        "resource": getattr(getattr(event, "resource", None), "name", None),
    }
    logging.info("Auth blocking function invoked. details=%s", log_details)

    if not email:
        logging.warning("Blocking auth: missing email. details=%s", log_details)
        raise https_fn.HttpsError("invalid-argument", "Email address is required.")

    raw_allowed_emails = AUTH_ALLOWED_EMAILS.value
    if not raw_allowed_emails or not raw_allowed_emails.strip():
        logging.error(
            "Blocking auth: allowed emails secret missing or empty. details=%s",
            log_details,
        )
        raise https_fn.HttpsError(
            "internal",
            "Configuration error: auth-allowed-emails is missing or empty.",
        )

    allowed_emails = [
        value.strip().lower()
        for value in raw_allowed_emails.split(",")
        if value.strip()
    ]
    if not allowed_emails:
        logging.error(
            "Blocking auth: allowed emails list empty after parsing. details=%s",
            log_details,
        )
        raise https_fn.HttpsError(
            "internal",
            "Configuration error: auth-allowed-emails is missing or empty.",
        )

    if email not in allowed_emails:
        logging.warning("Blocking auth: email not allowed. details=%s", log_details)
        raise https_fn.HttpsError("permission-denied", "Email not allowed.")

    logging.info(
        "Auth blocking function allowlist check passed. allowed_count=%s",
        len(allowed_emails),
    )


@identity_fn.before_user_created(secrets=["AUTH_ALLOWED_EMAILS"])
def before_create(event: identity_fn.AuthBlockingEvent) -> identity_fn.BeforeCreateResponse:
    logging.info("before_user_created start")
    _validate_email(event)
    logging.info("before_user_created allow")
    return identity_fn.BeforeCreateResponse()


@identity_fn.before_user_signed_in(secrets=["AUTH_ALLOWED_EMAILS"])
def before_sign_in(event: identity_fn.AuthBlockingEvent) -> identity_fn.BeforeSignInResponse:
    logging.info("before_user_signed_in start")
    _validate_email(event)
    logging.info("before_user_signed_in allow")
    return identity_fn.BeforeSignInResponse()
