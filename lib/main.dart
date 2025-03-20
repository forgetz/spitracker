import 'dart:ui';
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
import 'package:app_settings/app_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'dart:collection';
import 'package:path_provider/path_provider.dart';
import 'log_screen.dart'; // Add this import for the LogScreen
import 'log_utils.dart';
import 'location_service.dart';
import 'app_config.dart';
import 'device_info_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  await initializeService();
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
      foregroundServiceNotificationId: 888,
      initialNotificationTitle: 'SPITracker',
      initialNotificationContent: 'Tracking location in background',
      // foregroundServiceNotificationTitle: 'SPITracker',
      // notificationChannelId: 'spi_tracker_channel',
      // notificationChannelDescription: 'Shows tracking notification',
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onBackground,
      autoStart: true,
    ),
  );

  service.startService();
}

// Background service logic
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  // Add certificate bypass for background service
  HttpOverrides.global = MyHttpOverrides();
  
  myPrint("Background Service Started");

  // Use device info service
  final deviceInfoService = DeviceInfoService();
  await deviceInfoService.initializeDeviceInfo();
  
  // Use location service
  final locationService = LocationService();
  await locationService.startTracking();
  myPrint("Location service initialized");

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      locationService.stopTracking();
      service.stopSelf();
    });

    await service.setAsForegroundService();
    myPrint("Service set as foreground service");

    // Update notification content periodically
    Timer.periodic(Duration(minutes: AppConfig.BACKGROUND_UPDATE_INTERVAL_MINUTES), (timer) async {
      myPrint("Timer triggered at ${DateTime.now()}");
      if (await service.isForegroundService()) {
        final now = DateTime.now();
        final hour = now.hour;

        service.setForegroundNotificationInfo(
          title: "SPITracker",
          content: "Checking status... ${now.toString().split('.').first}",
        );

        if (AppConfig.isWithinActiveHours(now)) {
          try {
            myPrint("In active hours, checking location");
            final lastPosition = locationService.lastPosition;
            if (lastPosition == null) {
              myPrint("No position data available yet");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Waiting for location data...",
              );
              return;
            }

            myPrint("Preparing API call with position: ${lastPosition.latitude}, ${lastPosition.longitude}");
            
            // Use device info service for API payload
            final body = jsonEncode({
              'deviceId': deviceInfoService.deviceId,
              'latitude': lastPosition.latitude.toString(),
              'longitude': lastPosition.longitude.toString(),
              'androidVersion': deviceInfoService.osVersion,
              'model': deviceInfoService.deviceModel,
            });

            myPrint("Sending API request...");
            // Create HTTP client
            final httpClient = HttpClient()
              ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
            
            final request = await httpClient.postUrl(
              Uri.parse(AppConfig.getApiUrl())
            );
            
            request.headers.set('content-type', 'application/json');
            request.write(body);
            
            final response = await request.close().timeout(
              Duration(seconds: AppConfig.API_TIMEOUT_SECONDS),
              onTimeout: () {
                throw TimeoutException('The connection has timed out');
              },
            );

            final responseBody = await response.transform(utf8.decoder).join();

            // Update notification with status
            if (response.statusCode == 200) {
              myPrint("Background API call successful");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update: ${now.toString().split('.').first} (Success)",
              );
            } else {
              myPrint("Background API call failed: ${response.statusCode}");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update failed: ${now.toString().split('.').first}",
              );
            }
          } catch (e) {
            myPrint("Error in API call: $e");
            service.setForegroundNotificationInfo(
              title: "SPITracker",
              content: "Error: ${e.toString().split('\n').first}",
            );
          }
        } else {
          myPrint("Outside active hours");
          service.setForegroundNotificationInfo(
            title: "SPITracker",
            content: "Outside active hours (${AppConfig.ACTIVE_HOURS_START}:00-${AppConfig.ACTIVE_HOURS_END}:00)",
          );
        }

        myPrint("Background cycle completed");
      } else {
        myPrint("Service not in foreground, attempting to set as foreground");
        await service.setAsForegroundService();
      }
    });
  }
}

// iOS Background Task
Future<bool> onBackground(ServiceInstance service) async {
  myPrint("Background service running in background mode.");
  return true;
}

// API Call Function
Future<String> sendApiData() async {
  try {
    final now = DateTime.now();
    
    if (AppConfig.isWithinActiveHours(now)) {
      // Use location service
      final locationService = LocationService();
      bool hasPermission = await locationService.checkAndRequestLocationPermission();
      if (!hasPermission) {
        return "Error: Location permission denied";
      }
      
      final position = await locationService.getCurrentPosition();
      if (position == null) {
        return "Error: Couldn't get location";
      }
      
      // Use device info service
      final deviceInfoService = DeviceInfoService();
      await deviceInfoService.initializeDeviceInfo();
      
      // Create API payload
      final body = jsonEncode({
        'deviceId': deviceInfoService.deviceId,
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'androidVersion': deviceInfoService.osVersion,
        'model': deviceInfoService.deviceModel,
      });

      myPrint("calling API...");

      // Create a custom HTTP client that ignores certificate verification
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      
      final request = await httpClient.postUrl(
        Uri.parse(AppConfig.getApiUrl())
      );
      
      request.headers.set('content-type', 'application/json');
      request.write(body);
      
      final response = await request.close().timeout(
        Duration(seconds: AppConfig.API_TIMEOUT_SECONDS),
        onTimeout: () {
          throw TimeoutException('The connection has timed out');
        },
      );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        myPrint("API call successful.");
        return "Completed 200 on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      } else {
        myPrint("Body: ${body}");
        myPrint("API call failed: ${response.statusCode} ${responseBody}");
        return "Failed Status ${response.statusCode} ${responseBody} on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      }
    }
    return "Skipped (Out of Active Hours)";
  } catch (e) {
    myPrint("Error in API call: $e");
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
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  String _appVersion = "Loading application version";

  final LocationService _locationService = LocationService();
  final DeviceInfoService _deviceInfoService = DeviceInfoService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    // Initialize device info
    await _deviceInfoService.initializeDeviceInfo();
    setState(() {
      _deviceInfo = _deviceInfoService.getFormattedDeviceInfo();
      _deviceId = _deviceInfoService.deviceId;
      _appVersion = _deviceInfoService.appVersion;
    });
    
    // Check other services
    _checkServiceStatus();
    _checkLocationPermission();
    _updateLocationInfo();
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
    await _locationService.checkAndRequestLocationPermission();
  }

  // Add method to update location information
  Future<void> _updateLocationInfo() async {
    try {
      bool hasPermission = await _locationService.checkAndRequestLocationPermission();
      if (!hasPermission) {
        setState(() {
          _locationInfo = "Location permission denied";
        });
        return;
      }

      setState(() {
        _locationInfo = "Getting location...";
      });

      final position = await _locationService.getCurrentPosition();
      
      setState(() {
        if (position != null) {
          _locationInfo = "Latitude: ${position.latitude.toStringAsFixed(6)}\nLongitude: ${position.longitude.toStringAsFixed(6)}";
        } else {
          _locationInfo = "Error getting location";
        }
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
    bool hasPermission = await _locationService.checkAndRequestLocationPermission();
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

  // Add method to open battery optimization settings
  Future<void> _openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
      try {
        // Use app_settings package with the correct method
        await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
      } catch (e) {
        // Fallback to permission_handler if app_settings fails
        try {
          await Permission.ignoreBatteryOptimizations.request();
        } catch (e2) {
          myPrint("Failed to open settings: $e2");
          // Show a dialog with instructions if both methods fail
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text("Open Settings Manually"),
                content: Text(
                  "Please open your device settings and navigate to:\n"
                  "Battery > Battery Optimization > All Apps > SPITracker\n"
                  "Then select 'Don't optimize' to allow background operation."
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("OK"),
                  ),
                ],
              ),
            );
          }
        }
      }
    } else {
      // For iOS or other platforms
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Battery Optimization"),
          content: Text(
            Platform.isIOS
                ? "On iOS, please make sure Background App Refresh is enabled in Settings > General > Background App Refresh."
                : "Battery optimization settings are only available on Android devices."
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 4, // Add shadow to AppBar
        actions: [
          // Add debug log menu option
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'debug_logs') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LogScreen()),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'debug_logs',
                  child: Row(
                    children: [
                      Icon(Icons.bug_report, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Debug Logs'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0), // Add padding around the content
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Application", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_appVersion, style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Device ID", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_deviceId, style: TextStyle(fontSize: 16, color: Colors.blue)),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Current Location", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _locationInfo,
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _updateLocationInfo,
                icon: Icon(Icons.my_location),
                label: Text("Update Location"),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _toggleBackgroundService,
                    child: Text(_isBackgroundEnabled ? "Stop Background" : "Start Background"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _openBatteryOptimizationSettings,
                    icon: Icon(Icons.battery_charging_full),
                    label: Text("Battery Settings"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isApiCalling ? null : _callApiImmediately,
                child: _isApiCalling ? CircularProgressIndicator() : const Text("Send API Now"),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              const SizedBox(height: 10),
              Text(_apiStatus, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _checkServiceStatus,
                icon: Icon(Icons.refresh),
                label: Text("Refresh Status"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
