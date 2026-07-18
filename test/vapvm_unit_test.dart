import 'package:flutter_test/flutter_test.dart';
import 'package:vapvm/core/utils/geometry_utils.dart';
import 'package:vapvm/features/blueprint/domain/models/shape_model.dart';
import 'package:vapvm/features/navigation/domain/models/node_model.dart';
import 'package:vapvm/features/navigation/domain/models/edge_model.dart';
import 'package:vapvm/features/navigation/domain/services/pathfinding_service.dart';
import 'package:vapvm/features/project/domain/models/project_model.dart';

void main() {
  group('Geometry & Scale Tests', () {
    const scale = 10.0; // 10 pixels = 1.0 foot

    test('Pixel to Foot conversions', () {
      expect(GeometryUtils.pxToFt(100.0, scale), 10.0);
      expect(GeometryUtils.pxToFt(5.0, scale), 0.5);
      expect(GeometryUtils.pxToFtOffset(const Offset(50, 80), scale), const Offset(5, 8));
    });

    test('Foot to Pixel conversions', () {
      expect(GeometryUtils.ftToPx(20.0, scale), 200.0);
      expect(GeometryUtils.ftToPxOffset(const Offset(3, 4), scale), const Offset(30, 40));
    });

    test('Grid snapping math', () {
      final point = const Offset(12.3, 17.8);
      // Snapping to nearest 5 ft grid
      final snapped = GeometryUtils.snapPoint(
        pointFt: point,
        snapToGrid: true,
        gridIntervalFt: 5.0,
        snapToPoints: false,
        existingPointsFt: [],
      );
      expect(snapped, const Offset(10.0, 20.0));
    });

    test('Endpoint snapping override', () {
      final point = const Offset(10.2, 19.8);
      final existingNode = const Offset(10.0, 20.0);
      
      final snapped = GeometryUtils.snapPoint(
        pointFt: point,
        snapToGrid: false,
        gridIntervalFt: 5.0,
        snapToPoints: true,
        existingPointsFt: [existingNode],
        snapThresholdFt: 2.0,
      );
      expect(snapped, existingNode);
    });
  });

  group('A* Pathfinding Tests', () {
    late List<NavigationNode> nodes;
    late List<NavigationEdge> edges;

    setUp(() {
      nodes = [
        NavigationNode(id: 'A', xFt: 0, yFt: 0, name: 'Node A'),
        NavigationNode(id: 'B', xFt: 10, yFt: 0, name: 'Node B'),
        NavigationNode(id: 'C', xFt: 10, yFt: 10, name: 'Node C'),
        NavigationNode(id: 'D', xFt: 0, yFt: 10, name: 'Node D'),
        NavigationNode(id: 'E', xFt: 100, yFt: 100, name: 'Node E'), // Isolated
      ];

      edges = [
        NavigationEdge(startNodeId: 'A', endNodeId: 'B', distance: 10.0),
        NavigationEdge(startNodeId: 'B', endNodeId: 'C', distance: 10.0),
        NavigationEdge(startNodeId: 'C', endNodeId: 'D', distance: 10.0),
        NavigationEdge(startNodeId: 'D', endNodeId: 'A', distance: 10.0),
      ];
    });

    test('Shortest path A -> C (via B or D)', () {
      final path = PathfindingService.findShortestPath(nodes, edges, 'A', 'C');
      expect(path.length, 3);
      expect(path.first.id, 'A');
      expect(path.last.id, 'C');
      
      // Should traverse either A->B->C or A->D->C since both are length 20
      final intermediateId = path[1].id;
      expect(intermediateId == 'B' || intermediateId == 'D', isTrue);
    });

    test('Pathfinding to disconnected node E returns empty', () {
      final path = PathfindingService.findShortestPath(nodes, edges, 'A', 'E');
      expect(path, isEmpty);
    });
  });

  group('JSON Model Mapping Tests', () {
    test('Project model mapping serializes and restores cleanly', () {
      final project = ProjectModel.empty('test-id', 'Test Refinery');
      
      // Add custom shape
      final shape = BlueprintShape(
        id: 'shape-1',
        type: ShapeType.wall,
        pointsFt: [const Offset(0, 0), const Offset(20, 0)],
        layer: 2,
      );

      final updatedProj = project.copyWith(shapes: [shape]);
      
      final jsonMap = updatedProj.toJson();
      final restoredProj = ProjectModel.fromJson(jsonMap);

      expect(restoredProj.id, 'test-id');
      expect(restoredProj.name, 'Test Refinery');
      expect(restoredProj.shapes.length, 1);
      expect(restoredProj.shapes.first.type, ShapeType.wall);
      expect(restoredProj.shapes.first.pointsFt.last.dx, 20.0);
    });
  });
}
