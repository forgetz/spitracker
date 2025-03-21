import 'dart:async';
import 'package:flutter/material.dart';
import 'log_utils.dart';  // Import the new utility file

class LogScreen extends StatefulWidget {
  const LogScreen({Key? key}) : super(key: key);

  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scrollController = ScrollController();
  List<LogEntry> _logs = [];
  Timer? _refreshTimer;

  bool _showBackgroundLogs = true;
  bool _showInfoLogs = true;
  bool _showWarningLogs = true;
  bool _showErrorLogs = true;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
    
    // Refresh logs every second
    _refreshTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _refreshLogs();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshLogs() async {
    final logs = await loadLogsFromFile();
    setState(() {
      _logs = logs;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  List<String> getFilteredLogs(List<String> allLogs) {
    return allLogs.where((log) {
      if (log.contains("[BG-") && !_showBackgroundLogs) return false;
      
      if (!_showInfoLogs && (log.contains("[INFO]") || log.contains("[BG-INFO]"))) return false;
      if (!_showWarningLogs && (log.contains("[WARN]") || log.contains("[BG-WARN]"))) return false;
      if (!_showErrorLogs && (log.contains("[ERROR]") || log.contains("[BG-ERROR]"))) return false;
      
      return true;
    }).toList();
  }

  Row buildFilterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FilterChip(
          label: Text("Background"),
          selected: _showBackgroundLogs,
          onSelected: (value) {
            setState(() {
              _showBackgroundLogs = value;
            });
          },
        ),
        FilterChip(
          label: Text("Info"),
          selected: _showInfoLogs,
          onSelected: (value) {
            setState(() {
              _showInfoLogs = value;
            });
          },
        ),
        FilterChip(
          label: Text("Warning"),
          selected: _showWarningLogs,
          onSelected: (value) {
            setState(() {
              _showWarningLogs = value;
            });
          },
        ),
        FilterChip(
          label: Text("Error"),
          selected: _showErrorLogs,
          onSelected: (value) {
            setState(() {
              _showErrorLogs = value;
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scroll to bottom after build
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Debug Logs'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              // Show confirmation dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Clear Logs"),
                  content: Text("Are you sure you want to clear all logs?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context); // Close dialog
                        await clearLogs();
                        _refreshLogs();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Logs cleared"))
                        );
                      },
                      child: Text("Clear"),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Add filter chips to select log types
          // Padding(
          //   padding: const EdgeInsets.all(8.0),
          //   child: buildFilterRow(),
          // ),
          Expanded(
            child: _logs.isEmpty
                ? Center(child: Text('No logs available'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      
                      // Standard log entry without special formatting for background logs
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${log.formattedTime}] ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${log.level}: ',
                              style: TextStyle(
                                fontSize: 12,
                                // Use the color from the LogEntry class instead of a standard color
                                color: log.levelColor,  // This uses the colors defined in LogEntry
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                log.message,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scrollToBottom,
        child: Icon(Icons.arrow_downward),
        tooltip: 'Scroll to bottom',
      ),
    );
  }
} 