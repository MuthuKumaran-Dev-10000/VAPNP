import os
import uuid
from fastapi import FastAPI, UploadFile, File, Form, Depends, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from config import HOST, PORT, STORAGE_DIR
from database import SessionLocal, init_db, Landmark
from firebase_sync import sync_server_url
from vision_engine import get_vision_engine
from localization import localize_user

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

    # 3. Save landmark coordinates to SQLite database
    landmark = Landmark(
        id=landmark_id,
        name=name,
        description=description,
        image_url=local_url,
        descriptor_path=desc_path,
        touch_x=touch_x,
        touch_y=touch_y
    )
    
    db.add(landmark)
    db.commit()
    
    return {
        "status": "ok",
        "landmark_id": landmark_id,
        "image_url": local_url,
        "features_extracted": len(desc),
        "touch_x": touch_x,
        "touch_y": touch_y
    }

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
        "touch_y": l.touch_y
    } for l in landmarks]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
