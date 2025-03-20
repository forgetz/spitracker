import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'log_utils.dart';
import 'app_config.dart';  // Import the config

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Current position
  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  // Stream controller
  StreamSubscription<Position>? _positionStream;

  // Initialize location settings using the config value
  final LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: AppConfig.LOCATION_DISTANCE_FILTER_METERS,
  );

  // Start location tracking
  Future<void> startTracking() async {
    // Check permissions first
    bool hasPermission = await checkAndRequestLocationPermission();
    if (!hasPermission) {
      myPrint("Cannot start location tracking: Permission denied");
      return;
    }

    try {
      // Get initial position
      _lastPosition = await Geolocator.getCurrentPosition();
      myPrint("Initial position: ${_lastPosition?.latitude}, ${_lastPosition?.longitude}");

      // Start listening for position updates
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) {
          _lastPosition = position;
          myPrint("Position updated: ${position.latitude}, ${position.longitude}");
        },
        onError: (error) {
          myPrint("Position stream error: $error");
        }
      );
      myPrint("Location tracking started");
    } catch (e) {
      myPrint("Error starting location tracking: $e");
    }
  }

  // Stop location tracking
  void stopTracking() {
    if (_positionStream != null) {
      _positionStream!.cancel();
      _positionStream = null;
      myPrint("Location tracking stopped");
    }
  }

  // Get current position once
  Future<Position?> getCurrentPosition() async {
    try {
      bool hasPermission = await checkAndRequestLocationPermission();
      if (!hasPermission) {
        myPrint("Cannot get position: Permission denied");
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      _lastPosition = position; // Update last known position
      return position;
    } catch (e) {
      myPrint("Error getting current position: $e");
      return null;
    }
  }

  // Check and request location permission
  Future<bool> checkAndRequestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      myPrint('Location services are disabled.');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        myPrint('Location permissions are denied');
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever
      myPrint('Location permissions are permanently denied');
      return false;
    }

    // Permissions are granted
    return true;
  }

  // Get formatted location string
  String getFormattedLocation() {
    if (_lastPosition == null) {
      return "Location not available";
    }
    return "Latitude: ${_lastPosition!.latitude.toStringAsFixed(6)}\nLongitude: ${_lastPosition!.longitude.toStringAsFixed(6)}";
  }
} 