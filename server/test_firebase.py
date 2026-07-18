import json
import firebase_admin
from firebase_admin import credentials, db

try:
    with open("firebase_credentials.json", "r") as f:
        cred_dict = json.load(f)
    if "private_key" in cred_dict:
        cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n")
        
    cred = credentials.Certificate(cred_dict)
    firebase_admin.initialize_app(cred, {
        'databaseURL': "https://lubrication-indicator-default-rtdb.firebaseio.com/"
    })
    ref = db.reference('server')
    ref.update({'test_connection': 'ok'})
    print("SUCCESS: Successfully wrote test data to Firebase Realtime Database.")
except Exception as e:
    print(f"FAILED: Firebase error: {e}")
