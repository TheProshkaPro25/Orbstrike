#!/usr/bin/env python3
"""Проверки по области: --profile gameplay|presentation|models|full.
Без профиля сохранены прежние --full/--visual/--only. --list показывает план без запуска.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / 'build' / 'checks'
parser = argparse.ArgumentParser()
parser.add_argument('--profile', choices=['gameplay', 'presentation', 'models', 'full'])
parser.add_argument('--list', action='store_true', help='Показать выбранные проверки без выполнения')
parser.add_argument('--checks', nargs='+', help='Запустить только названные проверки профиля (без остальных)')
parser.add_argument('--full', action='store_true')
parser.add_argument('--visual', action='store_true')
parser.add_argument('--only', nargs='+', choices=['experience', 'autoplay'], help='Совместимость: повтор выбранной графической проверки')
args = parser.parse_args()
if args.only and args.profile:
    parser.error('--only и --profile выбирают область разными способами; укажите один')
MODELS = ['animation', 'support', 'flight', 'idle', 'stance', 'review-state', 'preparation-cache', 'preview-pool']
RULES = ['campaign', 'tournament', 'rules', 'rules-edges', 'cards', 'card-balance', 'card-matches', 'card-counters', 'card-scenarios', 'card-choices', 'card-audit-positions', 'ai', 'ai-gates', 'ai-outcomes', 'ai-rescue-matches', 'shot-physics']
SCRIPTS = {
    'duel-exit': 'tests/duel_exit_tests.gd',
    'online-core': 'tests/online_core_tests.gd',
    'online-messages': 'tests/online_message_validation_tests.gd',
    'online-physics': 'tests/online_physics_tests.gd',
    'online-ui': 'tests/online_ui_tests.gd',
    'online-disconnect': 'tests/online_disconnect_tests.gd',
    'online-gate-result': 'tests/online_gate_result_tests.gd',
    'npc-appearance': 'tests/npc_appearance_tests.gd',
    'hand-placement': 'tests/hand_placement_tests.gd',
    'campaign': 'tests/campaign_tests.gd',
    'campaign-flow': 'tests/campaign_flow_tests.gd',
    'campaign-ui': 'tests/campaign_ui_tests.gd',
    'tournament': 'tests/tournament_tests.gd',
    'tournament-flow': 'tests/tournament_flow_tests.gd',
    'tournament-ui': 'tests/tournament_ui_tests.gd',
    'sport-set': 'tests/sport_set_tests.gd',
    'street-set': 'tests/street_set_tests.gd',
    'vrm-preview': 'tests/vrm_preview_tests.gd',
    'vrm-parts': 'tests/vrm_parts_tests.gd',
    'wardrobe-wrists': 'tests/wardrobe_wrist_tests.gd',
    'vrm-fighter': 'tests/vrm_fighter_tests.gd',
    'fighter-lighting': 'tests/fighter_lighting_tests.gd',
    'motion-bank': 'tests/motion_bank_review.gd',
    'character-editor': 'tests/character_editor_tests.gd',
    'card-balance': 'tools/card_balance_probe.gd', 'card-matches': 'tools/card_balance_matches.gd', 'card-counters': 'tools/card_counter_probe.gd', 'card-scenarios': 'tests/card_balance_scenarios.gd', 'card-choices': 'tools/card_choice_audit.gd',
    'card-audit-positions': 'tests/card_audit_balance_tests.gd', 'card-audit-balance': 'tools/card_audit_balance_probe.gd',
    'battle-card-hover': 'tests/battle_card_hover_tests.gd',
    'cards': 'tests/card_revision_tests.gd', 'cards-ui': 'tests/card_readability_tests.gd',
    'menu-lighting': 'tools/menu_lighting_review.gd', 'sanctuary-mood': 'tools/sanctuary_mood_review.gd',
    'preview-pool': 'tests/preview_pool_tests.gd',
    'startup-loading': 'tools/startup_loading_review.gd', 'high-graphics': 'tools/high_graphics_review.gd', 'reveal-camera': 'tests/reveal_camera_tests.gd', 'window-lighting': 'tools/window_lighting_review.gd', 'turn-pool': 'tools/perf_turn_pool.gd', 'preparation-cache': 'tests/preparation_cache_tests.gd', 'sphere-pose': 'tests/sphere_pose_tests.gd', 'ability-input': 'tests/ability_input_tests.gd', 'shot-physics': 'tests/shot_physics_tests.gd', 'rules': 'tests/run_tests.gd', 'rules-edges': 'tests/rules_edge_tests.gd',
    'ai-rescue-matches': 'tools/ai_rescue_probe.gd', 'ai-gates': 'tests/ai_gate_strategy_tests.gd', 'ai-outcomes': 'tests/ai_outcome_strategy_tests.gd',
    'ai': 'tests/ai_tactics_tests.gd', 'animation': 'tests/animation_tests.gd',
    'support': 'tests/support_tests.gd', 'flight': 'tests/flight_pose_tests.gd',
    'idle': 'tests/idle_loop_tests.gd', 'stance': 'tests/stance_frame_tests.gd',
    'review-state': 'tests/model_review_state_tests.gd', 'gpu-core': 'tests/run_tests.gd',
    'experience': 'tools/experience_review.gd', 'autoplay': 'tools/autoplay.gd',
}
if args.profile == 'gameplay':
    plan = ['import', *RULES, 'online-core', 'online-messages', 'online-physics', 'online-ui', 'startup-loading', 'turn-pool', 'duel-exit', 'campaign-flow', 'tournament-flow', 'autoplay']
elif args.profile == 'presentation':
    plan = ['import', 'duel-exit', 'online-ui', 'online-disconnect', 'online-gate-result', 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'npc-appearance', 'hand-placement', 'campaign-ui', 'tournament-ui', 'menu-lighting', 'sanctuary-mood', 'shot-physics', 'sphere-pose', 'reveal-camera', 'ability-input', 'battle-card-hover', 'cards-ui', 'window-lighting', 'high-graphics', 'experience']
elif args.profile == 'models':
    plan = ['import', *MODELS]
elif args.profile == 'full':
    plan = ['import', *RULES, 'online-core', 'online-messages', 'online-physics', 'online-ui', *MODELS, 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'npc-appearance', 'hand-placement', 'campaign-ui', 'tournament-ui', 'gpu-core', 'menu-lighting', 'sanctuary-mood', 'sphere-pose', 'reveal-camera', 'ability-input', 'battle-card-hover', 'cards-ui', 'window-lighting', 'high-graphics', 'experience', 'startup-loading', 'turn-pool', 'duel-exit', 'campaign-flow', 'tournament-flow', 'autoplay']
elif args.only:
    plan = args.only
else:
    plan = ['import', *RULES]
    if args.full:
        plan += MODELS
    if args.visual:
        plan += ['gpu-core', 'ability-input', 'experience', 'autoplay']
# Статистический аудит запускается лишь явно: не добавлять 400 матчей к обычной
# проверке gameplay/full после каждого изменения правил.
if args.profile in ['gameplay', 'full'] and args.checks and 'card-audit-balance' in args.checks:
    plan.append('card-audit-balance')
if args.checks:
    unknown = set(args.checks) - set(plan)
    if unknown:
        parser.error('Проверки отсутствуют в выбранном профиле: ' + ', '.join(sorted(unknown)))
    plan = [name for name in plan if name in args.checks]
print('Profile: ' + (args.profile or 'legacy') + '; checks: ' + ', '.join(plan), flush=True)
if args.list:
    raise SystemExit(0)
OUT = BASE_OUT / args.profile if args.profile else BASE_OUT
if args.checks:
    OUT = OUT / ('selected-' + '-'.join(plan))
    if 'online-ui' in plan:
        OUT = OUT / time.strftime('%Y%m%d-%H%M%S')
OUT.mkdir(parents=True, exist_ok=True)
(BASE_OUT.parent / '.gdignore').touch()
env = dict(os.environ, XDG_CONFIG_HOME=str(OUT/'config'), XDG_DATA_HOME=str(OUT/'data'))
results = []

def run(name, command, timeout=300):
    begin = time.monotonic()
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
        output, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        output, code = str(error), 124
    log = OUT/(name + '.log')
    log.write_text(output)
    # Godot иногда возвращает 0 при ошибке скрипта: одного exit code недостаточно.
    bad = code != 0 or any(marker in output for marker in ['SCRIPT ERROR:', 'FAIL:', '\nERROR:', 'RIDs of type', 'ObjectDB instances were leaked', 'resources still in use'])
    results.append(dict(name=name, profile=args.profile or 'legacy', ok=not bad, exit_code=code,
                        seconds=round(time.monotonic()-begin, 2), log=str(log)))
    print(('FAIL' if bad else 'PASS') + ' ' + name, flush=True)

for name in plan:
    if name == 'motion-bank' and not all((ROOT / f'assets/avatars/motions/kevin_local/fighter_{i}.res').exists() for i in range(2)):
        if args.checks and name in args.checks:
            parser.error('motion-bank требует локальные лицензированные клипы: см. assets/avatars/motions/KEVIN.md')
        results.append(dict(name=name, profile=args.profile or 'legacy', ok=True, skipped=True,
                            reason='Локальный Kevin bank не установлен; проверяются запасные CC0-клипы в vrm-fighter'))
        print('SKIP motion-bank: локальные клипы не установлены', flush=True)
        continue
    command = ['godot', '--path', str(ROOT), '--log-file', str(OUT/(name + '-engine.log'))]
    if name == 'import':
        command += ['--headless', '--editor', '--import']
    else:
        graphics = name in ['duel-exit', 'online-ui', 'online-disconnect', 'online-gate-result', 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'battle-card-hover', 'cards-ui', 'menu-lighting', 'sanctuary-mood', 'startup-loading', 'experience', 'autoplay', 'gpu-core', 'ability-input', 'window-lighting', 'high-graphics', 'turn-pool', 'campaign-flow', 'campaign-flow', 'tournament-flow', 'tournament-ui', 'hand-placement', 'npc-appearance', 'campaign-ui'] or (name in MODELS and (args.visual or args.profile == 'full'))
        if not graphics:
            command += ['--headless']
        script = SCRIPTS[name]
        if graphics:
            # Окно сначала создаётся вне рабочего стола, затем сразу сворачивается.
            # Wrapper наследует настоящий тест, сохраняя его команды и проверки.
            wrapper = OUT / ('background-' + name + '.gd')
            wrapper.write_text('extends "res://' + script + '"\nfunc _initialize() -> void:\n\tpreload("res://tools/test_window.gd").background(self)\n\tsuper._initialize()\nfunc _finalize() -> void:\n\tpreload("res://tools/test_window.gd").finish(self)\n')
            script = wrapper.relative_to(ROOT).as_posix()
            command += ['--windowed', '--position', '-20000,-20000']
        command += ['-s', 'res://' + script]
        if name == 'online-ui':
            command += ['--', str(OUT/'ui')]
        elif name == 'rules':
            command += ['--', 'rules-only']
        elif name in ['menu-lighting', 'sanctuary-mood']:
            command += ['--', str(OUT/name)]
        elif name == 'startup-loading':
            command += ['--', str(OUT/'startup-loading')]
        elif name == 'experience':
            command += ['--', str(OUT/'experience')]
        elif name == 'battle-card-hover':
            command += ['--', str(OUT/'battle-card-hover')]
        elif name == 'cards-ui':
            command += ['--', str(OUT/'cards-ui')]
        elif name == 'card-balance':
            command += ['--', str(OUT/'card-balance.json')]
        elif name in ['card-audit-positions', 'card-audit-balance']:
            command += ['--', str(OUT/(name + '.json'))]
        elif name == 'card-matches':
            command += ['--', str(OUT/'card-balance-matches.json')]
        elif name == 'card-counters':
            command += ['--', str(OUT/'card-counters.json')]
        elif name == 'ai-rescue-matches':
            command += ['--', str(OUT/'ai-rescue-matches.json')]
        elif name == 'ai-outcomes':
            command += ['--', str(OUT/'ai-outcomes.json')]
        elif name == 'card-scenarios':
            command += ['--', str(OUT/'card-balance-scenarios.json')]
        elif name == 'card-choices':
            source = OUT/'card-balance-matches.json' if 'card-matches' in plan else BASE_OUT/'gameplay'/'selected-card-matches'/'card-balance-matches.json'
            command += ['--', str(source), str(OUT/'card-choice-audit.json')]
        elif name == 'high-graphics':
            command += ['--', str(OUT/'high-graphics')]
        elif name == 'window-lighting':
            command += ['--', str(OUT/'window-lighting')]
        elif name == 'turn-pool':
            command += ['--', str(OUT/'turn-pool-timings.json')]
    timeout = 1200 if name == 'card-audit-balance' else (600 if name in MODELS or name in ['autoplay', 'tournament-flow', 'online-ui'] else 360)
    run(name, command, timeout)

# Явные профили имеют собственную свежую сводку; результаты разных областей не смешиваются.
if args.only:
    previous = json.loads((OUT/'summary.json').read_text()) if (OUT/'summary.json').exists() else []
    replacement = {row['name']: row for row in results}
    current_names = {row['name'] for row in previous}
    results = [replacement.get(row['name'], row) for row in previous] + [row for row in results if row['name'] not in current_names]
(OUT/'summary.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
raise SystemExit(0 if all(row['ok'] for row in results) else 1)
