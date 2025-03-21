import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:permission_handler/permission_handler.dart';
import 'log_screen.dart'; // Add this import for the LogScreen
import 'log_utils.dart';
import 'location_service.dart';
import 'app_config.dart';
import 'device_info_service.dart';
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  
  // Initialize the background service
  final backgroundService = BackgroundServiceManager();
  await backgroundService.initializeService();
  
  runApp(const MyApp());
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
  final BackgroundServiceManager _backgroundService = BackgroundServiceManager();

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
      final isRunning = await _backgroundService.isServiceRunning();
      
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
    if (_isBackgroundEnabled) {
      await _backgroundService.stopService();
      setState(() {
        _isBackgroundEnabled = false;
        _serviceStatus = "Background service stopped";
      });
    } else {
      await _backgroundService.startService();
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

    String result = await sendApiData();  // Using the function from background_service.dart
    
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
        elevation: 4,
        actions: [
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Version and Service Status Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          "Application Status",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(height: 16),
                      _buildInfoTable([
                        {"App Version": _appVersion},
                        {"Service Status": _serviceStatus},
                      ]),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _toggleBackgroundService,
                            child: Text(_isBackgroundEnabled ? "Stop Service" : "Start Service"),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              backgroundColor: _isBackgroundEnabled ? Colors.red : Colors.green,
                            ),
                          ),
                          SizedBox(width: 10),
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
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Device Information Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          "Device Information",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(height: 16),
                      _buildInfoTable([
                        {"Device ID": _deviceId},
                        {"Model": _deviceInfoService.deviceModel},
                        {"OS Version": _deviceInfoService.osVersion},
                        {"Manufacturer": _deviceInfoService.manufacturer},
                      ]),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Location Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          "Location Data",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(height: 16),
                      _buildInfoTable([
                        {"Location": _locationInfo},
                      ]),
                      SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _updateLocationInfo,
                          icon: Icon(Icons.my_location),
                          label: Text("Update Location"),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // API Status Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          "API Status",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(height: 16),
                      _buildInfoTable([
                        {"Last API Call": _apiStatus},
                      ]),
                      SizedBox(height: 16),
                      Center(
                        child: ElevatedButton(
                          onPressed: _isApiCalling ? null : _callApiImmediately,
                          child: _isApiCalling 
                              ? SizedBox(
                                  width: 20, 
                                  height: 20, 
                                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white)
                                ) 
                              : Text("Send API Now"),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Refresh Button
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    _checkServiceStatus();
                    _updateLocationInfo();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Status refreshed"))
                    );
                  },
                  icon: Icon(Icons.refresh),
                  label: Text("Refresh All Status"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add this helper method to create tables
  Widget _buildInfoTable(List<Map<String, String>> data) {
    return Table(
      border: TableBorder.all(
        color: Colors.grey.shade300,
        width: 1,
      ),
      columnWidths: {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(3),
      },
      children: data.map((row) {
        String title = row.keys.first;
        String value = row.values.first;
        
        return TableRow(
          decoration: BoxDecoration(
            color: Colors.white,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(value),
            ),
          ],
        );
      }).toList(),
    );
  }
}
