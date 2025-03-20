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
              await clearLogs();
              _refreshLogs();
            },
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _logs.isEmpty
                ? Center(child: Text('No logs available'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
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
                                color: log.levelColor,
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