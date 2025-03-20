import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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

// Constants
const String LOG_FILE_PATH = 'app_logs.txt';
const int MAX_LOGS = 1000;

// Write a log entry to the file
Future<void> writeLogToFile(String message, {String level = 'INFO'}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$LOG_FILE_PATH');
    
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
      final file = File('${directory.path}/$LOG_FILE_PATH');
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
    final file = File('${directory.path}/$LOG_FILE_PATH');
    
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
            //print('Error parsing log entry: $e - Content: $line');
            // Try to recover the message even if JSON is corrupted
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
      if (logs.length > MAX_LOGS) {
        logs = logs.sublist(logs.length - MAX_LOGS);
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
    final file = File('${directory.path}/$LOG_FILE_PATH');
    
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    print('Error clearing logs: $e');
  }
}

// Print to console and log to file
void myPrint(String message) {
  print(message);
  // Try-catch to prevent any errors in logging from affecting app operation
  try {
    writeLogToFile(message);
  } catch (e) {
    print('Error in myPrint: $e');
  }
} 