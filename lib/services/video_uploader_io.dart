import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'video_upload_result.dart';

// モバイル/デスクトップ版: package:http のioクライアントはリクエストボディを
// 本当にストリーミング送信できるため、file_pickerのreadStreamをそのまま流せる。
Future<PickedVideoUpload?> pickAndUploadVideo({
  required String uploadUrl,
  required void Function(String fileName) onPicked,
}) async {
  final result = await FilePicker.pickFiles(withReadStream: true);
  if (result == null) return null;

  final file = result.files.first;
  onPicked(file.name);
  if (file.readStream == null) return null;

  final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
  request.files.add(
    http.MultipartFile('video', file.readStream!, file.size, filename: file.name),
  );
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode != 202) {
    throw Exception('動画のアップロードに失敗しました (status ${response.statusCode})');
  }

  final resData = jsonDecode(response.body) as Map<String, dynamic>;
  return PickedVideoUpload(
    jobId: resData['job_id'] as int,
    status: resData['status'] as String,
  );
}
