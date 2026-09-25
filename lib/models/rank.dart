// ランク(tier/division)の表示名と、目標までの差分計算用の数値化。
// バックエンドdatabase.pyのTIERS/DIVISIONSと値を揃えておくこと。

const rankTiers = [
  'IRON',
  'BRONZE',
  'SILVER',
  'GOLD',
  'PLATINUM',
  'EMERALD',
  'DIAMOND',
  'MASTER',
  'GRANDMASTER',
  'CHALLENGER',
];
const rankDivisions = ['IV', 'III', 'II', 'I'];
const apexTiers = {'MASTER', 'GRANDMASTER', 'CHALLENGER'};

const _tierLabels = {
  'IRON': 'アイアン',
  'BRONZE': 'ブロンズ',
  'SILVER': 'シルバー',
  'GOLD': 'ゴールド',
  'PLATINUM': 'プラチナ',
  'EMERALD': 'エメラルド',
  'DIAMOND': 'ダイヤモンド',
  'MASTER': 'マスター',
  'GRANDMASTER': 'グランドマスター',
  'CHALLENGER': 'チャレンジャー',
};

String tierLabel(String tier) => _tierLabels[tier] ?? tier;

String rankLabel(String tier, String? division) {
  if (apexTiers.contains(tier) || division == null) return tierLabel(tier);
  return '${tierLabel(tier)} $division';
}

// IRON IV 0LP = 0、1ディビジョン = 100LP換算の通し番号。
// MASTER以上はLPのみで区別されるので、MASTER 0LP = 2800を起点にLPを足すだけ。
// GRANDMASTER/CHALLENGERはLP閾値がサーバー・時期で変動するため、目標値としては数値化できない(null)。
int rankScore(String tier, String? division, int lp) {
  if (apexTiers.contains(tier)) return 2800 + lp;
  final t = rankTiers.indexOf(tier);
  final d = rankDivisions.indexOf(division ?? 'IV');
  return t * 400 + d * 100 + lp;
}

int? targetRankScore(String tier, String? division) {
  if (tier == 'GRANDMASTER' || tier == 'CHALLENGER') return null;
  return rankScore(tier, division, 0);
}
