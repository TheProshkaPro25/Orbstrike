#!/usr/bin/env python3
"""Evaluate the preregistered finite balance comparisons; never choose seeds or tune data."""
import collections
import hashlib
import json
from pathlib import Path
import sys

KEYS = ['fire', 'gale', 'light', 'stone', 'shadow', 'tide']

def load(path):
    raw = json.loads(Path(path).read_text())
    rows = []
    for row in raw['matches']:
        if row['mirror']:
            continue
        rows.append(dict(row, roster_key=tuple(raw['rosters'][row['roster']])))
    return raw, rows

def scores(rows, element):
    return [.5 if r['winner_player'] < 0 else float(r['elements'][r['winner_player']] == element) for r in rows if element in r['elements']]

def describe(rows):
    rosters = sorted({r['roster_key'] for r in rows})
    result = dict(matches=len(rows), draws=sum(r['winner_player'] < 0 for r in rows), limit_matches=sum(r['turns'] >= 60 for r in rows), unfinished=sum(not r['finished'] for r in rows))
    first = [.5 if r['winner_player'] < 0 else float(r['winner_player'] == r['first_player']) for r in rows]
    result['first_move'] = dict(wins=first.count(1), draws=first.count(.5), losses=first.count(0), score=sum(first)/len(first))
    result['elements'] = []
    for element, key in enumerate(KEYS):
        values = scores(rows, element)
        blocks = [scores([r for r in rows if r['roster_key'] == roster], element) for roster in rosters]
        by_roster = [sum(b)/len(b) for b in blocks]
        score = sum(values)/len(values)
        flag = (score <= .35 and sum(v <= .4 for v in by_roster)*3 >= 2*len(rosters)) or (score >= .65 and sum(v >= .6 for v in by_roster)*3 >= 2*len(rosters))
        result['elements'].append(dict(element=key, matches=len(values), wins=values.count(1), draws=values.count(.5), losses=values.count(0), score=score, roster_scores=by_roster, repeated_flag=flag))
    result['rosters'] = rosters
    result['extreme_pairs_requiring_review'] = []
    for a in range(6):
        for b in range(a+1, 6):
            blocks = []
            for roster in rosters:
                values = scores([r for r in rows if r['roster_key'] == roster and sorted(r['elements']) == [a,b]], a)
                if values:
                    blocks.append(dict(roster=roster, matches=len(values), score=sum(values)/len(values)))
            if sum(p['score'] <= .15 for p in blocks) >= 2 or sum(p['score'] >= .85 for p in blocks) >= 2:
                result['extreme_pairs_requiring_review'].append(dict(pair=[KEYS[a],KEYS[b]], blocks=blocks))
    result['corridors_pass'] = all(.35 <= e['score'] <= .65 for e in result['elements']) and .4 <= result['first_move']['score'] <= .6
    result['repeat_flags_pass'] = not any(e['repeated_flag'] for e in result['elements'])
    result['completion_pass'] = result['unfinished'] == 0 and result['limit_matches'] == 0
    return result

if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('usage: element_balance_acceptance.py after.json holdout.json result.json')
    after, arows = load(sys.argv[1])
    holdout, hrows = load(sys.argv[2])
    result = dict(method='Preregistered descriptive acceptance; correlated paired matches, no inferential population winrate.', sources={str(Path(p)): hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sys.argv[1:3]}, failures=after['failures']+holdout['failures'], after=describe(arows), holdout=describe(hrows), combined=describe(arows+hrows))
    result['acceptance_corridors_and_invariants_pass'] = not result['failures'] and all(result[name]['corridors_pass'] and result[name]['repeat_flags_pass'] and result[name]['completion_pass'] for name in ['holdout','combined'])
    Path(sys.argv[3]).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    for name in ['after','holdout','combined']:
        section = result[name]
        print(name, 'matches',section['matches'],'first',round(section['first_move']['score']*100,2),'corridors',section['corridors_pass'],'repeat_flags',section['repeat_flags_pass'],'extreme_pairs',len(section['extreme_pairs_requiring_review']))
        for e in section['elements']:
            print(' ',e['element'],e['wins'],e['draws'],e['losses'],round(e['score']*100,2))
