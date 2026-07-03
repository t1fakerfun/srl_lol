import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'video_upload_result.dart';

// Web版: package:http のBrowserClientはリクエストボディを送信前に丸ごと
// Uint8Listへ展開してしまう(await request.finalize().toBytes())ため、
// file_pickerのreadStreamで節約したメモリがここで無効化され、GB級動画で
// メインスレッドがフリーズする。ブラウザのFile(=Blob)をXMLHttpRequestの
// FormDataへ直接渡せば、ブラウザがディスクから直接ストリーミング送信し、
// Dart/JSヒープに全体を載せずに済む。
Future<PickedVideoUpload?> pickAndUploadVideo({
  required String uploadUrl,
  required void Function(String fileName) onPicked,
}) async {
  final file = await _pickFile();
  if (file == null) return null;

  onPicked(file.name);
  return _uploadFile(file, uploadUrl);
}

Future<web.File?> _pickFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'video/*'
    ..style.display = 'none';
  web.document.body!.appendChild(input);

  final completer = Completer<web.File?>();
  var settled = false;

  void changeListener(web.Event event) {
    if (settled) return;
    settled = true;
    final files = input.files;
    completer.complete(
      files != null && files.length > 0 ? files.item(0) : null,
    );
  }

  void cancelListener(web.Event event) {
    // ネイティブの'cancel'イベントに対応していないブラウザ向けのフォールバック。
    // file_picker_web.dartと同様、フォーカス復帰後もchangeが来なければキャンセル扱い。
    Future.delayed(const Duration(seconds: 1), () {
      if (!settled) {
        settled = true;
        completer.complete(null);
      }
    });
  }

  input.addEventListener('change', changeListener.toJS);
  input.addEventListener('cancel', cancelListener.toJS);
  web.window.addEventListener('focus', cancelListener.toJS);

  input.click();
  try {
    return await completer.future;
  } finally {
    web.window.removeEventListener('focus', cancelListener.toJS);
    input.remove();
  }
}

Future<PickedVideoUpload> _uploadFile(web.File file, String uploadUrl) {
  final formData = web.FormData();
  formData.append('video', file, file.name);

  final xhr = web.XMLHttpRequest();
  final completer = Completer<PickedVideoUpload>();

  xhr.addEventListener(
    'load',
    (web.Event event) {
      if (xhr.status == 202) {
        final resData = jsonDecode(xhr.responseText) as Map<String, dynamic>;
        completer.complete(PickedVideoUpload(
          jobId: resData['job_id'] as int,
          status: resData['status'] as String,
        ));
      } else {
        completer.completeError(
          Exception('動画のアップロードに失敗しました (status ${xhr.status})'),
        );
      }
    }.toJS,
  );
  xhr.addEventListener(
    'error',
    (web.Event event) {
      completer.completeError(Exception('動画のアップロード中に通信エラーが発生しました'));
    }.toJS,
  );

  xhr.open('POST', uploadUrl, true);
  xhr.send(formData);

  return completer.future;
}
