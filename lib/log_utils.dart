import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'app_config.dart';  // Import the config

// Log entry model that can be used across the app
class LogEntry {
  final String message;
  final String level;
  final DateTime timestamp;
  
  LogEntry(this.message, this.level, this.timestamp);
  
  String get formattedTime => 
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  
  Color get levelColor {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'DEBUG':
        return Colors.blue;
      default:
        return Colors.black;
    }
  }
}

// Constants now come from AppConfig
const int MAX_LOGS = AppConfig.MAX_LOG_ENTRIES;
const String LOG_FILE_PATH = AppConfig.LOG_FILE_NAME;

// Write a log entry to the file
Future<void> writeLogToFile(String message, {String level = 'INFO'}) async {
  // Skip if file logging is disabled or this log level is disabled
  if (!AppConfig.ENABLE_FILE_LOGGING || !AppConfig.shouldLogLevel(level)) {
    return;
  }
  
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${AppConfig.LOG_FILE_NAME}');
    
    // Ensure the message doesn't contain characters that would break JSON
    String safeMessage = message.replaceAll('"', '\\"');
    
    // Format log entry as JSON
    final logJson = jsonEncode({
      'message': safeMessage,
      'level': level,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Append to file
    await file.writeAsString('$logJson\n', mode: FileMode.append);
  } catch (e) {
    print('Error writing log to file: $e');
    // If JSON encoding fails, try a simpler format
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${AppConfig.LOG_FILE_NAME}');
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('{"message":"$level: $message","level":"$level","timestamp":"$timestamp"}\n', 
          mode: FileMode.append);
    } catch (e2) {
      print('Fallback logging also failed: $e2');
    }
  }
}

// Read log entries from the file
Future<List<LogEntry>> loadLogsFromFile() async {
  List<LogEntry> logs = [];
  
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${AppConfig.LOG_FILE_NAME}');
    
    if (await file.exists()) {
      final content = await file.readAsString();
      final lines = content.split('\n');
      
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          try {
            final logJson = jsonDecode(line);
            logs.add(LogEntry(
              logJson['message'] ?? 'No message',
              logJson['level'] ?? 'INFO',
              DateTime.tryParse(logJson['timestamp'] ?? '') ?? DateTime.now(),
            ));
          } catch (e) {
            // print('Error parsing log entry: $e - Content: $line');
            // // Try to recover the message even if JSON is corrupted
            // if (line.contains(':')) {
            //   logs.add(LogEntry(
            //     line,
            //     'ERROR',
            //     DateTime.now(),
            //   ));
            // }
          }
        }
      }
      
      // Sort logs by timestamp
      logs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Limit the number of logs
      if (logs.length > AppConfig.MAX_LOG_ENTRIES) {
        logs = logs.sublist(logs.length - AppConfig.MAX_LOG_ENTRIES);
      }
    }
  } catch (e) {
    print('Error loading logs from file: $e');
  }
  
  return logs;
}

// Clear all logs
Future<void> clearLogs() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${AppConfig.LOG_FILE_NAME}');
    
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    print('Error clearing logs: $e');
  }
}

// Print to console and log to file
void myPrint(String message, {String level = 'INFO'}) {
  // Console logging
  if (AppConfig.ENABLE_CONSOLE_LOGGING && AppConfig.shouldLogLevel(level)) {
    print("[$level] $message");
  }
  
  // File logging
  try {
    writeLogToFile(message, level: level);
  } catch (e) {
    if (AppConfig.ENABLE_CONSOLE_LOGGING) {
      print('Error in myPrint: $e');
    }
  }
}

// Enhanced logging methods for different log levels
void logInfo(String message) => myPrint(message, level: 'INFO');
void logWarning(String message) => myPrint(message, level: 'WARNING');
void logError(String message) => myPrint(message, level: 'ERROR');
void logDebug(String message) => myPrint(message, level: 'DEBUG'); 