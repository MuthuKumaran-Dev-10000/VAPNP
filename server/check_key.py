import json
from cryptography.hazmat.primitives import serialization

with open("firebase_credentials.json") as f:
    data = json.load(f)

key_str = data["private_key"]
print("Key length:", len(key_str))
try:
    # Try to load private key bytes
    key_bytes = key_str.encode("utf-8")
    serialization.load_pem_private_key(key_bytes, password=None)
    print("SUCCESS load using cryptography")
except Exception as e:
    print("FAILED load using cryptography:", e)
    # Print the characters around index 1600-1650
    print("Context around 1621:")
    print(repr(key_str[1600:1650]))
