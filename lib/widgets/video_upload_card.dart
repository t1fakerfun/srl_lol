import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/self_learning.dart' show backendBaseUrl;
import '../services/video_uploader.dart';
import '../theme/lumen_theme.dart';

// 試合動画のアップロードと非同期解析の進行状況を表示する、振り返りフォームとは独立したカード。
// 解析は時間がかかるため、振り返りの入力中も常に状態が見える位置に固定表示する。
class VideoUploadCard extends StatefulWidget {
  final ValueChanged<int?> onJobIdChanged;

  const VideoUploadCard({super.key, required this.onJobIdChanged});

  @override
  State<VideoUploadCard> createState() => VideoUploadCardState();
}

class VideoUploadCardState extends State<VideoUploadCard> {
  String? _fileName;
  int? _videoJobId;
  String? _status; // uploading / pending / processing / done / error
  Map<String, dynamic>? _result;
  Timer? _pollTimer;

  // 振り返り送信完了後、親ウィジェットから呼び出してカードを初期状態に戻す
  void reset() {
    _pollTimer?.cancel();
    setState(() {
      _fileName = null;
      _videoJobId = null;
      _status = null;
      _result = null;
    });
    widget.onJobIdChanged(null);
  }

  Future<void> _pickFile() async {
    _pollTimer?.cancel();
    setState(() {
      _videoJobId = null;
      _status = null;
      _result = null;
    });
    widget.onJobIdChanged(null);

    try {
      final upload = await pickAndUploadVideo(
        uploadUrl: '$backendBaseUrl/api/video_analysis',
        onPicked: (fileName) {
          setState(() {
            _fileName = fileName;
            _status = 'uploading';
          });
        },
      );
      if (upload == null) return; // ユーザーがピッカーをキャンセルした

      setState(() {
        _videoJobId = upload.jobId;
        _status = upload.status;
      });
      widget.onJobIdChanged(upload.jobId);
      _startPolling();
    } catch (e) {
      print('動画アップロードエラー: $e');
      if (mounted) {
        setState(() {
          _status = 'error';
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_videoJobId == null) {
        timer.cancel();
        return;
      }
      try {
        final response = await http.get(
          Uri.parse('$backendBaseUrl/api/video_analysis/$_videoJobId'),
        );
        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _status = resData['status'];
              _result = resData['result'];
            });
          }
          if (resData['status'] == 'done' || resData['status'] == 'error') {
            timer.cancel();
          }
        }
      } catch (e) {
        print('動画解析状況の取得エラー: $e');
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Widget _buildStatus() {
    switch (_status) {
      case 'uploading':
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('動画をアップロード中...'),
          ],
        );
      case 'pending':
      case 'processing':
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('動画を解析中...（振り返りの入力を続けてください）'),
          ],
        );
      case 'done':
        final ratio = _result?['impulse_control_failure_ratio'];
        final deathCount = _result?['death_count'];
        final ratioText = ratio != null
            ? '${(ratio * 100).toStringAsFixed(0)}%'
            : '-';
        return LumenReadout(
          icon: Icons.check_circle_outline,
          value: ratioText,
          caption: 'デス$deathCount回中の衝動性コントロール失敗率',
        );
      case 'error':
        return Row(
          children: [
            const Icon(Icons.error_outline, color: LumenColors.coral, size: 18),
            const SizedBox(width: 8),
            Text('動画の解析に失敗しました', style: TextStyle(color: LumenColors.coral)),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_outlined, color: LumenColors.brass),
                const SizedBox(width: 8),
                Text('試合動画', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('試合動画をアップロード'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 10),
              Text('選択中のファイル: $_fileName'),
              const SizedBox(height: 8),
              _buildStatus(),
            ],
          ],
        ),
      ),
    );
  }
}
