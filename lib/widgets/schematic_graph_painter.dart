import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/ambulance.dart';
import '../models/graph_edge.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';
import '../models/traffic_signal.dart';

/// Coordinate projection helper mapping geographic coordinates to canvas space.
class CanvasProjection {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final double canvasWidth;
  final double canvasHeight;
  final double padding;

  late final double _scale;
  late final double _offsetX;
  late final double _offsetY;
  late final double _deltaYm;
  late final double _centerLat;

  CanvasProjection({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    this.canvasWidth = 1000.0,
    this.canvasHeight = 900.0,
    this.padding = 90.0,
  }) {
    _centerLat = (minLat + maxLat) / 2.0;
    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(_centerLat * (math.pi / 180.0));

    final deltaXm = (maxLon - minLon) * mPerLon;
    _deltaYm = (maxLat - minLat) * mPerLat;

    final availW = canvasWidth - (2 * padding);
    final availH = canvasHeight - (2 * padding);

    _scale = math.min(availW / deltaXm, availH / _deltaYm);
    _offsetX = (canvasWidth - (deltaXm * _scale)) / 2.0;
    _offsetY = (canvasHeight - (_deltaYm * _scale)) / 2.0;
  }

  factory CanvasProjection.fromGraph(RoadGraph graph, {double width = 1000.0, double height = 900.0}) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;

    for (final node in graph.nodes.values) {
      if (node.lat < minLat) minLat = node.lat;
      if (node.lat > maxLat) maxLat = node.lat;
      if (node.lon < minLon) minLon = node.lon;
      if (node.lon > maxLon) maxLon = node.lon;
    }

    return CanvasProjection(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      canvasWidth: width,
      canvasHeight: height,
    );
  }

  Offset toCanvas(double lat, double lon) {
    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(_centerLat * (math.pi / 180.0));

    final xm = (lon - minLon) * mPerLon;
    final ym = (lat - minLat) * mPerLat;

    final cx = _offsetX + (xm * _scale);
    final cy = _offsetY + ((_deltaYm - ym) * _scale); // Flip y so north is up
    return Offset(cx, cy);
  }

  double metersToPixels(double meters) => meters * _scale;
}

/// CustomPainter that renders the road graph, signals, hospitals, and ambulance
/// on a high-performance dark schematic canvas.
class SchematicGraphPainter extends CustomPainter {
  final RoadGraph graph;
  final CanvasProjection projection;
  final Ambulance ambulance;
  final List<TrafficSignal> signals;
  final String? activeSignalId;
  final double triggerRadiusM;
  final List<int> routeNodeIds;
  final List<List<double>> routePolyline;
  final int? startNodeId;
  final Hospital? targetHospital;
  final bool isEnRoute;
  final String? highlightedRoadKey;

  SchematicGraphPainter({
    required this.graph,
    required this.projection,
    required this.ambulance,
    required this.signals,
    this.activeSignalId,
    required this.triggerRadiusM,
    required this.routeNodeIds,
    required this.routePolyline,
    this.startNodeId,
    this.targetHospital,
    required this.isEnRoute,
    this.highlightedRoadKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark neutral background with subtle grid pattern
    final bgPaint = Paint()..color = const Color(0xFF161B22);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    for (double x = 20; x < size.width; x += 35) {
      for (double y = 20; y < size.height; y += 35) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Draw Roads (edges)
    final seenEdges = <String>{};
    for (final edge in graph.edges) {
      final pairKey = RoadGraph.roadKey(edge.from, edge.to);
      if (seenEdges.contains(pairKey)) continue;
      seenEdges.add(pairKey);

      final uNode = graph.nodes[edge.from];
      final vNode = graph.nodes[edge.to];
      if (uNode == null || vNode == null) continue;

      final p1 = projection.toCanvas(uNode.lat, uNode.lon);
      final p2 = projection.toCanvas(vNode.lat, vNode.lon);

      Color roadColor;
      double strokeWidth = 2.5;

      switch (edge.state) {
        case RoadState.open:
          roadColor = const Color(0xFF607D8B); // Slate grey
          strokeWidth = 2.5;
          break;
        case RoadState.moderate:
          roadColor = const Color(0xFFFF9800); // Amber orange
          strokeWidth = 3.5;
          break;
        case RoadState.heavy:
          roadColor = const Color(0xFFE53935); // Solid red
          strokeWidth = 4.2;
          break;
        case RoadState.blocked:
          roadColor = const Color(0xFFD32F2F); // Impassable red
          strokeWidth = 3.5;
          break;
      }

      // Draw highlighted accent line if this road was recently tapped
      if (highlightedRoadKey != null && pairKey == highlightedRoadKey) {
        final highlightPaint = Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.9)
          ..strokeWidth = strokeWidth + 5.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p1, p2, highlightPaint);
      }

      final roadPaint = Paint()
        ..color = roadColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      if (edge.state == RoadState.blocked) {
        // Draw dashed line for blocked road (~8 px on, 6 px off)
        _drawDashedLine(canvas, p1, p2, roadPaint, dashLength: 8.0, dashSpace: 6.0);
      } else {
        canvas.drawLine(p1, p2, roadPaint);
      }
    }

    // 3. Draw Active Route Polyline
    if (routePolyline.length > 1) {
      final routePath = Path();
      final p0 = projection.toCanvas(routePolyline[0][0], routePolyline[0][1]);
      routePath.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < routePolyline.length; i++) {
        final pt = projection.toCanvas(routePolyline[i][0], routePolyline[i][1]);
        routePath.lineTo(pt.dx, pt.dy);
      }

      final routePaint = Paint()
        ..color = const Color(0xFF2979FF)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(routePath, routePaint);

      // Draw already-travelled portion in dim grey-blue
      final segIdx = ambulance.polylineSegmentIndex;
      if (segIdx > 0 && segIdx < routePolyline.length) {
        final traveledPath = Path();
        traveledPath.moveTo(p0.dx, p0.dy);
        for (int i = 1; i <= segIdx; i++) {
          final pt = projection.toCanvas(routePolyline[i][0], routePolyline[i][1]);
          traveledPath.lineTo(pt.dx, pt.dy);
        }
        // Line to current ambulance position
        final ambPt = projection.toCanvas(ambulance.lat, ambulance.lon);
        traveledPath.lineTo(ambPt.dx, ambPt.dy);

        final traveledPaint = Paint()
          ..color = const Color(0xFF546E7A)
          ..strokeWidth = 6.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(traveledPath, traveledPaint);
      }
    }

    // 4. Trigger Radius Circle around Next Active Signal
    if (isEnRoute && activeSignalId != null) {
      final activeSig = signals.cast<TrafficSignal?>().firstWhere(
            (s) => s?.id == activeSignalId,
            orElse: () => null,
          );
      if (activeSig != null) {
        final sigPt = projection.toCanvas(activeSig.lat, activeSig.lon);
        final radiusPx = projection.metersToPixels(triggerRadiusM);

        final fillPaint = Paint()
          ..color = (activeSig.state == SignalState.greenPriority ? const Color(0xFF00E676) : const Color(0xFFFFB300))
              .withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(sigPt, radiusPx, fillPaint);

        final borderPaint = Paint()
          ..color = (activeSig.state == SignalState.greenPriority ? const Color(0xFF00E676) : const Color(0xFFFFB300))
              .withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(sigPt, radiusPx, borderPaint);
      }
    }

    // 5. Junction Dots for non-signal nodes
    final junctionPaint = Paint()..color = const Color(0xFF37474F);
    for (final node in graph.nodes.values) {
      if (!node.hasSignal) {
        final pt = projection.toCanvas(node.lat, node.lon);
        canvas.drawCircle(pt, 3.5, junctionPaint);
      }
    }

    // 6. Draw Traffic Signals
    for (final sig in signals) {
      final pt = projection.toCanvas(sig.lat, sig.lon);
      final isPriority = sig.state == SignalState.greenPriority;
      final isPending = sig.state == SignalState.pendingGreen;
      final isOverridden = sig.isOverridden;

      Color bulbColor;
      switch (sig.state) {
        case SignalState.greenPriority:
          bulbColor = const Color(0xFF00E676);
          break;
        case SignalState.pendingGreen:
          bulbColor = const Color(0xFFFFC107);
          break;
        case SignalState.green:
          bulbColor = const Color(0xFF4CAF50);
          break;
        case SignalState.red:
          bulbColor = const Color(0xFFE53935);
          break;
      }

      // Outer glow for priority green or pending
      if (isPriority) {
        final haloPaint = Paint()
          ..color = const Color(0xFF00E676).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0;
        canvas.drawCircle(pt, 16.0, haloPaint);
      } else if (isPending) {
        final haloPaint = Paint()
          ..color = const Color(0xFFFFC107).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;
        canvas.drawCircle(pt, 14.0, haloPaint);
      }

      // Base circle housing
      final housingPaint = Paint()..color = const Color(0xFF212121);
      canvas.drawCircle(pt, 11.0, housingPaint);

      // Bulb circle
      final bulbPaint = Paint()..color = bulbColor;
      canvas.drawCircle(pt, isPriority ? 8.5 : 7.0, bulbPaint);

      // Purple ring for officer override
      if (isOverridden) {
        final overridePaint = Paint()
          ..color = const Color(0xFFAB47BC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(pt, 13.0, overridePaint);
      }

      // Signal ID label above marker
      _drawText(
        canvas: canvas,
        text: sig.id,
        position: Offset(pt.dx, pt.dy - 19),
        color: isPriority ? const Color(0xFF00E676) : Colors.white70,
        fontSize: 10,
        isBold: true,
      );
    }

    // 7. Hospitals (White square with red cross)
    for (final hosp in graph.hospitals) {
      final node = graph.nodes[hosp.nodeId];
      if (node == null) continue;
      final pt = projection.toCanvas(node.lat, node.lon);

      final isTarget = hosp.id == targetHospital?.id;

      // Hospital Box
      final boxRect = Rect.fromCenter(center: pt, width: 24, height: 24);
      final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(5));
      final boxPaint = Paint()..color = Colors.white;
      canvas.drawRRect(rrect, boxPaint);

      final borderPaint = Paint()
        ..color = isTarget ? Colors.redAccent : Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = isTarget ? 2.5 : 1.5;
      canvas.drawRRect(rrect, borderPaint);

      // Red Cross inside
      final crossPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(Offset(pt.dx - 6, pt.dy), Offset(pt.dx + 6, pt.dy), crossPaint);
      canvas.drawLine(Offset(pt.dx, pt.dy - 6), Offset(pt.dx, pt.dy + 6), crossPaint);

      // Label below
      _drawText(
        canvas: canvas,
        text: '${hosp.id}: ${hosp.name}',
        position: Offset(pt.dx, pt.dy + 17),
        color: Colors.white,
        fontSize: 10,
        isBold: true,
      );
    }

    // 8. Start Node (Green flag marker)
    if (startNodeId != null && graph.nodes[startNodeId] != null) {
      final startNode = graph.nodes[startNodeId]!;
      final sPt = projection.toCanvas(startNode.lat, startNode.lon);

      final startPaint = Paint()..color = const Color(0xFF00E676);
      canvas.drawCircle(sPt, 7.0, startPaint);

      final startRing = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(sPt, 7.0, startRing);

      _drawText(
        canvas: canvas,
        text: 'START',
        position: Offset(sPt.dx, sPt.dy - 16),
        color: const Color(0xFF00E676),
        fontSize: 9,
        isBold: true,
      );
    }

    // 9. Ambulance (Rotating pointer with glow)
    final aPt = projection.toCanvas(ambulance.lat, ambulance.lon);

    // Glow halo
    final ambGlow = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(aPt, 16.0, ambGlow);

    // Base body circle
    final ambBody = Paint()..color = const Color(0xFFE53935);
    canvas.drawCircle(aPt, 10.0, ambBody);

    final ambBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(aPt, 10.0, ambBorder);

    // Directional Pointer Arrow
    canvas.save();
    canvas.translate(aPt.dx, aPt.dy);
    canvas.rotate((ambulance.headingDegrees - 90.0) * (math.pi / 180.0));

    final arrowPath = Path();
    arrowPath.moveTo(12.0, 0.0);
    arrowPath.lineTo(4.0, -5.0);
    arrowPath.lineTo(4.0, 5.0);
    arrowPath.close();

    final arrowPaint = Paint()..color = Colors.white;
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.restore();
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLength = 8.0,
    double dashSpace = 6.0,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double currentDist = 0.0;
    while (currentDist < distance) {
      final startX = p1.dx + (unitX * currentDist);
      final startY = p1.dy + (unitY * currentDist);
      final endDist = math.min(currentDist + dashLength, distance);
      final endX = p1.dx + (unitX * endDist);
      final endY = p1.dy + (unitY * endDist);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
      currentDist += dashLength + dashSpace;
    }
  }

  void _drawText({
    required Canvas canvas,
    required String text,
    required Offset position,
    required Color color,
    required double fontSize,
    bool isBold = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - (textPainter.width / 2.0), position.dy - (textPainter.height / 2.0)),
    );
  }

  @override
  bool shouldRepaint(covariant SchematicGraphPainter oldDelegate) {
    return true; // repaints smoothly driven by controller
  }
}
