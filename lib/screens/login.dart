import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../session_controller.dart';
import '../theme/lumen_theme.dart';

// Riot APIのregion(プラットフォームルーティング値)。バックエンドのriot_api.pyの
// PLATFORM_TO_REGIONALと対応が取れている必要がある。
const Map<String, String> riotRegions = {
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

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _riotIdController = TextEditingController();
  String _selectedRegion = 'jp1';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromLegacyConfig();
  }

  // 旧User_config画面で保存していたRiot ID/regionがあれば初期値として使う
  Future<void> _prefillFromLegacyConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final riotId = prefs.getString('riotId');
    final region = prefs.getString('region');
    if (!mounted) return;
    setState(() {
      if (riotId != null) _riotIdController.text = riotId;
      if (region != null && riotRegions.containsKey(region)) {
        _selectedRegion = region;
      }
    });
  }

  Future<void> _submit() async {
    final riotId = _riotIdController.text.trim();
    final hashIndex = riotId.indexOf('#');
    if (hashIndex <= 0 || hashIndex == riotId.length - 1) {
      setState(() => _error = 'Riot IDは「ゲーム名#タグ」の形式で入力してください（例: Faker#KR1）');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(
            gameName: riotId.substring(0, hashIndex),
            tagLine: riotId.substring(hashIndex + 1),
            region: _selectedRegion,
          );
      // 成功するとAuthGateがホーム画面に切り替えるので、ここでは何もしない
    } on LoginException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _riotIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SRL LoL',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'サモナー名(Riot ID)を入力して始めましょう',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LumenColors.inkMuted),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _riotIdController,
                  enabled: !_submitting,
                  onSubmitted: (_) => _submit(),
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
                  items: riotRegions.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} (${e.value})'),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedRegion = val);
                          }
                        },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: LumenColors.coral)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('はじめる'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
