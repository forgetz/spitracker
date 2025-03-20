import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'log_utils.dart';

class DeviceInfoService {
  // Singleton pattern
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  // Instance of DeviceInfoPlugin
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  
  // Device information cache
  String _deviceId = "Unknown";
  String _deviceModel = "Unknown";
  String _osVersion = "Unknown";
  String _manufacturer = "Unknown";
  String _brand = "Unknown";
  String _appVersion = "Unknown";
  String _appName = "Unknown";
  String _appBuildNumber = "Unknown";
  String _appPackageName = "Unknown";
  
  // Getters for device info
  String get deviceId => _deviceId;
  String get deviceModel => _deviceModel;
  String get osVersion => _osVersion;
  String get manufacturer => _manufacturer;
  String get brand => _brand;
  String get appVersion => _appVersion;
  String get appName => _appName;
  String get appBuildNumber => _appBuildNumber;
  String get appPackageName => _appPackageName;
  
  // Full device information as a map
  Map<String, String> get deviceInfoMap => {
    'deviceId': _deviceId,
    'model': _deviceModel,
    'osVersion': _osVersion,
    'manufacturer': _manufacturer,
    'brand': _brand,
    'appVersion': _appVersion,
    'appName': _appName,
    'appBuildNumber': _appBuildNumber,
    'appPackageName': _appPackageName,
  };
  
  // Initialize all device info
  Future<void> initializeDeviceInfo() async {
    await Future.wait([
      _loadDeviceInfo(),
      _loadAppInfo(),
    ]);
    
    myPrint("Device info initialized: $deviceModel, $osVersion, ID: $deviceId");
  }
  
  // Load device-specific information
  Future<void> _loadDeviceInfo() async {
    try {
      if (kIsWeb) {
        await _loadWebInfo();
      } else if (Platform.isAndroid) {
        await _loadAndroidInfo();
      } else if (Platform.isIOS) {
        await _loadIosInfo();
      } else {
        myPrint("Unsupported platform for device info");
      }
    } catch (e) {
      myPrint("Error loading device info: $e");
    }
  }
  
  // Load Android device information
  Future<void> _loadAndroidInfo() async {
    final androidInfo = await _deviceInfoPlugin.androidInfo;
    _deviceId = androidInfo.id ?? "Unknown";
    _deviceModel = androidInfo.model ?? "Unknown";
    _osVersion = androidInfo.version.release ?? "Unknown";
    _manufacturer = androidInfo.manufacturer ?? "Unknown";
    _brand = androidInfo.brand ?? "Unknown";
  }
  
  // Load iOS device information
  Future<void> _loadIosInfo() async {
    final iosInfo = await _deviceInfoPlugin.iosInfo;
    _deviceId = iosInfo.identifierForVendor ?? "Unknown";
    _deviceModel = iosInfo.model ?? "Unknown";
    _osVersion = iosInfo.systemVersion ?? "Unknown";
    _manufacturer = "Apple";
    _brand = "Apple";
  }
  
  // Load Web device information
  Future<void> _loadWebInfo() async {
    final webInfo = await _deviceInfoPlugin.webBrowserInfo;
    _deviceId = webInfo.userAgent ?? "Unknown";
    _deviceModel = "Web Browser";
    _osVersion = webInfo.browserName.name;
    _manufacturer = "Web";
    _brand = "Web";
  }
  
  // Load application information
  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appName = packageInfo.appName;
      _appVersion = packageInfo.version;
      _appBuildNumber = packageInfo.buildNumber;
      _appPackageName = packageInfo.packageName;
    } catch (e) {
      myPrint("Error loading app info: $e");
    }
  }
  
  // Get formatted device info string for display
  String getFormattedDeviceInfo() {
    if (kIsWeb) {
      return '''
Platform: Web
Browser: $_osVersion
User Agent: $_deviceId
      ''';
    } else if (Platform.isAndroid) {
      return '''
Device: $_deviceModel
Brand: $_brand
Android Version: $_osVersion
Manufacturer: $_manufacturer
      ''';
    } else if (Platform.isIOS) {
      return '''
Device: $_deviceModel
iOS Version: $_osVersion
Manufacturer: Apple
      ''';
    } else {
      return 'Current platform information not available';
    }
  }
} 