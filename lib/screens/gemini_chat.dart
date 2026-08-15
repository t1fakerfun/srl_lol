import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../chat_controller.dart';
import '../theme/lumen_theme.dart';

class GeminiChatScreen extends ConsumerWidget {
  const GeminiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const LumenLabel('Gemini AI Assistant'),
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
