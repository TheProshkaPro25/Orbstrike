#!/usr/bin/env python3
"""Read saved raw event traces only; never start Godot, replays, or new matches."""
import collections
import json
import pathlib
import re


def summarize(rows):
    matches = []
    in_hand_starts = 0
    legal_windows = 0
    all_windows = 0
    for match_index, match in enumerate(rows):
        if match["mirror"] or 1 not in match["elements"]:
            continue
        player = match["elements"].index(1)
        hand = set(match["decks"][player][2])
        alive = [True] * 6
        locations = [-1] * 6
        battle_index = -1
        missing = []
        for event in match["events"]:
            tag = event.split("(")[0]
            if tag == "card_drawn":
                owner, card = re.match(r"card_drawn\((\d+), ([^)]+)", event).groups()
                if int(owner) == player and card.startswith("ability_"):
                    hand.add(card)
            elif tag == "ability_played":
                owner, card = re.match(r"ability_played\((\d+), ([^)]+)", event).groups()
                if int(owner) == player:
                    hand.discard(card)
            elif tag == "ability_attached":
                owner, _, card = re.match(r"ability_attached\((\d+), (\d+), ([^)]+)", event).groups()
                if int(owner) == player:
                    hand.discard(card)
            elif tag in ("abilities_recharged", "abilities_recalled"):
                if int(re.match(r"[^\(]+\((\d+)", event)[1]) == player:
                    hand.update(re.findall(r'&"([^"]+)"', event))
            elif tag == "creature_stood":
                uid, slot = map(int, re.match(r"creature_stood\((\d+), (\d+)", event).groups())
                locations[uid] = slot
            elif tag == "creature_relocated":
                uid, _, target = map(int, re.match(r"creature_relocated\((\d+), (-?\d+), (-?\d+)", event).groups())
                locations[uid] = target
            elif tag == "creature_returned":
                locations[int(re.match(r"[^\(]+\((\d+)", event)[1])] = -1
            elif tag == "creature_eliminated":
                uid = int(re.match(r"[^\(]+\((\d+)", event)[1])
                locations[uid] = -1
                alive[uid] = False
            elif tag == "creature_revived":
                uid = int(re.match(r"[^\(]+\((\d+)", event)[1])
                locations[uid] = -1
                alive[uid] = True
            elif tag == "fighter_swapped":
                old, new, _ = map(int, re.match(r"fighter_swapped\((\d+), (\d+), (\d+)", event).groups())
                locations[old] = locations[new] = -1
            elif tag == "ability_window" and event.startswith(f"ability_window({player},"):
                all_windows += 1
                legal_windows += "ability_gale_swap" in event
            elif tag == "battle_started":
                battle_index += 1
                _, attacker, defender = map(int, re.match(r"battle_started\((\d+), (\d+), (\d+)", event).groups())
                if "ability_gale_swap" in hand:
                    in_hand_starts += 1
                    if not any(alive[uid] and locations[uid] < 0 and uid not in (attacker, defender)
                               for uid in range(player * 3, player * 3 + 3)):
                        missing.append(battle_index)
        if missing:
            matches.append({"raw_match": match_index, "case": int(match["roster"]),
                            "elements": match["elements"], "result": "W" if match["winner_element"] == 1 else "D" if match["winner_player"] < 0 else "L",
                            "battle_indices": missing})
    no_reserve = sum(len(row["battle_indices"]) for row in matches)
    return {"matches_with_no_reserve": len(matches),
            "wdl": dict(collections.Counter(row["result"] for row in matches)),
            "no_reserve_battle_starts": no_reserve,
            "swap_in_hand_battle_starts": in_hand_starts,
            "potential_reserve_starts": in_hand_starts - no_reserve,
            "direct_legal_swap_windows": legal_windows, "all_gale_windows": all_windows,
            "matches": matches}


if __name__ == "__main__":
    base = pathlib.Path(__file__).resolve().parents[1] / "build/checks/element-balance-20261104"
    report = {name: summarize(json.loads((base / name).read_text())["matches"])
              for name in ("v4-after.json", "v4-holdout.json")}
    report["limits"] = ("Read-only hand/alive/slot reconstruction. Potential reserves do not validate attachment limits; "
                        "direct legal windows come from actual controller events. Late one-survivor states are included. "
                        "No-reserve matches are not counterfactual rescued losses; no action-prefix replays or new matches.")
    print(json.dumps({name: {key: value for key, value in data.items() if key != "matches"}
                      for name, data in report.items() if isinstance(data, dict)}, ensure_ascii=False))
    (base / "formation-v4-trace.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
