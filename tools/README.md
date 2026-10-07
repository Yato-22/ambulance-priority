# Road Graph Generator Tool

This tool generates road network graphs in JSON format for the Ambulance Priority Traffic Signal Management prototype.

## Features
- **OSM Mode (`--mode osm`)**: Downloads real drivable street networks from OpenStreetMap using `osmnx` and `networkx`. Extracts traffic signals (`highway=traffic_signals`) and hospitals (`amenity=hospital`), augments signals at busy junctions (>=250m apart) if fewer than 8 exist, and preserves road geometry.
- **Grid Mode (`--mode grid`)**: Fully offline synthetic 6x6 grid around Pune (Karve Nagar / Kothrud) with 10 traffic signals, 3 hospitals, and bidirectional streets with realistic names and randomized base congestion factors.

## Output Schema
The tool creates `assets/road_graph.json` with the following structure:
```json
{
  "meta": {
    "center": [18.4925, 73.8230],
    "radius_m": 1500,
    "source": "osm | grid",
    "generated": "2026-10-07T16:00:00Z"
  },
  "nodes": [
    {"id": 1, "lat": 18.4925, "lon": 73.8230, "signal": true, "signal_id": "S1", "signal_source": "osm"}
  ],
  "hospitals": [
    {"id": "H1", "name": "Sahyadri Hospital (Kothrud)", "node": 1}
  ],
  "edges": [
    {
      "from": 1,
      "to": 2,
      "length": 300.0,
      "name": "Karve Road",
      "base_congestion": 1.25,
      "oneway": false,
      "geometry": [[18.4925, 73.8230], [18.4952, 73.8230]]
    }
  ]
}
```

## Setup & Usage

### 1. Offline Mode (Zero External Dependencies)
Works immediately using standard Python 3:
```bash
python3 tools/generate_graph.py --mode grid --out assets/road_graph.json
```

### 2. OSM Mode (Requires Internet and osmnx)
Install dependencies:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/requirements.txt
```

Run for Karve Nagar / Kothrud, Pune:
```bash
python3 tools/generate_graph.py --mode osm --lat 18.4925 --lon 73.8230 --dist 1500 --out assets/road_graph.json
```

