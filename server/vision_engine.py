import os
import cv2
import numpy as np
from abc import ABC, abstractmethod
from config import IMAGES_DIR, DESCRIPTORS_DIR

class AbstractVisionEngine(ABC):
    @abstractmethod
    def extract_features(self, image_bytes: bytes):
        """Extract keypoints and descriptors from image bytes."""
        pass

    @abstractmethod
    def match_features(self, query_desc, train_desc):
        """Match query descriptors against train descriptors."""
        pass

    @abstractmethod
    def verify_geometry_and_project(self, query_kp, train_kp, matches, landmark_x: float, landmark_y: float, train_w: int, train_h: int, query_w: int, query_h: int):
        """Verify matches with RANSAC and project original coordinate to query coordinate. Returns (is_matched, confidence, px, py, inliers)."""
        pass

    def save_assets(self, landmark_id: str, image_bytes: bytes, descriptors):
        """Save image file and descriptors binary file locally."""
        image_path = os.path.join(IMAGES_DIR, f"{landmark_id}.jpg")
        with open(image_path, "wb") as f:
            f.write(image_bytes)

        desc_path = os.path.join(DESCRIPTORS_DIR, f"{landmark_id}.npy")
        np.save(desc_path, descriptors)
        
        return f"/static/images/{landmark_id}.jpg", desc_path

class SIFTExpVisionEngine(AbstractVisionEngine):
    def __init__(self):
        self.detector = cv2.SIFT_create()
        FLANN_INDEX_KDTREE = 1
        index_params = dict(algorithm=FLANN_INDEX_KDTREE, trees=5)
        search_params = dict(checks=50)
        self.matcher = cv2.FlannBasedMatcher(index_params, search_params)

    def extract_features(self, image_bytes: bytes):
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
        if img is None:
            return [], None, 0, 0
        h, w = img.shape
        kp, desc = self.detector.detectAndCompute(img, None)
        return kp, desc, w, h

    def match_features(self, query_desc, train_desc):
        if query_desc is None or train_desc is None:
            return []
        if len(query_desc) < 2 or len(train_desc) < 2:
            return []
        try:
            matches = self.matcher.knnMatch(query_desc, train_desc, k=2)
            good_matches = []
            for m, n in matches:
                if m.distance < 0.75 * n.distance:
                    good_matches.append(m)
            return good_matches
        except Exception:
            return []

    def verify_geometry_and_project(self, query_kp, train_kp, matches, landmark_x: float, landmark_y: float, train_w: int, train_h: int, query_w: int, query_h: int):
        if len(matches) < 4:
            return False, 0.0, 0.0, 0.0
        
        # SIFT matching indices map: queryIdx goes to query_kp, trainIdx goes to train_kp
        # Note: We want to map coordinate from Train image (original landmark) to Query image (current camera)
        pts_train = np.float32([train_kp[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
        pts_query = np.float32([query_kp[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
        
        # Find homography mapping Train -> Query
        H, mask = cv2.findHomography(pts_train, pts_query, cv2.RANSAC, 5.0)
        if H is None or mask is None:
            return False, 0.0, 0.0, 0.0
        
        inliers = np.sum(mask)
        confidence = float(inliers) / len(matches) if len(matches) > 0 else 0.0
        
        # Valid matches require minimal visual descriptors support
        is_valid = inliers >= 6 and confidence > 0.35
        
        inlier_pts = []
        if is_valid and H is not None and mask is not None:
            # Collect inliers coordinates relative to query image
            for idx, m in enumerate(matches):
                if mask[idx][0] == 1:
                    pt = query_kp[m.queryIdx].pt
                    inlier_pts.append({"x": round(float(pt[0]) / query_w, 4), "y": round(float(pt[1]) / query_h, 4)})
                    
        if not is_valid:
            return False, confidence, 0.0, 0.0, []

        # Project coordinates
        # Landmark coordinates are relative (0.0 to 1.0)
        orig_x_abs = landmark_x * train_w
        orig_y_abs = landmark_y * train_h
        
        src_pt = np.array([[[orig_x_abs, orig_y_abs]]], dtype=np.float32)
        dst_pt = cv2.perspectiveTransform(src_pt, H)
        
        proj_x_abs, proj_y_abs = dst_pt[0][0]
        
        # Convert back to relative coordinates of the Query image
        proj_x_rel = float(proj_x_abs) / query_w
        proj_y_rel = float(proj_y_abs) / query_h
        
        return True, confidence, proj_x_rel, proj_y_rel, inlier_pts

class ORBExpVisionEngine(AbstractVisionEngine):
    def __init__(self):
        self.detector = cv2.ORB_create(nfeatures=1000)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    def extract_features(self, image_bytes: bytes):
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
        if img is None:
            return [], None, 0, 0
        h, w = img.shape
        kp, desc = self.detector.detectAndCompute(img, None)
        return kp, desc, w, h

    def match_features(self, query_desc, train_desc):
        if query_desc is None or train_desc is None:
            return []
        try:
            matches = self.matcher.match(query_desc, train_desc)
            matches = sorted(matches, key=lambda x: x.distance)
            good_matches = [m for m in matches if m.distance < 55]
            return good_matches
        except Exception:
            return []

    def verify_geometry_and_project(self, query_kp, train_kp, matches, landmark_x: float, landmark_y: float, train_w: int, train_h: int, query_w: int, query_h: int):
        if len(matches) < 4:
            return False, 0.0, 0.0, 0.0
        
        pts_train = np.float32([train_kp[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
        pts_query = np.float32([query_kp[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
        
        H, mask = cv2.findHomography(pts_train, pts_query, cv2.RANSAC, 5.0)
        if H is None or mask is None:
            return False, 0.0, 0.0, 0.0
        
        inliers = np.sum(mask)
        confidence = float(inliers) / len(matches) if len(matches) > 0 else 0.0
        
        is_valid = inliers >= 5 and confidence > 0.30
        
        inlier_pts = []
        if is_valid and H is not None and mask is not None:
            for idx, m in enumerate(matches):
                if mask[idx][0] == 1:
                    pt = query_kp[m.queryIdx].pt
                    inlier_pts.append({"x": round(float(pt[0]) / query_w, 4), "y": round(float(pt[1]) / query_h, 4)})

        if not is_valid:
            return False, confidence, 0.0, 0.0, []

        orig_x_abs = landmark_x * train_w
        orig_y_abs = landmark_y * train_h
        
        src_pt = np.array([[[orig_x_abs, orig_y_abs]]], dtype=np.float32)
        dst_pt = cv2.perspectiveTransform(src_pt, H)
        
        proj_x_abs, proj_y_abs = dst_pt[0][0]
        
        proj_x_rel = float(proj_x_abs) / query_w
        proj_y_rel = float(proj_y_abs) / query_h
        
        return True, confidence, proj_x_rel, proj_y_rel, inlier_pts

vision_engines = {
    "SIFT": SIFTExpVisionEngine(),
    "ORB": ORBExpVisionEngine()
}

CURRENT_ENGINE_TYPE = "SIFT"

def get_vision_engine() -> AbstractVisionEngine:
    return vision_engines.get(CURRENT_ENGINE_TYPE, vision_engines["SIFT"])
