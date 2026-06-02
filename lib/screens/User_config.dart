import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class User_configWidget extends StatefulWidget {
  @override
  _User_configWidgetState createState() => _User_configWidgetState();
}

class _User_configWidgetState extends State<User_configWidget> {
  final _riotIdController = TextEditingController();
  final _regionController = TextEditingController();
  final _rankController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _riotIdController.text = prefs.getString('riotId') ?? '';
      _regionController.text = prefs.getString('region') ?? '';
      _rankController.text = prefs.getString('rank') ?? '';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('riotId', _riotIdController.text);
    await prefs.setString('region', _regionController.text);
    await prefs.setString('rank', _rankController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved successfully!')),
      );
    }
  }

  @override
  void dispose() {
    _riotIdController.dispose();
    _regionController.dispose();
    _rankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Configuration'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _riotIdController,
              decoration: const InputDecoration(
                labelText: 'Riot ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: 'Region',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rankController,
              decoration: const InputDecoration(
                labelText: 'Rank',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveData,
              child: const Text('Save Configuration'),
            ),
          ],
        ),
      ),
    );
  }
}