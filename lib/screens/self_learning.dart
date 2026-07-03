import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

import '../services/video_uploader.dart';

const backendBaseUrl = 'http://127.0.0.1:5001';
const backendUrl = '$backendBaseUrl/api/reflection';

var url = Uri.parse(backendUrl);

class SelflearningWidget extends StatefulWidget {
  @override
  _SelflearningWidgetState createState() => _SelflearningWidgetState();
}

// データベース保存用のデータ構造クラス
class SRLReflection {
  String? targetType;
  double routineScore; // Sliderに合わせてdoubleに変更
  List<String> monitoringMetrics;
  List<String> failureCategories;
  String judgementLogic;
  String lessonLearned;
  int lessonQuality;
  int? videoJobId;

  SRLReflection({
    required this.targetType,
    required this.routineScore,
    required this.monitoringMetrics,
    required this.failureCategories,
    required this.judgementLogic,
    required this.lessonLearned,
    required this.lessonQuality,
    this.videoJobId,
  });

  Map<String, dynamic> toMap() {
    return {
      'targetType': targetType ?? '未設定',
      'routineScore': routineScore,
      'monitoringMetrics': monitoringMetrics.join(','),
      'failureCategories': failureCategories.join(','),
      'judgementLogic': judgementLogic,
      'lessonLearned': lessonLearned,
      'lessonQuality': lessonQuality,
      'videoJobId': videoJobId,
    };
  }
}

class _SelflearningWidgetState extends State<SelflearningWidget> {
  // ステッパーの現在のページ管理
  int _currentStep = 0;

  // 各フォームの状態を保持する変数
  String? _selectedTargetType;
  double _routineScore = 3.0;
  List<String> _selectedMetrics = [];
  List<String> _selectedFailures = [];

  final TextEditingController _logicController = TextEditingController();
  final TextEditingController _lessonController = TextEditingController();
  String? _fileName;

  // 動画解析ジョブの状態（アップロード直後から振り返り送信より前にバックグラウンドで進む）
  int? _videoJobId;
  String? _videoAnalysisStatus; // pending / processing / done / error
  Map<String, dynamic>? _videoAnalysisResult;
  Timer? _pollTimer;

  // データベースへの送信処理
  Future<void> _submitReflection() async {
    final reflection = SRLReflection(
      targetType: _selectedTargetType,
      routineScore: _routineScore,
      monitoringMetrics: _selectedMetrics,
      failureCategories: _selectedFailures,
      judgementLogic: _logicController.text,
      lessonLearned: _lessonController.text,
      lessonQuality: 3, // 必要に応じてLLM解析などで動的に変更
      videoJobId: _videoJobId,
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(reflection.toMap()),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('振り返りが保存されました!')));
        }
      } else {
        final resData = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存に失敗しました: ${resData['error']}')),
          );
        }
        return;
      }

      // 送信後のクリア処理
      _logicController.clear();
      _lessonController.clear();
      _pollTimer?.cancel();
      setState(() {
        _selectedTargetType = null;
        _routineScore = 3.0;
        _selectedMetrics = [];
        _selectedFailures = [];
        _currentStep = 0;
        _fileName = null;
        _videoJobId = null;
        _videoAnalysisStatus = null;
        _videoAnalysisResult = null;
      });
    } catch (e) {
      print('通信エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('サーバーとの通信に失敗しました')));
      }
    }
  }

  // 動画ファイルを選択し、即座にバックエンドへアップロードして非同期解析を開始する
  Future<void> _pickFile() async {
    _pollTimer?.cancel();
    setState(() {
      _videoJobId = null;
      _videoAnalysisStatus = null;
      _videoAnalysisResult = null;
    });

    try {
      final upload = await pickAndUploadVideo(
        uploadUrl: '$backendBaseUrl/api/video_analysis',
        onPicked: (fileName) {
          setState(() {
            _fileName = fileName;
            _videoAnalysisStatus = 'uploading';
          });
        },
      );
      if (upload == null) return; // ユーザーがピッカーをキャンセルした

      setState(() {
        _videoJobId = upload.jobId;
        _videoAnalysisStatus = upload.status;
      });
      _startPollingVideoStatus();
    } catch (e) {
      print('動画アップロードエラー: $e');
      if (mounted) {
        setState(() {
          _videoAnalysisStatus = 'error';
        });
      }
    }
  }

  // ジョブ状態を定期的にポーリングする（動画解析は時間がかかるため非同期ジョブ化されている）
  void _startPollingVideoStatus() {
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
              _videoAnalysisStatus = resData['status'];
              _videoAnalysisResult = resData['result'];
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
    _logicController.dispose();
    _lessonController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Widget _buildVideoAnalysisStatus() {
    switch (_videoAnalysisStatus) {
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
        final ratio = _videoAnalysisResult?['impulse_control_failure_ratio'];
        final deathCount = _videoAnalysisResult?['death_count'];
        final ratioText = ratio != null
            ? '${(ratio * 100).toStringAsFixed(0)}%'
            : '-';
        return Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('動画解析完了: デス$deathCount回中、衝動性コントロール失敗率 $ratioText'),
            ),
          ],
        );
      case 'error':
        return const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text('動画の解析に失敗しました'),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Step> _step = [
      Step(
        isActive: _currentStep >= 0,
        title: const Text('予見段階: 目標と計画の確認'),
        content: Column(
          children: [
            ElevatedButton(
              onPressed: _pickFile,
              child: const Text('Upload Your Match Video'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 10),
              Text('Selected file: $_fileName'),
              const SizedBox(height: 8),
              _buildVideoAnalysisStatus(),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '設定した目標のタイプ',
                border: OutlineInputBorder(),
              ),
              value: _selectedTargetType,
              items:
                  ['キル関与率を上げる', 'デス数を減らす', '視界確保を強化する', 'CSを安定させる', 'レーンを勝ちにいく']
                      .map(
                        (val) => DropdownMenuItem(value: val, child: Text(val)),
                      )
                      .toList(),
              onChanged: (val) => setState(() => _selectedTargetType = val),
            ),
            const SizedBox(height: 16),
            Text('練習の構造化ルーチン (現在のスコア: ${_routineScore.toInt()})'),
            Slider(
              value: _routineScore,
              min: 1,
              max: 5,
              divisions: 4,
              label: _routineScore.toInt().toString(),
              onChanged: (value) => setState(() => _routineScore = value),
            ),
          ],
        ),
      ),
      Step(
        isActive: _currentStep >= 1,
        title: const Text('遂行段階: 自己監視'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('プレイ中に監視していた指標（複数選択可）'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              children: ['統計データ (CS/KDA)', '技術・フォーム (位置取りなど)', '敵の状況 (スキル有無等)']
                  .map((metric) {
                    final isSelected = _selectedMetrics.contains(metric);
                    return FilterChip(
                      label: Text(metric),
                      selected: isSelected,
                      onSelected: (checked) {
                        setState(() {
                          if (checked) {
                            _selectedMetrics.add(metric);
                          } else {
                            _selectedMetrics.remove(metric);
                          }
                        });
                      },
                    );
                  })
                  .toList(),
            ),
          ],
        ),
      ),
      Step(
        isActive: _currentStep >= 2,
        title: const Text('自己省察段階: 分析と適応'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('失敗・ミスのカテゴリー（複数選択可）'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              children:
                  [
                    '技術・戦術',
                    '生理・身体 (疲労・ラグ)',
                    '認知・心理 (焦り・ティルト)',
                    '社会・対人 (報告不足)',
                    '自己調整 (目標不適切)',
                  ].map((cat) {
                    final isSelected = _selectedFailures.contains(cat);
                    return FilterChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (checked) {
                        setState(() {
                          if (checked) {
                            _selectedFailures.add(cat);
                          } else {
                            _selectedFailures.remove(cat);
                          }
                        });
                      },
                    );
                  }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _logicController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '判断基準の再定義（その判断の根拠やルールは何でしたか？）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      Step(
        isActive: _currentStep >= 3,
        title: const Text('次回への計画段階: 教訓のまとめ'),
        content: Column(
          children: [
            TextField(
              controller: _lessonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '獲得した教訓（次のプレイでどう活かすか）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      Step(
        isActive: _currentStep >= 4,
        title: const Text('送信'),
        content: Column(
          children: [
            const Text('すべての項目の入力が完了しました。データを保存して振り返りを終了します。'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitReflection,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50), // ボタンを横いっぱいに広げる
              ),
              child: const Text('Submit Reflection'),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Self Learning (Reflection)')),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          setState(() {
            if (_currentStep < _step.length - 1) {
              _currentStep++;
            }
          });
        },
        onStepCancel: () {
          setState(() {
            if (_currentStep > 0) {
              _currentStep--;
            }
          });
        },
        onStepTapped: (index) {
          setState(() {
            _currentStep = index;
          });
        },
        steps: _step,
      ),
    );
  }
}
