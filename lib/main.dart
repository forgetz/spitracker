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

  // Request location permission when service starts
  await _checkAndRequestLocationPermission();

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

// Check and request location permission
Future<bool> _checkAndRequestLocationPermission() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Location services are not enabled
    print('Location services are disabled.');
    return false;
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Permissions are denied
      print('Location permissions are denied');
      return false;
    }
  }
  
  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever
    print('Location permissions are permanently denied');
    return false;
  }

  // Permissions are granted
  return true;
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
      // Check location permission before getting position
      bool hasPermission = await _checkAndRequestLocationPermission();
      if (!hasPermission) {
        return "Error: Location permission denied";
      }
      
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
  String _serviceStatus = "Checking..."; // Add service status tracking
  String _locationInfo = "Location not available"; // Add location info tracking

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getDeviceInfo();
      _getDeviceId();
      _checkServiceStatus(); // Check service status on startup
      _checkLocationPermission(); // Check location permission on startup
      _updateLocationInfo(); // Get initial location
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

  // Add method to check background service status
  Future<void> _checkServiceStatus() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      setState(() {
        _isBackgroundEnabled = isRunning;
        _serviceStatus = isRunning 
            ? "Background service is running" 
            : "Background service is stopped";
      });
    } catch (e) {
      setState(() {
        _serviceStatus = "Error checking service: $e";
      });
    }
  }

  // Add method to check location permission
  Future<void> _checkLocationPermission() async {
    await _checkAndRequestLocationPermission();
  }

  // Add method to update location information
  Future<void> _updateLocationInfo() async {
    try {
      bool hasPermission = await _checkAndRequestLocationPermission();
      if (!hasPermission) {
        setState(() {
          _locationInfo = "Location permission denied";
        });
        return;
      }

      setState(() {
        _locationInfo = "Getting location...";
      });

      final position = await Geolocator.getCurrentPosition();
      
      setState(() {
        _locationInfo = "Latitude: ${position.latitude.toStringAsFixed(6)}\nLongitude: ${position.longitude.toStringAsFixed(6)}";
      });
    } catch (e) {
      setState(() {
        _locationInfo = "Error getting location: $e";
      });
    }
  }

  void _toggleBackgroundService() async {
    final service = FlutterBackgroundService();
    
    if (_isBackgroundEnabled) {
      service.invoke("stopService");
      setState(() {
        _isBackgroundEnabled = false;
        _serviceStatus = "Background service stopped";
      });
    } else {
      await service.startService();
      setState(() {
        _isBackgroundEnabled = true;
        _serviceStatus = "Background service started";
      });
    }
    
    // Verify actual status after a short delay
    Future.delayed(Duration(milliseconds: 500), () {
      _checkServiceStatus();
    });
  }

  Future<void> _callApiImmediately() async {
    setState(() {
      _isApiCalling = true;
      _apiStatus = "Calling API...";
    });

    // Check location permission before calling API
    bool hasPermission = await _checkAndRequestLocationPermission();
    if (!hasPermission) {
      setState(() {
        _isApiCalling = false;
        _apiStatus = "Error: Location permission denied";
      });
      return;
    }

    String result = await sendApiData();
    
    // Update location info after API call
    _updateLocationInfo();

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
            // const Text("Device Information", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            // const SizedBox(height: 10),
            // Text(_deviceInfo),
            // const SizedBox(height: 20),
            const Text("Device ID", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(_deviceId, style: TextStyle(fontSize: 16, color: Colors.blue)),
            const SizedBox(height: 20),
            // Add location information display
            const Text("Current Location", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _locationInfo,
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _updateLocationInfo,
              icon: Icon(Icons.my_location),
              label: Text("Update Location"),
            ),
            const SizedBox(height: 20),
            // Add service status indicator
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isBackgroundEnabled ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _serviceStatus,
                style: TextStyle(
                  color: _isBackgroundEnabled ? Colors.green.shade800 : Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
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
            // Add refresh button to manually check service status
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _checkServiceStatus,
              icon: Icon(Icons.refresh),
              label: Text("Refresh Status"),
            ),
          ],
        ),
      ),
    );
  }
}
