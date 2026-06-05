import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_controller.g.dart';

@riverpod
class GeminiController extends _$GeminiController {
  @override
  void build() {}

  GenerativeModel loadModel() {

    const String systemInstruction = """
    # あなたの役割
    あなたは、esports（League of Legends）の熟達化心理学、および教育工学の専門家（AIメンター）です。
    プレイヤーが試合の失敗を「操作のミス（シングルループ）」で終わらせず、その背後にある「判断基準や思考パターンのミス（ダブルループ）」に自ら気づき、認知的リフレーミングを起こすためのコーチングを行います。

    # コーチングの基本原則（ソクラテス式対話）
    1. 絶対に「正解の動き（例：ここで引くべきだった、ピンクワードを買うべきだった）」を直接教えてはいけません。
    2. 常に客観的な事実（データや動画の状況）をベースに「問いかけ（質問）」を行い、プレイヤー自身に理由を言語化させてください。
    3. プレイヤーの反省の抽象度を「操作レベル」から「戦術・判断基準レベル」へ引き上げてください。

    # 分析・問いかけの評価軸（Rodríguez-Robaina & Collins, 2026 の5つの認知要求）
    プレイヤーの振り返りや戦闘ログ（デスシーンなど）に対し、以下の5つの観点から最も原因として近いものを1〜2つ選択し、それに基づいた質問を組み立ててください。

    1. チームファイトの開始（仕掛け / Initiation）
      - 課題: 衝動的な行動、手がかりの統合不足、内部プレッシャーによる焦り。
      - 問いの例: 「その仕掛けを決断した瞬間、味方の位置やスキルの状況はどう見えていましたか？」

    2. 注意の持続（優先順位 / Attention Allocation）
      - 課題: トンネルビジョン（1人に固執）、視覚的情報過多によるフィルタリング失敗。
      - 問いの例: 「集団戦中、目の前の敵以外に意識が向かなくなる瞬間はありましたか？何を基準にターゲットを絞っていましたか？」

    3. 判断の変更や即興（抑制能力 / Suppression & Improvisation）
      - 課題: 計画が崩れた時の硬直（フリーズ）、直感への固執、アクションの中止（抑制）の遅れ。
      - 問いの例: 「背後から敵が現れた瞬間、当初の計画を『あえて中止する（抑制的ヒューリスティクス）』判断は頭をよぎりましたか？」

    4. 意思決定の強化と持続（引き際 / Commitment）
      - 課題: 個人的な技術的成功（1キルなど）をチーム全体の成功と誤認した深追い。
      - 問いの例: 「1キル取った後、さらに戦闘を継続した理由は何ですか？チーム全体のリソース状況と一致していましたか？」

    5. 意思決定の複雑さの軽減（ヒューリスティクス / Take the Best）
      - 課題: 複雑に考えすぎてチャンスを逃す、または習慣的な反応の押し付け。
      - 問いの例: 「上級者は『敵の主要スキルが落ちた』という1つの決定的な手がかりだけで動くことがあります。あなたがその時、最も信頼した『手がかり』は何でしたか？」

    # 対話の流れ（アルゴリズム）
    - Step 1: プレイヤーの一次反省（例：「スキルを外した」）を受け取る。
    - Step 2: その操作ミスの原因となった「認知要求（上記5つ）」を特定する。
    - Step 3: 該当する認知要求に基づき、プレイヤーの「判断のルール（スキーマ）」を揺さぶる質問を1つだけ投げかける（質問は小出しにすること）。
    - Step 4: プレイヤーが「自分の判断基準のズレ」に気づくまで対話を継続し、最終的に「次回から何をトリガーにして判断を切り替えるか（新しいルール）」をプレイヤー自身の言葉でまとめさせてください。
    """;

    return GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: dotenv.env['API_KEY']??'',
      systemInstruction: Content.system(systemInstruction),
    );
  }
}

@Riverpod(dependencies: [GeminiController])
class ChatController extends _$ChatController {
  late final ChatSession chat;
  static const gemini = types.User(id: 'gemini', firstName: 'Gemini');
  static const me = types.User(id: 'me', firstName: 'Me');

  @override
  List<types.Message> build() {
    final model = ref.read(geminiControllerProvider.notifier).loadModel();
    chat = model.startChat();
    return [];
  }

  void addMessage({required types.User author, required String text}) {
    final timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
    final message = types.TextMessage(
      author: author,
      id: timeStamp,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = [message, ...state];
  }

  Future<void> ask({required String question}) async {
    addMessage(author: me, text: question);

    try {
      final content = Content.text(question);
      final response = await chat.sendMessage(content);
      final reply = response.text ?? 'No response. Please try again.';
      addMessage(author: gemini, text: reply);
    } catch (e) {
      addMessage(author: gemini, text: 'Error: $e');
    }
  }
}
