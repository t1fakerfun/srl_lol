import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/player.dart';
import '../models/rank.dart';
import '../session_controller.dart';
import '../theme/lumen_theme.dart';
import '../widgets/help_button.dart';
import '../widgets/match_detail_dialog.dart';
import 'self_learning.dart' show backendBaseUrl;

class StatsWidget extends ConsumerStatefulWidget {
  const StatsWidget({super.key});

  @override
  ConsumerState<StatsWidget> createState() => _StatsWidgetState();
}

class _StatsWidgetState extends ConsumerState<StatsWidget> {
  bool _loading = true;

  Map<String, dynamic>? _rankStats;
  String? _rankStatsError;

  List<Map<String, dynamic>>? _matches;
  String? _matchesError;

  List<Map<String, dynamic>>? _reflections;
  String? _reflectionsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final player = ref.read(sessionControllerProvider).valueOrNull;
    if (player == null) return;

    setState(() {
      _loading = true;
      _rankStats = null;
      _rankStatsError = null;
      _matches = null;
      _matchesError = null;
      _reflections = null;
      _reflectionsError = null;
    });

    await Future.wait([
      _loadRankStats(player),
      _loadMatches(player),
      _loadReflections(player),
    ]);

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // 現在ランク・ランク推移。バックエンドはこの呼び出しのたびにランクのスナップショットを記録する。
  Future<void> _loadRankStats(Player player) async {
    try {
      final response = await http.get(
        Uri.parse('$backendBaseUrl/api/players/${player.id}/stats'),
      );
      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        _rankStats = resData;
      } else {
        _rankStatsError = resData['message'] as String? ?? 'ランク情報の取得に失敗しました';
      }
    } catch (e) {
      _rankStatsError = 'サーバーとの通信に失敗しました';
    }
  }

  // Riot APIから直近の試合を取得する。動画解析を挟まないので即座に描画できる。
  Future<void> _loadMatches(Player player) async {
    try {
      final uri = Uri.parse('$backendBaseUrl/api/riot/matches').replace(
        queryParameters: {
          'gameName': player.gameName,
          'tagLine': player.tagLine,
          'region': player.region,
          'count': '20',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = List<Map<String, dynamic>>.from(
          jsonDecode(response.body) as List,
        );
        // Riot APIは新しい順に返すので、グラフでは古い順（左）から新しい順（右）に並べる
        _matches = decoded.reversed.toList();
      } else {
        final resData = jsonDecode(response.body);
        _matchesError = resData['message'] as String? ?? '試合情報の取得に失敗しました';
      }
    } catch (e) {
      _matchesError = 'Riot APIとの通信に失敗しました';
    }
  }

  Future<void> _loadReflections(Player player) async {
    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/reflections',
      ).replace(queryParameters: {'player_id': '${player.id}'});
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = List<Map<String, dynamic>>.from(
          jsonDecode(response.body) as List,
        );
        // created_at DESCで返るので、グラフでは古い順（左）から新しい順（右）に並べる
        _reflections = decoded.reversed.toList();
      } else {
        _reflectionsError = '振り返りの取得に失敗しました';
      }
    } catch (e) {
      _reflectionsError = 'サーバーとの通信に失敗しました';
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: const Text('壁打ちの会話内容は破棄されます。振り返りはサーバーに保存済みなので消えません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sessionControllerProvider.notifier).logout();
    }
  }

  Future<void> _editTargetRank(Player player) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _TargetRankDialog(
        initialTier: player.targetTier,
        initialDivision: player.targetDivision,
      ),
    );
    if (result == null) return;

    final (tier, division) = result;
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .updateTarget(tier, division);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目標ランクの保存に失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(sessionControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(player?.riotId ?? 'Stats'),
        actions: [
          HelpButton(
            title: '統計の見方',
            points: [
              'ログイン中のサモナーの現在ランクと目標ランク、Riot APIの直近の試合データ、保存された振り返りの推移をまとめて表示します。',
              '「目標ランク」の編集ボタンから目指すランクを設定すると、現在ランクとの差をLP換算で表示します（1ディビジョン=100LPとして概算）。',
              'ランク推移は、この画面を開いた時点のランクを記録していくものです。開くたびに少しずつグラフが伸びます。',
              '試合をタップすると、CS・ダメージ量・ビジョンスコア・ゴールド推移などの詳細を確認できます。',
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _buildBody(player),
    );
  }

  Widget _buildBody(Player? player) {
    if (_loading || player == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('ランク', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildRankSection(player),
        const SizedBox(height: 32),
        Text('試合データ（Riot API）', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildMatchesSection(player),
        const SizedBox(height: 32),
        Text('振り返りの推移', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildReflectionsSection(),
      ],
    );
  }

  Widget _buildRankSection(Player player) {
    if (_rankStatsError != null) {
      return Text(_rankStatsError!, style: TextStyle(color: LumenColors.coral));
    }
    final stats = _rankStats ?? {};
    final ranks = (stats['ranks'] as List?)?.cast<Map<String, dynamic>>();
    final solo = ranks
        ?.where((r) => r['queue_type'] == 'RANKED_SOLO_5x5')
        .firstOrNull;
    final history = (stats['rank_history'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final String currentLabel;
    if (stats['ranks_error'] != null) {
      currentLabel = '取得失敗: ${stats['ranks_error']}';
    } else if (solo == null) {
      currentLabel = 'ソロランク未ランク';
    } else {
      final wins = solo['wins'] as int;
      final losses = solo['losses'] as int;
      final winRate = wins + losses > 0 ? wins / (wins + losses) * 100 : 0;
      currentLabel =
          '${rankLabel(solo['tier'], solo['division'])} ${solo['lp']}LP'
          '  ・  $wins勝$losses敗 (${winRate.toStringAsFixed(0)}%)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumenReadout(
          icon: Icons.military_tech,
          value: '現在',
          caption: currentLabel,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LumenReadout(
                icon: Icons.flag,
                value: '目標',
                caption: player.targetTier == null
                    ? '未設定'
                    : rankLabel(player.targetTier!, player.targetDivision),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '目標ランクを設定',
              onPressed: () => _editTargetRank(player),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildGapText(player, solo),
        if (history.length >= 2) ...[
          const SizedBox(height: 16),
          SizedBox(height: 200, child: LineChart(_buildRankChartData(history))),
          const SizedBox(height: 4),
          Text(
            'ソロランクの推移（統計を開いた時点のランクを記録）',
            style: TextStyle(fontSize: 12, color: LumenColors.inkMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildGapText(Player player, Map<String, dynamic>? solo) {
    final targetTier = player.targetTier;
    if (targetTier == null || solo == null) return const SizedBox.shrink();

    final target = targetRankScore(targetTier, player.targetDivision);
    final String text;
    if (target == null) {
      text = '${tierLabel(targetTier)}はLPの閾値が時期によって変わるため、差分は表示できません';
    } else {
      final current = rankScore(
        solo['tier'],
        solo['division'],
        solo['lp'] as int,
      );
      final gap = target - current;
      text = gap <= 0 ? '目標ランクに到達しています' : '目標まであと約${gap}LP';
    }
    return Text(text, style: TextStyle(color: LumenColors.inkMuted));
  }

  LineChartData _buildRankChartData(List<Map<String, dynamic>> history) {
    final spots = [
      for (var i = 0; i < history.length; i++)
        FlSpot(
          i.toDouble(),
          rankScore(
            history[i]['tier'],
            history[i]['division'],
            history[i]['lp'] as int,
          ).toDouble(),
        ),
    ];
    final ys = spots.map((s) => s.y);
    // 上下にティア1つ分の余白を取り、ティア境界(400刻み)でグリッドを引く
    final minY = ((ys.reduce((a, b) => a < b ? a : b) / 400).floor() * 400)
        .toDouble();
    final maxY = ((ys.reduce((a, b) => a > b ? a : b) / 400).ceil() * 400)
        .toDouble();

    return LineChartData(
      minX: 0,
      maxX: (history.length - 1).toDouble(),
      minY: minY,
      maxY: maxY == minY ? minY + 400 : maxY,
      gridData: const FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 400,
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 72,
            interval: 400,
            getTitlesWidget: (value, meta) {
              final i = (value / 400).floor().clamp(0, 7);
              return Text(
                tierLabel(rankTiers[i]),
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [_line(spots, LumenColors.brass)],
    );
  }

  Widget _buildMatchesSection(Player player) {
    if (_matchesError != null) {
      return Text(_matchesError!, style: TextStyle(color: LumenColors.coral));
    }
    final matches = _matches ?? [];
    if (matches.isEmpty) {
      return Text('試合データがありません', style: TextStyle(color: LumenColors.inkMuted));
    }

    final winCount = matches.where((m) => m['win'] as bool).length;
    final winRate = winCount / matches.length * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumenReadout(
          icon: Icons.emoji_events,
          value: '${winRate.toStringAsFixed(0)}%',
          caption: '直近${matches.length}試合の勝率（$winCount勝）',
        ),
        const SizedBox(height: 16),
        SizedBox(height: 220, child: LineChart(_buildKdaChartData(matches))),
        const SizedBox(height: 8),
        _buildLegend([
          ('キル', LumenColors.brass),
          ('デス', LumenColors.coral),
          ('アシスト', LumenColors.inkMuted),
        ]),
        const SizedBox(height: 16),
        // 一覧は新しい順で見たいので、グラフ用に反転したリストを戻す
        ...matches.reversed.map((match) => _buildMatchTile(match, player)),
      ],
    );
  }

  Widget _buildMatchTile(Map<String, dynamic> match, Player player) {
    final win = match['win'] as bool;
    final seconds = match['game_duration_sec'] as int;
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          win ? Icons.emoji_events : Icons.close,
          color: win ? LumenColors.brass : LumenColors.coral,
        ),
        title: Text(
          '${match['champion']}  ${match['kills']}/${match['deaths']}/${match['assists']}',
        ),
        subtitle: Text('${win ? '勝利' : '敗北'}  ・  $duration'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showDialog(
          context: context,
          builder: (_) => MatchDetailDialog(
            matchId: match['match_id'] as String,
            puuid: match['puuid'] as String,
            region: player.region,
          ),
        ),
      ),
    );
  }

  Widget _buildReflectionsSection() {
    if (_reflectionsError != null) {
      return Text(
        _reflectionsError!,
        style: TextStyle(color: LumenColors.coral),
      );
    }
    final reflections = _reflections ?? [];
    if (reflections.isEmpty) {
      return Text(
        '振り返りデータがありません',
        style: TextStyle(color: LumenColors.inkMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(_buildReflectionChartData(reflections)),
        ),
        const SizedBox(height: 8),
        _buildLegend([
          ('SRLスコア (0-5)', LumenColors.brass),
          ('ルーチンスコア (1-5)', LumenColors.coral),
        ]),
      ],
    );
  }

  LineChartData _buildKdaChartData(List<Map<String, dynamic>> matches) {
    List<FlSpot> spotsFor(String key) {
      return [
        for (var i = 0; i < matches.length; i++)
          FlSpot(i.toDouble(), (matches[i][key] as num).toDouble()),
      ];
    }

    return LineChartData(
      minX: 0,
      maxX: (matches.length - 1).toDouble(),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 28),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            // interval を試合数-1に固定し、両端(最初・最後)だけにラベルを呼ばせる。
            // 未指定だとfl_chartが左端付近に極端に細かい間隔でラベルを大量に呼び出してしまう。
            interval: matches.length > 1 ? (matches.length - 1).toDouble() : 1,
            getTitlesWidget: (value, meta) =>
                _matchIndexLabel(value, matches.length),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        _line(spotsFor('kills'), LumenColors.brass),
        _line(spotsFor('deaths'), LumenColors.coral),
        _line(spotsFor('assists'), LumenColors.inkMuted),
      ],
    );
  }

  LineChartData _buildReflectionChartData(
    List<Map<String, dynamic>> reflections,
  ) {
    List<FlSpot> spotsFor(String key) {
      return [
        for (var i = 0; i < reflections.length; i++)
          FlSpot(i.toDouble(), ((reflections[i][key] as num?) ?? 0).toDouble()),
      ];
    }

    return LineChartData(
      minX: 0,
      maxX: (reflections.length - 1).toDouble(),
      minY: 0,
      maxY: 5,
      gridData: const FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 1,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            // interval を振り返り数-1に固定し、両端(最初・最後)だけにラベルを呼ばせる。
            interval: reflections.length > 1
                ? (reflections.length - 1).toDouble()
                : 1,
            getTitlesWidget: (value, meta) =>
                _matchIndexLabel(value, reflections.length),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        _line(spotsFor('srl_score'), LumenColors.brass),
        _line(spotsFor('routine_score'), LumenColors.coral),
      ],
    );
  }

  // X軸の混雑を避けるため、最初と最後の番号だけラベルを出す
  Widget _matchIndexLabel(double value, int total) {
    final i = value.round();
    if (i < 0 || i >= total) return const SizedBox.shrink();
    if (i != 0 && i != total - 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('${i + 1}', style: const TextStyle(fontSize: 10)),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _buildLegend(List<(String, Color)> items) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: items.map((item) {
        final (label, color) = item;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: LumenColors.inkMuted),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _TargetRankDialog extends StatefulWidget {
  final String? initialTier;
  final String? initialDivision;

  const _TargetRankDialog({this.initialTier, this.initialDivision});

  @override
  State<_TargetRankDialog> createState() => _TargetRankDialogState();
}

class _TargetRankDialogState extends State<_TargetRankDialog> {
  late String _tier = widget.initialTier ?? 'GOLD';
  late String _division = widget.initialDivision ?? 'IV';

  @override
  Widget build(BuildContext context) {
    final isApex = apexTiers.contains(_tier);
    return AlertDialog(
      title: const Text('目標ランク'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'ティア',
              border: OutlineInputBorder(),
            ),
            initialValue: _tier,
            items: rankTiers
                .map(
                  (t) => DropdownMenuItem(value: t, child: Text(tierLabel(t))),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _tier = val);
            },
          ),
          const SizedBox(height: 16),
          // MASTER以上はディビジョンが無い
          if (!isApex)
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'ディビジョン',
                border: OutlineInputBorder(),
              ),
              initialValue: _division,
              items: rankDivisions
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _division = val);
              },
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((_tier, isApex ? null : _division)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
