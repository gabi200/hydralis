import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';

import 'api_config.dart';

class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  final String baseUrl = ApiConfig.restRoot;
  final String apiV1Url = ApiConfig.apiV1;
  final String wsUrl = ApiConfig.wsStream;

  String? _token;
  String? _userId;
  String? _userName;
  String? _deviceId;
  String? _deviceLabel;
  String? _selectedBuildingId;
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;

  String? get deviceId => _deviceId;
  String? get deviceLabel => _deviceLabel;
  String? get selectedBuildingId => _selectedBuildingId;
  String? get userName => _userName;

  // Stream controller to broadcast events from the WebSocket
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  String? get userId => _userId;

  // Dedicated stream and storage for emergency alerts
  final _alertController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream;
  final List<Map<String, dynamic>> activeAlerts = [];

  // Gas alert stream — broadcast every gas:alert / gas:resolved event.
  final _gasAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get gasAlertStream => _gasAlertController.stream;
  final List<Map<String, dynamic>> activeGasAlerts = [];

  Future<void> initialize() async {
    await _authenticateDummyUser();
    await _ensureGasDeviceRegistered();
    await _loadSelectedBuilding();
    _connectWebSocket();
    _startHeartbeat();
  }

  Future<void> _loadSelectedBuilding() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedBuildingId = prefs.getString('hydralis_building_id');
  }

  Future<void> setSelectedBuilding(String? buildingId) async {
    final prefs = await SharedPreferences.getInstance();
    _selectedBuildingId = buildingId;
    if (buildingId == null) {
      await prefs.remove('hydralis_building_id');
    } else {
      await prefs.setString('hydralis_building_id', buildingId);
    }
  }

  Future<List<Map<String, dynamic>>> fetchBuildings() async {
    try {
      final res = await http.get(
        Uri.parse('$apiV1Url/gas/buildings'),
        headers: _token != null ? {"Authorization": "Bearer $_token"} : {},
      );
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      return (data['buildings'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Fetch buildings error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSensorsForBuilding(
    String buildingId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$apiV1Url/gas/sensors'),
        headers: _token != null ? {"Authorization": "Bearer $_token"} : {},
      );
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final list = (data['sensors'] as List).cast<Map<String, dynamic>>();
      return list.where((s) => s['buildingId'] == buildingId).toList();
    } catch (e) {
      print('Fetch sensors error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchGasAlerts({bool? active}) async {
    try {
      final uri = Uri.parse('$apiV1Url/gas/alerts').replace(
        queryParameters: active == null ? null : {'active': '$active'},
      );
      final res = await http.get(
        uri,
        headers: _token != null ? {"Authorization": "Bearer $_token"} : {},
      );
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      return (data['alerts'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Fetch alerts error: $e');
      return [];
    }
  }

  Future<void> _ensureGasDeviceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('gas_device_id');
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await prefs.setString('gas_device_id', _deviceId!);
    }
    _deviceLabel = prefs.getString('gas_device_label');
    if (_deviceLabel == null) {
      final platform = _platformName();
      final suffix = _deviceId!.substring(_deviceId!.length - 4).toUpperCase();
      _deviceLabel = 'Phone $platform-$suffix';
      await prefs.setString('gas_device_label', _deviceLabel!);
    }
    await _registerGasDevice();
  }

  String _generateDeviceId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
    return 'dev-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  String _platformName() {
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Mobile';
  }

  Future<void> _registerGasDevice() async {
    if (_deviceId == null || _deviceLabel == null) return;
    try {
      await http.post(
        Uri.parse('$apiV1Url/gas/devices'),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token",
        },
        body: jsonEncode({
          "device_id": _deviceId,
          "label": _deviceLabel,
          "platform": _platformName(),
          "owner": _userName,
        }),
      );
    } catch (e) {
      print("Gas device register error: $e");
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_deviceId == null) return;
      try {
        await http.post(
          Uri.parse('$apiV1Url/gas/devices/$_deviceId/heartbeat'),
          headers: {
            "Content-Type": "application/json",
            if (_token != null) "Authorization": "Bearer $_token",
          },
        );
      } catch (_) {}
    });
  }

  Future<void> setDeviceLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    _deviceLabel = label;
    await prefs.setString('gas_device_label', label);
    await _registerGasDevice();
  }

  Future<bool> ackGasAlert(int alertId) async {
    if (_deviceId == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$apiV1Url/gas/alerts/$alertId/ack'),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token",
        },
        body: jsonEncode({"device_id": _deviceId}),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      print("Gas ack error: $e");
      return false;
    }
  }

  Future<void> _authenticateDummyUser() async {
    final loginPayload = {
      "email": "andrei.ionescu@hydralis.com",
      "password": "secure_password",
    };

    try {
      // Try login first
      final loginRes = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(loginPayload),
      );

      if (loginRes.statusCode == 200) {
        final data = jsonDecode(loginRes.body);
        _token = data['token'];
        _userId = data['user']['user_id'];
        _userName = data['user']['full_name'];
      } else {
        // If login fails, try signup
        final signupPayload = {
          "full_name": "Andrei Ionescu",
          "email": "andrei.ionescu@hydralis.com",
          "password": "secure_password",
          "birthday": "1985-06-15",
          "primary_location": "Galati Port Facility",
          "safety_level": 3,
        };

        final signupRes = await http.post(
          Uri.parse('$baseUrl/auth/signup'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(signupPayload),
        );

        if (signupRes.statusCode == 201) {
          final data = jsonDecode(signupRes.body);
          _token = data['token'];
          _userId = data['user_id'];
          _userName = "Andrei Ionescu"; // Default for new signup in demo
        } else {
          print("Failed to authenticate dummy user: ${signupRes.body}");
        }
      }
    } catch (e) {
      print("Authentication error: $e");
    }
  }

  void _connectWebSocket() {
    print("Attempting to connect to WebSocket: $wsUrl");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          print("WebSocket RECEIVED: $message");
          try {
            final data = jsonDecode(message);
            _eventController.add(data);

            // Intercept emergency status events and route them to alerts
            final eventType = data['event'] ?? data['type'];
            if (eventType == 'user:status_emergency') {
              activeAlerts.add(data);
              _alertController.add(data);
            }

            if (eventType == 'gas:alert') {
              final payload = data['payload'] is Map
                  ? Map<String, dynamic>.from(data['payload'])
                  : <String, dynamic>{};
              activeGasAlerts.add(payload);
              _gasAlertController.add({
                'event': 'gas:alert',
                'payload': payload,
              });
            }

            if (eventType == 'gas:resolved') {
              final payload = data['payload'] is Map
                  ? Map<String, dynamic>.from(data['payload'])
                  : <String, dynamic>{};
              final sensorId = payload['sensorId'];
              if (sensorId != null) {
                activeGasAlerts.removeWhere(
                  (alert) => alert['sensorId'] == sensorId,
                );
              }
              _gasAlertController.add({
                'event': 'gas:resolved',
                'payload': payload,
              });
            }
          } catch (e) {
            print("WebSocket parse error: $e");
          }
        },
        onError: (e) {
          print("WebSocket ERROR: $e");
          _reconnectWebSocket();
        },
        onDone: () {
          print("WebSocket CLOSED");
          _reconnectWebSocket();
        },
      );
    } catch (e) {
      print("WebSocket connection error: $e");
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    Future.delayed(const Duration(seconds: 5), () {
      _connectWebSocket();
    });
  }

  Future<Map<String, dynamic>?> fetchMapData(LatLng location) async {
    try {
      final res = await http.get(
        Uri.parse(
          '$baseUrl/map/data?lat=${location.latitude}&lng=${location.longitude}&radius=10km',
        ),
        headers: _token != null ? {"Authorization": "Bearer $_token"} : {},
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        print("Failed to fetch map data: ${res.body}");
        return null;
      }
    } catch (e) {
      print("Fetch map data error: $e");
      return null;
    }
  }

  Future<void> postUserStatus(LatLng location, String status) async {
    if (_userId == null) return;

    try {
      final payload = {
        "user_id": _userId,
        "status": status,
        "current_location": {
          "lat": location.latitude,
          "lng": location.longitude,
        },
      };

      await http.post(
        Uri.parse('$baseUrl/user/status'),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token",
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      print("Post user status error: $e");
    }
  }

  Future<String?> triggerManDown(
    LatLng location, {
    Map<String, dynamic>? mobilityInfo,
    String userStatus = "Man Down",
  }) async {
    if (_userId == null || _token == null) return null;

    try {
      final payload = {
        "user_id": _userId,
        "user_name": _userName ?? "Unknown Worker",
        "user_status": userStatus,
        "mobility_info": mobilityInfo,
        "current_location": {
          "lat": location.latitude,
          "lng": location.longitude,
        },
        "message": "MAN-DOWN DETECTED: Zero movement for 60 seconds.",
      };

      final response = await http.post(
        Uri.parse('$baseUrl/alerts/trigger'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_token",
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alert_id'];
      }
    } catch (e) {
      print("Trigger alert error: $e");
    }
    return null;
  }

  // Helper to remove an alert once it's been handled
  void removeAlert(Map<String, dynamic> alert) {
    activeAlerts.remove(alert);
  }

  Future<void> cancelAlert(String alertId) async {
    try {
      // Mark the dispatch alert as accidental instead of closing it silently.
      await http.patch(
        Uri.parse('$apiV1Url/alerts/$alertId/message'),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token",
        },
        body: jsonEncode({
          "message": "Accidental Detection — Worker confirmed safe.",
        }),
      );
      await http.patch(
        Uri.parse('$apiV1Url/alerts/$alertId/status'),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token",
        },
        body: jsonEncode({"status": "accidental"}),
      );
    } catch (e) {
      print("Cancel alert error: $e");
    }
  }

  Future<void> cancelLatestAlert() async {
    if (_token == null) return;

    try {
      await http.post(
        Uri.parse('$baseUrl/alerts/accidental'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_token",
        },
      );
    } catch (e) {
      print("Cancel latest alert error: $e");
    }
  }
}
