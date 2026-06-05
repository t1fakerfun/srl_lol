import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../chat_controller.dart';

class GeminiChatScreen extends ConsumerWidget {
  const GeminiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gemini AI Assistant',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple, Colors.indigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D0B14), Color(0xFF161224)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Chat(
          messages: messages,
          onSendPressed: (types.PartialText text) {
            ref.read(chatControllerProvider.notifier).ask(question: text.text);
          },
          user: ChatController.me,
          theme: const DarkChatTheme(
            backgroundColor: Colors.transparent,
            primaryColor: Colors.deepPurpleAccent,
            secondaryColor: Color(0xFF231E39),
            inputBackgroundColor: Color(0xFF1F1A30),
            inputTextColor: Colors.white,
            inputTextCursorColor: Colors.deepPurpleAccent,
            messageBorderRadius: 16.0,
            sentMessageBodyTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
            receivedMessageBodyTextStyle: TextStyle(
              color: Color(0xFFE6E6E6),
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
