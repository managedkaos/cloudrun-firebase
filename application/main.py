import logging
import os
import json

os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8081"
os.environ["FIREBASE_AUTH_EMULATOR_HOST"] = "localhost:9099"

from pydantic import BaseModel

from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi import Depends, FastAPI, Request, HTTPException, Security, Cookie, status, Response
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer

# from firebase_admin import auth, credentials, firestore, initialize_app
from firebase_admin import auth, firestore, initialize_app
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles

# 0. Initialize Logger
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


# 1. Initialize Firebase Admin
# If FIREBASE_AUTH_EMULATOR_HOST is in env, it connects to local emulator automatically
if not len(initialize_app().name):
    initialize_app()
    logger.info("Initialized application.")
else:
    logger.info("Application already initialized.")

db = firestore.client()

app = FastAPI(title="Multi-Tenant CRUD API")


# Mount Static and Templates
app.mount("/static", StaticFiles(directory="static"), name="static")

templates = Jinja2Templates(directory="templates")

firebase_config_raw = os.getenv("FIREBASE_CONFIG_JSON")

if firebase_config_raw:
    firebase_config = json.loads(firebase_config_raw)
else:
    # Fallback for local development
    firebase_config = {}

class SessionRequest(BaseModel):
    token: str

# 2. Security Schemes
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)
bearer_scheme = HTTPBearer(auto_error=False)

# 3. Identity Resolver Dependency
async def get_tenant_id(
    api_key: str = Security(api_key_header),
    token: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    session: str = Cookie(None) # Look for a cookie named 'session'
) -> str:
    # Path A: Check API Key (Automation)
    if api_key:
        key_doc = db.collection("api_keys").document(api_key).get()
        if key_doc.exists:
            return key_doc.to_dict().get("uid")

    # Path B: Check Bearer Token (Frontend User)
    if token:
        try:
            decoded_token = auth.verify_id_token(token.credentials)
            return decoded_token["uid"]
        except: pass

    # Path C: Check Cookie (HTML Frontend)
    if session:
        # In production, verify the Firebase session cookie here
        return session

    raise HTTPException(status_code=401, detail="Not authenticated")


# 4. CRUD Routes
# TODO: Need firestore to automatically create an ID for each item
@app.put("/items/{item_name}")
async def update_or_create_item(item_name: str, payload: dict, uid: str = Depends(get_tenant_id)):
    """
    Uses item_name as the Document ID to prevent duplicates.
    """
    # Sanitize the item_name to ensure it's a valid Firestore ID (no slashes)
    doc_id = item_name.replace("/", "-")

    doc_ref = db.collection("user_data").document(uid).collection("items").document(doc_id)

    # .set with merge=True behaves like a traditional PUT/UPSERT
    doc_ref.set({
        **payload,
        "item_name": item_name,
        "owner_id": uid,
        "updated_at": firestore.SERVER_TIMESTAMP
    }, merge=True)

    return {"id": doc_id, "message": "Item updated/created"}

@app.get("/items")
async def list_items(uid: str = Depends(get_tenant_id)):
    """Lists items only belonging to the authenticated user/API key owner."""
    logger.info("list_items:start uid=%s", uid)
    items_ref = db.collection("user_data").document(uid).collection("items")
    try:
        docs = list(items_ref.stream())
        logger.info("list_items:stream_complete uid=%s count=%s", uid, len(docs))
        items = [doc.to_dict() for doc in docs]
        logger.debug("list_items:success uid=%s", uid)
        return items
    except Exception:
        logger.exception("list_items:failed uid=%s", uid)
        raise


@app.get("/health", status_code=status.HTTP_200_OK)
async def health():
    return {"status": "online"}

@app.get("/debug-db")
async def debug_db():
    # Attempt to list all keys in the collection
    docs = db.collection("api_keys").stream()
    keys_found = [doc.id for doc in docs]
    return {
        "project_id": os.getenv("GOOGLE_CLOUD_PROJECT"),
        "emulator_host": os.getenv("FIRESTORE_EMULATOR_HOST"),
        "keys_in_db": keys_found
    }

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, uid: str = Depends(get_tenant_id)):
    if not uid:
        return RedirectResponse(url="/login")

    # Fetch data using the uid (resolved from Cookie, Header, or Token)
    items_ref = db.collection("user_data").document(uid).collection("items")
    items = [doc.to_dict() | {"id": doc.id} for doc in items_ref.stream()]

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "items": items,
        "user": {"email": "test@example.com"} # TODO: pull real email from Auth
    })

@app.get("/")
async def root():
    return RedirectResponse(url="/dashboard")

@app.get("/login")
async def login(request: Request):
    return templates.TemplateResponse("login.html", {"request": request,"firebase_config": firebase_config})

@app.get("/debug-login")
async def debug_login(uid: str = "default-user"):
    """
    Simulates a login by setting the 'session' cookie.
    Access via: http://localhost:8080/debug-login?uid=your_test_uid
    """
    response = RedirectResponse(url="/dashboard")
    # In production, use httponly=True and secure=True
    response.set_cookie(key="session", value=uid)
    return response

@app.get("/logout")
async def logout():
    """
    Clears the cookie and redirects home.
    """
    response = RedirectResponse(url="http://localhost:5002") # TODO: update for deployment
    response.delete_cookie("session")
    return response

@app.post("/auth/session")
async def create_session(request: Request, session_data: SessionRequest):
    # In a real production app, you would create a session cookie using firebase_admin.auth.create_session_cookie
    # For this demo, we are setting the ID token as a cookie directly as requested.
    response = JSONResponse(content={"status": "success"})
    # limit max_age to 1 hour or less for ID tokens
    response.set_cookie(key="session", value=session_data.token, httponly=True, secure=True)
    return response
