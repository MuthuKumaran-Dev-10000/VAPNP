import os
import cv2
import numpy as np
from sqlalchemy.orm import Session
from database import Landmark, RouteWaypoint
from vision_engine import get_vision_engine

def localize_user(db_session: Session, image_bytes: bytes):
    """
    Match query image against all registered landmarks.
    Project original (touch_x, touch_y) onto current query frame coordinates.
    Returns list of visible markers in the viewfinder along with tracking points (inliers).
    """
    engine = get_vision_engine()
    
    # 1. Extract query features
    query_kp, query_desc, query_w, query_h = engine.extract_features(image_bytes)
    if query_desc is None or len(query_desc) == 0:
        return []

    landmarks = db_session.query(Landmark).all()
    results = []

    for lm in landmarks:
        # Load stored descriptor from npy
        if not os.path.exists(lm.descriptor_path):
            continue
        try:
            train_desc = np.load(lm.descriptor_path)
        except Exception:
            continue

        # Match features
        matches = engine.match_features(query_desc, train_desc)
        if len(matches) < 4:
            continue

        # Re-extract keypoints of original image to compute projected coordinates
        image_filename = os.path.basename(lm.image_url)
        storage_dir = os.path.dirname(os.path.dirname(lm.descriptor_path))
        image_absolute_path = os.path.join(storage_dir, "images", image_filename)
        
        train_kp = []
        train_w, train_h = 0, 0
        if os.path.exists(image_absolute_path):
            try:
                with open(image_absolute_path, "rb") as f:
                    train_kp, _, train_w, train_h = engine.extract_features(f.read())
            except Exception:
                pass
        
        if not train_kp:
            continue

        # Verify geometry and project original coordinate (touch_x, touch_y) -> (curr_x, curr_y)
        is_matched, confidence, proj_x, proj_y, inlier_pts = engine.verify_geometry_and_project(
            query_kp=query_kp,
            train_kp=train_kp,
            matches=matches,
            landmark_x=lm.touch_x,
            landmark_y=lm.touch_y,
            train_w=train_w,
            train_h=train_h,
            query_w=query_w,
            query_h=query_h
        )

        # Check if projected coordinate falls within image bounds
        if is_matched and 0.0 <= proj_x <= 1.0 and 0.0 <= proj_y <= 1.0:
            results.append({
                "id": lm.id,
                "name": lm.name,
                "description": lm.description,
                "x": round(proj_x, 4),
                "y": round(proj_y, 4),
                "confidence": round(confidence * 100, 1),
                "image_url": lm.image_url,
                "form_schema": lm.form_schema,
                "tracking_points": inlier_pts
            })

    # Sort matches by confidence descending
    results = sorted(results, key=lambda x: x["confidence"], reverse=True)
    return results

def localize_route_user(db_session: Session, route_key: str, image_bytes: bytes):
    """
    Match query image against all waypoints under route_key.
    Returns the step info with the highest visual match confidence.
    """
    engine = get_vision_engine()
    
    # 1. Extract query features
    query_kp, query_desc, query_w, query_h = engine.extract_features(image_bytes)
    if query_desc is None or len(query_desc) == 0:
        return None

    waypoints = db_session.query(RouteWaypoint).filter(RouteWaypoint.route_key == route_key).all()
    if not waypoints:
        return None

    best_match = None
    max_inliers = 0
    best_inlier_pts = []

    for wp in waypoints:
        if not os.path.exists(wp.descriptor_path):
            continue
        try:
            train_desc = np.load(wp.descriptor_path)
        except Exception:
            continue

        matches = engine.match_features(query_desc, train_desc)
        if len(matches) < 4:
            continue

        image_filename = os.path.basename(wp.image_url)
        storage_dir = os.path.dirname(os.path.dirname(wp.descriptor_path))
        image_absolute_path = os.path.join(storage_dir, "images", image_filename)
        
        train_kp = []
        train_w, train_h = 0, 0
        if os.path.exists(image_absolute_path):
            try:
                with open(image_absolute_path, "rb") as f:
                    train_kp, _, train_w, train_h = engine.extract_features(f.read())
            except Exception:
                pass
        
        if not train_kp:
            continue

        is_matched, confidence, _, _, inlier_pts = engine.verify_geometry_and_project(
            query_kp=query_kp,
            train_kp=train_kp,
            matches=matches,
            landmark_x=0.5,
            landmark_y=0.5,
            train_w=train_w,
            train_h=train_h,
            query_w=query_w,
            query_h=query_h
        )

        if is_matched:
            inliers_count = len(inlier_pts)
            if inliers_count > max_inliers and inliers_count >= 10:
                max_inliers = inliers_count
                best_inlier_pts = inlier_pts
                best_match = wp

    if best_match:
        return {
            "id": best_match.id,
            "route_key": best_match.route_key,
            "step_index": best_match.step_index,
            "instruction": best_match.instruction,
            "tracking_points": best_inlier_pts
        }
    return None
