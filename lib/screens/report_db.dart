import 'package:SRL_LoL/screens/self_learning.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:convert';

import '../theme/lumen_theme.dart';

// ファイル名（例: "highlight_1_NORMAL_DEATH_43s.mp4"）を日本語ラベルに変換する
String _highlightLabel(String highlightRef) {
  final filename = highlightRef.split('/').last;
  final match = RegExp(
    r'_(IMPULSE_MISSED|NORMAL_DEATH)_(\d+)s\.mp4$',
  ).firstMatch(filename);
  if (match == null) return 'ハイライト';
  final typeLabel = match.group(1) == 'IMPULSE_MISSED' ? '衝動性の制御失敗' : '通常のデス';
  final seconds = match.group(2);
  return '$typeLabel @ $seconds秒';
}

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
      _reflectionsFuture = http
          .get(Uri.parse('$backendBaseUrl/api/reflections'))
          .then((response) {
            if (response.statusCode == 200) {
              final List<dynamic> decodedList = jsonDecode(response.body);
              return decodedList
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
            } else {
              throw Exception('Failed to load reflections');
            }
          })
          .catchError((error) {
            print('Error fetching reflections: $error');
            throw error;
          });
    });
  }

  // 動画解析ジョブが紐づいている場合のみ、srl_scoreとは別の指標として表示する
  Widget _buildVideoMetric(Map<String, dynamic> ref) {
    final status = ref['video_status'];
    if (status == null) return const SizedBox.shrink();

    if (status != 'done') {
      final label = status == 'error' ? '動画解析に失敗しました' : '動画解析中...';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(label, style: TextStyle(color: LumenColors.inkMuted)),
      );
    }

    final result = ref['video_result'] as Map<String, dynamic>?;
    final ratio = result?['impulse_control_failure_ratio'];
    final deathCount = result?['death_count'];
    if (ratio == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: LumenReadout(
        icon: Icons.speed,
        value: '${(ratio * 100).toStringAsFixed(0)}%',
        caption: 'デス$deathCount回中の衝動性コントロール失敗率',
      ),
    );
  }

  // 解析済みのハイライトクリップを一覧表示し、タップで再生ダイアログを開く
  Widget _buildHighlightList(Map<String, dynamic> ref) {
    if (ref['video_status'] != 'done') return const SizedBox.shrink();

    final result = ref['video_result'] as Map<String, dynamic>?;
    final highlightRefs = (result?['highlight_refs'] as List?)?.cast<String>();
    if (highlightRefs == null || highlightRefs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: highlightRefs.map((highlightRef) {
          return ActionChip(
            avatar: const Icon(Icons.play_arrow, size: 18),
            label: Text(_highlightLabel(highlightRef)),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _HighlightPlayerDialog(
                url: '$backendBaseUrl/api/video_analysis/highlights/$highlightRef',
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflection History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshList),
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
              final date = DateTime.parse(
                ref['date'],
              ).toLocal().toString().split('.')[0];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(ref['topic']),
                      subtitle: Text('${ref['content']}\n\n$date'),
                      isThreeLine: true,
                    ),
                    _buildVideoMetric(ref),
                    _buildHighlightList(ref),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ハイライトクリップをダイアログ内でインライン再生するウィジェット
class _HighlightPlayerDialog extends StatefulWidget {
  final String url;

  const _HighlightPlayerDialog({required this.url});

  @override
  State<_HighlightPlayerDialog> createState() =>
      _HighlightPlayerDialogState();
}

class _HighlightPlayerDialogState extends State<_HighlightPlayerDialog> {
  late final VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isInitialized) ...[
                Flexible(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
                VideoProgressIndicator(_controller, allowScrubbing: true),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      onPressed: () {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      },
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
