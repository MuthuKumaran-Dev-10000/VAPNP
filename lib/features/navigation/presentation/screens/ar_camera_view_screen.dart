import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/services/ar_server_service.dart';

class ArCameraViewScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const ArCameraViewScreen({super.key, required this.cameras});

  @override
  State<ArCameraViewScreen> createState() => _ArCameraViewScreenState();
}

class _ArCameraViewScreenState extends State<ArCameraViewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Camera controller
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // Connection Configuration
  String _serverUrl = "http://localhost:9000";
  bool _isServerOnline = false;
  bool _isLoading = false;
  bool _isLocalizing = false;

  // Viewport Pitch & Yaw controls (for mock mode only)
  double _cameraYaw = 0.0;
  double _cameraPitch = 0.0;

  // Active markers currently tracked in viewpoint
  List<Map<String, dynamic>> _trackedMarkers = [];
  Map<String, dynamic>? _selectedMarker;
  
  Timer? _matchingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConfig();
    _initializeCamera();
    _startSpatialLocalizationLoop();
  }

  @override
  void dispose() {
    _matchingTimer?.cancel();
    _tabController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final url = await ArServerService.getServerUrl();
    setState(() => _serverUrl = url);
    _checkServerConnection();
  }

  Future<void> _checkServerConnection() async {
    final online = await ArServerService.checkServerStatus(_serverUrl);
    setState(() => _isServerOnline = online);
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      debugPrint("No physical cameras available. Using camera simulation feed.");
      return;
    }

    _cameraController = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  Future<void> _pullFirebaseUrl() async {
    setState(() => _isLoading = true);
    final resolvedUrl = await ArServerService.fetchLiveUrlFromFirebase();
    setState(() => _isLoading = false);
    if (resolvedUrl != null) {
      setState(() => _serverUrl = resolvedUrl);
      await ArServerService.setServerUrl(resolvedUrl);
      _checkServerConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server endpoint configured: $resolvedUrl"), backgroundColor: AppTheme.primary),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not resolve dynamic URL. Verify Firebase credentials."), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  bool _isCapturing = false;

  /// Telemetry matching loop (runs every 3 seconds to allow auto-focus capture)
  void _startSpatialLocalizationLoop() {
    _matchingTimer = Timer.periodic(const Duration(milliseconds: 3000), (timer) async {
      if (!mounted) return;
      if (_isCapturing) return;

      if (_isServerOnline && !_isLoading) {
        final frameBytes = await _captureCurrentFrameBytes();
        if (frameBytes.isEmpty) return;

        setState(() => _isLocalizing = true);
        final markers = await ArServerService.localize(
          baseUrl: _serverUrl,
          imageBytes: frameBytes,
        );

        if (mounted) {
          setState(() {
            _isLocalizing = false;
            if (markers != null) {
              _trackedMarkers = List<Map<String, dynamic>>.from(markers);
            }
          });
        }
      }
    });
  }

  Future<Uint8List> _captureCurrentFrameBytes() async {
    if (_isCameraInitialized && _cameraController != null) {
      if (_isCapturing) {
        return Uint8List(0);
      }
      _isCapturing = true;
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        return bytes;
      } catch (e) {
        debugPrint("Error taking picture: $e");
      } finally {
        _isCapturing = false;
      }
      return Uint8List(0);
    }
    // Fallback simulated image contents
    final frameData = List<int>.generate(200, (index) => (index + _cameraYaw.toInt() + _cameraPitch.toInt()) % 256);
    return Uint8List.fromList(frameData);
  }

  // Handle tap to register a landmark
  void _triggerRegistrationAtCoordinate(TapUpDetails details, BoxConstraints constraints) {
    if (!_isServerOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vision server offline. Connect to register landmarks."), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final double relativeX = details.localPosition.dx / constraints.maxWidth;
    final double relativeY = details.localPosition.dy / constraints.maxHeight;

    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Register Place on Viewport"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Place/Landmark Name",
                  hintText: "e.g. Pump Valve Switch",
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: "Description",
                  hintText: "e.g. Turn off in case of high heat",
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Touch Coordinate: (${relativeX.toStringAsFixed(2)}, ${relativeY.toStringAsFixed(2)})",
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _savePlaceToServer(name, desc, relativeX, relativeY);
                }
              },
              child: const Text("Save Location"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePlaceToServer(String name, String desc, double rx, double ry) async {
    setState(() => _isLoading = true);

    final frameBytes = await _captureCurrentFrameBytes();
    final res = await ArServerService.addLandmark(
      baseUrl: _serverUrl,
      name: name,
      description: desc,
      touchX: rx,
      touchY: ry,
      imageBytes: frameBytes,
    );

    setState(() => _isLoading = false);

    if (res != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Visual place '$name' anchored successfully!"), backgroundColor: AppTheme.primary),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to register place. Check console logs."), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _onPinClicked(Map<String, dynamic> marker) async {
    setState(() {
      _selectedMarker = marker;
    });

    final frameBytes = await _captureCurrentFrameBytes();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LandmarkDetailsPage(
            marker: marker,
            otherMarkers: _trackedMarkers.where((m) => m['id'] != marker['id']).toList(),
            capturedImageBytes: frameBytes,
            serverUrl: _serverUrl,
            hasRealCamera: _isCameraInitialized,
          ),
        ),
      ).then((_) {
        setState(() {
          _selectedMarker = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AR Landmark Portal"),
        backgroundColor: AppTheme.surface,
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: "Open Settings Panel",
            );
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: "CREATE TAB"),
            Tab(text: "VIEW TAB"),
          ],
        ),
      ),
      // Left Drawer holding the configuration settings
      drawer: Drawer(
        child: Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text("SPATIAL AR PORTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary)),
              const SizedBox(height: 6),
              const Text("Dynamic camera vision matching system", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const Divider(color: AppTheme.border, height: 36),

              const Text("CONNECTION SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 5,
                    backgroundColor: _isServerOnline ? AppTheme.primary : AppTheme.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isServerOnline ? "Server Online: $_serverUrl" : "Offline: Run Python on 9000",
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: _serverUrl),
                decoration: const InputDecoration(
                  labelText: "Server Base IP/URL",
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onSubmitted: (val) {
                  setState(() => _serverUrl = val);
                  ArServerService.setServerUrl(val);
                  _checkServerConnection();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _checkServerConnection,
                      child: const Text("Ping"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pullFirebaseUrl,
                      child: const Text("Sync URL"),
                    ),
                  ),
                ],
              ),
              const Divider(color: AppTheme.border, height: 36),

              // Mock Camera Viewfinder Controls
              if (!_isCameraInitialized) ...[
                const Text("SIMULATION CONTROLS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 12),
                const Text("Slide to pan simulated camera angle:", style: TextStyle(fontSize: 11)),
                const SizedBox(height: 16),
                Text("Camera Yaw: ${_cameraYaw.toInt()}°"),
                Slider(
                  value: _cameraYaw,
                  min: -180.0,
                  max: 180.0,
                  onChanged: (val) {
                    setState(() => _cameraYaw = val);
                  },
                ),
                Text("Camera Pitch: ${_cameraPitch.toInt()}°"),
                Slider(
                  value: _cameraPitch,
                  min: -90.0,
                  max: 90.0,
                  onChanged: (val) {
                    setState(() => _cameraPitch = val);
                  },
                ),
                const Divider(color: AppTheme.border, height: 36),
              ],

              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close Drawer
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back to Viewfinder"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.border,
                  minimumSize: const Size.fromHeight(48),
                ),
              )
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Live camera viewport taking up 100% of the screen
          Positioned.fill(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCameraViewport(isCreate: true),
                _buildCameraViewport(isCreate: false),
              ],
            ),
          ),

          // 2. Localizing status banner
          if (_isLocalizing)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                    ),
                    SizedBox(width: 8),
                    Text("SIFT SCANNING CORRESPONDENCES...", style: TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold)),
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

  Widget _buildCameraViewport({required bool isCreate}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) {
            if (isCreate) {
              _triggerRegistrationAtCoordinate(details, constraints);
            }
          },
          child: Stack(
            children: [
              // Real Camera Feed or Fallback Simulator
              Positioned.fill(
                child: _isCameraInitialized && _cameraController != null
                    ? AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      )
                    : CustomPaint(
                        painter: _ViewfinderPainter(yaw: _cameraYaw, pitch: _cameraPitch),
                      ),
              ),

              // Render tracked visual keypoints (cloudpoints)
              ..._trackedMarkers.expand((marker) {
                final List<dynamic>? pts = marker['tracking_points'] as List<dynamic>?;
                if (pts == null) return <Widget>[];
                return pts.map((pt) {
                  final double px = (pt['x'] as num).toDouble() * constraints.maxWidth;
                  final double py = (pt['y'] as num).toDouble() * constraints.maxHeight;

                  return Positioned(
                    left: px - 2.5,
                    top: py - 2.5,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent,
                        boxShadow: [
                          BoxShadow(color: Colors.green, blurRadius: 4, spreadRadius: 1),
                        ],
                      ),
                    ),
                  );
                }).toList();
              }),

              // Renders projected landmark pin overlays
              ..._trackedMarkers.map((marker) {
                final double px = (marker['x'] as num).toDouble() * constraints.maxWidth;
                final double py = (marker['y'] as num).toDouble() * constraints.maxHeight;

                final bool isSelected = _selectedMarker != null && _selectedMarker!['id'] == marker['id'];

                return Positioned(
                  left: px - 20,
                  top: py - 20,
                  child: GestureDetector(
                    onTap: () {
                      if (!isCreate) {
                        _onPinClicked(marker);
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppTheme.accent.withOpacity(0.35)
                            : AppTheme.primary.withOpacity(0.2),
                        border: Border.all(
                          color: isSelected ? AppTheme.accent : AppTheme.primary,
                          width: isSelected ? 3.0 : 1.5,
                        ),
                      ),
                      child: Icon(
                        isSelected ? Icons.gps_fixed : Icons.place,
                        color: isSelected ? AppTheme.accent : AppTheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                );
              }),

              // Viewfinder crosshair overlay
              Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Mode indicators
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isCreate ? "TAP SCREEN TO CAPTURE & ANCHOR" : "VIEW MODE: PLACE FINDER ACTIVE",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final double yaw;
  final double pitch;

  _ViewfinderPainter({required this.yaw, required this.pitch});

  @override
  void paint(Canvas canvas, Size size) {
    // Backdrop background
    final bgPaint = Paint()..color = const Color(0xff090f1d);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = AppTheme.border.withOpacity(0.2)
      ..strokeWidth = 1.0;

    // Viewfinder grids translation simulation
    final double dx = (yaw * 3) % 80;
    final double dy = (pitch * 3) % 80;

    for (double i = dx; i < size.width; i += 80) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), linePaint);
    }
    for (double i = dy; i < size.height; i += 80) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), linePaint);
    }

    // Keypoints feature circles simulation
    final rnd = Random(123);
    for (int i = 0; i < 30; i++) {
      final double x = (rnd.nextDouble() * size.width + (yaw * 2)) % size.width;
      final double y = (rnd.nextDouble() * size.height + (pitch * 2)) % size.height;
      final double r = rnd.nextDouble() * 6 + 2;

      final circlePaint = Paint()
        ..color = AppTheme.secondary.withOpacity(0.25)
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, y), r, circlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) {
    return oldDelegate.yaw != yaw || oldDelegate.pitch != pitch;
  }
}

// Details screen
class LandmarkDetailsPage extends StatelessWidget {
  final Map<String, dynamic> marker;
  final List<Map<String, dynamic>> otherMarkers;
  final Uint8List capturedImageBytes;
  final String serverUrl;
  final bool hasRealCamera;

  const LandmarkDetailsPage({
    super.key,
    required this.marker,
    required this.otherMarkers,
    required this.capturedImageBytes,
    required this.serverUrl,
    required this.hasRealCamera,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(marker['name'] ?? 'Place Details'),
        backgroundColor: AppTheme.surface,
      ),
      body: Row(
        children: [
          // Left: Capture viewer with highlighted pin
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Renders real captured picture or simulator grid background
                      Positioned.fill(
                        child: hasRealCamera
                            ? Image.memory(capturedImageBytes, fit: BoxFit.cover)
                            : CustomPaint(
                                painter: _ViewfinderPainter(yaw: 0.0, pitch: 0.0),
                              ),
                      ),

                      // Highlight clicked pin in amber/accent color
                      Positioned(
                        left: (marker['x'] as num).toDouble() * constraints.maxWidth - 20,
                        top: (marker['y'] as num).toDouble() * constraints.maxHeight - 20,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent.withOpacity(0.4),
                            border: Border.all(color: AppTheme.accent, width: 3.0),
                          ),
                          child: const Icon(Icons.stars, color: AppTheme.accent, size: 20),
                        ),
                      ),

                      // Render keypoints if available
                      if (marker['tracking_points'] != null)
                        ...(marker['tracking_points'] as List<dynamic>).map((pt) {
                          final double px = (pt['x'] as num).toDouble() * constraints.maxWidth;
                          final double py = (pt['y'] as num).toDouble() * constraints.maxHeight;
                          return Positioned(
                            left: px - 2.0,
                            top: py - 2.0,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.greenAccent,
                                boxShadow: [
                                  BoxShadow(color: Colors.green, blurRadius: 2),
                                ],
                              ),
                            ),
                          );
                        }),

                      // Render other pins in plain primary color
                      ...otherMarkers.map((m) {
                        final double px = (m['x'] as num).toDouble() * constraints.maxWidth;
                        final double py = (m['y'] as num).toDouble() * constraints.maxHeight;
                        return Positioned(
                          left: px - 12,
                          top: py - 12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary.withOpacity(0.15),
                              border: Border.all(color: AppTheme.primary, width: 1.0),
                            ),
                            child: const Icon(Icons.place, color: AppTheme.primary, size: 12),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),

          // Right: Place metadata dashboard details
          Container(
            width: 360,
            color: AppTheme.surface,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place, color: AppTheme.accent, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        marker['name'] ?? 'Place Node',
                        style: textTheme.titleLarge?.copyWith(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text("DESCRIPTION", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 6),
                Text(
                  marker['description'] != null && marker['description'].toString().isNotEmpty
                      ? marker['description']
                      : "No description provided.",
                  style: const TextStyle(fontSize: 14),
                ),
                const Divider(color: AppTheme.border, height: 36),

                const Text("VISION SPECS", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 10),
                _buildRow("Pin ID", marker['id'] ?? 'N/A'),
                _buildRow("SIFT Match Conf", "${marker['confidence']}%"),
                _buildRow("Relative coordinate", "(${marker['x'].toStringAsFixed(2)}, ${marker['y'].toStringAsFixed(2)})"),
                const Divider(color: AppTheme.border, height: 36),

                // Serve static file original image from Python server if available
                const Text("ORIGINAL REFERENCE VIEW", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 10),
                if (marker['image_url'] != null)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.black,
                        child: Image.network(
                          "$serverUrl${marker['image_url']}",
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.broken_image, color: AppTheme.textMuted));
                          },
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
