class AppConfig {
  // API endpoints
  static const String API_BASE_URL = 'https://gpstracking-tkgsit.aeonth.com';
  static const String API_GPS_ENDPOINT = '/v1/GPS/gps-save-papi';
  
  // Get full API URL
  static String getApiUrl() {
    return '$API_BASE_URL$API_GPS_ENDPOINT';
  }
  
  // Active hours configuration
  static const int ACTIVE_HOURS_START = 7;  // 7:00 AM
  static const int ACTIVE_HOURS_END = 24;   // 24:00 (midnight)
  
  // Check if current hour is within active hours
  static bool isWithinActiveHours(DateTime dateTime) {
    final hour = dateTime.hour;
    return hour >= ACTIVE_HOURS_START && hour < ACTIVE_HOURS_END;
  }
  
  // Background service configuration
  static const int BACKGROUND_UPDATE_INTERVAL_MINUTES = 1;
  
  // Location settings
  static const int LOCATION_DISTANCE_FILTER_METERS = 10;
  
  // API timeout
  static const int API_TIMEOUT_SECONDS = 20;
  
  // Log settings
  static const int MAX_LOG_ENTRIES = 1000;
  static const String LOG_FILE_NAME = 'app_logs.txt';
} 