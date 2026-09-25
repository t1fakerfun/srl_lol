import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../chat_controller.dart';
import '../theme/lumen_theme.dart';
import '../widgets/help_button.dart';

class GeminiChatScreen extends ConsumerWidget {
  const GeminiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const LumenLabel('Gemini AI Assistant'),
        actions: [
          HelpButton(
            title: 'AIコーチとの対話の使い方',
            points: [
              'このチャットは正解のプレイを直接教えてくれるコーチではなく、質問を通して気づきを促すソクラテス式のコーチです。',
              '「何のボタンを押し間違えたか」ではなく「その場面でどんな判断基準に従ったか」を聞かれたら、そこを言葉にしてみましょう。',
              '振り返りフォームの採点(SRLスコア)とは別機能です。ここでの会話は保存・採点されません。',
            ],
          ),
        ],
      ),
      body: Container(
        color: LumenColors.paper,
        child: Chat(
          messages: messages,
          onSendPressed: (types.PartialText text) {
            ref.read(chatControllerProvider.notifier).ask(question: text.text);
          },
          user: ChatController.me,
          theme: DarkChatTheme(
            backgroundColor: LumenColors.paper,
            primaryColor: LumenColors.brass,
            secondaryColor: LumenColors.paperRaised,
            inputBackgroundColor: LumenColors.paperMuted,
            inputTextColor: LumenColors.ink,
            inputTextCursorColor: LumenColors.brass,
            messageBorderRadius: 10.0,
            sentMessageBodyTextStyle: const TextStyle(
              color: LumenColors.paper,
              fontSize: 15,
            ),
            receivedMessageBodyTextStyle: TextStyle(
              color: LumenColors.ink,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
