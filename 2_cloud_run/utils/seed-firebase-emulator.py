#!/usr/bin/env python3
import os
import firebase_admin
from firebase_admin import auth, firestore

# Set GCP_PROJECT
os.environ.setdefault("GCP_PROJECT", "default-project")

# Point to the local emulators
os.environ.setdefault("FIRESTORE_EMULATOR_HOST", "localhost:8081")
os.environ.setdefault("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099")

firebase_admin.initialize_app()
db = firestore.client()


def seed_data():
    print("Initializing Local Emulator Data...")

    # 1. Create a User in Auth
    try:
        user = auth.get_user_by_email("test@example.com")
        print(f"User already exists: {user.uid}")
    except:
        user = auth.create_user(
            email="test@example.com",
            password="default-password",
            uid="default-user"  # Hardcoding for testing consistency
        )
        print(f"Created user: {user.uid}")

    # 2. Create the API Key mapping in Firestore
    # We use the key as the Document ID as discussed
    api_key = "default-apikey"
    db.collection("api_keys").document(api_key).set({
        "uid": user.uid,
        "name": "Default Dev Key",
        "created_at": firestore.SERVER_TIMESTAMP
    })

    print(f"Mapped API Key '{api_key}' to UID '{user.uid}'")
    print("Done!")


if __name__ == "__main__":
    seed_data()
