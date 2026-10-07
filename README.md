# LoRa-Based Smart Traffic Signal Management for Ambulance Priority (Prototype)

A complete, self-contained software simulation and prototype of an emergency ambulance priority traffic management system built in Flutter (Dart).

All road graphs, pathfinding algorithms (A* with admissible Haversine heuristic), kinematics interpolation, and simulated LoRa SX1262 (865 MHz) RF link transceivers run locally inside the application in pure Dart. The visual UI utilizes a custom schematic canvas (`CustomPainter` inside `InteractiveViewer`) with zero external map tiles, zero web asset dependencies, and complete offline autonomy.

---

## 1. Architecture Overview

```
+-----------------------------------------------------------------------------------+
|                                FLUTTER APPLICATION                               |
|                                                                                   |
|  +--------------------+   +-----------------------+   +------------------------+  |
|  |   Schematic Map    |   |    Signals Screen     |   |     Hospital Screen    |  |
|  |  (Custom Canvas &  |   |   (Control Station    |   |   (Emergency Reception |  |
|  | InteractiveViewer) |   |  LoRa 865 MHz Log)    |   |     Live Countdown)    |  |
|  +---------+----------+   +-----------+-----------+   +-----------+------------+  |
|            |                          |                           |               |
|            +--------------------------+---------------------------+               |
|                                       |                                           |
|                            [Provider State Consumer]                              |
|                                       v                                           |
|                   +---------------------------------------+                       |
|                   |         SimulationController          |                       |
|                   |    (ChangeNotifier, 500ms Tick Clock) |                       |
|                   +---+---------------+---------------+---+                       |
|                       |               |               |                           |
|       +---------------+               |               +----------------+          |
|       v                               v                                v          |
|  +--------------------+      +--------------------+      +--------------------+   |
|  |     AStarRouter    |      |   AmbulanceMover   |      |   SignalManager    |   |
|  | (Min-Heap A* Search|      | (Kinematics along  |      | (Green preemption, |   |
|  |  Admissible Heur.) |      |  Dense Polyline)   |      |  Hysteresis revert)|   |
|  +--------------------+      +--------------------+      +---------+----------+   |
|                                                                    |              |
|                                                                    v              |
|                                                      +------------------------+   |
|                                                      |   LoRaLinkSimulator    |   |
|                                                      |  (SX1262 865 MHz Link, |   |
|                                                      |  100-300ms, Retries)   |   |
|                                                      +------------------------+   |
+-----------------------------------------------------------------------------------+
                                        ^
                                        | Instantiates in-memory graph
                                        |
+---------------------------------------+-------------------------------------------+
|                          PROCEDURAL GRAPH BUILDER (Pure Dart)                     |
|                                                                                   |
|  lib/data/sample_graph.dart                                                       |
|   - Fixed-seed 6x7 road network (42 junctions) with +-40m organic jitter          |
|   - Fully-connected guarantee (verified via BFS) with ~12% edge removals         |
|   - 12 Traffic Signals (S1..S12) + 2 Hospitals (H1 City, H2 Lifeline)            |
+-----------------------------------------------------------------------------------+
```

---

## 2. Root Cause Analysis & Fix Pass Details

### Problem A: Map Misalignment & Internet Dependencies
- **Issue**: A synthetic coordinate grid was overlaid on top of real OpenStreetMap raster tiles, causing road lines to misalign with real-world geography and requiring external internet connectivity.
- **Resolution**:
  - Removed `flutter_map` and `latlong2`.
  - Replaced with an interactive schematic canvas powered by `CustomPainter` inside `InteractiveViewer`.
  - Equirectangular projection maps lat/lon to canvas coordinates with padding, flipped Y (north up), and isotropic meters-to-pixel scaling so trigger radius circles (200m) render true to scale.

### Problem B: Premature Arrival Bug ("ARRIVED 0m 0s")
- **Root Cause**:
  1. Default start node (Node 1) was identical to default hospital node (Node 1). Start == destination yielded a 0-meter route.
  2. The arrival check condition `distanceTravelledM >= totalDistanceMeters` evaluated to `0 >= 0` (true) on the very first tick.
  3. `SignalManager` sliced upcoming route nodes using `polylineSegmentIndex` (which indexes dense polyline points, not route nodes), causing upcoming route node sets to prematurely empty.
  4. In `SignalManager`, `_revertSignal` did not immediately clear preemption, causing asynchronous LoRa delays to trigger hundreds of repeated revert increments in consecutive ticks.
- **Resolution**:
  1. **Trip Setup Validation**: Starting a trip requires $\text{start} \ne \text{destination}$. If unselected or equal, the system automatically selects the node farthest from the destination ($> 2000$ m away). Trips under 500 m or with fewer than 2 nodes are strictly rejected with `NO_ROUTE`.
  2. **State Machine Safeguards**: Arrival condition requires `status == EN_ROUTE`, `distanceTravelledM > 0`, `totalRouteDistanceM >= 500m`, and `remainingDistanceM < 15m`.
  3. **Arc-Length Route Tracking**: SignalManager tracks the exact cumulative distance of every junction along the route. Segment-crossing checks guarantee that even at $5\times$ speed, signals cannot be skipped.
  4. **Idempotent Revert**: `_revertSignal` immediately marks the signal as cleared and sets its state to RED while the simulated LoRa ACK transmits, preventing repeated increments.

---

## 3. Algorithms & Research Paper Mapping

### 3.1 Haversine Formula (`lib/algorithms/haversine.dart`)
- **Formula**:
  $$a = \sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta\lambda}{2}\right)$$
  $$c = 2 \cdot \text{atan2}\left(\sqrt{a}, \sqrt{1-a}\right), \quad d = R \cdot c \quad (R = 6,371,000\text{ m})$$
- Evaluates distance in $O(1)$ constant time with zero external dependencies.

### 3.2 A* Route Search (`lib/algorithms/astar.dart`)
- **Cost Function**: $g(n) = \sum \text{length}(e) \times \text{congestion}(e)$.
- **Admissibility**: Because edge congestion is constrained to $\ge 1.0$ and street length $\ge$ Euclidean straight-line distance, $h(n)$ (Haversine straight-line distance) never overestimates remaining cost. A* is strictly admissible and optimal.
- **Impassable Roads**: Edges with $\text{congestion} \ge 50.0$ are skipped during neighbor expansion.
- **Dijkstra Benchmark**: Includes an embedded Dijkstra router ($h(n) = 0$) for comparing explored node counts.

---

## 4. How to Run the App

### Linux Desktop
```bash
flutter run -d linux
```

### Web (Chrome)
```bash
flutter run -d chrome
```

### Run All 22 Unit, Simulation, & Headless Tests
```bash
flutter test
```

---

## 5. Live Demo Script (3-Minute Walkthrough)

1. **Step 1: Start Trip (0:00 - 0:40)**
   - Open the app on the **Map** tab.
   - Notice the start node (Node 1, green flag) and destination (*Lifeline Hospital*, Node 42, bottom-right).
   - Tap **START TRIP**.
   - Watch the ambulance travel along the blue route polyline with live speed, distance, and ETA updating.

2. **Step 2: Emergency Preemption & Revert (0:40 - 1:20)**
   - As the ambulance approaches signal `S2` within **200 m**, a green trigger radius halo appears.
   - Signal `S2` transitions: `NORMAL RED` $\to$ `PENDING` $\to$ bright glowing **PRIORITY GREEN**.
   - As the ambulance crosses `S2` and distance increases, `S2` reverts to its background cycle, and `Cleared: 1` increments.

3. **Step 3: Mid-Trip Road Block & Seamless Reroute (1:20 - 2:00)**
   - Tap the orange **Congestion Mode** button on the right edge.
   - Tap an upcoming road ahead of the ambulance to cycle it: `Normal` $\to$ `Congested (3.0x)` $\to$ `Blocked`.
   - Observe the **Dynamic Reroute** banner: A* recalculates an alternate clear detour from the ambulance's current position without teleportation.

4. **Step 4: Control Station & LoRa Activity (2:00 - 2:30)**
   - Switch to the **Signals** tab.
   - Observe signals sorted by proximity to the ambulance.
   - Set an upcoming signal to **Force Red** (manual override). Notice it remains red even when the ambulance approaches. Clear the override to watch it immediately engage priority green.
   - Tap the LoRa antenna icon to view the **LoRa SX1262 865 MHz Transceiver Log** showing latency and ACKs.

5. **Step 5: Hospital Reception & Mission Arrival (2:30 - 3:00)**
   - Switch to the **Hospital** tab.
   - See the real-time ETA countdown, clinical readiness banner, and milestone timeline.
   - When the ambulance reaches the hospital bay, observe the arrival banner and final mission statistics.
