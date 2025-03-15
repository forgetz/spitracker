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
      isForegroundMode: false,
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

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        print("Running background task...");
        await sendApiData();
      }
    }
  });
}

// iOS Background Task
Future<bool> onBackground(ServiceInstance service) async {
  print("Background service running in background mode.");
  return true;
}

// API Call Function
Future<void> sendApiData() async {
  try {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 7 && hour < 24) { // Only run API call during active hours
      final position = await Geolocator.getCurrentPosition();
      final deviceInfoPlugin = DeviceInfoPlugin();
      String deviceId = "Unknown";

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? "Unknown";
      }

      final response = await http.post(
        Uri.parse('https://httpbin.org/post'),
        body: {
          'device_id': deviceId,
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
        },
      );

      if (response.statusCode == 200) {
        print("API call successful.");
      } else {
        print("API call failed: ${response.statusCode}");
      }
    }
  } catch (e) {
    print("Error in API call: $e");
  }
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
  String _locationInfo = 'Loading location...';
  String _deviceId = 'Loading device ID...';
  bool _isBackgroundEnabled = false;
  bool _isApiCalling = false;

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getDeviceInfo();
      _getLocation();
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
SDK Version: ${androidInfo.version.sdkInt}
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

  Future<void> _getLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationInfo = 'Location permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationInfo = 'Location permission permanently denied';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _locationInfo = '''
Latitude: ${position.latitude}
Longitude: ${position.longitude}
Altitude: ${position.altitude}
Accuracy: ${position.accuracy}m
''';
      });
    } catch (e) {
      setState(() {
        _locationInfo = 'Error getting location: $e';
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
    });

    await sendApiData();

    setState(() {
      _isApiCalling = false;
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
            Text(_deviceInfo),
            Text(_deviceId),
            Text(_locationInfo),
            ElevatedButton(
              onPressed: _toggleBackgroundService,
              child: Text(_isBackgroundEnabled ? "Stop Background" : "Start Background"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isApiCalling ? null : _callApiImmediately,
              child: _isApiCalling ? CircularProgressIndicator() : const Text("Send API Now"),
            ),
          ],
        ),
      ),
    );
  }
}
