// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$geminiControllerHash() => r'85f3a1370fe2d3d2b10f129df068c9a8c9b6f2c1';

/// See also [GeminiController].
@ProviderFor(GeminiController)
final geminiControllerProvider =
    AutoDisposeNotifierProvider<GeminiController, void>.internal(
      GeminiController.new,
      name: r'geminiControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$geminiControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GeminiController = AutoDisposeNotifier<void>;
String _$chatControllerHash() => r'3d4d0e1e726ab367107ad612991943f606da9203';

/// See also [ChatController].
@ProviderFor(ChatController)
final chatControllerProvider =
    AutoDisposeNotifierProvider<ChatController, List<types.Message>>.internal(
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

typedef _$ChatController = AutoDisposeNotifier<List<types.Message>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
