// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$geminiControllerHash() => r'7e430639376e755edd06450e3cd2a2b681299892';

/// See also [GeminiController].
@ProviderFor(GeminiController)
final geminiControllerProvider =
    NotifierProvider<GeminiController, void>.internal(
      GeminiController.new,
      name: r'geminiControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$geminiControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GeminiController = Notifier<void>;
String _$chatControllerHash() => r'6b6b5ef56242780089aa6ed5de000af8954425f9';

/// See also [ChatController].
@ProviderFor(ChatController)
final chatControllerProvider =
    NotifierProvider<ChatController, List<types.Message>>.internal(
      ChatController.new,
      name: r'chatControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$chatControllerHash,
      dependencies: <ProviderOrFamily>[geminiControllerProvider],
      allTransitiveDependencies: <ProviderOrFamily>{
        geminiControllerProvider,
        ...?geminiControllerProvider.allTransitiveDependencies,
      },
    );

typedef _$ChatController = Notifier<List<types.Message>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
