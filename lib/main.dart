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

// HTTP certificate bypass helper
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  // Set up HTTP certificate bypass for background service
  HttpOverrides.global = MyHttpOverrides();
  
  // Add a special log entry to indicate background service start
  logBackground("Background Service Started");

  // Initialize device info
  final deviceInfoService = DeviceInfoService();
  await deviceInfoService.initializeDeviceInfo();
  
  // Initialize location service
  final locationService = LocationService();
  await locationService.startTracking();
  logBackground("Location service initialized in background");

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      logBackground("Service setAsForeground listen");
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      logBackground("Service setAsBackground listen");
      service.setAsBackgroundService();
    });
  }

  if (service is AndroidServiceInstance) {

    service.on('stopService').listen((event) {
      locationService.stopTracking();
      logBackground("Service stopping due to stopService request");
      service.stopSelf();
    });

    try {
      // Create notification and set as foreground service
      await service.setAsForegroundService();
      logBackground("Successfully set as foreground service with notification");
    } catch (e) {
      logBackground("Error setting foreground service: $e", isError: true);
    }

    await service.setAsForegroundService();
    logBackground("Service set as foreground service");

    // Update notification content periodically
    Timer.periodic(Duration(minutes: AppConfig.BACKGROUND_UPDATE_INTERVAL_MINUTES), (timer) async {
      logBackground("Timer triggered at ${DateTime.now()}");
      
      if (await service.isForegroundService()) {
        final now = DateTime.now();

        service.setForegroundNotificationInfo(
          title: "SPITracker",
          content: "Checking status... ${now.toString().split('.').first}",
        );

        if (AppConfig.isWithinActiveHours(now)) {
          try {
            logBackground("In active hours, checking location");
            final lastPosition = locationService.lastPosition;
            
            if (lastPosition == null) {
              logBackground("No position data available yet", isWarning: true);
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Waiting for location data...",
              );
              return;
            }

            logBackground("Preparing API call with position: ${lastPosition.latitude}, ${lastPosition.longitude}");
            
            // Prepare API call
            final body = jsonEncode({
              'deviceId': deviceInfoService.deviceId,
              'latitude': lastPosition.latitude.toString(),
              'longitude': lastPosition.longitude.toString(),
              'androidVersion': deviceInfoService.osVersion,
              'model': deviceInfoService.deviceModel,
            });

            logBackground("Sending API request...");
            
            // Create HTTP client
            final httpClient = HttpClient()
              ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
            
            final request = await httpClient.postUrl(
              Uri.parse(AppConfig.getApiUrl())
            );
            
            request.headers.set('content-type', 'application/json');
            request.write(body);
            
            final response = await request.close();
            final responseBody = await response.transform(utf8.decoder).join();

            // Update notification with status
            if (response.statusCode == 200) {
              logBackground("Background API call successful");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update: ${now.toString().split('.').first} (Success)",
              );
            } else {
              logBackground("Background API call failed: ${response.statusCode}", isError: true);
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update failed: ${now.toString().split('.').first}",
              );
            }
          } catch (e) {
            logBackground("Error in API call: $e", isError: true);
            service.setForegroundNotificationInfo(
              title: "SPITracker",
              content: "Error: ${e.toString().split('\n').first}",
            );
          }
        } else {
          logBackground("Outside active hours");
          service.setForegroundNotificationInfo(
            title: "SPITracker",
            content: "Outside active hours (${AppConfig.ACTIVE_HOURS_START}:00-${AppConfig.ACTIVE_HOURS_END}:00)",
          );
        }

        logBackground("Background cycle completed");
      } else {
        logBackground("Service not in foreground, attempting to set as foreground", isWarning: true);
        await service.setAsForegroundService();
      }
    });
  }
}

// iOS Background Task
@pragma('vm:entry-point')
Future<bool> onBackground(ServiceInstance service) async {
  logInfo("Background service running in background mode.");
  return true;
}

// Initialize the background service
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      foregroundServiceNotificationId: 888,
      initialNotificationTitle: 'SPITracker',
      initialNotificationContent: 'Tracking location in background',
      autoStartOnBoot: true,
      // notificationChannelId: 'spi_tracker_channel',
      // notificationChannelName: 'SPITracker Service',
      // notificationChannelDescription: 'Shows service running in background',
      // notificationChannelImportance: AndroidNotificationChannelImportance.HIGH,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onBackground,
      autoStart: true,
    ),
  );

  bool started = await service.startService();
  logBackground("Background service start attempt result: $started");
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
        logError("Location permission denied");
        return "Error: Location permission denied";
      }
      
      final position = await locationService.getCurrentPosition();
      if (position == null) {
        logError("Couldn't get location");
        return "Error: Couldn't get location";
      }
      
      // Use device info service
      final deviceInfoService = DeviceInfoService();
      await deviceInfoService.initializeDeviceInfo();
      
      logInfo("Calling API from foreground...");

      final body = jsonEncode({
        'deviceId': deviceInfoService.deviceId,
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'androidVersion': deviceInfoService.osVersion,
        'model': deviceInfoService.deviceModel,
      });

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
          logError("API call timed out");
          throw TimeoutException('The connection has timed out');
        },
      );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        logInfo("API call successful");
        return "Completed 200 on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      } else {
        logError("API call failed: ${response.statusCode} ${responseBody}");
        return "Failed Status ${response.statusCode} ${responseBody} on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      }
    }
    logInfo("Skipped API call (Out of Active Hours)");
    return "Skipped (Out of Active Hours)";
  } catch (e) {
    logError("Error in API call: $e");
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  
  // Initialize the background service directly
  await initializeBackgroundService();
  
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
  bool _isIgnoringBatteryOptimization = false;

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
    
    // Explicitly request battery optimization exemption
    await _requestIgnoreBatteryOptimization();
    
    // Check other services
    _checkServiceStatus();
    _checkLocationPermission();
    _updateLocationInfo();
    _checkBatteryOptimizationStatus();
    
    // Add auto-start on boot verification
    _verifyAutoStartOnBoot();
  }

  // Add method to check background service status
  Future<void> _checkServiceStatus() async {
    try {
      final isRunning = await isServiceRunning();
      
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

  // Add this method to check battery optimization status
  Future<void> _checkBatteryOptimizationStatus() async {
    if (Platform.isAndroid) {
      try {
        bool isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
        setState(() {
          _isIgnoringBatteryOptimization = isIgnoring;
        });
        myPrint("Battery optimization ignored: $isIgnoring");
      } catch (e) {
        myPrint("Error checking battery optimization status: $e");
        setState(() {
          _isIgnoringBatteryOptimization = false;
        });
      }
    }
  }

  // Add this method to verify and enable auto-start on boot
  Future<void> _verifyAutoStartOnBoot() async {
    if (Platform.isAndroid) {
      try {
        // Just make sure the service is running
        bool isRunning = await isServiceRunning();
        if (!isRunning) {
          await startService();
          myPrint("Started service to ensure boot auto-start works");
        } else {
          myPrint("Service is running with boot auto-start enabled in configuration");
        }
      } catch (e) {
        myPrint("Error checking service status: $e");
      }
    }
  }

  // Check if the service is running
  Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  // Start the service
  Future<void> startService() async {
    final service = FlutterBackgroundService();
    logBackground("startService > FlutterBackgroundService");
    await service.startService();
  }

  // Stop the service
  Future<void> stopService() async {
    final service = FlutterBackgroundService();
    logBackground("stopService > FlutterBackgroundService");
    service.invoke("stopService");
  }

  void _toggleBackgroundService() async {
    // if (_isBackgroundEnabled) {
    //   await stopService();
    //   setState(() {
    //     _isBackgroundEnabled = false;
    //     _serviceStatus = "Background service stopped";
    //   });
    // } else {
      await startService();
      setState(() {
        _isBackgroundEnabled = true;
        _serviceStatus = "Background service started";
      });
    //}
    
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

  // Modify your _openBatteryOptimizationSettings method to update status after settings change
  Future<void> _openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
      try {
        // Use app_settings package with the correct method
        await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
        // Check status again after a delay to allow user to make changes
        Future.delayed(Duration(seconds: 2), () {
          _checkBatteryOptimizationStatus();
        });
      } catch (e) {
        // Fallback to permission_handler if app_settings fails
        try {
          await Permission.ignoreBatteryOptimizations.request();
          // Check status immediately after request
          _checkBatteryOptimizationStatus();
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

  Future<void> _requestIgnoreBatteryOptimization() async {
    if (Platform.isAndroid) {
      bool isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
      if (!isIgnoring) {
        try {
          // Request permission directly
          PermissionStatus status = await Permission.ignoreBatteryOptimizations.request();
          logBackground("Battery optimization permission request result: ${status.toString()}");
          setState(() {
            _isIgnoringBatteryOptimization = status.isGranted;
          });
        } catch (e) {
          logBackground("Error requesting battery optimization: $e", isError: true);
        }
      }
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
                        {"Battery Optimization": _isIgnoringBatteryOptimization ? "Disabled (Good)" : "Enabled (May affect background service)"},
                      ]),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _toggleBackgroundService,
                            child: Text(_isBackgroundEnabled ? "✅ Restart Background Service" : "❌ Restart Background Service"),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              backgroundColor: _isBackgroundEnabled ? Colors.red : Colors.green,
                            ),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _checkServiceStatus();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Background service status: ${_isBackgroundEnabled ? 'Running' : 'Stopped'}")),
                              );
                            },
                            icon: Icon(Icons.health_and_safety),
                            label: Text("Check Status"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openBatteryOptimizationSettings,
                            icon: Icon(Icons.battery_charging_full),
                            label: Text(_isIgnoringBatteryOptimization 
                                ? "Battery Opt. Disabled" 
                                : "Disable Battery Opt."),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isIgnoringBatteryOptimization ? Colors.green : Colors.orange,
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
                    _checkBatteryOptimizationStatus();
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

