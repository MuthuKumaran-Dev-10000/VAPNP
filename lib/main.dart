import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/screens/ar_camera_view_screen.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error initializing cameras: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Visual Landmark Portal',
      theme: AppTheme.themeData,
      debugShowCheckedModeBanner: false,
      home: ArCameraViewScreen(cameras: cameras),
    );
  }
}
