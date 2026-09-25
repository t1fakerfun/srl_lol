import os
import requests

RIOT_API_KEY_ENV = "RIOT_API_KEY"
REQUEST_TIMEOUT = 10

# プラットフォームルーティング値 -> 広域ルーティング値
# account-v1(Riot ID解決)とmatch-v5(試合情報)はこちらの広域ルーティングを使う。
PLATFORM_TO_REGIONAL = {
    "na1": "americas",
    "br1": "americas",
    "la1": "americas",
    "la2": "americas",
    "oc1": "americas",
    "kr": "asia",
    "jp1": "asia",
    "euw1": "europe",
    "eun1": "europe",
    "tr1": "europe",
    "ru": "europe",
}


class RiotApiError(Exception):
    def __init__(self, message, status_code=502):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _headers():
    api_key = os.environ.get(RIOT_API_KEY_ENV)
    if not api_key:
        raise RiotApiError("RIOT_API_KEYが設定されていません", 500)
    return {"X-Riot-Token": api_key}


def _regional_routing(platform_region):
    routing = PLATFORM_TO_REGIONAL.get(platform_region.lower())
    if routing is None:
        raise RiotApiError(
            f"未対応のregionです: {platform_region}"
            f"（対応region: {', '.join(sorted(PLATFORM_TO_REGIONAL))}）",
            400,
        )
    return routing


def _get(url, params=None):
    try:
        resp = requests.get(url, headers=_headers(), params=params, timeout=REQUEST_TIMEOUT)
    except requests.RequestException as e:
        raise RiotApiError(f"Riot APIとの通信に失敗しました: {e}", 502)

    if resp.status_code == 404:
        raise RiotApiError("指定されたRiot IDまたは試合が見つかりませんでした", 404)
    if resp.status_code == 401 or resp.status_code == 403:
        raise RiotApiError("Riot APIキーが無効です", 401)
    if resp.status_code == 429:
        raise RiotApiError("Riot APIのレート制限に達しました。しばらく待ってから再試行してください", 429)
    if resp.status_code >= 400:
        raise RiotApiError(f"Riot APIエラー: {resp.status_code}", 502)

    return resp.json()


def _platform_host(platform_region):
    # league-v4などプラットフォーム単位のAPIは広域ルーティングではなくjp1/kr等のホストを使う。
    # 対応regionかどうかの検証は_regional_routingに寄せる。
    _regional_routing(platform_region)
    return f"https://{platform_region.lower()}.api.riotgames.com"


def get_puuid(game_name, tag_line, platform_region):
    regional = _regional_routing(platform_region)
    url = f"https://{regional}.api.riotgames.com/riot/account/v1/accounts/by-riot-id/{game_name}/{tag_line}"
    return _get(url)["puuid"]


def get_match_ids(puuid, platform_region, count=10):
    regional = _regional_routing(platform_region)
    url = f"https://{regional}.api.riotgames.com/lol/match/v5/matches/by-puuid/{puuid}/ids"
    return _get(url, params={"start": 0, "count": count})


def get_match_detail(match_id, platform_region):
    regional = _regional_routing(platform_region)
    url = f"https://{regional}.api.riotgames.com/lol/match/v5/matches/{match_id}"
    return _get(url)


def get_match_timeline(match_id, platform_region):
    regional = _regional_routing(platform_region)
    url = f"https://{regional}.api.riotgames.com/lol/match/v5/matches/{match_id}/timeline"
    return _get(url)


def summarize_match(match_json, puuid):
    info = match_json["info"]
    participant = next(p for p in info["participants"] if p["puuid"] == puuid)
    return {
        "match_id": match_json["metadata"]["matchId"],
        "puuid": puuid,
        "champion": participant["championName"],
        "win": participant["win"],
        "kills": participant["kills"],
        "deaths": participant["deaths"],
        "assists": participant["assists"],
        "game_duration_sec": info["gameDuration"],
        "game_creation": info["gameCreation"],  # エポックミリ秒
        "queue_id": info["queueId"],
    }


def summarize_match_detail(match_json, puuid):
    info = match_json["info"]
    participant = next(p for p in info["participants"] if p["puuid"] == puuid)
    return {
        "match_id": match_json["metadata"]["matchId"],
        "champion": participant["championName"],
        "win": participant["win"],
        "kills": participant["kills"],
        "deaths": participant["deaths"],
        "assists": participant["assists"],
        "cs": participant.get("totalMinionsKilled", 0)
        + participant.get("neutralMinionsKilled", 0),
        "gold_earned": participant.get("goldEarned"),
        "damage_dealt_to_champions": participant.get("totalDamageDealtToChampions"),
        "damage_taken": participant.get("totalDamageTaken"),
        "vision_score": participant.get("visionScore"),
        "wards_placed": participant.get("wardsPlaced"),
        "wards_killed": participant.get("wardsKilled"),
        "team_position": participant.get("teamPosition"),
        "game_duration_sec": info["gameDuration"],
        "game_creation": info["gameCreation"],
        "queue_id": info["queueId"],
    }


def get_gold_timeline(match_json, timeline_json, puuid):
    participant = next(
        p for p in match_json["info"]["participants"] if p["puuid"] == puuid
    )
    participant_id = participant["participantId"]

    points = []
    for frame in timeline_json["info"]["frames"]:
        pframe = frame["participantFrames"].get(str(participant_id))
        if pframe is None:
            continue
        points.append({
            "minute": frame["timestamp"] // 60000,
            "gold": pframe["totalGold"],
        })
    return points


def get_recent_matches(game_name, tag_line, platform_region, count=10):
    puuid = get_puuid(game_name, tag_line, platform_region)
    match_ids = get_match_ids(puuid, platform_region, count=count)
    return [
        summarize_match(get_match_detail(match_id, platform_region), puuid)
        for match_id in match_ids
    ]


def get_match_full(match_id, platform_region, puuid):
    match_json = get_match_detail(match_id, platform_region)
    timeline_json = get_match_timeline(match_id, platform_region)
    return {
        "detail": summarize_match_detail(match_json, puuid),
        "gold_timeline": get_gold_timeline(match_json, timeline_json, puuid),
    }


def get_ranked_entries(puuid, platform_region):
    """ランク戦の現在ランクをキューごとに返す。未ランクなら空リスト。"""
    url = f"{_platform_host(platform_region)}/lol/league/v4/entries/by-puuid/{puuid}"
    return [
        {
            "queue_type": entry["queueType"],  # RANKED_SOLO_5x5 / RANKED_FLEX_SR
            "tier": entry["tier"],
            "division": entry["rank"],  # MASTER以上でも"I"が返る
            "lp": entry["leaguePoints"],
            "wins": entry["wins"],
            "losses": entry["losses"],
        }
        for entry in _get(url)
    ]
