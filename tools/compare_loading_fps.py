#!/usr/bin/env python3
"""Serialized A/B comparison of reproduced legacy loading and startup catalogue.

This is a minimized offscreen GPU benchmark, not fullscreen player FPS.
Example: python tools/compare_loading_fps.py --pairs 3
Smoke:   python tools/compare_loading_fps.py --pairs 1 --warmup .2 --measure .4 --out build/checks/loading-fps-smoke
No source, model, user settings, or historical git checkout is changed.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = ('legacy_path', 'startup_catalog')
STAGES = ('time_to_menu_seconds', 'play_to_team_seconds', 'team_to_battle_ready_seconds',
          'menu_to_battle_ready_seconds', 'battle_ready_seconds_total')
FPS_METRICS = ('mean_fps', 'mean_frame_ms', 'median_frame_ms', 'p95_frame_ms',
               'gpu_render_ms_mean', 'cpu_render_ms_mean', 'cpu_frame_setup_ms_mean',
               'engine_drawn_per_process_frame', 'post_draw_per_process_frame')
LIMITATION = ('No historical pre-task snapshot exists. Both paths run the same current code, '
              'graphics and models; legacy_path reconstructs only the former menu-first '
              'six-creature preparation with a test-only loading overlay. This does not '
              'compare against git HEAD 0.2.9 or isolate every intervening optimization. '
              'FPS is measured on a minimized offscreen stand without screen presentation '
              'or swap, not fullscreen player FPS. OS/driver caches are not flushed. '
              'Each run uses a fresh Godot process and isolated XDG directories. '
              'GPU/CPU times describe the latest viewport draw; explicit draw counters '
              'expose repeated rendering. Animated screenshots are for visual review, '
              'not pixel-equality assertions.')


def model_hashes():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / 'assets' / 'creatures_hd').glob('*.glb'))}


def percent_change(before, after):
    return (after / before - 1) * 100 if before else None


def median(values):
    return statistics.median(values) if values else None


def summarize(rows, expected_pairs):
    good = [r for r in rows if r['ok']]
    summary = {'limitation': LIMITATION, 'expected_pairs': expected_pairs,
               'successful_runs': len(good), 'all_runs_ok': len(rows) == 2 * expected_pairs and len(good) == len(rows),
               'variants': {}, 'deltas_percent_after_vs_before': {}, 'pairs': [], 'draw_warning': []}
    for variant in VARIANTS:
        subset = [r['result'] for r in good if r['variant'] == variant]
        summary['variants'][variant] = {
            'repeats': len(subset),
            'stages_median_seconds': {key: median([r['stages'][key] for r in subset]) for key in STAGES},
            'process_spawn_to_menu_seconds_median': median([r['process_spawn_to_menu_seconds'] for r in subset]),
            'process_spawn_to_battle_ready_seconds_median': median([r['process_spawn_to_battle_ready_seconds'] for r in subset]),
            'shots_median_over_repeats': {},
        }
        for shot in ('overview', 'battle', 'closeup'):
            samples = [next(s for s in r['shots'] if s['shot'] == shot) for r in subset]
            summary['variants'][variant]['shots_median_over_repeats'][shot] = {
                metric: median([s[metric] for s in samples]) for metric in FPS_METRICS}
            if samples and max(s['post_draw_per_process_frame'] for s in samples) > 1.2:
                summary['draw_warning'].append(f'{variant}/{shot}: more than one frame_post_draw per process frame; FPS includes extra rendering from the background draw path.')
    if all(summary['variants'][v]['repeats'] for v in VARIANTS):
        before, after = (summary['variants'][v] for v in VARIANTS)
        summary['deltas_percent_after_vs_before']['stages'] = {
            key: percent_change(before['stages_median_seconds'][key], after['stages_median_seconds'][key])
            for key in STAGES}
        summary['deltas_percent_after_vs_before']['shots'] = {
            shot: {key: percent_change(before['shots_median_over_repeats'][shot][key],
                                       after['shots_median_over_repeats'][shot][key])
                   for key in FPS_METRICS}
            for shot in ('overview', 'battle', 'closeup')}
    for pair in range(1, expected_pairs + 1):
        pair_rows = [r for r in good if r['pair'] == pair]
        if len(pair_rows) != 2:
            continue
        a, b = (next(r['result'] for r in pair_rows if r['variant'] == v) for v in VARIANTS)
        summary['pairs'].append({'pair': pair, 'identical_six_creatures': a['creatures'] == b['creatures'],
                                 'stages_before': a['stages'], 'stages_after': b['stages']})
    return summary


def write_report(out, rows, pairs, hashes):
    summary = summarize(rows, pairs)
    summary['model_glb_sha256'] = hashes
    summary['runs'] = rows
    (out / 'comparison.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    lines = ['Сравнение воспроизведённого прежнего пути и стартового каталога.',
             'Стенд свёрнут, кадры не выводятся на экран; это не полноэкранный FPS.',
             f"Успешных запусков: {summary['successful_runs']} / {pairs * 2}",
             'Медианы повторений:']
    for variant, record in summary['variants'].items():
        lines.append(f"{variant}: повторений {record['repeats']}")
        for key, value in record['stages_median_seconds'].items():
            if value is not None:
                lines.append(f'  {key}: {value:.3f} s')
        for shot, record in record['shots_median_over_repeats'].items():
            if record['mean_fps'] is not None:
                lines.append(f"  {shot}: {record['mean_fps']:.2f} FPS, median {record['median_frame_ms']:.2f} ms, p95 {record['p95_frame_ms']:.2f} ms, post_draw/process {record['post_draw_per_process_frame']:.3f}")
    lines.extend(summary['draw_warning'])
    lines.append(LIMITATION)
    (out / 'comparison.txt').write_text('\n'.join(lines) + '\n')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pairs', type=int, default=3)
    parser.add_argument('--warmup', type=float, default=2.0)
    parser.add_argument('--measure', type=float, default=4.0)
    parser.add_argument('--timeout', type=float, default=480.0)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--out', type=Path, default=ROOT / 'build' / 'checks' / 'loading-fps-comparison')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.pairs < 1 or args.warmup <= 0 or args.measure <= 0:
        parser.error('pairs, warmup and measure must be positive')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build' / '.gdignore').touch()
    hashes = model_hashes()
    if not hashes:
        raise SystemExit('No model GLBs found')
    rows = []
    expected_roster = None
    for pair in range(1, args.pairs + 1):
        # Counterbalance order: A→B, B→A, A→B. Never run two Godot processes at once.
        order = VARIANTS if pair % 2 else tuple(reversed(VARIANTS))
        for order_index, variant in enumerate(order, 1):
            run_dir = out / f'pair-{pair}-{order_index}-{variant}'
            run_dir.mkdir(parents=True, exist_ok=True)
            command = [args.godot, '--path', str(ROOT), '--log-file', str(run_dir / 'engine.log'),
                       '--windowed', '--position', '-20000,-20000', '--resolution', '1920x1080',
                       '-s', 'res://tools/loading_fps_benchmark.gd', '--', f'variant={variant}',
                       f'out={run_dir}', f'warmup={args.warmup}', f'measure={args.measure}']
            print(f'Pair {pair}/{args.pairs}: {variant}', flush=True)
            if args.dry_run:
                print(json.dumps(command, ensure_ascii=False), flush=True)
                continue
            env = dict(os.environ, XDG_CONFIG_HOME=str(run_dir / 'config'),
                       XDG_DATA_HOME=str(run_dir / 'data'), XDG_CACHE_HOME=str(run_dir / 'cache'))
            launch_epoch = time.time()
            start = time.monotonic()
            try:
                completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=args.timeout)
                output, code = completed.stdout + completed.stderr, completed.returncode
            except subprocess.TimeoutExpired as exc:
                def as_text(value):
                    return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
                output, code = as_text(exc.stdout) + as_text(exc.stderr) + '\nFAIL: benchmark process timed out\n', 124
            (run_dir / 'console.log').write_text(output)
            errors = []
            if code != 0: errors.append(f'exit code {code}')
            if re.search(r'(^|\n)(ERROR:|SCRIPT ERROR:|FAIL:)', output): errors.append('engine/test error in console')
            if any(marker in output for marker in ('RIDs of type', 'ObjectDB instances were leaked', 'resources still in use')):
                errors.append('resource leak warning in console')
            result_path = run_dir / 'result.json'
            try:
                result = json.loads(result_path.read_text())
            except (OSError, ValueError) as exc:
                result = {}
                errors.append(f'missing/invalid result: {exc}')
            if result:
                if result.get('failures'): errors.append('benchmark assertions failed')
                if result.get('variant') != variant: errors.append('variant mismatch')
                roster = result.get('creatures', [])
                if len(roster) != 6: errors.append('roster does not contain six creatures')
                if expected_roster is None:
                    expected_roster = roster
                elif roster != expected_roster:
                    errors.append('six creature identities differ from the first run')
                shots = result.get('shots', [])
                if [s.get('shot') for s in shots] != ['overview', 'battle', 'closeup']:
                    errors.append('missing or mismatched camera measurements')
                for shot in shots:
                    if shot.get('process_frame_count', 0) <= 0 or not math.isfinite(shot.get('mean_fps', float('nan'))):
                        errors.append('invalid frame sample')
                stages = result.get('stages', {})
                if 'menu_epoch_seconds' in stages and 'battle_ready_epoch_seconds' in stages:
                    result['process_spawn_to_menu_seconds'] = stages['menu_epoch_seconds'] - launch_epoch
                    result['process_spawn_to_battle_ready_seconds'] = stages['battle_ready_epoch_seconds'] - launch_epoch
                else:
                    errors.append('missing stage timestamps')
            if model_hashes() != hashes: errors.append('model GLBs changed during comparison')
            row = {'pair': pair, 'order': order_index, 'variant': variant, 'ok': not errors,
                   'errors': errors, 'exit_code': code, 'wall_seconds': time.monotonic() - start,
                   'directory': str(run_dir), 'command': command, 'result': result}
            rows.append(row)
            write_report(out, rows, args.pairs, hashes)
            print(('PASS' if not errors else 'FAIL') + ' ' + variant + (': ' + '; '.join(errors) if errors else ''), flush=True)
            if errors:
                return 1
    if args.dry_run:
        return 0
    summary = write_report(out, rows, args.pairs, hashes)
    print((out / 'comparison.txt').read_text(), flush=True)
    return 0 if summary['all_runs_ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
