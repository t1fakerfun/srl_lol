import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_controller.dart';
import 'models/player.dart';
import 'screens/self_learning.dart' show backendBaseUrl;

part 'session_controller.g.dart';

class LoginException implements Exception {
  final String message;
  const LoginException(this.message);

  @override
  String toString() => message;
}

// ログイン中のプレイヤー。null = 未ログイン。
// パスワードは無く「Riot APIでサモナーが見つかる = ログイン可」という仕様なので、
// 端末にはサーバーが返したプレイヤー情報をそのまま保存して自動ログインに使う。
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  static const _prefsKey = 'player';

  @override
  Future<Player?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      return Player.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 保存形式が変わった等で読めない場合は未ログイン扱いにする
      await prefs.remove(_prefsKey);
      return null;
    }
  }

  // 失敗時はLoginExceptionを投げる。stateをloadingにしないのは、
  // AuthGateがログイン画面ごと作り直して入力内容が消えるのを避けるため。
  Future<void> login({
    required String gameName,
    required String tagLine,
    required String region,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$backendBaseUrl/api/players/login'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'gameName': gameName,
          'tagLine': tagLine,
          'region': region,
        }),
      );
    } catch (_) {
      throw const LoginException('サーバーとの通信に失敗しました');
    }

    final resData = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw LoginException(resData['message'] as String? ?? 'ログインに失敗しました');
    }

    final player = Player.fromJson(resData);
    await _save(player);
    state = AsyncData(player);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    // 壁打ちの会話は前のプレイヤーのものなので破棄する
    ref.invalidate(chatControllerProvider);
    state = const AsyncData(null);
  }

  Future<void> updateTarget(String tier, String? division) async {
    final player = state.valueOrNull;
    if (player == null) return;

    final response = await http.put(
      Uri.parse('$backendBaseUrl/api/players/${player.id}/target_rank'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'tier': tier, 'division': division}),
    );
    final resData = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(resData['message'] ?? '目標ランクの保存に失敗しました');
    }

    final updated = player.copyWithTarget(
      resData['target_tier'] as String?,
      resData['target_division'] as String?,
    );
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> _save(Player player) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(player.toJson()));
  }
}
