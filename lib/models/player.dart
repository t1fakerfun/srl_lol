// POST /api/players/login が返すプレイヤー。キーはバックエンドのsnake_caseに揃える。
class Player {
  final int id;
  final String puuid;
  final String gameName;
  final String tagLine;
  final String region;
  final String? targetTier;
  final String? targetDivision;

  const Player({
    required this.id,
    required this.puuid,
    required this.gameName,
    required this.tagLine,
    required this.region,
    this.targetTier,
    this.targetDivision,
  });

  String get riotId => '$gameName#$tagLine';

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as int,
      puuid: json['puuid'] as String,
      gameName: json['game_name'] as String,
      tagLine: json['tag_line'] as String,
      region: json['region'] as String,
      targetTier: json['target_tier'] as String?,
      targetDivision: json['target_division'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'puuid': puuid,
    'game_name': gameName,
    'tag_line': tagLine,
    'region': region,
    'target_tier': targetTier,
    'target_division': targetDivision,
  };

  Player copyWithTarget(String? tier, String? division) {
    return Player(
      id: id,
      puuid: puuid,
      gameName: gameName,
      tagLine: tagLine,
      region: region,
      targetTier: tier,
      targetDivision: division,
    );
  }
}
