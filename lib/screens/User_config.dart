import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/lumen_theme.dart';
import '../widgets/help_button.dart';
import '../widgets/match_detail_dialog.dart';
import 'self_learning.dart' show backendBaseUrl;

// Riot APIのregion(プラットフォームルーティング値)。バックエンドのriot_api.pyの
// PLATFORM_TO_REGIONALと対応が取れている必要がある。
const Map<String, String> _riotRegions = {
  'jp1': '日本',
  'kr': '韓国',
  'na1': '北米',
  'euw1': '西ヨーロッパ',
  'eun1': '北・東ヨーロッパ',
  'br1': 'ブラジル',
  'la1': 'ラテンアメリカ北',
  'la2': 'ラテンアメリカ南',
  'oc1': 'オセアニア',
  'tr1': 'トルコ',
  'ru': 'ロシア',
};

class User_configWidget extends StatefulWidget {
  @override
  _User_configWidgetState createState() => _User_configWidgetState();
}

class _User_configWidgetState extends State<User_configWidget> {
  final _riotIdController = TextEditingController();
  final _rankController = TextEditingController();
  String _selectedRegion = 'jp1';

  bool _loadingMatches = false;
  String? _matchesError;
  List<Map<String, dynamic>>? _matches;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRegion = prefs.getString('region');
    setState(() {
      _riotIdController.text = prefs.getString('riotId') ?? '';
      if (savedRegion != null && _riotRegions.containsKey(savedRegion)) {
        _selectedRegion = savedRegion;
      }
      _rankController.text = prefs.getString('rank') ?? '';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('riotId', _riotIdController.text);
    await prefs.setString('region', _selectedRegion);
    await prefs.setString('rank', _rankController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved successfully!')),
      );
    }
  }

  // Riot ID("ゲーム名#タグ")とregionから直近の試合情報を取得する
  Future<void> _fetchMatches() async {
    final riotId = _riotIdController.text.trim();
    final hashIndex = riotId.indexOf('#');
    if (hashIndex <= 0 || hashIndex == riotId.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Riot IDは「ゲーム名#タグ」の形式で入力してください（例: Faker#KR1）'),
        ),
      );
      return;
    }
    final gameName = riotId.substring(0, hashIndex);
    final tagLine = riotId.substring(hashIndex + 1);

    setState(() {
      _loadingMatches = true;
      _matchesError = null;
    });

    try {
      final uri = Uri.parse('$backendBaseUrl/api/riot/matches').replace(
        queryParameters: {
          'gameName': gameName,
          'tagLine': tagLine,
          'region': _selectedRegion,
          'count': '10',
        },
      );
      final response = await http.get(uri);
      final resData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _matches = List<Map<String, dynamic>>.from(resData as List);
        });
      } else {
        setState(() {
          _matchesError = resData['message'] as String? ?? '試合情報の取得に失敗しました';
        });
      }
    } catch (e) {
      setState(() {
        _matchesError = 'サーバーとの通信に失敗しました';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingMatches = false;
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildMatchList() {
    if (_loadingMatches) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_matchesError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_matchesError!, style: TextStyle(color: LumenColors.coral)),
      );
    }
    if (_matches == null) {
      return const SizedBox.shrink();
    }
    if (_matches!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('試合が見つかりませんでした'),
      );
    }

    return Column(
      children: _matches!.map((match) {
        final win = match['win'] as bool;
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
            subtitle: Text(
              '${win ? '勝利' : '敗北'}  ・  ${_formatDuration(match['game_duration_sec'] as int)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (_) => MatchDetailDialog(
                matchId: match['match_id'] as String,
                puuid: match['puuid'] as String,
                region: _selectedRegion,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _riotIdController.dispose();
    _rankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Configuration'),
        actions: [
          HelpButton(
            title: 'ユーザー設定の使い方',
            points: [
              'Riot ID(ゲーム名#タグ)・リージョン・ランクを入力して保存できます。',
              'この情報は端末内(ローカル)に保存されます。「最近の試合を取得」を押した時だけ、入力したRiot IDとリージョンがバックエンド経由でRiot APIに送られます。',
              '「最近の試合を取得」で、直近10試合のチャンピオン・勝敗・KDA・試合時間を確認できます。試合をタップすると、CS・ダメージ量・ビジョンスコア・ゴールド推移などの詳細を確認できます。',
            ],
          ),
        ],
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
                hintText: '例: Faker#KR1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Region',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedRegion,
              items: _riotRegions.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text('${e.key} (${e.value})'),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedRegion = val);
              },
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
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            Text('Riot APIから試合情報を取得', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadingMatches ? null : _fetchMatches,
              icon: const Icon(Icons.refresh),
              label: const Text('最近の試合を取得'),
            ),
            const SizedBox(height: 8),
            _buildMatchList(),
          ],
        ),
      ),
    );
  }
}
