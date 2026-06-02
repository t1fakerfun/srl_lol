import 'package:flutter/material.dart';
import '../helpers/database_helper.dart';
import 'package:file_picker/file_picker.dart';

class SelflearningWidget extends StatefulWidget {
  @override
  _SelflearningWidgetState createState() => _SelflearningWidgetState();
}

class _SelflearningWidgetState extends State<SelflearningWidget> {
  final _topicController = TextEditingController();
  final _contentController = TextEditingController();
  String? _fileName;

  Future<void> _submitReflection() async {
    if (_topicController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all fields.')),
      );
      return;
    }

    final reflection = {
      'topic': _topicController.text,
      'content': _contentController.text,
      'date': DateTime.now().toIso8601String(),
    };

    await DatabaseHelper.instance.insertReflection(reflection);

    _topicController.clear();
    _contentController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reflection saved successfully!')),
      );
    }
  }
  Future<void> _pickFile() async{
    FilePickerResult? result = await FilePicker.pickFiles();
      if(result != null){
        setState((){
          _fileName = result.files.first.name;
        });
      }
  }
  @override
  void dispose() {
    _topicController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Self Learning (Reflection)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What did you learn or reflect on today?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton(
              onPressed: _pickFile,
              child: const Text('Upload Your Match Video'),
            ),
            const SizedBox(height: 10),
            if(_fileName != null) Text('Selected file: $_fileName'),
            const SizedBox(height: 16),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: 'Match ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Reflection Content',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitReflection,
              child: const Text('Submit Reflection'),
            ),
          ],
        ),
      ),
    );
  }
}