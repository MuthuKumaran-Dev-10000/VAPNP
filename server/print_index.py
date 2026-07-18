import json
with open("firebase_credentials.json") as f:
    data = json.load(f)
key = data["private_key"]
print("Character at 1620:", repr(key[1620]))
print("Character at 1621:", repr(key[1621]))
print("Character at 1622:", repr(key[1622]))
print("ASCII at 1621:", ord(key[1621]))
print("Context:")
for i in range(1615, 1630):
    print(f"{i}: {repr(key[i])} (ASCII {ord(key[i])})")
