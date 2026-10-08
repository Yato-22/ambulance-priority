import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/graph_edge.dart';
import '../models/graph_node.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';
import '../models/sim_state.dart';
import '../simulation/simulation_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/eta_card.dart';
import '../widgets/schematic_graph_painter.dart';
import '../widgets/status_banner.dart';

enum MapInteractionMode {
  none,
  selectStart,
  congestion,
}

/// Schematic Map Screen powered by CustomPainter and InteractiveViewer.
/// Features full pan/zoom, interactive road congestion cycling, start selection, and telemetry overlays.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TransformationController _transController = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();
  MapInteractionMode _interactionMode = MapInteractionMode.none;
  CanvasProjection? _projection;

  static const double canvasW = 1000.0;
  static const double canvasH = 900.0;

  Size? _lastViewportSize;
  bool _didInitialFit = false;
  String? _highlightedRoadKey;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _transController.dispose();
    super.dispose();
  }

  void _highlightRoad(String roadKey) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedRoadKey = roadKey;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _highlightedRoadKey = null;
        });
      }
    });
  }

  /// Calculates and applies the transform matrix that fits the entire schematic
  /// graph cleanly into the visible area between top status banners and bottom dock.
  void _fitGraphToScreen(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    const topMargin = 72.0;
    const bottomMargin = 160.0;
    final availW = viewportSize.width;
    final availH = math.max(120.0, viewportSize.height - topMargin - bottomMargin);

    final scaleX = availW / canvasW;
    final scaleY = availH / canvasH;
    final fitScale = (math.min(scaleX, scaleY) * 0.94).clamp(0.1, 3.0);

    final renderedW = canvasW * fitScale;
    final renderedH = canvasH * fitScale;
    final tx = (availW - renderedW) / 2.0;
    final ty = topMargin + (availH - renderedH) / 2.0;

    _transController.value =
        Matrix4.translationValues(tx, ty, 0.0) * Matrix4.diagonal3Values(fitScale, fitScale, 1.0);
  }

  /// Zooms in or out centered at the center of the viewport.
  void _zoom(double factor, Size viewportSize) {
    final currentMatrix = _transController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    if (factor > 1.0 && currentScale >= 4.0) return;
    if (factor < 1.0 && currentScale <= 0.12) return;

    final center = Offset(viewportSize.width / 2.0, viewportSize.height / 2.0);

    final zoomMatrix = Matrix4.translationValues(center.dx, center.dy, 0.0) *
        Matrix4.diagonal3Values(factor, factor, 1.0) *
        Matrix4.translationValues(-center.dx, -center.dy, 0.0);

    _transController.value = zoomMatrix * currentMatrix;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SimulationController>();
    final state = controller.state;
    final graph = controller.graph;

    final isLight = Theme.of(context).brightness == Brightness.light;
    final mapColors = Theme.of(context).extension<MapColors>() ??
        (isLight ? MapColors.light : MapColors.dark);

    if (graph != null && _projection == null) {
      _projection = CanvasProjection.fromGraph(graph, width: canvasW, height: canvasH);
    }

    return Scaffold(
      backgroundColor: mapColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          // Automatically fit and center graph on initial load or resize
          if (!_didInitialFit && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
            _didInitialFit = true;
            _lastViewportSize = viewportSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitGraphToScreen(viewportSize);
            });
          } else if (_lastViewportSize != null &&
              (_lastViewportSize!.width != viewportSize.width ||
                  _lastViewportSize!.height != viewportSize.height)) {
            _lastViewportSize = viewportSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitGraphToScreen(viewportSize);
            });
          }

          return Stack(
            children: [
              // 1. Interactive Canvas with unrestricted Pan & Pinch Zoom
              if (graph != null && _projection != null)
                InteractiveViewer(
                  key: _viewerKey,
                  transformationController: _transController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(800),
                  minScale: 0.1,
                  maxScale: 4.5,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final renderBox = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
                      final viewportPoint = renderBox != null
                          ? renderBox.globalToLocal(details.globalPosition)
                          : details.localPosition;
                      final scenePoint = _transController.toScene(viewportPoint);
                      _handleCanvasTap(context, controller, scenePoint);
                    },
                    child: SizedBox(
                      width: canvasW,
                      height: canvasH,
                      child: CustomPaint(
                        size: const Size(canvasW, canvasH),
                        painter: SchematicGraphPainter(
                          graph: graph,
                          projection: _projection!,
                          ambulance: state.ambulance,
                          signals: state.signals,
                          activeSignalId: state.activeSignalId,
                          triggerRadiusM: controller.greenTriggerRadiusM,
                          routeNodeIds: state.routeNodeIds,
                          routePolyline: state.routePolyline,
                          startNodeId: state.startNodeId,
                          targetHospital: state.targetHospital,
                          isEnRoute: state.status == SimulationStatus.enRoute ||
                              state.status == SimulationStatus.heldAtSignal,
                          isHeldAtSignal: state.status == SimulationStatus.heldAtSignal,
                          heldSignalId: state.heldSignalId,
                          highlightedRoadKey: _highlightedRoadKey,
                          mapColors: mapColors,
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. Status Banner (top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Column(
                    children: [
                      StatusBanner(state: state),
                      if (_interactionMode == MapInteractionMode.congestion)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: isLight ? const Color(0xFFFFE0B2) : Colors.deepOrange.shade900,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: isLight ? const Color(0xFFBF360C) : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'CONGESTION MODE: Tap any road segment to cycle (Open -> Moderate -> Heavy -> Blocked)',
                                  style: TextStyle(
                                    color: isLight ? const Color(0xFFBF360C) : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_interactionMode == MapInteractionMode.selectStart)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: isLight ? const Color(0xFFCCFBF1) : Colors.teal.shade900,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.flag_rounded,
                                color: isLight ? const Color(0xFF115E59) : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'SELECT START MODE: Tap any junction on the grid to set start location',
                                  style: TextStyle(
                                    color: isLight ? const Color(0xFF115E59) : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Floating Telemetry Card (moved below banners)
              if (state.status != SimulationStatus.idle)
                Positioned(
                  top: _interactionMode != MapInteractionMode.none ? 76 : 50,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: EtaCard(state: state),
                  ),
                ),

              // 4. Map Action Buttons on right edge (Congestion, Start, Zoom In, Zoom Out, Fit)
              Positioned(
                right: 16,
                bottom: 140,
                child: Builder(
                  builder: (context) {
                    final fabBg = isLight ? Theme.of(context).colorScheme.surface : Colors.blueGrey.shade800;
                    final fabFg = isLight ? Theme.of(context).colorScheme.onSurface : Colors.white;

                    return Column(
                      children: [
                        // Toggle Congestion Tool
                        FloatingActionButton.small(
                          heroTag: 'cong_btn',
                          tooltip: 'Congestion & Road Block Mode',
                          backgroundColor: _interactionMode == MapInteractionMode.congestion
                              ? Colors.deepOrange
                              : fabBg,
                          foregroundColor: _interactionMode == MapInteractionMode.congestion
                              ? Colors.white
                              : fabFg,
                          onPressed: () {
                            setState(() {
                              _interactionMode = _interactionMode == MapInteractionMode.congestion
                                  ? MapInteractionMode.none
                                  : MapInteractionMode.congestion;
                            });
                          },
                          child: const Icon(Icons.traffic_rounded),
                        ),
                        const SizedBox(height: 8),
                        // Toggle Select Start Node
                        FloatingActionButton.small(
                          heroTag: 'start_btn',
                          tooltip: 'Set Start Location',
                          backgroundColor: _interactionMode == MapInteractionMode.selectStart
                              ? (isLight ? const Color(0xFF0D9488) : Colors.tealAccent.shade700)
                              : fabBg,
                          foregroundColor: _interactionMode == MapInteractionMode.selectStart
                              ? Colors.white
                              : fabFg,
                          onPressed: () {
                            setState(() {
                              _interactionMode = _interactionMode == MapInteractionMode.selectStart
                                  ? MapInteractionMode.none
                                  : MapInteractionMode.selectStart;
                            });
                          },
                          child: const Icon(Icons.flag_rounded),
                        ),
                        const SizedBox(height: 8),
                        // Zoom In Button
                        FloatingActionButton.small(
                          heroTag: 'zoom_in',
                          tooltip: 'Zoom In',
                          backgroundColor: fabBg,
                          foregroundColor: fabFg,
                          onPressed: () => _zoom(1.3, viewportSize),
                          child: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        // Zoom Out Button
                        FloatingActionButton.small(
                          heroTag: 'zoom_out',
                          tooltip: 'Zoom Out',
                          backgroundColor: fabBg,
                          foregroundColor: fabFg,
                          onPressed: () => _zoom(0.77, viewportSize),
                          child: const Icon(Icons.remove_rounded),
                        ),
                        const SizedBox(height: 8),
                        // Fit Whole Graph
                        FloatingActionButton.small(
                          heroTag: 'zoom_fit',
                          tooltip: 'Fit Whole Graph',
                          backgroundColor: fabBg,
                          foregroundColor: fabFg,
                          onPressed: () => _fitGraphToScreen(viewportSize),
                          child: const Icon(Icons.fit_screen_rounded),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 5. Traffic Legend Card in bottom-left corner
              Positioned(
                left: 16,
                bottom: 140,
                child: _buildLegendCard(context, mapColors, isLight),
              ),

              // 6. Bottom Navigation & Trip Control Dock
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomControlDock(context, controller, state, graph),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomControlDock(
    BuildContext context,
    SimulationController controller,
    SimState state,
    dynamic graph,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Select Start Node and Destination Hospital picker
            if (state.status == SimulationStatus.idle && graph != null) ...[
              Row(
                children: [
                  const Icon(Icons.flag_rounded, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Start: #${state.startNodeId ?? 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  const Spacer(),
                  const Icon(Icons.local_hospital_rounded, color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: DropdownButton<Hospital>(
                      value: state.targetHospital,
                      underline: const SizedBox(),
                      isDense: true,
                      isExpanded: true,
                      items: (graph.hospitals as List<Hospital>).map((Hospital h) {
                        return DropdownMenuItem<Hospital>(
                          value: h,
                          child: Text(
                            h.name,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (Hospital? h) {
                        if (h != null) controller.selectHospital(h);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                if (state.status == SimulationStatus.idle) ...[
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Start Trip',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setState(() => _interactionMode = MapInteractionMode.none);
                          controller.startTrip();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: _buildSpeedChips(controller),
                  ),
                ] else if (state.status == SimulationStatus.enRoute ||
                    state.status == SimulationStatus.heldAtSignal) ...[
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: state.isPaused ? Colors.green.shade700 : Colors.amber.shade700,
                          foregroundColor: state.isPaused ? Colors.white : Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(
                          state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 18,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            state.isPaused ? 'Resume' : 'Pause',
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        onPressed: () =>
                            state.isPaused ? controller.resumeTrip() : controller.pauseTrip(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'New Trip',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        onPressed: () => controller.resetTrip(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: _buildSpeedChips(controller),
                  ),
                ] else ...[
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text(
                          'New Trip',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => controller.resetTrip(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: _buildSpeedChips(controller),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedChips(SimulationController controller) {
    return SizedBox(
      height: 48,
      child: SegmentedButton<double>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: 1.0,
            label: Text('1x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          ButtonSegment(
            value: 2.0,
            label: Text('2x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          ButtonSegment(
            value: 5.0,
            label: Text('5x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
        selected: {controller.timeScale},
        onSelectionChanged: (val) => controller.setTimeScale(val.first),
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _handleCanvasTap(BuildContext context, SimulationController controller, Offset scenePoint) {
    if (_projection == null || controller.graph == null) return;
    final graph = controller.graph!;

    final double zoomScale = _transController.value.getMaxScaleOnAxis();

    // 1. If in Congestion mode: cycle road state (open -> moderate -> heavy -> blocked -> open)
    if (_interactionMode == MapInteractionMode.congestion) {
      // Pick nearest road by point-to-segment distance within about 20 screen pixels (divide by current zoom scale)
      final double toleranceInScene = 20.0 / math.max(0.01, zoomScale);
      GraphEdge? closestEdge;
      double minPixelDist = double.infinity;

      for (final edge in graph.edges) {
        final u = graph.nodes[edge.from];
        final v = graph.nodes[edge.to];
        if (u == null || v == null) continue;

        final p1 = _projection!.toCanvas(u.lat, u.lon);
        final p2 = _projection!.toCanvas(v.lat, v.lon);

        final d = _pointToSegmentDist(scenePoint, p1, p2);
        if (d < minPixelDist) {
          minPixelDist = d;
          closestEdge = edge;
        }
      }

      // If road is within 20 screen pixels, cycle its discrete state
      if (closestEdge != null && minPixelDist <= toleranceInScene) {
        final newState = controller.cycleRoadState(closestEdge.from, closestEdge.to);
        final roadPairKey = RoadGraph.roadKey(closestEdge.from, closestEdge.to);
        _highlightRoad(roadPairKey);

        final roadName = closestEdge.name.isNotEmpty ? closestEdge.name : 'Road';
        final stateLabel = newState == RoadState.blocked
            ? 'Blocked'
            : '${newState.name[0].toUpperCase()}${newState.name.substring(1)} (${newState.factor.toStringAsFixed(0)}x)';

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$roadName segment: $stateLabel'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 2. If in Select Start mode: set start node
    if (_interactionMode == MapInteractionMode.selectStart ||
        controller.state.status == SimulationStatus.idle) {
      final double nodeTolerance = 30.0 / math.max(0.01, zoomScale);
      GraphNode? closestNode;
      double minNodeDist = double.infinity;

      for (final node in graph.nodes.values) {
        final pt = _projection!.toCanvas(node.lat, node.lon);
        final d = (scenePoint - pt).distance;
        if (d < minNodeDist) {
          minNodeDist = d;
          closestNode = node;
        }
      }

      if (closestNode != null && minNodeDist <= nodeTolerance) {
        if (closestNode.id == controller.state.targetHospital?.nodeId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot select destination hospital as start node!')),
          );
          return;
        }

        controller.selectStartNode(closestNode.id);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Start location set to Node #${closestNode.id}'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _interactionMode = MapInteractionMode.none);
      }
    }
  }

  Widget _buildLegendCard(BuildContext context, MapColors mapColors, bool isLight) {
    final theme = Theme.of(context);
    return Card(
      color: isLight ? theme.colorScheme.surface : const Color(0xEE1A2230),
      elevation: isLight ? 2 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isLight ? theme.colorScheme.outlineVariant : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TRAFFIC LEGEND',
              style: TextStyle(
                color: isLight ? theme.colorScheme.onSurfaceVariant : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            _buildLegendRow(
              mapColors.openRoad,
              'Open (1x)',
              isDashed: false,
              textColor: isLight ? theme.colorScheme.onSurface : Colors.white,
            ),
            const SizedBox(height: 4),
            _buildLegendRow(
              mapColors.moderateRoad,
              'Moderate (2x)',
              isDashed: false,
              textColor: isLight ? theme.colorScheme.onSurface : Colors.white,
            ),
            const SizedBox(height: 4),
            _buildLegendRow(
              mapColors.heavyRoad,
              'Heavy (4x)',
              isDashed: false,
              textColor: isLight ? theme.colorScheme.onSurface : Colors.white,
            ),
            const SizedBox(height: 4),
            _buildLegendRow(
              mapColors.blockedRoad,
              'Blocked',
              isDashed: true,
              textColor: isLight ? theme.colorScheme.onSurface : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow(
    Color color,
    String label, {
    required bool isDashed,
    required Color textColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 6,
          child: isDashed
              ? Row(
                  children: [
                    Container(width: 6, height: 3, color: color),
                    const SizedBox(width: 3),
                    Container(width: 6, height: 3, color: color),
                    const SizedBox(width: 3),
                    Container(width: 4, height: 3, color: color),
                  ],
                )
              : Container(height: 3, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: textColor, fontSize: 11),
        ),
      ],
    );
  }

  double _pointToSegmentDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLenSq == 0) return (p - a).distance;

    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + (t * ab.dx), a.dy + (t * ab.dy));
    return (p - proj).distance;
  }
}
