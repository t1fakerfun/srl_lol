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
    final apiKey = dotenv.env['API_KEY'] ?? '';
    return GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
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