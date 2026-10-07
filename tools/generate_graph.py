#!/usr/bin/env python3
"""
Road graph generator for LoRa-Based Smart Traffic Signal Management Simulation.
Can generate from OpenStreetMap (OSM) via osmnx or generate a synthetic 6x6 grid (offline mode).
Outputs a JSON file compatible with the Flutter prototype.
"""

import argparse
import datetime
import json
import math
import os
import random
import sys

EARTH_RADIUS_M = 6371000.0


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great-circle distance between two points in meters."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2.0) ** 2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return EARTH_RADIUS_M * c


def generate_grid_graph(center_lat: float, center_lon: float, grid_size: int = 6, spacing_m: float = 300.0) -> dict:
    """
    Generate an offline synthetic grid graph around center_lat, center_lon.
    Produces grid_size x grid_size nodes with bidirectional streets.
    """
    rng = random.Random(42)

    # Coordinate offsets per meter
    m_per_lat_deg = 111320.0
    m_per_lon_deg = 111320.0 * math.cos(math.radians(center_lat))

    half_offset = (grid_size - 1) / 2.0

    nodes = []
    node_id_map = {}  # (r, c) -> node_id

    # Street names for realism (Pune Karve Nagar / Kothrud themed)
    east_west_streets = [
        "Karve Road",
        "DP Road",
        "Cummins College Road",
        "Mayur Colony Road",
        "Dahanukar Colony Rd",
        "Warje Bypass Road",
    ]
    north_south_avenues = [
        "Paud Road Link",
        "Kothrud Main Ave",
        "Hingne Road",
        "Gandhi Bhavan Rd",
        "Canal Road",
        "Shastri Nagar Road",
    ]

    curr_id = 1
    for r in range(grid_size):
        for c in range(grid_size):
            d_north = (r - half_offset) * spacing_m
            d_east = (c - half_offset) * spacing_m
            lat = round(center_lat + (d_north / m_per_lat_deg), 6)
            lon = round(center_lon + (d_east / m_per_lon_deg), 6)

            node_id_map[(r, c)] = curr_id
            nodes.append({
                "id": curr_id,
                "lat": lat,
                "lon": lon,
                "r": r,
                "c": c,
                "signal": False,
                "signal_id": None,
                "signal_source": None,
            })
            curr_id += 1

    # Select 8-10 signals at central intersections
    signal_coords = [
        (1, 1), (1, 3), (1, 4),
        (2, 2), (2, 3),
        (3, 1), (3, 2), (3, 4),
        (4, 2), (4, 3)
    ]
    signal_counter = 1
    for (r, c) in signal_coords:
        n_id = node_id_map[(r, c)]
        node = next(n for n in nodes if n["id"] == n_id)
        node["signal"] = True
        node["signal_id"] = f"S{signal_counter}"
        node["signal_source"] = "grid_planned"
        signal_counter += 1

    # Hospitals at strategic outer locations
    hospital_nodes = [
        {"id": "H1", "name": "Sahyadri Hospital (Kothrud)", "node": node_id_map[(0, 0)]},
        {"id": "H2", "name": "Deenanath Mangeshkar Hospital", "node": node_id_map[(grid_size - 1, grid_size - 1)]},
        {"id": "H3", "name": "Mai Mangeshkar Hospital (Warje)", "node": node_id_map[(0, grid_size - 1)]},
    ]

    edges = []
    # Build horizontal and vertical edges
    for r in range(grid_size):
        for c in range(grid_size):
            u_id = node_id_map[(r, c)]
            u_node = next(n for n in nodes if n["id"] == u_id)

            # Connect East (horizontal)
            if c + 1 < grid_size:
                v_id = node_id_map[(r, c + 1)]
                v_node = next(n for n in nodes if n["id"] == v_id)
                dist = round(haversine_distance(u_node["lat"], u_node["lon"], v_node["lat"], v_node["lon"]), 1)
                road_name = east_west_streets[r % len(east_west_streets)]
                base_cong_1 = round(rng.uniform(1.0, 1.8), 2)
                base_cong_2 = round(rng.uniform(1.0, 1.8), 2)

                edges.append({
                    "from": u_id,
                    "to": v_id,
                    "length": dist,
                    "name": road_name,
                    "base_congestion": base_cong_1,
                    "oneway": false_if_bidirectional(False),
                    "geometry": [[u_node["lat"], u_node["lon"]], [v_node["lat"], v_node["lon"]]],
                })
                edges.append({
                    "from": v_id,
                    "to": u_id,
                    "length": dist,
                    "name": road_name,
                    "base_congestion": base_cong_2,
                    "oneway": false_if_bidirectional(False),
                    "geometry": [[v_node["lat"], v_node["lon"]], [u_node["lat"], u_node["lon"]]],
                })

            # Connect North (vertical)
            if r + 1 < grid_size:
                v_id = node_id_map[(r + 1, c)]
                v_node = next(n for n in nodes if n["id"] == v_id)
                dist = round(haversine_distance(u_node["lat"], u_node["lon"], v_node["lat"], v_node["lon"]), 1)
                road_name = north_south_avenues[c % len(north_south_avenues)]
                base_cong_1 = round(rng.uniform(1.0, 1.8), 2)
                base_cong_2 = round(rng.uniform(1.0, 1.8), 2)

                edges.append({
                    "from": u_id,
                    "to": v_id,
                    "length": dist,
                    "name": road_name,
                    "base_congestion": base_cong_1,
                    "oneway": false_if_bidirectional(False),
                    "geometry": [[u_node["lat"], u_node["lon"]], [v_node["lat"], v_node["lon"]]],
                })
                edges.append({
                    "from": v_id,
                    "to": u_id,
                    "length": dist,
                    "name": road_name,
                    "base_congestion": base_cong_2,
                    "oneway": false_if_bidirectional(False),
                    "geometry": [[v_node["lat"], v_node["lon"]], [u_node["lat"], u_node["lon"]]],
                })

    # Clean temporary keys from nodes
    output_nodes = []
    for n in nodes:
        node_dict = {
            "id": n["id"],
            "lat": n["lat"],
            "lon": n["lon"],
            "signal": n["signal"],
        }
        if n["signal"]:
            node_dict["signal_id"] = n["signal_id"]
            node_dict["signal_source"] = n["signal_source"]
        output_nodes.append(node_dict)

    return {
        "meta": {
            "center": [center_lat, center_lon],
            "radius_m": int(grid_size * spacing_m / 2.0),
            "source": "grid",
            "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
        "nodes": output_nodes,
        "hospitals": hospital_nodes,
        "edges": edges,
    }


def false_if_bidirectional(is_oneway: bool) -> bool:
    return is_oneway


def generate_osm_graph(center_lat: float, center_lon: float, dist_m: float = 1500.0) -> dict:
    """
    Generate graph using osmnx and networkx from real OpenStreetMap data.
    """
    try:
        import osmnx as ox
        import networkx as nx
    except ImportError:
        print("ERROR: osmnx or networkx not installed. Please run:")
        print("  pip install -r tools/requirements.txt")
        print("Or use --mode grid for offline generation.")
        sys.exit(1)

    print(f"Downloading drivable road network around ({center_lat}, {center_lon}) radius {dist_m}m...")
    # Fetch graph
    G = ox.graph_from_point((center_lat, center_lon), dist=dist_m, network_type="drive", simplify=True)

    # Keep largest strongly connected component
    if not nx.is_strongly_connected(G):
        print("Extracting largest strongly connected component...")
        largest_scc = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(largest_scc).copy()

    print(f"Graph nodes: {len(G.nodes)}, edges: {len(G.edges)}")

    # Map OSM node IDs to integer IDs starting from 1
    osm_to_int = {}
    nodes = []
    for i, (osm_id, data) in enumerate(G.nodes(data=True), start=1):
        osm_to_int[osm_id] = i
        lat = round(float(data['y']), 6)
        lon = round(float(data['x']), 6)
        is_signal = False
        signal_source = None
        # Check highway tag for traffic signals
        if data.get('highway') == 'traffic_signals':
            is_signal = True
            signal_source = "osm"

        nodes.append({
            "id": i,
            "osm_id": osm_id,
            "lat": lat,
            "lon": lon,
            "signal": is_signal,
            "signal_id": None,
            "signal_source": signal_source,
            "degree": G.degree(osm_id),
        })

    # Count signals found from OSM
    osm_signals = [n for n in nodes if n["signal"]]
    print(f"OSM traffic signals found: {len(osm_signals)}")

    # Top up signals if fewer than 8
    rng = random.Random(42)
    if len(osm_signals) < 8:
        print("Fewer than 8 signals found; augmenting with high-degree junctions (>= 250m apart)...")
        # Candidate nodes with degree >= 6 or high degree
        candidates = [n for n in nodes if not n["signal"] and n["degree"] >= 4]
        candidates.sort(key=lambda n: n["degree"], reverse=True)

        for cand in candidates:
            # Check distance to already designated signals
            too_close = False
            for s in osm_signals:
                if haversine_distance(cand["lat"], cand["lon"], s["lat"], s["lon"]) < 250.0:
                    too_close = True
                    break
            if not too_close:
                cand["signal"] = True
                cand["signal_source"] = "auto"
                osm_signals.append(cand)
                if len(osm_signals) >= 12:
                    break

    # Assign signal IDs S1, S2, ...
    for idx, s in enumerate(osm_signals, start=1):
        s["signal_id"] = f"S{idx}"
    print(f"Total signals after augmentation: {len(osm_signals)}")

    # Find hospitals
    hospitals = []
    try:
        print("Querying OSM for hospitals...")
        hosp_tags = {"amenity": "hospital"}
        gdf = ox.features_from_point((center_lat, center_lon), tags=hosp_tags, dist=dist_m)
        if not gdf.empty:
            for idx, (_, row) in enumerate(gdf.iterrows(), start=1):
                name = row.get("name", f"Hospital {idx}")
                if not isinstance(name, str) or not name.strip():
                    name = f"Hospital {idx}"
                geom = row.geometry
                pt_lat = geom.centroid.y
                pt_lon = geom.centroid.x
                # Nearest graph node
                nearest_osm = ox.distance.nearest_nodes(G, pt_lon, pt_lat)
                nearest_int = osm_to_int[nearest_osm]
                hospitals.append({
                    "id": f"H{idx}",
                    "name": name,
                    "node": nearest_int,
                })
                if len(hospitals) >= 3:
                    break
    except Exception as e:
        print(f"Hospital query note: {e}")

    # Fallback hospitals if none found
    if len(hospitals) < 2:
        print("Augmenting hospitals at well-spaced peripheral nodes...")
        sorted_by_lat = sorted(nodes, key=lambda n: n["lat"])
        h1 = sorted_by_lat[0]
        h2 = sorted_by_lat[-1]
        sorted_by_lon = sorted(nodes, key=lambda n: n["lon"])
        h3 = sorted_by_lon[-1]
        default_names = ["Sahyadri Specialty Hospital", "Deenanath Mangeshkar Hospital", "Mai Mangeshkar Hospital"]
        hospitals = [
            {"id": "H1", "name": default_names[0], "node": h1["id"]},
            {"id": "H2", "name": default_names[1], "node": h2["id"]},
            {"id": "H3", "name": default_names[2], "node": h3["id"]},
        ]

    # Build edges
    edges = []
    edge_seen = set()
    for u, v, data in G.edges(data=True):
        u_int = osm_to_int[u]
        v_int = osm_to_int[v]
        length = round(float(data.get('length', 0.0)), 1)
        if length <= 0.0:
            u_node = next(n for n in nodes if n["id"] == u_int)
            v_node = next(n for n in nodes if n["id"] == v_int)
            length = round(haversine_distance(u_node["lat"], u_node["lon"], v_node["lat"], v_node["lon"]), 1)

        name = data.get('name', '')
        if isinstance(name, list):
            name = name[0] if name else ""
        elif not isinstance(name, str):
            name = ""

        is_oneway = bool(data.get('oneway', False))
        base_cong = round(rng.uniform(1.0, 1.8), 2)

        # Simplify edge geometry if present
        geom_points = []
        if 'geometry' in data:
            line = data['geometry']
            # Coordinates are (lon, lat) in Shapely line
            coords = list(line.coords)
            step = max(1, len(coords) // 6)
            sampled = coords[::step]
            if sampled[-1] != coords[-1]:
                sampled.append(coords[-1])
            geom_points = [[round(lat, 6), round(lon, 6)] for (lon, lat) in [(c[1], c[0]) for c in sampled]]
        else:
            u_node = next(n for n in nodes if n["id"] == u_int)
            v_node = next(n for n in nodes if n["id"] == v_int)
            geom_points = [[u_node["lat"], u_node["lon"]], [v_node["lat"], v_node["lon"]]]

        edge_key = (u_int, v_int)
        if edge_key not in edge_seen:
            edge_seen.add(edge_key)
            edges.append({
                "from": u_int,
                "to": v_int,
                "length": length,
                "name": name,
                "base_congestion": base_cong,
                "oneway": is_oneway,
                "geometry": geom_points,
            })

    output_nodes = []
    for n in nodes:
        node_dict = {
            "id": n["id"],
            "lat": n["lat"],
            "lon": n["lon"],
            "signal": n["signal"],
        }
        if n["signal"]:
            node_dict["signal_id"] = n["signal_id"]
            node_dict["signal_source"] = n["signal_source"]
        output_nodes.append(node_dict)

    return {
        "meta": {
            "center": [center_lat, center_lon],
            "radius_m": int(dist_m),
            "source": "osm",
            "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        },
        "nodes": output_nodes,
        "hospitals": hospitals,
        "edges": edges,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate road network graph JSON for Ambulance Priority Prototype.")
    parser.add_argument("--lat", type=float, default=18.4925, help="Center latitude (default: 18.4925 Karve Nagar Pune)")
    parser.add_argument("--lon", type=float, default=73.8230, help="Center longitude (default: 73.8230 Pune)")
    parser.add_argument("--dist", type=float, default=1500.0, help="Radius in meters (default: 1500)")
    parser.add_argument("--out", type=str, default="assets/road_graph.json", help="Output JSON path (default: assets/road_graph.json)")
    parser.add_argument("--mode", type=str, choices=["osm", "grid"], default="osm", help="Generation mode: osm or grid (default: osm)")

    args = parser.parse_args()

    # Ensure output directory exists
    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    print(f"Generating road graph [mode={args.mode}] around ({args.lat}, {args.lon})...")
    if args.mode == "grid":
        graph_data = generate_grid_graph(args.lat, args.lon)
    else:
        try:
            graph_data = generate_osm_graph(args.lat, args.lon, args.dist)
        except Exception as e:
            print(f"OSM generation failed ({e}). Falling back to synthetic grid mode...")
            graph_data = generate_grid_graph(args.lat, args.lon)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(graph_data, f, indent=2)

    num_signals = sum(1 for n in graph_data["nodes"] if n.get("signal"))
    print(f"Saved road graph to {args.out}")
    print(f"Summary: {len(graph_data['nodes'])} nodes, {len(graph_data['edges'])} edges, "
          f"{num_signals} signals, {len(graph_data['hospitals'])} hospitals.")


if __name__ == "__main__":
    main()

