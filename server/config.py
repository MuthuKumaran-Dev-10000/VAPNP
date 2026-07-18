import os

# Host configuration
PORT = 9000
HOST = "0.0.0.0"

# Directories
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STORAGE_DIR = os.path.join(BASE_DIR, "storage")
IMAGES_DIR = os.path.join(STORAGE_DIR, "images")
DESCRIPTORS_DIR = os.path.join(STORAGE_DIR, "descriptors")

# Ensure folders exist
for folder in [STORAGE_DIR, IMAGES_DIR, DESCRIPTORS_DIR]:
    os.makedirs(folder, exist_ok=True)

# Database path
DATABASE_PATH = os.path.join(STORAGE_DIR, "database.db")
DATABASE_URL = f"sqlite:///{DATABASE_PATH}"

# Firebase Settings
FIREBASE_CREDENTIALS_PATH = os.path.join(BASE_DIR, "firebase_credentials.json")
FIREBASE_DATABASE_URL = "https://lubrication-indicator-default-rtdb.firebaseio.com/"
