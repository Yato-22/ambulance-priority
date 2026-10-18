import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/ambulance.dart';
import '../models/graph_edge.dart';
import '../models/graph_node.dart';
import '../models/hospital.dart';
import '../models/road_graph.dart';
import '../models/traffic_signal.dart';
import '../theme/app_theme.dart';

/// Geographic bounding box for a graph or route.
class GraphBounds {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  const GraphBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  bool get isEmpty =>
      minLat.isInfinite ||
      maxLat.isInfinite ||
      minLon.isInfinite ||
      maxLon.isInfinite ||
      minLat > maxLat ||
      minLon > maxLon;

  factory GraphBounds.fromGraph(RoadGraph graph) {
    return GraphBounds.fromNodes(graph.nodes.values);
  }

  factory GraphBounds.fromNodes(Iterable<GraphNode> nodes) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;

    for (final node in nodes) {
      if (node.lat < minLat) minLat = node.lat;
      if (node.lat > maxLat) maxLat = node.lat;
      if (node.lon < minLon) minLon = node.lon;
      if (node.lon > maxLon) maxLon = node.lon;
    }

    return GraphBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
  }

  factory GraphBounds.fromPoints(Iterable<List<double>> points) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;

    for (final pt in points) {
      if (pt.length < 2) continue;
      if (pt[0] < minLat) minLat = pt[0];
      if (pt[0] > maxLat) maxLat = pt[0];
      if (pt[1] < minLon) minLon = pt[1];
      if (pt[1] > maxLon) maxLon = pt[1];
    }

    return GraphBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
  }
}

/// Pure projection helper mapping geographic coordinates to canvas pixel space.
class GraphProjection {
  final GraphBounds bounds;
  final Size canvasSize;
  final EdgeInsets padding;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double deltaYm;
  final double centerLat;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  const GraphProjection._({
    required this.bounds,
    required this.canvasSize,
    required this.padding,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.deltaYm,
    required this.centerLat,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  /// Fits [graphBounds] within [canvasSize] applying [padding].
  /// Returns null if the canvas size or bounds are invalid/degenerate.
  static GraphProjection? fit(
    GraphBounds graphBounds,
    Size canvasSize, [
    EdgeInsets padding = const EdgeInsets.all(24.0),
  ]) {
    if (graphBounds.isEmpty) return null;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return null;
    if (canvasSize.width.isNaN || canvasSize.height.isNaN) return null;
    if (canvasSize.width.isInfinite || canvasSize.height.isInfinite) return null;

    final availW = canvasSize.width - padding.horizontal;
    final availH = canvasSize.height - padding.vertical;
    if (availW <= 0 || availH <= 0) return null;

    double minLat = graphBounds.minLat;
    double maxLat = graphBounds.maxLat;
    double minLon = graphBounds.minLon;
    double maxLon = graphBounds.maxLon;

    // Expand degenerate bounds so we never divide by zero
    if ((maxLat - minLat).abs() < 1e-6) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if ((maxLon - minLon).abs() < 1e-6) {
      minLon -= 0.001;
      maxLon += 0.001;
    }

    final centerLat = (minLat + maxLat) / 2.0;
    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(centerLat * (math.pi / 180.0));

    final deltaXm = (maxLon - minLon) * mPerLon;
    final deltaYm = (maxLat - minLat) * mPerLat;

    if (deltaXm <= 0 || deltaYm <= 0) return null;

    final scaleX = availW / deltaXm;
    final scaleY = availH / deltaYm;
    final scale = math.min(scaleX, scaleY);

    if (scale <= 0 || scale.isNaN || scale.isInfinite) return null;

    final effectiveW = deltaXm * scale;
    final effectiveH = deltaYm * scale;

    final offsetX = padding.left + (availW - effectiveW) / 2.0;
    final offsetY = padding.top + (availH - effectiveH) / 2.0;

    return GraphProjection._(
      bounds: graphBounds,
      canvasSize: canvasSize,
      padding: padding,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      deltaYm: deltaYm,
      centerLat: centerLat,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );
  }

  /// Factory constructor preserved for backward-compatibility with tests & MapScreen.
  factory GraphProjection.fromGraph(
    RoadGraph graph, {
    double width = 1000.0,
    double height = 900.0,
    double padding = 90.0,
  }) {
    final bounds = GraphBounds.fromGraph(graph);
    final proj = GraphProjection.fit(
      bounds,
      Size(width, height),
      EdgeInsets.all(padding),
    );
    if (proj != null) return proj;

    return GraphProjection._(
      bounds: bounds,
      canvasSize: Size(width, height),
      padding: EdgeInsets.all(padding),
      scale: 1.0,
      offsetX: 0.0,
      offsetY: 0.0,
      deltaYm: 1000.0,
      centerLat: 0.0,
      minLat: 0.0,
      maxLat: 0.0,
      minLon: 0.0,
      maxLon: 0.0,
    );
  }

  Offset toCanvas(double lat, double lon) {
    const mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(centerLat * (math.pi / 180.0));

    final xm = (lon - minLon) * mPerLon;
    final ym = (lat - minLat) * mPerLat;

    final cx = offsetX + (xm * scale);
    final cy = offsetY + ((deltaYm - ym) * scale); // Flip y so north is up
    return Offset(cx, cy);
  }

  double metersToPixels(double meters) => meters * scale;
}

/// Backwards compatibility alias for CanvasProjection.
typedef CanvasProjection = GraphProjection;

/// CustomPainter that renders the road graph, signals, hospitals, and ambulance
/// on a high-performance dark schematic canvas.
/// Supports [compact] mode for the hospital screen's overview mini map.
class SchematicGraphPainter extends CustomPainter {
  final RoadGraph graph;
  final GraphProjection? projection;
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
  final bool compact;
  final EdgeInsets? padding;
  final bool isHeldAtSignal;
  final String? heldSignalId;
  final MapColors mapColors;

  /// Holds the projection computed during the most recent paint call.
  GraphProjection? lastProjection;

  SchematicGraphPainter({
    required this.graph,
    this.projection,
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
    this.compact = false,
    this.padding,
    this.isHeldAtSignal = false,
    this.heldSignalId,
    this.mapColors = MapColors.dark,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Determine bounding box: frame the active route during a trip, or whole graph when idle
    GraphBounds bounds;
    if (compact && (isEnRoute || routePolyline.length > 1)) {
      final pts = <List<double>>[...routePolyline];
      pts.add([ambulance.lat, ambulance.lon]);
      if (targetHospital != null && graph.nodes[targetHospital!.nodeId] != null) {
        final hNode = graph.nodes[targetHospital!.nodeId]!;
        pts.add([hNode.lat, hNode.lon]);
      }
      bounds = GraphBounds.fromPoints(pts);
    } else {
      bounds = GraphBounds.fromGraph(graph);
    }

    if (bounds.isEmpty) return;

    final projPadding = padding ?? (compact ? const EdgeInsets.all(22.0) : const EdgeInsets.all(90.0));
    final effectiveProjection = (compact || projection == null)
        ? GraphProjection.fit(bounds, size, projPadding)
        : projection!;

    if (effectiveProjection == null ||
        effectiveProjection.scale <= 0 ||
        effectiveProjection.scale.isNaN ||
        effectiveProjection.scale.isInfinite) {
      return;
    }

    lastProjection = effectiveProjection;

    // 1. Background
    final bgPaint = Paint()..color = mapColors.background;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (!compact) {
      final dotPaint = Paint()
        ..color = mapColors.gridDot
        ..strokeWidth = 1.0;
      for (double x = 20; x < size.width; x += 35) {
        for (double y = 20; y < size.height; y += 35) {
          canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
        }
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

      final p1 = effectiveProjection.toCanvas(uNode.lat, uNode.lon);
      final p2 = effectiveProjection.toCanvas(vNode.lat, vNode.lon);

      Color roadColor;
      double strokeWidth;

      final isMajor = edge.isMajor;

      switch (edge.state) {
        case RoadState.open:
          roadColor = mapColors.openRoad;
          strokeWidth = isMajor ? (compact ? 2.5 : 4.5) : (compact ? 1.4 : 2.2);
          break;
        case RoadState.moderate:
          roadColor = mapColors.moderateRoad;
          strokeWidth = isMajor ? (compact ? 3.2 : 5.5) : (compact ? 1.8 : 3.0);
          break;
        case RoadState.heavy:
          roadColor = mapColors.heavyRoad;
          strokeWidth = isMajor ? (compact ? 3.8 : 6.5) : (compact ? 2.2 : 3.6);
          break;
        case RoadState.blocked:
          roadColor = mapColors.blockedRoad;
          strokeWidth = isMajor ? (compact ? 3.0 : 5.0) : (compact ? 1.8 : 3.0);
          break;
      }

      if (!compact && highlightedRoadKey != null && pairKey == highlightedRoadKey) {
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
        _drawDashedLine(
          canvas,
          p1,
          p2,
          roadPaint,
          dashLength: compact ? 5.0 : 8.0,
          dashSpace: compact ? 4.0 : 6.0,
        );
      } else {
        canvas.drawLine(p1, p2, roadPaint);
      }

      // Draw direction arrow for one-way roads
      if (edge.direction == RoadDirection.oneWay) {
        _drawOneWayArrow(canvas, p1, p2, compact, mapColors);
      }
    }

    // 3. Draw Active Route Polyline
    if (routePolyline.length > 1) {
      final routePath = Path();
      final p0 = effectiveProjection.toCanvas(routePolyline[0][0], routePolyline[0][1]);
      routePath.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < routePolyline.length; i++) {
        final pt = effectiveProjection.toCanvas(routePolyline[i][0], routePolyline[i][1]);
        routePath.lineTo(pt.dx, pt.dy);
      }

      final routePaint = Paint()
        ..color = mapColors.route
        ..strokeWidth = compact ? 3.5 : 6.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(routePath, routePaint);

      // Draw already-travelled portion
      final segIdx = ambulance.polylineSegmentIndex;
      if (segIdx > 0 && segIdx < routePolyline.length) {
        final traveledPath = Path();
        traveledPath.moveTo(p0.dx, p0.dy);
        for (int i = 1; i <= segIdx; i++) {
          final pt = effectiveProjection.toCanvas(routePolyline[i][0], routePolyline[i][1]);
          traveledPath.lineTo(pt.dx, pt.dy);
        }
        final ambPt = effectiveProjection.toCanvas(ambulance.lat, ambulance.lon);
        traveledPath.lineTo(ambPt.dx, ambPt.dy);

        final traveledPaint = Paint()
          ..color = mapColors.routeTravelled
          ..strokeWidth = compact ? 3.5 : 6.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(traveledPath, traveledPaint);
      }
    }

    // 4. Trigger Radius Circle around Next Active Signal (full mode only)
    if (!compact && isEnRoute && activeSignalId != null) {
      final activeSig = signals.cast<TrafficSignal?>().firstWhere(
            (s) => s?.id == activeSignalId,
            orElse: () => null,
          );
      if (activeSig != null) {
        final sigPt = effectiveProjection.toCanvas(activeSig.lat, activeSig.lon);
        final radiusPx = effectiveProjection.metersToPixels(triggerRadiusM);
        final triggerColor = activeSig.state == SignalState.greenPriority
            ? mapColors.triggerRadiusGreen
            : mapColors.triggerRadiusYellow;

        final fillPaint = Paint()
          ..color = triggerColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(sigPt, radiusPx, fillPaint);

        final borderPaint = Paint()
          ..color = triggerColor.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(sigPt, radiusPx, borderPaint);
      }
    }

    // 5. Junction Dots for non-signal nodes
    final junctionPaint = Paint()..color = mapColors.junctionDot;
    for (final node in graph.nodes.values) {
      if (!node.hasSignal) {
        final pt = effectiveProjection.toCanvas(node.lat, node.lon);
        canvas.drawCircle(pt, compact ? 1.5 : 3.5, junctionPaint);
      }
    }

    // 6. Draw Traffic Signals
    for (final sig in signals) {
      final pt = effectiveProjection.toCanvas(sig.lat, sig.lon);
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

      if (compact) {
        // Compact mini map: signals as small colored dots with NO text labels
        canvas.drawCircle(pt, 3.5, Paint()..color = bulbColor);
        if (isPriority) {
          canvas.drawCircle(
            pt,
            6.0,
            Paint()
              ..color = const Color(0xFF00E676).withValues(alpha: 0.4)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      } else {
        // Full mode: halo, housing, bulb, override ring, and ID label
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

        final housingPaint = Paint()..color = mapColors.signalHousing;
        canvas.drawCircle(pt, 11.0, housingPaint);

        if (mapColors.signalBorder != Colors.transparent) {
          final outlinePaint = Paint()
            ..color = mapColors.signalBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          canvas.drawCircle(pt, 11.0, outlinePaint);
        }

        final bulbPaint = Paint()..color = bulbColor;
        canvas.drawCircle(pt, isPriority ? 8.5 : 7.0, bulbPaint);

        if (isOverridden) {
          final overridePaint = Paint()
            ..color = mapColors.signalOverrideRing
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5;
          canvas.drawCircle(pt, 13.0, overridePaint);
        }

        _drawText(
          canvas: canvas,
          text: sig.id,
          position: Offset(pt.dx, pt.dy - 19),
          color: isPriority ? const Color(0xFF00E676) : mapColors.labelChipText,
          chipBackground: mapColors.labelChipBackground,
          chipBorder: mapColors.labelChipBorder,
          fontSize: 10,
          isBold: true,
        );
      }

      final isHeldSig = sig.id == heldSignalId;
      if (isHeldSig) {
        final heldGlow = Paint()
          ..color = mapColors.heldGlow
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, compact ? 12.0 : 22.0, heldGlow);

        final heldRing = Paint()
          ..color = mapColors.heldRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 2.5 : 3.5;
        canvas.drawCircle(pt, compact ? 10.0 : 18.0, heldRing);
      }
    }

    // 7. Hospitals (White square with red cross)
    for (final hosp in graph.hospitals) {
      final node = graph.nodes[hosp.nodeId];
      if (node == null) continue;
      final pt = effectiveProjection.toCanvas(node.lat, node.lon);
      final isTarget = hosp.id == targetHospital?.id;

      if (compact) {
        // Mini map: destination hospital clearly visible with name below
        final boxSize = isTarget ? 22.0 : 16.0;
        final boxRect = Rect.fromCenter(center: pt, width: boxSize, height: boxSize);
        final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(4));
        canvas.drawRRect(rrect, Paint()..color = mapColors.hospitalBoxBackground);
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = isTarget ? Colors.redAccent : mapColors.hospitalBoxBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = isTarget ? 2.0 : 1.0,
        );

        final crossLen = isTarget ? 5.0 : 3.5;
        final crossPaint = Paint()
          ..color = mapColors.hospitalCross
          ..strokeWidth = isTarget ? 2.5 : 1.8
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(Offset(pt.dx - crossLen, pt.dy), Offset(pt.dx + crossLen, pt.dy), crossPaint);
        canvas.drawLine(Offset(pt.dx, pt.dy - crossLen), Offset(pt.dx, pt.dy + crossLen), crossPaint);

        // Only ONE label: the destination hospital name, placed below its icon
        if (isTarget) {
          _drawText(
            canvas: canvas,
            text: hosp.name,
            position: Offset(pt.dx, pt.dy + 17),
            color: mapColors.labelChipText,
            chipBackground: mapColors.labelChipBackground,
            chipBorder: mapColors.labelChipBorder,
            fontSize: 10,
            isBold: true,
          );
        }
      } else {
        // Full mode: all hospitals with labels
        final boxRect = Rect.fromCenter(center: pt, width: 24, height: 24);
        final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(5));
        final boxPaint = Paint()..color = mapColors.hospitalBoxBackground;
        canvas.drawRRect(rrect, boxPaint);

        final borderPaint = Paint()
          ..color = isTarget ? Colors.redAccent : mapColors.hospitalBoxBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = isTarget ? 2.5 : 1.5;
        canvas.drawRRect(rrect, borderPaint);

        final crossPaint = Paint()
          ..color = mapColors.hospitalCross
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(Offset(pt.dx - 6, pt.dy), Offset(pt.dx + 6, pt.dy), crossPaint);
        canvas.drawLine(Offset(pt.dx, pt.dy - 6), Offset(pt.dx, pt.dy + 6), crossPaint);

        _drawText(
          canvas: canvas,
          text: '${hosp.id}: ${hosp.name}',
          position: Offset(pt.dx, pt.dy + 17),
          color: mapColors.labelChipText,
          chipBackground: mapColors.labelChipBackground,
          chipBorder: mapColors.labelChipBorder,
          fontSize: 10,
          isBold: true,
        );
      }
    }

    // 8. Start Node (Only in full mode, removed in compact mode)
    if (!compact && startNodeId != null && graph.nodes[startNodeId] != null) {
      final startNode = graph.nodes[startNodeId]!;
      final sPt = effectiveProjection.toCanvas(startNode.lat, startNode.lon);

      final startPaint = Paint()..color = mapColors.startCircleFill;
      canvas.drawCircle(sPt, 7.0, startPaint);

      final startRing = Paint()
        ..color = mapColors.startCircleBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(sPt, 7.0, startRing);

      _drawText(
        canvas: canvas,
        text: 'START',
        position: Offset(sPt.dx, sPt.dy - 16),
        color: mapColors.startText,
        chipBackground: mapColors.labelChipBackground,
        chipBorder: mapColors.labelChipBorder,
        fontSize: 9,
        isBold: true,
      );
    }

    // 9. Ambulance (Rotating pointer or amber pause icon when held)
    final aPt = effectiveProjection.toCanvas(ambulance.lat, ambulance.lon);

    final ambRadius = compact ? 8.0 : 10.0;
    final glowRadius = compact ? 13.0 : 16.0;

    final haloColor = isHeldAtSignal ? Colors.amberAccent : mapColors.ambulanceHalo;
    final bodyColor = isHeldAtSignal ? const Color(0xFFFFA000) : mapColors.ambulanceBody;

    // Glow halo
    canvas.drawCircle(
      aPt,
      glowRadius,
      Paint()
        ..color = isHeldAtSignal ? haloColor.withValues(alpha: 0.45) : haloColor
        ..style = PaintingStyle.fill,
    );

    // Base body circle
    canvas.drawCircle(aPt, ambRadius, Paint()..color = bodyColor);

    // Border
    canvas.drawCircle(
      aPt,
      ambRadius,
      Paint()
        ..color = mapColors.ambulanceBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.5 : 2.0,
    );

    if (isHeldAtSignal) {
      // Pause icon (||)
      final pausePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = compact ? 1.8 : 2.2
        ..strokeCap = StrokeCap.round;
      final barH = compact ? 3.5 : 4.5;
      final barSpacing = compact ? 2.2 : 3.0;
      canvas.drawLine(Offset(aPt.dx - barSpacing, aPt.dy - barH), Offset(aPt.dx - barSpacing, aPt.dy + barH), pausePaint);
      canvas.drawLine(Offset(aPt.dx + barSpacing, aPt.dy - barH), Offset(aPt.dx + barSpacing, aPt.dy + barH), pausePaint);
    } else {
      // Directional Pointer Arrow
      canvas.save();
      canvas.translate(aPt.dx, aPt.dy);
      canvas.rotate((ambulance.headingDegrees - 90.0) * (math.pi / 180.0));

      final arrowPath = Path();
      final arrowLen = compact ? 9.0 : 12.0;
      final arrowHalfW = compact ? 3.5 : 5.0;
      final arrowBack = compact ? 3.0 : 4.0;
      arrowPath.moveTo(arrowLen, 0.0);
      arrowPath.lineTo(arrowBack, -arrowHalfW);
      arrowPath.lineTo(arrowBack, arrowHalfW);
      arrowPath.close();

      final arrowPaint = Paint()..color = mapColors.ambulanceBorder;
      canvas.drawPath(arrowPath, arrowPaint);
      canvas.restore();
    }
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

  void _drawOneWayArrow(
    Canvas canvas,
    Offset fromPt,
    Offset toPt,
    bool compact,
    MapColors mapColors,
  ) {
    final dx = toPt.dx - fromPt.dx;
    final dy = toPt.dy - fromPt.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 18.0) return;

    final ux = dx / dist;
    final uy = dy / dist;
    final nx = -uy;
    final ny = ux;

    final arrowLen = compact ? 4.5 : 7.0;
    final arrowHalfW = compact ? 3.0 : 4.5;

    final midX = fromPt.dx + dx * 0.5;
    final midY = fromPt.dy + dy * 0.5;

    final tip = Offset(midX + ux * arrowLen * 0.6, midY + uy * arrowLen * 0.6);
    final left = Offset(midX - ux * arrowLen * 0.4 + nx * arrowHalfW, midY - uy * arrowLen * 0.4 + ny * arrowHalfW);
    final indent = Offset(midX - ux * arrowLen * 0.1, midY - uy * arrowLen * 0.1);
    final right = Offset(midX - ux * arrowLen * 0.4 - nx * arrowHalfW, midY - uy * arrowLen * 0.4 - ny * arrowHalfW);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(indent.dx, indent.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    final isLight = mapColors.background == MapColors.light.background;
    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: isLight ? 0.95 : 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = isLight ? const Color(0xFF334155).withValues(alpha: 0.8) : Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(path, borderPaint);
  }

  void _drawText({
    required Canvas canvas,
    required String text,
    required Offset position,
    required Color color,
    Color? chipBackground,
    Color? chipBorder,
    required double fontSize,
    bool isBold = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
        shadows: (chipBackground == null || chipBackground == Colors.transparent)
            ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))]
            : null,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textW = textPainter.width;
    final textH = textPainter.height;

    if (chipBackground != null && chipBackground != Colors.transparent) {
      final chipRect = Rect.fromCenter(
        center: position,
        width: textW + 8.0,
        height: textH + 4.0,
      );
      final rrect = RRect.fromRectAndRadius(chipRect, const Radius.circular(4));
      canvas.drawRRect(rrect, Paint()..color = chipBackground);
      if (chipBorder != null && chipBorder != Colors.transparent) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = chipBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }

    textPainter.paint(
      canvas,
      Offset(position.dx - (textW / 2.0), position.dy - (textH / 2.0)),
    );
  }

  @override
  bool shouldRepaint(covariant SchematicGraphPainter oldDelegate) {
    return true; // repaints smoothly driven by controller
  }
}
