import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/self_learning.dart' show backendBaseUrl;
import '../theme/lumen_theme.dart';

// 試合一覧のカードをタップした時に開く、1試合分の詳細ダイアログ。
// ダメージ量・CS・ビジョンスコアなどの詳細スタッツと、ゴールド推移の簡易グラフを表示する。
class MatchDetailDialog extends StatefulWidget {
  final String matchId;
  final String puuid;
  final String region;

  const MatchDetailDialog({
    super.key,
    required this.matchId,
    required this.puuid,
    required this.region,
  });

  @override
  State<MatchDetailDialog> createState() => _MatchDetailDialogState();
}

class _MatchDetailDialogState extends State<MatchDetailDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _goldTimeline = [];

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final uri = Uri.parse('$backendBaseUrl/api/riot/matches/${widget.matchId}')
          .replace(
            queryParameters: {'puuid': widget.puuid, 'region': widget.region},
          );
      final response = await http.get(uri);
      final resData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _detail = Map<String, dynamic>.from(resData['detail'] as Map);
          _goldTimeline = List<Map<String, dynamic>>.from(
            (resData['gold_timeline'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );
        });
      } else {
        setState(() {
          _error = resData['message'] as String? ?? '試合詳細の取得に失敗しました';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'サーバーとの通信に失敗しました';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(padding: const EdgeInsets.all(20), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(_error!, style: TextStyle(color: LumenColors.coral)),
        ),
      );
    }

    final d = _detail!;
    final win = d['win'] as bool;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                win ? Icons.emoji_events : Icons.close,
                color: win ? LumenColors.brass : LumenColors.coral,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${d['champion']}（${d['team_position'] ?? '-'}）',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${win ? '勝利' : '敗北'}  ・  ${_formatDuration(d['game_duration_sec'] as int)}',
            style: TextStyle(color: LumenColors.inkMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              LumenReadout(
                icon: Icons.sports_kabaddi,
                value: '${d['kills']}/${d['deaths']}/${d['assists']}',
                caption: 'KDA',
              ),
              LumenReadout(icon: Icons.grass, value: '${d['cs']}', caption: 'CS'),
              LumenReadout(
                icon: Icons.paid,
                value: '${d['gold_earned']}',
                caption: '獲得ゴールド',
              ),
              LumenReadout(
                icon: Icons.local_fire_department,
                value: '${d['damage_dealt_to_champions']}',
                caption: '与ダメージ(対チャンピオン)',
              ),
              LumenReadout(
                icon: Icons.shield,
                value: '${d['damage_taken']}',
                caption: '被ダメージ',
              ),
              LumenReadout(
                icon: Icons.visibility,
                value: '${d['vision_score']}',
                caption: 'ビジョンスコア',
              ),
              LumenReadout(
                icon: Icons.flag,
                value: '${d['wards_placed']}/${d['wards_killed']}',
                caption: 'ワード設置/破壊',
              ),
            ],
          ),
          if (_goldTimeline.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('ゴールドの推移', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CustomPaint(painter: _GoldChartPainter(_goldTimeline)),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> points;

  _GoldChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final golds = points.map((p) => p['gold'] as int).toList();
    final minutes = points.map((p) => p['minute'] as int).toList();
    final maxGold = golds.reduce((a, b) => a > b ? a : b);
    final maxMinute = minutes.reduce((a, b) => a > b ? a : b);

    final axisPaint = Paint()
      ..color = LumenColors.hairline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    final linePaint = Paint()
      ..color = LumenColors.brass
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final minute = minutes[i];
      final gold = golds[i];
      final x = maxMinute == 0 ? 0.0 : (minute / maxMinute) * size.width;
      final y = maxGold == 0
          ? size.height
          : size.height - (gold / maxGold) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _GoldChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
