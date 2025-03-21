import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'log_utils.dart';
import 'app_config.dart';
import 'location_service.dart';
import 'device_info_service.dart';

class BackgroundServiceManager {
  // Singleton pattern
  static final BackgroundServiceManager _instance = BackgroundServiceManager._internal();
  factory BackgroundServiceManager() => _instance;
  BackgroundServiceManager._internal();

  // Initialize background service
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
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onBackground,
        autoStart: true,
      ),
    );

    service.startService();
  }

  // Check if the service is running
  Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  // Start the service
  Future<void> startService() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  // Stop the service
  Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");
  }
}

// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Set up HTTP certificate bypass for background service
  HttpOverrides.global = MyHttpOverrides();
  
  logInfo("Background Service Started");

  // Initialize device info
  final deviceInfoService = DeviceInfoService();
  await deviceInfoService.initializeDeviceInfo();
  
  // Initialize location service
  final locationService = LocationService();
  await locationService.startTracking();
  logInfo("Location service initialized in background");

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      locationService.stopTracking();
      service.stopSelf();
    });

    await service.setAsForegroundService();
    logInfo("Service set as foreground service");

    // Update notification content periodically
    Timer.periodic(Duration(minutes: AppConfig.BACKGROUND_UPDATE_INTERVAL_MINUTES), (timer) async {
      logDebug("Timer triggered at ${DateTime.now()}");
      
      if (await service.isForegroundService()) {
        final now = DateTime.now();

        service.setForegroundNotificationInfo(
          title: "SPITracker",
          content: "Checking status... ${now.toString().split('.').first}",
        );

        if (AppConfig.isWithinActiveHours(now)) {
          try {
            logInfo("In active hours, checking location");
            final lastPosition = locationService.lastPosition;
            
            if (lastPosition == null) {
              logWarning("No position data available yet");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Waiting for location data...",
              );
              return;
            }

            logDebug("Preparing API call with position: ${lastPosition.latitude}, ${lastPosition.longitude}");
            
            // Prepare API call
            final body = jsonEncode({
              'deviceId': deviceInfoService.deviceId,
              'latitude': lastPosition.latitude.toString(),
              'longitude': lastPosition.longitude.toString(),
              'androidVersion': deviceInfoService.osVersion,
              'model': deviceInfoService.deviceModel,
            });

            logDebug("Sending API request...");
            
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
              logInfo("Background API call successful");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update: ${now.toString().split('.').first} (Success)",
              );
            } else {
              logError("Background API call failed: ${response.statusCode}");
              service.setForegroundNotificationInfo(
                title: "SPITracker",
                content: "Last update failed: ${now.toString().split('.').first}",
              );
            }
          } catch (e) {
            logError("Error in API call: $e");
            service.setForegroundNotificationInfo(
              title: "SPITracker",
              content: "Error: ${e.toString().split('\n').first}",
            );
          }
        } else {
          logInfo("Outside active hours");
          service.setForegroundNotificationInfo(
            title: "SPITracker",
            content: "Outside active hours (${AppConfig.ACTIVE_HOURS_START}:00-${AppConfig.ACTIVE_HOURS_END}:00)",
          );
        }

        logDebug("Background cycle completed");
      } else {
        logWarning("Service not in foreground, attempting to set as foreground");
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

// HTTP certificate bypass helper
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
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
      
      logInfo("calling API...");

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
          throw TimeoutException('The connection has timed out');
        },
      );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        logInfo("API call successful.");
        return "Completed 200 on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      } else {
        logWarning("Body: ${body}");
        logError("API call failed: ${response.statusCode} ${responseBody}");
        return "Failed Status ${response.statusCode} ${responseBody} on ${now.day} ${_getMonthName(now.month)} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      }
    }
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