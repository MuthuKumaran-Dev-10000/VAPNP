import json
import base64

with open("firebase_credentials.json") as f:
    data = json.load(f)

key_str = data["private_key"]
# Strip header and footer
base64_data = key_str.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replace("\n", "").replace("\r", "")

try:
    decoded = base64.b64decode(base64_data)
    print("SUCCESS: Base64 decoded successfully. Length:", len(decoded))
except Exception as e:
    print("FAILED: Base64 decode failed:", e)
