import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const backendUrl = 'http://127.0.0.1:5001/api/reflection';

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

  SRLReflection({
    required this.targetType,
    required this.routineScore,
    required this.monitoringMetrics,
    required this.failureCategories,
    required this.judgementLogic,
    required this.lessonLearned,
    required this.lessonQuality,
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
      setState(() {
        _selectedTargetType = null;
        _routineScore = 3.0;
        _selectedMetrics = [];
        _selectedFailures = [];
        _currentStep = 0;
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

  // 動画ファイル選択
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result != null) {
      setState(() {
        _fileName = result.files.first.name;
      });
    }
  }

  @override
  void dispose() {
    _logicController.dispose();
    _lessonController.dispose();
    super.dispose();
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
