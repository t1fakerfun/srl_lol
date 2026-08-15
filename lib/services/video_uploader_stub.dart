import 'video_upload_result.dart';

// io/web どちらのプラットフォームにも該当しない場合のフォールバック。
// Flutterのビルドターゲット(io or web)では実際には使用されない。
Future<PickedVideoUpload?> pickAndUploadVideo({
  required String uploadUrl,
  required void Function(String fileName) onPicked,
}) {
  throw UnsupportedError('This platform does not support video uploads.');
}
