import logging
import os

os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8081"
os.environ["FIREBASE_AUTH_EMULATOR_HOST"] = "localhost:9099"



from fastapi import Depends, FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer

# from firebase_admin import auth, credentials, firestore, initialize_app
from firebase_admin import auth, firestore, initialize_app

# 0. Initialize Logger
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


# Force check for the environment variable
endpoint = os.getenv("FIRESTORE_EMULATOR_HOST")
print(f"DEBUG: Connecting to Firestore Emulator at {endpoint}")



# 1. Initialize Firebase Admin
# If FIREBASE_AUTH_EMULATOR_HOST is in env, it connects to local emulator automatically
if not len(initialize_app().name):
    initialize_app()
    logger.info("Initialized application.")
else:
    logger.info("Application already initialized.")

db = firestore.client()

app = FastAPI(title="Multi-Tenant CRUD API")

# 2. Security Schemes
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)
bearer_scheme = HTTPBearer(auto_error=False)


# 3. Identity Resolver Dependency
async def get_tenant_id(
    api_key: str = Security(api_key_header),
    token: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    # Path A: API Key (Automation)
    if api_key:
        key_doc = db.collection("api_keys").document(api_key).get()
        if key_doc.exists:
            return key_doc.to_dict().get("uid")
        raise HTTPException(status_code=403, detail="Invalid API Key")

    # Path B: Firebase Token (Frontend User)
    if token:
        try:
            decoded_token = auth.verify_id_token(token.credentials)
            return decoded_token["uid"]
        except Exception:
            raise HTTPException(status_code=401, detail="Invalid/Expired Token")

    raise HTTPException(status_code=401, detail="Authentication required")


# 4. CRUD Routes
@app.put("/items/{item_name}")
async def update_or_create_item(item_name: str, payload: dict, uid: str = Depends(get_tenant_id)):
    """
    Uses item_name as the Document ID to prevent duplicates.
    """
    # Sanitize the item_name to ensure it's a valid Firestore ID (no slashes)
    doc_id = item_name.replace("/", "-")

    doc_ref = db.collection("users").document(uid).collection("items").document(doc_id)

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
    items_ref = db.collection("users").document(uid).collection("items")
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
