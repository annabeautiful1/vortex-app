import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/utils/logger.dart';

part 'support_provider.g.dart';

class ChatMessage {
  final String id;
  final String? text;
  final String? imageUrl;
  final bool isFromUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    this.text,
    this.imageUrl,
    required this.isFromUser,
    required this.timestamp,
  });
}

class SupportState {
  final List<ChatMessage> messages;
  final bool isOnline;
  final bool isLoading;

  const SupportState({
    this.messages = const [],
    this.isOnline = true,
    this.isLoading = false,
  });

  SupportState copyWith({
    List<ChatMessage>? messages,
    bool? isOnline,
    bool? isLoading,
  }) {
    return SupportState(
      messages: messages ?? this.messages,
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

@riverpod
class Support extends _$Support {
  @override
  SupportState build() {
    return const SupportState();
  }

  void sendMessage(String text) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, message],
    );

    VortexLogger.i('Sent message: $text');

    // TODO: Send to server and handle response
    // This would integrate with Telegram bot or custom support system
  }

  void sendImage(String imagePath) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageUrl: imagePath,
      isFromUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, message],
    );

    VortexLogger.i('Sent image: $imagePath');
  }

  void receiveMessage(ChatMessage message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  void setOnlineStatus(bool isOnline) {
    state = state.copyWith(isOnline: isOnline);
  }

  void clearMessages() {
    state = state.copyWith(messages: []);
  }
}

final supportProvider = SupportProvider();
