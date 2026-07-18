import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../domain/services/ar_server_service.dart';

class ArRecorderScreen extends StatefulWidget {
  const ArRecorderScreen({super.key});

  @override
  State<ArRecorderScreen> createState() => _ArRecorderScreenState();
}

class _ArRecorderScreenState extends State<ArRecorderScreen> {
  // Config
  String _serverUrl = "http://localhost:9000";
  bool _isServerOnline = false;
  bool _isLoading = false;
  String? _activeSessionId;

  // Telemetry (Simulated or native sensors)
  double _gyroHeading = 0.0;
  int _stepCount = 0;
  double _gpsLat = 13.0827;
  double _gpsLng = 80.2707;

  // Active Twin Graph Map
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _edges = [];
  String? _selectedNodeId;
  String? _linkStartNodeId;

  // Interactive Map Settings
  final TransformationController _mapTransformationController = TransformationController();
  bool _isPlacingMarkerMode = false;
  bool _isDrawingRoadMode = false;

  // AR Scanner Simulation State
  bool _isRecording = false;
  bool _isArViewActive = false;
  List<Map<String, dynamic>> _localizationCandidates = [];
  Map<String, dynamic>? _activeNavigationResult;
  String? _navStartNodeId;
  String? _navEndNodeId;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _startTelemetryLoop();
  }

  Future<void> _loadConfig() async {
    final url = await ArServerService.getServerUrl();
    setState(() => _serverUrl = url);
    _checkServer();
  }

  Future<void> _checkServer() async {
    final online = await ArServerService.checkServerStatus(_serverUrl);
    setState(() => _isServerOnline = online);
    if (online) {
      _fetchDigitalTwin();
    }
  }

  Future<void> _fetchDigitalTwin() async {
    final twin = await ArServerService.fetchDigitalTwin(_serverUrl);
    if (twin != null) {
      setState(() {
        _nodes = List<Map<String, dynamic>>.from(twin['nodes'] ?? []);
        _edges = List<Map<String, dynamic>>.from(twin['edges'] ?? []);
      });
    }
  }

  void _startTelemetryLoop() {
    // Simulate real-time sensor updates for development
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return false;
      if (_isRecording) {
        setState(() {
          // Micro-movement simulation
          _gyroHeading = (_gyroHeading + (Random().nextDouble() * 10 - 5)) % 360;
          if (_gyroHeading < 0) _gyroHeading += 360;
          _stepCount += Random().nextInt(3);
          _gpsLat += (Random().nextDouble() - 0.5) * 0.0001;
          _gpsLng += (Random().nextDouble() - 0.5) * 0.0001;
        });
      }
      return true;
    });
  }

  Future<void> _syncFirebaseUrl() async {
    setState(() => _isLoading = true);
    final resolvedUrl = await ArServerService.fetchLiveUrlFromFirebase();
    setState(() => _isLoading = false);
    if (resolvedUrl != null) {
      setState(() => _serverUrl = resolvedUrl);
      await ArServerService.setServerUrl(resolvedUrl);
      _checkServer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Resolved live URL: $resolvedUrl"), backgroundColor: AppTheme.primary),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to resolve server URL from Firebase RTDB."), backgroundColor: AppTheme.danger),
      );
    }
  }

  // Create Place / Landmark
  Future<void> _registerLandmarkAtPoint(double mapX, double mapY) async {
    if (!_isServerOnline) return;

    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Register Visual Place (Landmark)"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Place Name",
                  hintText: "e.g., Boiler Room Valve A",
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Saving this place captures visual features & coordinates to the SQLite visual localization base.",
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _saveLandmarkToServer(name, mapX, mapY);
                }
              },
              child: const Text("Capture & Register"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveLandmarkToServer(String name, double mapX, double mapY) async {
    setState(() => _isLoading = true);

    // Mock high-quality JPEG capturing (solid color pattern with noise to extract mock features)
    final landmarkId = "lm_${const Uuid().v4().substring(0, 8)}";
    final nodeId = "node_${const Uuid().v4().substring(0, 8)}";

    // Create solid test image bytes
    final imgBytes = Uint8List.fromList(List.generate(1000, (index) => index % 256));

    // Register node waypoint first
    await ArServerService.addWaypoint(
      baseUrl: _serverUrl,
      waypointId: nodeId,
      telemetry: {"gps_lat": _gpsLat, "gps_lng": _gpsLng, "mapX": mapX, "mapY": mapY},
    );

    // Register landmark visual features
    final res = await ArServerService.addLandmark(
      baseUrl: _serverUrl,
      landmarkId: landmarkId,
      name: name,
      graphNodeId: nodeId,
      heading: _gyroHeading,
      steps: _stepCount,
      lat: _gpsLat,
      lng: _gpsLng,
      imageBytes: imgBytes,
    );

    setState(() => _isLoading = false);

    if (res != null) {
      _fetchDigitalTwin();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Successfully registered place '$name' locally!"), backgroundColor: AppTheme.primary),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to register place. Ensure Vision Server is online."), backgroundColor: AppTheme.danger),
      );
    }
  }

  // Draw Road / Edge
  Future<void> _createRoad(String startId, String endId) async {
    final instController = TextEditingController(text: "Go Straight");
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Create Road/Connection"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: instController,
                decoration: const InputDecoration(
                  labelText: "Routing Instruction",
                  hintText: "e.g., Turn right at corner",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _linkStartNodeId = null);
                Navigator.pop(context);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final instruction = instController.text.trim();
                Navigator.pop(context);
                _saveRoad(startId, endId, instruction);
              },
              child: const Text("Create Road"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveRoad(String startId, String endId, String instruction) async {
    setState(() => _isLoading = true);
    final edgeId = "edge_${const Uuid().v4().substring(0, 8)}";
    final dist = Random().nextDouble() * 30 + 10; // Simulated distance feet

    final success = await ArServerService.addEdge(
      baseUrl: _serverUrl,
      edgeId: edgeId,
      startNodeId: startId,
      endNodeId: endId,
      distance: dist,
      instruction: instruction,
      expectedHeading: _gyroHeading,
    );

    setState(() {
      _linkStartNodeId = null;
      _isLoading = false;
    });

    if (success) {
      _fetchDigitalTwin();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Road connecting points established successfully."), backgroundColor: AppTheme.primary),
      );
    }
  }

  // Visual Localization Matcher
  Future<void> _triggerLocalization() async {
    if (!_isServerOnline) return;
    setState(() => _isLoading = true);
    
    // Captured query test image bytes
    final imgBytes = Uint8List.fromList(List.generate(1000, (index) => (index + 20) % 256));

    final candidates = await ArServerService.localize(
      baseUrl: _serverUrl,
      heading: _gyroHeading,
      steps: _stepCount,
      lat: _gpsLat,
      lng: _gpsLng,
      imageBytes: imgBytes,
    );

    setState(() => _isLoading = false);

    if (candidates != null && candidates.isNotEmpty) {
      setState(() {
        _localizationCandidates = List<Map<String, dynamic>>.from(candidates);
        _navStartNodeId = candidates[0]['graph_node_id'];
      });
      _showLocalizationResultDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Localization Match failed. No matching Visual Landmarks found."), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _showLocalizationResultDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Visual Localization Result"),
          content: SizedBox(
            width: 320,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _localizationCandidates.length,
              itemBuilder: (context, index) {
                final cand = _localizationCandidates[index];
                return ListTile(
                  leading: const Icon(Icons.pin_drop, color: AppTheme.accent),
                  title: Text(cand['name'] ?? 'Unknown Node'),
                  subtitle: Text("Visual Conf: ${cand['confidence']}% • Fused: ${cand['final_score']}%"),
                  trailing: index == 0
                      ? const Chip(label: Text("Best Match"), backgroundColor: AppTheme.primary)
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  // Fetch Navigation Route
  Future<void> _fetchRoute() async {
    if (_navStartNodeId == null || _navEndNodeId == null) return;
    setState(() => _isLoading = true);

    final route = await ArServerService.navigate(
      baseUrl: _serverUrl,
      startNodeId: _navStartNodeId!,
      endNodeId: _navEndNodeId!,
    );

    setState(() => _isLoading = false);

    if (route != null && (route['path'] as List).isNotEmpty) {
      setState(() {
        _activeNavigationResult = route;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No route matches found between selected places."), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // 1. Zoomable Custom Maps Canvas (Google Maps style)
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (details) {
                if (_isPlacingMarkerMode) {
                  // Translate touch coordinates to zoom space
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localOffset = box.globalToLocal(details.globalPosition);
                  _registerLandmarkAtPoint(localOffset.dx, localOffset.dy);
                }
              },
              child: InteractiveViewer(
                transformationController: _mapTransformationController,
                maxScale: 5.0,
                minScale: 0.5,
                child: Stack(
                  children: [
                    // Blueprint Grid View background
                    Container(
                      width: 2000,
                      height: 2000,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        image: DecorationImage(
                          image: const AssetImage('assets/icon.png'), // Fallback background
                          fit: BoxFit.none,
                          colorFilter: ColorFilter.mode(
                            Colors.black.withOpacity(0.08),
                            BlendMode.dstATop,
                          ),
                        ),
                      ),
                    ),

                    // Custom map coordinates grid
                    CustomPaint(
                      size: const Size(2000, 2000),
                      painter: _GridPainter(),
                    ),

                    // Render Roads (Edges)
                    ..._edges.map((edge) {
                      final startNode = _nodes.firstWhere((n) => n['id'] == edge['start'], orElse: () => {});
                      final endNode = _nodes.firstWhere((n) => n['id'] == edge['end'], orElse: () => {});
                      if (startNode.isEmpty || endNode.isEmpty) return const SizedBox();

                      // Read coordinates
                      final startX = _getNodeX(startNode);
                      final startY = _getNodeY(startNode);
                      final endX = _getNodeX(endNode);
                      final endY = _getNodeY(endNode);

                      // Highlighting active path edges in routing mode
                      bool isHighlighted = false;
                      if (_activeNavigationResult != null) {
                        final path = _activeNavigationResult!['path'] as List;
                        for (int i = 0; i < path.length - 1; i++) {
                          if ((path[i]['id'] == edge['start'] && path[i+1]['id'] == edge['end']) ||
                              (path[i]['id'] == edge['end'] && path[i+1]['id'] == edge['start'])) {
                            isHighlighted = true;
                            break;
                          }
                        }
                      }

                      return Positioned(
                        left: 0,
                        top: 0,
                        child: CustomPaint(
                          size: const Size(2000, 2000),
                          painter: _RoadPainter(
                            startX: startX,
                            startY: startY,
                            endX: endX,
                            endY: endY,
                            isHighlighted: isHighlighted,
                          ),
                        ),
                      );
                    }),

                    // Render Places Markers (Nodes)
                    ..._nodes.map((node) {
                      final double x = _getNodeX(node);
                      final double y = _getNodeY(node);
                      final String nodeId = node['id'];
                      final bool isLandmark = node['is_landmark'] ?? false;

                      Color pinColor = isLandmark ? AppTheme.accent : AppTheme.secondary;
                      if (nodeId == _selectedNodeId) pinColor = AppTheme.primary;
                      if (nodeId == _linkStartNodeId) pinColor = AppTheme.accent;

                      return Positioned(
                        left: x - 18,
                        top: y - 18,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedNodeId = nodeId;
                            });

                            if (_isDrawingRoadMode) {
                              if (_linkStartNodeId == null) {
                                setState(() => _linkStartNodeId = nodeId);
                              } else if (_linkStartNodeId != nodeId) {
                                _createRoad(_linkStartNodeId!, nodeId);
                              }
                            }
                          },
                          child: Tooltip(
                            message: node['name'] ?? 'Place Node',
                            child: Icon(
                              isLandmark ? Icons.place : Icons.radio_button_checked,
                              color: pinColor,
                              size: 36,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          // 2. Mock Live AR Camera view overlay
          if (_isArViewActive)
            Positioned(
              left: 20,
              bottom: 120,
              width: 320,
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Simulated visual video frame background
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.camera_alt_outlined, color: Colors.white24, size: 48),
                      ),
                    ),
                    // Live camera matching targets
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lens, color: AppTheme.danger, size: 8),
                            SizedBox(width: 4),
                            Text("SIMULATED LENS", style: TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                    // Compass/Heading indicator
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.black.withOpacity(0.84),
                        child: Transform.rotate(
                          angle: _gyroHeading * (pi / 180),
                          child: const Icon(Icons.navigation_outlined, color: AppTheme.accent, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Side Controller Sheet (GMap-style Places and routing configurations)
          Positioned(
            right: 20,
            top: 20,
            bottom: 20,
            width: 380,
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server connection header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("LOCAL SPATIAL SERVER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary)),
                          Text(
                            _isServerOnline ? "ONLINE: $_serverUrl" : "OFFLINE",
                            style: TextStyle(
                              color: _isServerOnline ? AppTheme.primary : AppTheme.danger,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.sync),
                        onPressed: _syncFirebaseUrl,
                        tooltip: "Sync Server URL from Firebase RTDB",
                      )
                    ],
                  ),
                  const Divider(color: AppTheme.border),

                  // Map controls
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isPlacingMarkerMode = !_isPlacingMarkerMode;
                              _isDrawingRoadMode = false;
                            });
                          },
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: Text(_isPlacingMarkerMode ? "Active" : "Place Landmark"),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _isPlacingMarkerMode ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isDrawingRoadMode = !_isDrawingRoadMode;
                              _isPlacingMarkerMode = false;
                              _linkStartNodeId = null;
                            });
                          },
                          icon: const Icon(Icons.edit_road_outlined),
                          label: Text(_isDrawingRoadMode ? "Active" : "Draw Road"),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _isDrawingRoadMode ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dynamic place detail
                  if (_selectedNodeId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Selected Point",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primary),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() => _selectedNodeId = null),
                              )
                            ],
                          ),
                          Text("Node ID: $_selectedNodeId", style: const TextStyle(fontSize: 10)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _navStartNodeId = _selectedNodeId;
                                  });
                                },
                                child: const Text("Set as Start"),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _navEndNodeId = _selectedNodeId;
                                  });
                                },
                                child: const Text("Set as Dest"),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Telemetry board
                  const Text("SENSORS TELEMETRY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Heading: ${_gyroHeading.toStringAsFixed(1)}°"),
                      Text("Steps: $_stepCount"),
                      Text("GPS: ${_gpsLat.toStringAsFixed(4)}, ${_gpsLng.toStringAsFixed(4)}"),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Switch(
                        value: _isRecording,
                        onChanged: (val) {
                          setState(() => _isRecording = val);
                        },
                      ),
                      const Text("Record Sensors / Run Telemetry"),
                      const Spacer(),
                      IconButton(
                        icon: Icon(_isArViewActive ? Icons.videocam : Icons.videocam_off),
                        onPressed: () {
                          setState(() => _isArViewActive = !_isArViewActive);
                        },
                      )
                    ],
                  ),
                  const Divider(color: AppTheme.border),

                  // Route calculations
                  const Text("GMAP ROUTING SYSTEM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: _navStartNodeId,
                          hint: const Text("Start Place", style: TextStyle(fontSize: 11)),
                          isExpanded: true,
                          items: _nodes.map((n) {
                            return DropdownMenuItem<String>(
                              value: n['id'],
                              child: Text(n['name'] ?? 'Node', style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _navStartNodeId = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: _navEndNodeId,
                          hint: const Text("Destination Place", style: TextStyle(fontSize: 11)),
                          isExpanded: true,
                          items: _nodes.map((n) {
                            return DropdownMenuItem<String>(
                              value: n['id'],
                              child: Text(n['name'] ?? 'Node', style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _navEndNodeId = val),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _triggerLocalization,
                        icon: const Icon(Icons.my_location),
                        label: const Text("Auto Localize (Camera Match)"),
                      ),
                      ElevatedButton(
                        onPressed: _fetchRoute,
                        child: const Text("Find Route"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Active Directions / Instructions Panel
                  Expanded(
                    child: _activeNavigationResult != null
                        ? _buildDirectionsHud()
                        : const Center(
                            child: Text(
                              "No active path calculations. Start localization or select targets.",
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Loading banner
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionsHud() {
    final dist = _activeNavigationResult!['total_distance'] ?? 0.0;
    final insts = _activeNavigationResult!['instructions'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Directions (${dist.toStringAsFixed(1)} ft)",
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent),
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 14),
                onPressed: () {
                  setState(() {
                    _activeNavigationResult = null;
                  });
                },
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: insts.length,
              itemBuilder: (context, index) {
                final step = insts[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.arrow_forward, color: AppTheme.primary, size: 14),
                  title: Text(step['action'] ?? 'Go Straight'),
                  subtitle: Text("Expected Heading: ${step['heading']}°"),
                  trailing: Text("${(step['distance'] as num).toStringAsFixed(1)} ft"),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _getNodeX(Map<String, dynamic> node) {
    if (node.containsKey('telemetry_json')) {
      try {
        final Map<String, dynamic> telemetry = jsonDecode(node['sensor_snapshot_json'] ?? '{}');
        return (telemetry['mapX'] as num? ?? 100.0).toDouble();
      } catch (_) {}
    }
    // Fallback coordinates
    return 100.0 + (Random().nextDouble() * 300);
  }

  double _getNodeY(Map<String, dynamic> node) {
    if (node.containsKey('telemetry_json')) {
      try {
        final Map<String, dynamic> telemetry = jsonDecode(node['sensor_snapshot_json'] ?? '{}');
        return (telemetry['mapY'] as num? ?? 100.0).toDouble();
      } catch (_) {}
    }
    return 100.0 + (Random().nextDouble() * 300);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.border.withOpacity(0.3)
      ..strokeWidth = 1.0;

    const double step = 50.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoadPainter extends CustomPainter {
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final bool isHighlighted;

  _RoadPainter({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.isHighlighted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isHighlighted ? AppTheme.accent : AppTheme.border
      ..strokeWidth = isHighlighted ? 6.0 : 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
