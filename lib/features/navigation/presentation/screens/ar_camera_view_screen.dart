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

  // Telemetry Yaw & Pitch (for mock mode fallback)
  double _cameraYaw = 0.0;
  double _cameraPitch = 0.0;

  // State caches
  List<Map<String, dynamic>> _trackedMarkers = []; // Visual matches currently tracked in viewpoint
  List<Map<String, dynamic>> _allLandmarks = [];   // Previously registered places database list
  Map<String, dynamic>? _selectedMarker;
  
  Timer? _matchingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadConfig();
    _initializeCamera();
    _startSpatialLocalizationLoop();
  }

  @override
  void dispose() {
    _matchingTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    _fetchAllRegisteredLandmarks();
  }

  Future<void> _loadConfig() async {
    final url = await ArServerService.getServerUrl();
    setState(() => _serverUrl = url);
    await _checkServerConnection();
    _fetchAllRegisteredLandmarks();
  }

  Future<void> _checkServerConnection() async {
    final online = await ArServerService.checkServerStatus(_serverUrl);
    setState(() => _isServerOnline = online);
  }

  Future<void> _fetchAllRegisteredLandmarks() async {
    if (!_isServerOnline) return;
    final list = await ArServerService.fetchAllLandmarks(_serverUrl);
    if (list != null && mounted) {
      setState(() {
        _allLandmarks = List<Map<String, dynamic>>.from(list);
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      debugPrint("No physical cameras available. Using simulated viewfinder feed.");
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
      await _checkServerConnection();
      _fetchAllRegisteredLandmarks();
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

  /// Telemetry matching loop (runs in BOTH tabs to keep markers dynamically projected)
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

  // --- GEOMETRIC SCREEN TO IMAGE COORDINATE CONVERSIONS ---
  // Maps touch coordinate on screen to relative coordinate on the actual captured image
  Map<String, double> _mapScreenToImage(double screenX, double screenY, double screenW, double screenH) {
    if (!_isCameraInitialized || _cameraController == null) {
      return {"x": screenX / screenW, "y": screenY / screenH};
    }
    
    // aspect ratio is height/width (landscape mode on device)
    // For portrait preview: 1.0 / aspectRatio
    double cameraAspect = 1.0 / _cameraController!.value.aspectRatio;
    
    double previewH = screenH;
    double previewW = screenH * cameraAspect;
    if (previewW < screenW) {
      previewW = screenW;
      previewH = screenW / cameraAspect;
    }
    
    double offsetX = (previewW - screenW) / 2;
    double offsetY = (previewH - screenH) / 2;
    
    double imgX = (screenX + offsetX) / previewW;
    double imgY = (screenY + offsetY) / previewH;
    
    return {"x": imgX, "y": imgY};
  }

  // Maps relative coordinate on captured image back to absolute screen pixels
  Map<String, double> _mapImageToScreen(double imgX, double imgY, double screenW, double screenH) {
    if (!_isCameraInitialized || _cameraController == null) {
      return {"x": imgX * screenW, "y": imgY * screenH};
    }
    
    double cameraAspect = 1.0 / _cameraController!.value.aspectRatio;
    
    double previewH = screenH;
    double previewW = screenH * cameraAspect;
    if (previewW < screenW) {
      previewW = screenW;
      previewH = screenW / cameraAspect;
    }
    
    double offsetX = (previewW - screenW) / 2;
    double offsetY = (previewH - screenH) / 2;
    
    double screenX = (imgX * previewW) - offsetX;
    double screenY = (imgY * previewH) - offsetY;
    
    return {"x": screenX, "y": screenY};
  }

  // Handle tap to register a landmark in Create Tab
  void _onViewfinderTapInCreate(TapUpDetails details, BoxConstraints constraints) {
    if (!_isServerOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vision server offline. Connect to register landmarks."), backgroundColor: AppTheme.danger),
      );
      return;
    }

    // Convert tapped screen coordinates to cropped camera image coordinates
    final coords = _mapScreenToImage(
      details.localPosition.dx,
      details.localPosition.dy,
      constraints.maxWidth,
      constraints.maxHeight,
    );
    final double relativeX = coords['x']!;
    final double relativeY = coords['y']!;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormCreatorPage(
          serverUrl: _serverUrl,
          touchX: relativeX,
          touchY: relativeY,
          captureFrameCallback: _captureCurrentFrameBytes,
        ),
      ),
    ).then((saved) {
      if (saved == true) {
        _fetchAllRegisteredLandmarks();
      }
    });
  }

  // Edit existing landmark form layout
  void _editLandmarkForm(Map<String, dynamic> landmark) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormCreatorPage(
          serverUrl: _serverUrl,
          landmark: landmark,
          captureFrameCallback: _captureCurrentFrameBytes,
        ),
      ),
    ).then((saved) {
      if (saved == true) {
        _fetchAllRegisteredLandmarks();
      }
    });
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
            mapImageToScreen: _mapImageToScreen,
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
        title: const Text("AR Asset Forms Portal"),
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
            Tab(text: "CREATE TAB (FORM BUILDER)"),
            Tab(text: "VIEW TAB (FORM SUBMISSION)"),
          ],
        ),
      ),
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
                  _checkServerConnection().then((_) => _fetchAllRegisteredLandmarks());
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _checkServerConnection().then((_) => _fetchAllRegisteredLandmarks());
                      },
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
                  Navigator.pop(context); 
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
          Positioned.fill(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCameraViewport(isCreate: true),
                _buildCameraViewport(isCreate: false),
              ],
            ),
          ),

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
                    Text("SIFT SCANNERS ACTIVE...", style: TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

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
              _onViewfinderTapInCreate(details, constraints);
            }
          },
          child: Stack(
            children: [
              // Real Camera Feed fitted to cover full screen with zero overflow spacing issues
              Positioned.fill(
                child: _isCameraInitialized && _cameraController != null
                    ? ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _cameraController!.value.previewSize!.height,
                              height: _cameraController!.value.previewSize!.width,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                        ),
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
                  // Map raw image relative coordinates to screen coordinates
                  final screenCoords = _mapImageToScreen(
                    (pt['x'] as num).toDouble(),
                    (pt['y'] as num).toDouble(),
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final double px = screenCoords['x']!;
                  final double py = screenCoords['y']!;

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

              // RENDER SCENARIOS FOR TAB 1: CREATE MODE
              if (isCreate) ...[
                // Renders dynamic blue markers for matched landmarks (only visible when in camera view!)
                ..._trackedMarkers.map((lm) {
                  final screenCoords = _mapImageToScreen(
                    (lm['x'] as num).toDouble(),
                    (lm['y'] as num).toDouble(),
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final double px = screenCoords['x']!;
                  final double py = screenCoords['y']!;

                  return Positioned(
                    left: px - 20,
                    top: py - 20,
                    child: GestureDetector(
                      onTap: () {
                        // Find the original landmark dict from _allLandmarks that matches this ID to edit it
                        final matchedLm = _allLandmarks.firstWhere((element) => element['id'] == lm['id'], orElse: () => lm);
                        _editLandmarkForm(matchedLm);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.secondary.withOpacity(0.35),
                          border: Border.all(color: AppTheme.secondary, width: 3.0),
                        ),
                        child: const Icon(Icons.edit_note, color: AppTheme.secondary, size: 20),
                      ),
                    ),
                  );
                }),
              ],

              // RENDER SCENARIOS FOR TAB 2: VIEW MODE
              if (!isCreate) ...[
                // Renders green markers for matched landmarks
                ..._trackedMarkers.map((marker) {
                  final screenCoords = _mapImageToScreen(
                    (marker['x'] as num).toDouble(),
                    (marker['y'] as num).toDouble(),
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final double px = screenCoords['x']!;
                  final double py = screenCoords['y']!;

                  final bool isSelected = _selectedMarker != null && _selectedMarker!['id'] == marker['id'];

                  return Positioned(
                    left: px - 20,
                    top: py - 20,
                    child: GestureDetector(
                      onTap: () => _onPinClicked(marker),
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
              ],

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
                    isCreate ? "TAP FEED TO ANCHOR NEW PLACE | DYNAMIC BLUE PINS TRACK OBJECTS TO EDIT" : "ACTIVE CAMERA TRACKER: TAP OVERLAY PIN TO SUBMIT READINGS",
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
    final bgPaint = Paint()..color = const Color(0xff090f1d);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = AppTheme.border.withOpacity(0.2)
      ..strokeWidth = 1.0;

    final double dx = (yaw * 3) % 80;
    final double dy = (pitch * 3) % 80;

    for (double i = dx; i < size.width; i += 80) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), linePaint);
    }
    for (double i = dy; i < size.height; i += 80) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), linePaint);
    }

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

class FormCreatorPage extends StatefulWidget {
  final String serverUrl;
  final double? touchX;
  final double? touchY;
  final Map<String, dynamic>? landmark; 
  final Future<Uint8List> Function() captureFrameCallback;

  const FormCreatorPage({
    key,
    required this.serverUrl,
    this.touchX,
    this.touchY,
    this.landmark,
    required this.captureFrameCallback,
  }) : super(key: key);

  @override
  State<FormCreatorPage> createState() => _FormCreatorPageState();
}

class _FormCreatorPageState extends State<FormCreatorPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  
  List<String> _formFields = [];
  bool _isSaving = false;

  bool get _isEditMode => widget.landmark != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.landmark?['name'] ?? '');
    _descController = TextEditingController(text: widget.landmark?['description'] ?? '');

    if (_isEditMode && widget.landmark?['form_schema'] != null) {
      try {
        final List<dynamic> fields = jsonDecode(widget.landmark!['form_schema']);
        _formFields = List<String>.from(fields);
      } catch (e) {
        _formFields = [];
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _addNewField() {
    final fieldController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Custom Field"),
          content: TextField(
            controller: fieldController,
            decoration: const InputDecoration(
              labelText: "Field Name / Question",
              hintText: "e.g. Temperature (C) or Oil Level",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final label = fieldController.text.trim();
                if (label.isNotEmpty) {
                  setState(() {
                    _formFields.add(label);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  void _removeField(int index) {
    setState(() {
      _formFields.removeAt(index);
    });
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final String schemaJson = jsonEncode(_formFields);

    if (_isEditMode) {
      final ok = await ArServerService.updateLandmark(
        baseUrl: widget.serverUrl,
        landmarkId: widget.landmark!['id'],
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        formSchema: schemaJson,
      );
      setState(() => _isSaving = false);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Asset form updated successfully!"), backgroundColor: AppTheme.primary),
        );
        Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to update form on server."), backgroundColor: AppTheme.danger),
          );
        }
      }
    } else {
      final frameBytes = await widget.captureFrameCallback();
      if (frameBytes.isEmpty) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to capture reference snapshot frame."), backgroundColor: AppTheme.danger),
        );
        return;
      }

      final res = await ArServerService.addLandmark(
        baseUrl: widget.serverUrl,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        touchX: widget.touchX!,
        touchY: widget.touchY!,
        formSchema: schemaJson,
        imageBytes: frameBytes,
      );

      setState(() => _isSaving = false);

      if (res != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Form configured for '${_nameController.text}'!"), backgroundColor: AppTheme.primary),
        );
        Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to save asset form. Check server log."), backgroundColor: AppTheme.danger),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? "Edit Asset Form" : "Create Asset Form"),
        backgroundColor: AppTheme.surface,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Text("ASSET PROFILE", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.accent)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Asset Name", hintText: "e.g., Main Steam Boiler"),
                  validator: (val) => val == null || val.trim().isEmpty ? "Required field" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: "Description", hintText: "e.g., Model B-24 Valve parameters"),
                  maxLines: 2,
                ),
                const Divider(color: AppTheme.border, height: 40),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "FORM TEXTBOXES (GFORMS ENGINE)",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _addNewField,
                      icon: const Icon(Icons.add),
                      label: const Text("Add Field"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_formFields.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.border, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text("No custom TextBoxes added yet.\nClick 'Add Field' above.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                else
                  ..._formFields.asMap().entries.map((entry) {
                    final int idx = entry.key;
                    final String fieldLabel = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.text_fields_outlined, color: AppTheme.primary),
                        title: Text(fieldLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text("Data Input Type: Textbox", style: TextStyle(fontSize: 10)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                          onPressed: () => _removeField(idx),
                        ),
                      ),
                    );
                  }),
                
                const SizedBox(height: 36),

                if (_isSaving)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                else
                  ElevatedButton(
                    onPressed: _saveForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      _isEditMode ? "Save Changes" : "Create Asset",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LandmarkDetailsPage extends StatefulWidget {
  final Map<String, dynamic> marker;
  final List<Map<String, dynamic>> otherMarkers;
  final Uint8List capturedImageBytes;
  final String serverUrl;
  final bool hasRealCamera;
  final Map<String, double> Function(double, double, double, double) mapImageToScreen;

  const LandmarkDetailsPage({
    key,
    required this.marker,
    required this.otherMarkers,
    required this.capturedImageBytes,
    required this.serverUrl,
    required this.hasRealCamera,
    required this.mapImageToScreen,
  }) : super(key: key);

  @override
  State<LandmarkDetailsPage> createState() => _LandmarkDetailsPageState();
}

class _LandmarkDetailsPageState extends State<LandmarkDetailsPage> {
  final _readingsKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  bool _isSubmitting = false;
  List<String> _fields = [];

  @override
  void initState() {
    super.initState();
    if (widget.marker['form_schema'] != null) {
      try {
        final List<dynamic> list = jsonDecode(widget.marker['form_schema']);
        _fields = List<String>.from(list);
        for (var field in _fields) {
          _controllers[field] = TextEditingController();
        }
      } catch (e) {
        _fields = [];
      }
    }
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitReadings() async {
    if (!_readingsKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final Map<String, String> readingsPayload = {};
    _controllers.forEach((field, ctrl) {
      readingsPayload[field] = ctrl.text.trim();
    });

    final ok = await ArServerService.submitReadings(
      baseUrl: widget.serverUrl,
      landmarkId: widget.marker['id'],
      readings: readingsPayload,
    );

    setState(() => _isSubmitting = false);

    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Readings saved to date_readings.json!"), backgroundColor: AppTheme.primary),
      );
      Navigator.pop(context);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to submit readings to server."), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.marker['name'] ?? 'Place Details'),
        backgroundColor: AppTheme.surface,
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: widget.hasRealCamera
                            ? Image.memory(widget.capturedImageBytes, fit: BoxFit.cover)
                            : CustomPaint(
                                painter: _ViewfinderPainter(yaw: 0.0, pitch: 0.0),
                              ),
                      ),

                      if (widget.marker['tracking_points'] != null)
                        ...(widget.marker['tracking_points'] as List<dynamic>).map((pt) {
                          final screenCoords = widget.mapImageToScreen(
                            (pt['x'] as num).toDouble(),
                            (pt['y'] as num).toDouble(),
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final double px = screenCoords['x']!;
                          final double py = screenCoords['y']!;
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

                      // Highlight selected pin
                      Positioned(
                        left: () {
                          final screenCoords = widget.mapImageToScreen(
                            (widget.marker['x'] as num).toDouble(),
                            (widget.marker['y'] as num).toDouble(),
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return screenCoords['x']! - 20;
                        }(),
                        top: () {
                          final screenCoords = widget.mapImageToScreen(
                            (widget.marker['x'] as num).toDouble(),
                            (widget.marker['y'] as num).toDouble(),
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return screenCoords['y']! - 20;
                        }(),
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

                      // Other markers
                      ...widget.otherMarkers.map((m) {
                        final screenCoords = widget.mapImageToScreen(
                          (m['x'] as num).toDouble(),
                          (m['y'] as num).toDouble(),
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        final double px = screenCoords['x']!;
                        final double py = screenCoords['y']!;
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

          // Right: Form submission metadata details
          Container(
            width: 380,
            color: AppTheme.surface,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment, color: AppTheme.accent, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.marker['name'] ?? 'Place Form',
                        style: textTheme.titleLarge?.copyWith(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("DESCRIPTION", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted, fontSize: 10)),
                const SizedBox(height: 4),
                Text(
                  widget.marker['description'] != null && widget.marker['description'].toString().isNotEmpty
                      ? widget.marker['description']
                      : "No description provided.",
                  style: const TextStyle(fontSize: 13),
                ),
                const Divider(color: AppTheme.border, height: 24),

                // Form entries scroll list
                Expanded(
                  child: Form(
                    key: _readingsKey,
                    child: ListView(
                      children: [
                        Text("LOG DAILY READINGS", style: textTheme.titleMedium?.copyWith(color: AppTheme.primary)),
                        const SizedBox(height: 12),
                        
                        if (_fields.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              "No dynamic text fields configured for this asset.\nGo to Create Tab and tap this pin to add fields.",
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ..._fields.map((field) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                controller: _controllers[field],
                                decoration: InputDecoration(
                                  labelText: field,
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? "Required entry" : null,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),

                const Divider(color: AppTheme.border, height: 24),

                if (_isSubmitting)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                else if (_fields.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _submitReadings,
                    icon: const Icon(Icons.cloud_upload, color: Colors.white),
                    label: const Text(
                      "Submit Readings",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
