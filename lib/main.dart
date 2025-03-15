import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService(); // Initialize background service
  runApp(const MyApp());
}

// Initialize Background Service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onBackground,
    ),
  );

  service.startService();
}

// Background service logic
void onStart(ServiceInstance service) async {
  print("Background Service Started");

  Timer? timer;
  timer = Timer.periodic(const Duration(minutes: 1), (t) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        print("Running background task...");
        await sendApiData();
      }
    }
  });

  service.on('stopService').listen((event) {
    timer?.cancel(); // Stop periodic timer
    print("Background service stopped.");
    service.stopSelf();
  });

}

// iOS Background Task
Future<bool> onBackground(ServiceInstance service) async {
  print("Background service running in background mode.");
  return true;
}

// API Call Function
Future<String> sendApiData() async {
  try {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 7 && hour < 24) { // Only run API call during active hours
      final position = await Geolocator.getCurrentPosition();
      final deviceInfoPlugin = DeviceInfoPlugin();
      String deviceId = "Unknown";
      String androidVersion = "Unknown";
      String model = "Unknown";

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceId = androidInfo.id ?? "Unknown";
        androidVersion = androidInfo.version.release ?? "Unknown";
        model = androidInfo.model ?? "Unknown";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? "Unknown";
        androidVersion = iosInfo.systemVersion ?? "Unknown";
        model = iosInfo.model ?? "Unknown";
      }

      if (deviceId.isEmpty || position.latitude == null || position.longitude == null) {
        return "Error: Missing Required Data";
      }

      final response = await http.post(
        Uri.parse('https://httpbin.org/post'),
        body: {
          'device_id': deviceId,
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'android_version': androidVersion,
          'model': model,
        },
      );

      if (response.statusCode == 200) {
        print("API call successful.");
        return "Completed 200 on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      } else {
        print("API call failed: ${response.statusCode}");
        return "Failed Status ${response.statusCode} on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      }
    }
    return "Skipped (Out of Active Hours)";
  } catch (e) {
    print("Error in API call: $e");
    return "Error: $e";
  }
}

// Convert month number to month name
String _getMonthName(int month) {
  const monthNames = [
    "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  return monthNames[month];
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Device Info App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'SPITracker'),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _deviceInfo = 'Loading device info...';
  String _deviceId = 'Loading device ID...';
  String _apiStatus = "API not called yet"; // API call status message
  bool _isBackgroundEnabled = false;
  bool _isApiCalling = false;

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getDeviceInfo();
      _getDeviceId();
    });
  }

  Future<void> _getDeviceId() async {
    try {
      if (kIsWeb) {
        setState(() {
          _deviceId = 'Device ID not available on web';
        });
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        setState(() {
          _deviceId = androidInfo.id;
        });
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        setState(() {
          _deviceId = iosInfo.identifierForVendor ?? 'Not available';
        });
      } else {
        setState(() {
          _deviceId = 'Device ID not available on this platform';
        });
      }
    } catch (e) {
      setState(() {
        _deviceId = 'Error getting device ID: $e';
      });
    }
  }

  Future<void> _getDeviceInfo() async {
    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfoPlugin.webBrowserInfo;
        setState(() {
          _deviceInfo = '''
Platform: Web
Browser: ${webInfo.browserName.name}
Version: ${webInfo.appVersion}
Platform: ${webInfo.platform}
''';
        });
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        setState(() {
          _deviceInfo = '''
Device: ${androidInfo.model}
Brand: ${androidInfo.brand}
Android Version: ${androidInfo.version.release}
Manufacturer: ${androidInfo.manufacturer}
''';
        });
      } else {
        setState(() {
          _deviceInfo = 'Current platform information not available';
        });
      }
    } catch (e) {
      setState(() {
        _deviceInfo = 'Error getting device info: $e';
      });
    }
  }

  void _toggleBackgroundService() {
    if (_isBackgroundEnabled) {
      FlutterBackgroundService().invoke("stopService");
      setState(() {
        _isBackgroundEnabled = false;
      });
    } else {
      FlutterBackgroundService().startService();
      setState(() {
        _isBackgroundEnabled = true;
      });
    }
  }

  Future<void> _callApiImmediately() async {
    setState(() {
      _isApiCalling = true;
      _apiStatus = "Calling API...";
    });

    String result = await sendApiData();

    setState(() {
      _isApiCalling = false;
      _apiStatus = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Device Information", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(_deviceInfo),
            const SizedBox(height: 20),
            const Text("Device ID", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(_deviceId, style: TextStyle(fontSize: 16, color: Colors.blue)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _toggleBackgroundService,
              child: Text(_isBackgroundEnabled ? "Stop Background" : "Start Background"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isApiCalling ? null : _callApiImmediately,
              child: _isApiCalling ? CircularProgressIndicator() : const Text("Send API Now"),
            ),
            const SizedBox(height: 10),
            Text(_apiStatus, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
        
      ),
    );
  }
}
