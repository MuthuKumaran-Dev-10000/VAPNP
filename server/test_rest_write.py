import urllib.request
import json

# Try to write anonymously to lubrication-indicator
try:
    url = "https://lubrication-indicator-default-rtdb.firebaseio.com/server.json"
    data = {"test_rest": "ok"}
    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), method="PATCH")
    with urllib.request.urlopen(req, timeout=3) as response:
        print("SUCCESS: Anonymous write to lubrication-indicator RTDB succeeded.")
except Exception as e:
    print(f"FAILED: Anonymous write to lubrication-indicator failed: {e}")

# Try to write anonymously to euphoric-coast-384514
try:
    url = "https://euphoric-coast-384514-default-rtdb.firebaseio.com/server.json"
    data = {"test_rest": "ok"}
    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), method="PATCH")
    with urllib.request.urlopen(req, timeout=3) as response:
        print("SUCCESS: Anonymous write to euphoric-coast-384514 RTDB succeeded.")
except Exception as e:
    print(f"FAILED: Anonymous write to euphoric-coast-384514 failed: {e}")
