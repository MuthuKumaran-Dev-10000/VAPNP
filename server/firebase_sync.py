import socket
import urllib.request
import json
from config import PORT

def get_local_ip():
    """Get the active local network IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

def get_ngrok_url():
    """Query the local ngrok API to find the active public HTTPS tunnel."""
    try:
        req = urllib.request.Request("http://localhost:4040/api/tunnels")
        with urllib.request.urlopen(req, timeout=2) as response:
            data = json.loads(response.read().decode())
            for tunnel in data.get("tunnels", []):
                if tunnel.get("proto") == "https":
                    return tunnel.get("public_url")
    except Exception:
        pass
    return None

def sync_server_url():
    """Sync URL anonymously to Firebase RTDB via REST API."""
    url = get_ngrok_url()
    
    if not url:
        local_ip = get_local_ip()
        url = f"http://{local_ip}:{PORT}"
        print(f"[Firebase Sync] No active ngrok tunnel found. Using local network URL: {url}")
    else:
        print(f"[Firebase Sync] Found active ngrok tunnel: {url}")

    # Synchronize using standard anonymous REST API PATCH request
    payload = {
        'ngrok_url': url,
        'local_ip_url': f"http://{get_local_ip()}:{PORT}"
    }

    # Write to lubrication-indicator RTDB
    try:
        rtdb_url = "https://lubrication-indicator-default-rtdb.firebaseio.com/server.json"
        req = urllib.request.Request(
            rtdb_url, 
            data=json.dumps(payload).encode("utf-8"), 
            method="PATCH"
        )
        req.add_header('Content-Type', 'application/json')
        with urllib.request.urlopen(req, timeout=4) as response:
            print("[Firebase Sync] Successfully synced dynamic URL to lubrication-indicator RTDB.")
            return url
    except Exception as e:
        print(f"[Firebase Sync] Error syncing to lubrication-indicator: {e}")
        
    return url

if __name__ == "__main__":
    sync_server_url()
