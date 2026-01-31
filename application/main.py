from fastapi import Depends, FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer

# from firebase_admin import auth, credentials, firestore, initialize_app
from firebase_admin import auth, firestore, initialize_app

# 1. Initialize Firebase Admin
# If FIREBASE_AUTH_EMULATOR_HOST is in env, it connects to local emulator automatically
if not len(initialize_app().name):
    initialize_app()

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
@app.post("/items")
async def create_item(payload: dict, uid: str = Depends(get_tenant_id)):
    """Creates an item inside the user's specific subcollection."""
    doc_ref = db.collection("users").document(uid).collection("items").document()
    doc_ref.set({**payload, "owner_id": uid})
    return {"id": doc_ref.id, "message": "Item created"}


@app.get("/items")
async def list_items(uid: str = Depends(get_tenant_id)):
    """Lists items only belonging to the authenticated user/API key owner."""
    items_ref = db.collection("users").document(uid).collection("items")
    docs = items_ref.stream()
    return [doc.to_dict() for doc in docs]


@app.get("/health", status_code=status.HTTP_200_OK)
async def health():
    return {"status": "online"}
