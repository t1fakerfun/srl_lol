// 動画アップロード完了時に返される、非同期解析ジョブの識別情報。
class PickedVideoUpload {
  final int jobId;
  final String status;

  const PickedVideoUpload({required this.jobId, required this.status});
}
