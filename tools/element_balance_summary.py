#!/usr/bin/env python3
"""Descriptive summary of the preregistered element diagnostic. No inferential CI."""
import collections
import hashlib
import itertools
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
raw = json.loads(path.read_text())
catalog = json.loads(path.with_name(path.stem + '-catalog.json').read_text())
rows = [r for r in raw['matches'] if not r['mirror']]
keys = ['fire', 'gale', 'light', 'stone', 'shadow', 'tide']
names = ['Пламя', 'Буря', 'Свет', 'Камень', 'Тень', 'Прилив']
new = ['ability_fire_toll', 'ability_gale_call', 'ability_light_reserve', 'ability_stone_ceiling', 'ability_shadow_triumph', 'ability_tide_wash', 'arena_valor']
cards = {c['id']: c for c in catalog['cards']}

def summarize(group, element):
    scores, alive, eliminated, revivals = [], [], 0, 0
    played, attached, active, drawn, opened, legal = [collections.Counter() for _ in range(6)]
    for row in group:
        if element not in row['elements']:
            continue
        player = row['elements'].index(element)
        scores.append(.5 if row['winner_player'] < 0 else float(row['winner_player'] == player))
        alive.append(row['final_alive'][player])
        eliminated += sum(e[1] == player for e in row['eliminated'])
        revivals += sum(e[1] == player for e in row['revived'])
        for counter, field in [(played, 'played'), (attached, 'attached'), (active, 'active'), (opened, 'opened'), (legal, 'legal_new')]:
            counter.update(row[field][player])
        drawn.update(row['drawn'][player])
    return dict(matches=len(scores), wins=scores.count(1), draws=scores.count(.5), losses=scores.count(0), score=sum(scores)/len(scores) if scores else None, final_alive_mean=sum(alive)/len(alive) if alive else None, eliminated_events=eliminated, actual_revived_events=revivals, played=dict(played), attached=dict(attached), active_battle_occurrences=dict(active), drawn=dict(drawn), opened=dict(opened), legal_new_windows=dict(legal))

elements = []
for element in range(6):
    item = summarize(rows, element)
    item['element'] = keys[element]
    item['by_roster_seed'] = [summarize([r for r in rows if r['roster'] == roster], element) for roster in range(len(raw['rosters']))]
    item['by_playerID'] = [summarize([r for r in rows if element in r['elements'] and r['elements'].index(element) == p], element) for p in range(2)]
    item['by_first_move'] = [summarize([r for r in rows if element in r['elements'] and (r['first_player'] == r['elements'].index(element)) == first], element) for first in [True, False]]
    item['exploratory_flag'] = (item['score'] >= .65 and sum(g['score'] >= .60 for g in item['by_roster_seed']) >= (2*len(raw['rosters'])+2)//3) or (item['score'] <= .35 and sum(g['score'] <= .40 for g in item['by_roster_seed']) >= (2*len(raw['rosters'])+2)//3)
    elements.append(item)

first_wins = sum(r['winner_player'] == r['first_player'] for r in rows)
side0_wins = sum(r['winner_player'] == 0 for r in rows)
matrix = [[None if a == b else summarize([r for r in rows if sorted(r['elements']) == sorted([a,b])], a)['score'] for b in range(6)] for a in range(6)]
coverage = []
for card_id in new:
    coverage.append(dict(id=card_id, name=cards[card_id]['name'], drawn=sum(e['drawn'].get(card_id, 0) for e in elements), played=sum(e['played'].get(card_id, 0) for e in elements), attached=sum(e['attached'].get(card_id, 0) for e in elements), active=sum(e['active_battle_occurrences'].get(card_id, 0) for e in elements), legal_windows=sum(e['legal_new_windows'].get(card_id, 0) for e in elements), opened=sum(e['opened'].get(card_id, 0) for e in elements)))

actual = collections.Counter()
for row in rows:
    actual['gale_call_return_signals'] += sum(e[1] == 'gale_call' for e in row['returned'])
    actual['valor_placements'] += sum(a[0] in ['throw_with_gate', 'place_arena_card'] and a[1][1] == 'arena_valor' for a in row['actions'])
    for battle in row['battles']:
        toll = [line['delta'] for line in battle['breakdown'] if line['source'] == 'ability:ability_fire_toll' and line['delta'] < 0]
        actual['toll_battles_with_actual_penalty'] += bool(toll)
        actual['toll_penalty_lines'] += len(toll)
        actual['toll_total_negative_G'] += -sum(toll)
        # Ceiling has no separate limiting line. Identify the actual 100G result of
        # an otherwise nominal 200G fusion in its two active production sequences.
        if any(p[1] == 'ability_stone_ceiling' and p not in battle['cancelled'] for p in battle['plays']):
            actual['ceiling_100G_nominal_200G_heart_lines'] += sum(line['source'] == 'ability:ability_dragnar_heart' and line['delta'] == 100 for line in battle['breakdown'])
    boundaries = [i for i, event in enumerate(row['events']) if event.startswith('battle_resolved(')]
    assert len(boundaries) == len(row['battles'])
    for index, battle in enumerate(row['battles']):
        start = boundaries[index]
        end = boundaries[index+1] if index+1 < len(boundaries) else len(row['events'])
        events = row['events'][start+1:end]
        next_turn = next((event for event in events if event.startswith('turn_started(')), None)
        for side, card_id in enumerate(battle['reserve_intentions']):
            owner = (battle['attacker'] if side == 0 else battle['defender']) // 3
            if card_id and any(event.startswith(f'abilities_recalled({owner},') and f'"{card_id}"' in event for event in events):
                actual['reserve_actual_target_recalled'] += 1
        if battle['ordinary'] and battle['loser'] >= 0:
            side = 0 if battle['loser'] == battle['attacker'] else 1
            owner = battle['loser'] // 3
            eliminated = f"creature_eliminated({battle['loser']})" in events
            if battle['triumph_intentions'][side] and eliminated and next_turn and next_turn.startswith(f'turn_started({owner},'):
                actual['triumph_actual_elimination_and_next_turn'] += 1

seen = set(itertools.chain.from_iterable(r['drawn'][p] for r in rows for p in range(2)))
started = {card_id for r in rows for d in r['decks'] for cards_ in d[1:] for card_id in cards_}
played_any = {card_id for e in elements for field in ['played','attached','opened'] for card_id in e[field]}
swap_differences = [dict(block=i, first_role=j, elements=rows[i]['elements'], roster=rows[i]['roster'], a_scores=[rows[i+j]['a_score'], rows[i+2+j]['a_score']]) for i in range(0,len(rows),4) for j in range(2) if rows[i+j]['a_score'] != rows[i+2+j]['a_score']]
out = dict(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), failures=raw['failures'], cross_matches=len(rows), mirrors=len(raw['matches'])-len(rows), first_wins=first_wins, side0_wins=side0_wins, draws=sum(r['winner_player'] < 0 for r in rows), turn_limit_matches=sum(r['turns'] >= 60 for r in rows), turns_range=[min(r['turns'] for r in rows), max(r['turns'] for r in rows)], battles=sum(len(r['battles']) for r in rows), elements=elements, matrix=matrix, new_cards=coverage, actual_new_effect_evidence=dict(actual), side_swap_outcome_differences=swap_differences, coverage=dict(catalog=len(cards), initial_or_drawn=len(seen|started), drawn=len(seen), played_attached_or_opened=len(played_any), never_seen=sorted(set(cards)-seen-started), never_played_attached_opened=sorted(set(cards)-played_any)))
target = path.with_name(path.stem + '-summary.json')
target.write_text(json.dumps(out, ensure_ascii=False, indent=2)+'\n')
print(json.dumps({k: v for k, v in out.items() if k not in ['elements', 'matrix']}, ensure_ascii=False, indent=2))
for e in elements:
    print(e['element'], e['wins'], e['draws'], e['losses'], round(e['score'], 4), 'rosters', [round(r['score'], 3) for r in e['by_roster_seed']], 'first/second', [round(r['score'], 3) for r in e['by_first_move']], 'flag', e['exploratory_flag'])
print('matrix', matrix)
