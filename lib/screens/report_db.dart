import 'package:flutter/material.dart';
import '../helpers/database_helper.dart';

class Report_dbWidget extends StatefulWidget {
  @override
  _Report_dbWidgetState createState() => _Report_dbWidgetState();
}

class _Report_dbWidgetState extends State<Report_dbWidget> {
  late Future<List<Map<String, dynamic>>> _reflectionsFuture;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _reflectionsFuture = DatabaseHelper.instance.fetchReflections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflection History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshList,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reflectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No reflections found.'));
          }

          final reflections = snapshot.data!;

          return ListView.builder(
            itemCount: reflections.length,
            itemBuilder: (context, index) {
              final ref = reflections[index];
              final date = DateTime.parse(ref['date']).toLocal().toString().split('.')[0];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(ref['topic']),
                  subtitle: Text('${ref['content']}\n\n$date'),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}