#!/usr/bin/env python3
"""Summarize the fixed, purposive 400-match card audit (not population inference)."""
import collections
import json
import random
import sys
from pathlib import Path


def score(row):
    return 1.0 if row['win'] == 1 else (0.5 if row['win'] == -1 else 0.0)


def totals(rows):
    keys = ['active_battles', 'plays', 'attached', 'placed', 'opened', 'late_opened',
            'opponent_cards_muted', 'cancelled', 'local_outcome_changes',
            'actual_revived', 'target_revived', 'returned_target', 'returned_other',
            'natural_recharged_target', 'reused', 'early_returns', 'last_creature_returns']
    return {'matches': len(rows), 'wins': sum(r['win'] == 1 for r in rows),
            'draws': sum(r['win'] == -1 for r in rows),
            'losses': sum(r['win'] == 0 for r in rows),
            'score': sum(map(score, rows)) / len(rows),
            **{key: sum(r[key] for r in rows) for key in keys}}


def compare(rows):
    paired = collections.defaultdict(dict)
    for r in rows:
        paired[(r['sample'], r['seed'], r['side'])][r['variant']] = r
    if any(set(p) != {0, 1} for p in paired.values()):
        raise ValueError('Missing matched variant')
    clusters = collections.defaultdict(list)
    for (sample, seed, side), pair in paired.items():
        if pair[0]['pool_hash'] != pair[1]['pool_hash']:
            raise ValueError('Unmatched draw pool')
        clusters[(sample, seed)].append(score(pair[1]) - score(pair[0]))
    if any(len(values) != 2 for values in clusters.values()):
        raise ValueError('Missing mirrored side')
    cluster_values = [sum(v) / len(v) for v in clusters.values()]
    rng = random.Random(11703)
    boot = sorted(sum(rng.choices(cluster_values, k=len(cluster_values))) /
                  len(cluster_values) for _ in range(10000))
    a = totals([r for r in rows if r['variant'] == 0])
    b = totals([r for r in rows if r['variant'] == 1])
    def composition(row):
        # Species j0/j2 share a label but have different element/roster pairs.
        return row['sample'] + ' | ' + ','.join(row['decks'][0][0]) + ' vs ' + ','.join(row['decks'][1][0])
    samples = sorted({composition(r) for r in rows})
    contexts = {}
    for sample in samples:
        subset = [r for r in rows if composition(r) == sample]
        aa = totals([r for r in subset if r['variant'] == 0])
        bb = totals([r for r in subset if r['variant'] == 1])
        contexts[sample] = {'a': aa, 'b': bb, 'delta': bb['score'] - aa['score']}
    delta = b['score'] - a['score']
    sign = 1 if delta >= 0 else -1
    positive_fraction = sum(sign * c['delta'] > 0 for c in contexts.values()) / len(contexts)
    low, high = boot[249], boot[9749]
    directional_low = low if sign == 1 else -high
    active = b['active_battles'] if sign == 1 else a['active_battles']
    trigger = abs(delta) >= 0.20 and directional_low > 0.05 and positive_fraction >= 0.75 and active >= 20
    gaps = [v for r in rows for v in r['rescue_cooldown_gaps']]
    return {'a': a, 'b': b, 'paired_delta': delta, 'paired_ci95': [low, high],
            'cluster_count': len(cluster_values), 'direction_positive_context_fraction': positive_fraction,
            'preregistered_change_signal': trigger, 'contexts': contexts,
            'turn_range': [min(r['turns'] for r in rows), max(r['turns'] for r in rows)],
            'actual_rescue_recharge_gaps': gaps,
            'revivals_by_source': dict(collections.Counter(e['source'] for r in rows for e in r['events'])),
            'policy_only': rows[0]['group'] == 'rescue'}


def main(path):
    report = json.loads(path.read_text())
    if report['failures'] or len(report['matches']) != 400:
        raise ValueError('Fixed grid incomplete or failed')
    validation = report.get('revival_trace_validation')
    if not validation or validation['failures']:
        raise ValueError('Actual revival provenance not validated')
    groups = collections.defaultdict(list)
    for row in report['matches']:
        groups[row['group']].append(row)
    summary = {'preregistered': report['preregistered'],
               'revival_trace_validation': validation,
               'fixture_repair': report.get('fixture_repair'),
               'fixture_repair_manifest': 'fixture-repair-manifest.json',
               'raw_historical': 'card-audit-balance-fixture-draft-uncorrected.json',
               'limits': 'Paired CI conditional on purposive fixtures, not global meta; local ablation not alternate match; rescue measures policy only.',
               'groups': {group: compare(rows) for group, rows in groups.items()}}
    out = path.with_name('card-audit-balance-summary.json')
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    for group, value in summary['groups'].items():
        print(group, 'A', value['a']['wins'], value['a']['draws'], value['a']['losses'],
              'B', value['b']['wins'], value['b']['draws'], value['b']['losses'],
              'delta', round(value['paired_delta'], 4), 'CI', value['paired_ci95'],
              'change_signal', value['preregistered_change_signal'])
        for sample, context in value['contexts'].items():
            print(' ', sample, round(context['delta'], 4))
    print(out)


if __name__ == '__main__':
    main(Path(sys.argv[1]))
