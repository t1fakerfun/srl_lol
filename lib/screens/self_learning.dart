import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../session_controller.dart';
import '../theme/lumen_theme.dart';
import '../widgets/help_button.dart';
import '../widgets/video_upload_card.dart';

// ローカル実行時は何も指定しなければ127.0.0.1:5001を使う。
// 本番ビルド時は --dart-define=BACKEND_URL=https://api.yatuharo.com を明示的に渡す。
const backendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://127.0.0.1:5001',
);
const backendUrl = '$backendBaseUrl/api/reflection';

var url = Uri.parse(backendUrl);

class SelflearningWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<SelflearningWidget> createState() => _SelflearningWidgetState();
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
  int? playerId;
  String? riotId;

  SRLReflection({
    required this.targetType,
    required this.routineScore,
    required this.monitoringMetrics,
    required this.failureCategories,
    required this.judgementLogic,
    required this.lessonLearned,
    required this.lessonQuality,
    this.videoJobId,
    this.playerId,
    this.riotId,
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
      'playerId': playerId,
      'riotId': riotId,
    };
  }
}

class _SelflearningWidgetState extends ConsumerState<SelflearningWidget> {
  final _videoUploadKey = GlobalKey<VideoUploadCardState>();
  int? _videoJobId;

  // 各フォームの状態を保持する変数
  String? _selectedTargetType;
  double _routineScore = 3.0;
  List<String> _selectedMetrics = [];
  List<String> _selectedFailures = [];

  final TextEditingController _logicController = TextEditingController();
  final TextEditingController _lessonController = TextEditingController();

  // 各段階セクションの開閉状態。Stepperの「次へ進んだら前が自動で閉じる」挙動をやめ、
  // ユーザーがクリックした通りの開閉状態を保持する。
  final List<bool> _isExpanded = [true, false, false, false];

  // データベースへの送信処理
  Future<void> _submitReflection() async {
    // ログイン中のプレイヤーを、この振り返りの持ち主として紐付ける
    final player = ref.read(sessionControllerProvider).valueOrNull;

    final reflection = SRLReflection(
      targetType: _selectedTargetType,
      routineScore: _routineScore,
      monitoringMetrics: _selectedMetrics,
      failureCategories: _selectedFailures,
      judgementLogic: _logicController.text,
      lessonLearned: _lessonController.text,
      lessonQuality: 3, // 必要に応じてLLM解析などで動的に変更
      videoJobId: _videoJobId,
      playerId: player?.id,
      riotId: player?.riotId,
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(reflection.toMap()),
      );
      final resData = jsonDecode(response.body);
      final success = response.statusCode == 200;
      if (mounted) {
        _showAnalysisResultDialog(
          success: success,
          errorType: resData['error_type'] as String?,
          message: resData['message'] as String? ?? '',
          score: (resData['score'] as num?)?.toDouble(),
          good: resData['good'] as String?,
          questions: (resData['questions'] as List?)?.cast<String>(),
        );
      }
      if (!success) return;

      // 送信後のクリア処理
      _logicController.clear();
      _lessonController.clear();
      _videoUploadKey.currentState?.reset();
      setState(() {
        _selectedTargetType = null;
        _routineScore = 3.0;
        _selectedMetrics = [];
        _selectedFailures = [];
        _videoJobId = null;
        for (var i = 0; i < _isExpanded.length; i++) {
          _isExpanded[i] = i == 0;
        }
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

  // AI採点結果(スコア・良かった点・書いた内容へのツッコミ質問)をダイアログで表示する
  void _showAnalysisResultDialog({
    required bool success,
    // バックエンドのAI採点が失敗した時だけ入る（RATE_LIMITED / AI_ERROR / PARSE_ERROR / EMPTY_INPUT）
    required String? errorType,
    required String message,
    required double? score,
    required String? good,
    required List<String>? questions,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          success
              ? '保存されました'
              : errorType != null
              ? 'AI採点に失敗しました'
              : '基準を満たしませんでした',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (score != null) ...[
                const SizedBox(height: 12),
                LumenReadout(
                  icon: Icons.speed,
                  value: score.toStringAsFixed(1),
                  caption: 'SRLスコア（保存の基準: 3.0以上）',
                ),
              ],
              if (good != null && good.isNotEmpty && good != '特になし') ...[
                const SizedBox(height: 16),
                Text('良かった点', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(good),
              ],
              if (questions != null && questions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('この振り返りへのツッコミ', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                ...questions.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(q)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _logicController.dispose();
    _lessonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = <(String, Widget)>[
      (
        '予見段階: 目標と計画の確認',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '設定した目標のタイプ',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedTargetType,
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
      (
        '遂行段階: 自己監視',
        Column(
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
      (
        '自己省察段階: 分析と適応',
        Column(
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
      (
        '次回への計画段階: 教訓のまとめ',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Self Learning (Reflection)'),
        actions: [
          HelpButton(
            title: '振り返りの使い方',
            points: [
              '各段階のタイトルをタップすると開閉できます。自動では閉じないので、前の段階を見返しながら入力できます。',
              '試合動画は画面上部の「試合動画」カードからいつでもアップロードできます。解析はバックグラウンドで進み、進行状況がここに常に表示されます。',
              '一番下の「振り返りを送信」を押すと内容がAIによって採点されます。内容が薄い（結果だけで判断基準に触れていない等）と判断された場合は保存されず、やり直しになります。',
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VideoUploadCard(
              key: _videoUploadKey,
              onJobIdChanged: (jobId) => setState(() => _videoJobId = jobId),
            ),
            const SizedBox(height: 16),
            ExpansionPanelList(
              elevation: 0,
              expansionCallback: (index, isExpanded) {
                setState(() => _isExpanded[index] = isExpanded);
              },
              children: sections.asMap().entries.map((entry) {
                final index = entry.key;
                final (title, content) = entry.value;
                return ExpansionPanel(
                  canTapOnHeader: true,
                  isExpanded: _isExpanded[index],
                  headerBuilder: (context, isExpanded) => ListTile(
                    title: Text(title),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: content,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitReflection,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('振り返りを送信'),
            ),
          ],
        ),
      ),
    );
  }
}
