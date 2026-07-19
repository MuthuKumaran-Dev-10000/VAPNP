import os
import uuid
import datetime
import json
from fastapi import FastAPI, UploadFile, File, Form, Depends, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from config import HOST, PORT, STORAGE_DIR
from database import SessionLocal, init_db, Landmark, RouteWaypoint
from firebase_sync import sync_server_url
from vision_engine import get_vision_engine
from localization import localize_user, localize_route_user

app = FastAPI(title="Factory Digital Twin Camera Localization Server")

# Enable CORS for Mobile devices and web testers
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serves static files locally
app.mount("/static", StaticFiles(directory=STORAGE_DIR), name="static")

# Database dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Startup hooks
@app.on_event("startup")
def startup_event():
    init_db()
    sync_server_url()
    print(f"[Server] Visual Landmark Camera Server running on port {PORT}.")

@app.get("/status")
def status():
    return {"status": "online", "message": "Visual Landmark Overlay Server is fully functional"}

@app.post("/graph/landmarks")
async def add_landmark(
    name: str = Form(...),
    description: str = Form(""),
    touch_x: float = Form(...),
    touch_y: float = Form(...),
    form_schema: str = Form("[]"), # JSON array containing custom textboxes names
    image: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    contents = await image.read()
    
    # 1. Extract visual features using the pluggable engine
    vision = get_vision_engine()
    kp, desc, w, h = vision.extract_features(contents)
    
    if desc is None or len(desc) == 0:
        raise HTTPException(status_code=400, detail="Could not extract visual features from image")

    # Generate unique ID
    landmark_id = f"lm_{str(uuid.uuid4())[:8]}"

    # 2. Save image and descriptors locally
    local_url, desc_path = vision.save_assets(landmark_id, contents, desc)

    # 3. Save landmark coordinates and schema to SQLite database
    landmark = Landmark(
        id=landmark_id,
        name=name,
        description=description,
        image_url=local_url,
        descriptor_path=desc_path,
        touch_x=touch_x,
        touch_y=touch_y,
        form_schema=form_schema
    )
    
    db.add(landmark)
    db.commit()
    
    return {
        "status": "ok",
        "landmark_id": landmark_id,
        "image_url": local_url,
        "features_extracted": len(desc),
        "touch_x": touch_x,
        "touch_y": touch_y,
        "form_schema": form_schema
    }

@app.put("/graph/landmarks/{landmark_id}")
def update_landmark(
    landmark_id: str,
    name: str = Form(...),
    description: str = Form(""),
    form_schema: str = Form("[]"),
    db: Session = Depends(get_db)
):
    landmark = db.query(Landmark).filter(Landmark.id == landmark_id).first()
    if not landmark:
        raise HTTPException(status_code=404, detail="Landmark not found")
        
    landmark.name = name
    landmark.description = description
    landmark.form_schema = form_schema
    
    db.commit()
    return {"status": "ok", "landmark_id": landmark_id}

@app.post("/readings")
async def save_readings(payload: dict):
    landmark_id = payload.get("landmark_id")
    readings = payload.get("readings")
    if not landmark_id:
        raise HTTPException(status_code=400, detail="Missing landmark_id")
        
    # Format date filename: e.g. 18-07-2026_readings.json
    now = datetime.datetime.now()
    filename = now.strftime("%d-%m-%Y_readings.json")
    filepath = os.path.join(STORAGE_DIR, filename)
    
    # Read existing readings
    existing_data = []
    if os.path.exists(filepath):
        try:
            with open(filepath, "r") as f:
                existing_data = json.load(f)
        except Exception:
            existing_data = []
            
    # Append new entry
    new_entry = {
        "landmark_id": landmark_id,
        "timestamp": now.isoformat(),
        "readings": readings
    }
    existing_data.append(new_entry)
    
    # Save back to file
    with open(filepath, "w") as f:
        json.dump(existing_data, f, indent=4)
        
    return {"status": "ok", "file": filename, "entries": len(existing_data)}

@app.post("/localization")
async def localize(
    image: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    contents = await image.read()
    results = localize_user(db, image_bytes=contents)
    return {"markers": results}

@app.get("/landmarks")
def get_landmarks(db: Session = Depends(get_db)):
    landmarks = db.query(Landmark).all()
    return [{
        "id": l.id,
        "name": l.name,
        "description": l.description,
        "image_url": l.image_url,
        "touch_x": l.touch_x,
        "touch_y": l.touch_y,
        "form_schema": l.form_schema
    } for l in landmarks]

@app.post("/routes/waypoints")
async def add_route_waypoint(
    route_key: str = Form(...),
    step_index: int = Form(...),
    instruction: str = Form(...),
    image: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    contents = await image.read()
    vision = get_vision_engine()
    kp, desc, w, h = vision.extract_features(contents)
    
    if desc is None or len(desc) == 0:
        raise HTTPException(status_code=400, detail="Could not extract features from image")
        
    waypoint_id = f"wp_{str(uuid.uuid4())[:8]}"
    local_url, desc_path = vision.save_assets(waypoint_id, contents, desc)
    
    waypoint = RouteWaypoint(
        id=waypoint_id,
        route_key=route_key,
        step_index=step_index,
        instruction=instruction,
        image_url=local_url,
        descriptor_path=desc_path
    )
    db.add(waypoint)
    db.commit()
    
    return {
        "status": "ok",
        "waypoint_id": waypoint_id,
        "route_key": route_key,
        "step_index": step_index,
        "instruction": instruction
    }

@app.post("/routes/localize")
async def localize_route(
    route_key: str = Form(...),
    image: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    contents = await image.read()
    result = localize_route_user(db, route_key=route_key, image_bytes=contents)
    return {"match": result}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
