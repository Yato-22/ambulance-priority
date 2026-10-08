import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ambulance_priority/data/sample_graph.dart';
import 'package:ambulance_priority/screens/hospital_screen.dart';
import 'package:ambulance_priority/simulation/simulation_controller.dart';
import 'package:ambulance_priority/widgets/schematic_graph_painter.dart';

void main() {
  group('HospitalScreen Mini Map Projection & Layout Tests', () {
    testWidgets('Mini map computes valid projection at 400x800 without collapsing to a point', (
      WidgetTester tester,
    ) async {
      // Set viewport to 400x800 as specified in requirement 7
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = SimulationController();
      addTearDown(() => controller.dispose());
      final graph = SampleGraphBuilder.build();
      controller.setGraph(graph);

      bool tappedMap = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<SimulationController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: HospitalScreen(
                onTapMap: () {
                  tappedMap = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the CustomPaint rendering the mini map
      final customPaintFinder = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is SchematicGraphPainter,
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as SchematicGraphPainter;

      // Verify compact mode is enabled for the mini map
      expect(painter.compact, isTrue);

      // Verify projection was computed and cached during paint
      expect(painter.lastProjection, isNotNull);
      final projection = painter.lastProjection!;

      // 1. Assert scale is strictly positive and non-zero
      expect(projection.scale, greaterThan(0.0));
      expect(projection.scale.isNaN, isFalse);
      expect(projection.scale.isInfinite, isFalse);

      // 2. Assert projected positions of two different nodes are NOT the same
      final node1 = graph.nodes[1]!;
      final node42 = graph.nodes[42]!;
      final p1 = projection.toCanvas(node1.lat, node1.lon);
      final p42 = projection.toCanvas(node42.lat, node42.lon);

      expect(p1, isNot(equals(p42)), reason: 'Node 1 and Node 42 must not collapse to the same point');
      expect((p1.dx - p42.dx).abs() + (p1.dy - p42.dy).abs(), greaterThan(50.0));

      // 3. Assert all projected points fall inside the canvas bounds
      final canvasSize = projection.canvasSize;
      expect(canvasSize.width, greaterThan(0.0));
      expect(canvasSize.height, equals(260.0)); // Fixed height

      for (final node in graph.nodes.values) {
        final pt = projection.toCanvas(node.lat, node.lon);
        expect(
          pt.dx,
          inInclusiveRange(0.0, canvasSize.width),
          reason: 'Node ${node.id} x=${pt.dx} must fall within [0, ${canvasSize.width}]',
        );
        expect(
          pt.dy,
          inInclusiveRange(0.0, canvasSize.height),
          reason: 'Node ${node.id} y=${pt.dy} must fall within [0, ${canvasSize.height}]',
        );
      }

      // 4. Test tapping mini map calls onTapMap callback
      await tester.tap(customPaintFinder);
      await tester.pumpAndSettle();
      expect(tappedMap, isTrue);

      // 5. Test height remains fixed at 260px after starting trip
      final sizeIdle = tester.getSize(customPaintFinder);
      expect(sizeIdle.height, equals(260.0));

      controller.startTrip();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sizeEnRoute = tester.getSize(customPaintFinder);
      expect(sizeEnRoute.height, equals(260.0), reason: 'Mini map height must not change when trip starts');
      controller.pauseTrip();
    });
  });
}
