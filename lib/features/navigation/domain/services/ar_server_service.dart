import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ArServerService {
  static const String _serverUrlKey = "ar_navigation_server_url";
  static const String _defaultUrl = "http://localhost:9000";
  static const String _firebaseRtdbUrl = "https://lubrication-indicator-default-rtdb.firebaseio.com/server.json";

  /// Gets the currently configured server URL.
  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? _defaultUrl;
  }

  /// Sets/Saves a custom server URL.
  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  /// Dynamically pulls the live server url from Firebase Realtime Database.
  static Future<String?> fetchLiveUrlFromFirebase() async {
    try {
      final response = await http.get(Uri.parse(_firebaseRtdbUrl)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final Map<String, dynamic>? data = jsonDecode(response.body);
        if (data != null) {
          final ngrokUrl = data['ngrok_url'] as String?;
          if (ngrokUrl != null && ngrokUrl.isNotEmpty) {
            return ngrokUrl;
          }
          final localIpUrl = data['local_ip_url'] as String?;
          if (localIpUrl != null && localIpUrl.isNotEmpty) {
            return localIpUrl;
          }
        }
      }
    } catch (e) {
      // Fail silently
    }
    return null;
  }

  /// Checks if the server is online.
  static Future<bool> checkServerStatus(String baseUrl) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/status")).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'online';
      }
    } catch (_) {}
    return false;
  }

  /// Registers a Landmark place: uploads image + touch pixel location + form schema
  static Future<Map<String, dynamic>?> addLandmark({
    required String baseUrl,
    required String name,
    required String description,
    required double touchX,
    required double touchY,
    required String formSchema, // JSON string
    required Uint8List imageBytes,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/graph/landmarks");
      final request = http.MultipartRequest("POST", uri);

      request.fields['name'] = name;
      request.fields['description'] = description;
      request.fields['touch_x'] = touchX.toString();
      request.fields['touch_y'] = touchY.toString();
      request.fields['form_schema'] = formSchema;

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'landmark.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  /// Updates an existing landmark metadata and form schema
  static Future<bool> updateLandmark({
    required String baseUrl,
    required String landmarkId,
    required String name,
    required String description,
    required String formSchema,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/graph/landmarks/$landmarkId");
      final response = await http.put(
        uri,
        body: {
          'name': name,
          'description': description,
          'form_schema': formSchema,
        },
      );
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Submits form readings to backend daily log JSON
  static Future<bool> submitReadings({
    required String baseUrl,
    required String landmarkId,
    required Map<String, String> readings,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/readings");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'landmark_id': landmarkId,
          'readings': readings,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Queries visual localization with query viewfinder frame.
  static Future<List<dynamic>?> localize({
    required String baseUrl,
    required Uint8List imageBytes,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/localization");
      final request = http.MultipartRequest("POST", uri);

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'query.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['markers'] as List<dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  /// Fetches all registered visual places.
  static Future<List<dynamic>?> fetchAllLandmarks(String baseUrl) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/landmarks"));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>?;
      }
    } catch (_) {}
    return null;
  }
}
