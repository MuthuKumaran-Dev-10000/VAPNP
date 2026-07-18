from sqlalchemy.orm import Session
from database import Landmark, Waypoint, Edge
import heapq
import json

def build_graph(db_session: Session):
    """Reconstruct navigation graph from database nodes and edges."""
    landmarks = db_session.query(Landmark).all()
    waypoints = db_session.query(Waypoint).all()
    edges = db_session.query(Edge).all()

    nodes = {}
    # Compile all node coordinates.
    # Landmarks have GPS/local telemetry, waypoints are intermediate points.
    for lm in landmarks:
        # In a real app we mapping to 2D coordinates (x, y) or GPS
        nodes[lm.graph_node_id] = {
            "id": lm.graph_node_id,
            "name": lm.name,
            "lat": lm.gps_lat,
            "lng": lm.gps_lng,
            "is_landmark": True
        }
    
    for wp in waypoints:
        # Parse sensor snapshot to get relative coordinates if any, or default lat/lng
        try:
            snapshot = json.loads(wp.sensor_snapshot_json)
            lat = snapshot.get("gps_lat", 0.0)
            lng = snapshot.get("gps_lng", 0.0)
        except Exception:
            lat, lng = 0.0, 0.0
        
        nodes[wp.id] = {
            "id": wp.id,
            "name": f"Waypoint {wp.id[:6]}",
            "lat": lat,
            "lng": lng,
            "is_landmark": False
        }

    # Compile adjacency list
    adj = {node_id: [] for node_id in nodes}
    for edge in edges:
        # Verify nodes exist
        if edge.start_node_id not in nodes or edge.end_node_id not in nodes:
            continue
        
        adj[edge.start_node_id].append({
            "target": edge.end_node_id,
            "distance": edge.distance,
            "instruction": edge.direction_instruction,
            "heading": edge.expected_heading
        })
        # Bidirectional graph logic
        adj[edge.end_node_id].append({
            "target": edge.start_node_id,
            "distance": edge.distance,
            "instruction": f"Reverse: {edge.direction_instruction}",
            "heading": (edge.expected_heading + 180) % 360
        })

    return nodes, adj

def calculate_shortest_path(db_session: Session, start_node_id: str, end_node_id: str):
    """
    A* algorithm logic to calculate routes from a localized point.
    Returns path nodes list and step directions instructions.
    """
    nodes, adj = build_graph(db_session)
    
    if start_node_id not in nodes or end_node_id not in nodes:
        return {"path": [], "instructions": [], "total_distance": 0.0}

    # Dijkstra/A* queue: (cumulative_distance, current_node, path_history, instruction_history)
    queue = [(0.0, start_node_id, [start_node_id], [])]
    visited = set()

    while queue:
        dist, curr, path, insts = heapq.heappop(queue)
        
        if curr == end_node_id:
            # Route found!
            # Format the output paths
            formatted_path = [nodes[n] for n in path]
            return {
                "path": formatted_path,
                "instructions": insts,
                "total_distance": round(dist, 1)
            }

        if curr in visited:
            continue
        visited.add(curr)

        for edge in adj.get(curr, []):
            target = edge["target"]
            if target in visited:
                continue
            
            new_dist = dist + edge["distance"]
            new_path = path + [target]
            
            # Compile rich instruction message
            inst_msg = {
                "action": edge["instruction"] or "Go Straight",
                "distance": edge["distance"],
                "heading": edge["heading"],
                "target_name": nodes[target]["name"]
            }
            new_insts = insts + [inst_msg]

            heapq.heappush(queue, (new_dist, target, new_path, new_insts))

    return {"path": [], "instructions": [], "total_distance": 0.0}
