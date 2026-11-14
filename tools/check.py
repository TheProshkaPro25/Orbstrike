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
parser.add_argument('--logic-only', action='store_true', help='Явно выбранные стенды без дисплея; без PNG/визуальной приёмки')
parser.add_argument('--list', action='store_true', help='Показать выбранные проверки без выполнения')
parser.add_argument('--checks', nargs='+', help='Запустить только названные проверки профиля (без остальных)')
parser.add_argument('--full', action='store_true')
parser.add_argument('--visual', action='store_true')
parser.add_argument('--only', nargs='+', choices=['experience', 'autoplay'], help='Совместимость: повтор выбранной графической проверки')
args = parser.parse_args()
if args.logic_only and not args.checks:
    parser.error('--logic-only требует явные --checks')
if args.only and args.profile:
    parser.error('--only и --profile выбирают область разными способами; укажите один')
MODELS = ['animation', 'support', 'flight', 'idle', 'stance', 'review-state', 'preparation-cache', 'preview-pool', 'memory-catalog', 'cloth-sharing', 'hd-material-retention']
RULES = ['career', 'career-power', 'card-effect-edges', 'elemental-cards', 'species-cards', 'battle-lockout', 'ai-swap-combo', 'ai-fallen-call', 'ai-formation', 'card-price-rules', 'standoff-lottery', 'last-rush', 'ai-interruption', 'ai-material', 'ai-forecast', 'ai-gust-risk', 'ai-target-flow', 'cards033', 'campaign', 'tournament', 'rules', 'rules-edges', 'cards', 'card-balance', 'card-matches', 'card-counters', 'card-scenarios', 'card-choices', 'card-audit-positions', 'ai', 'ai-gates', 'ai-outcomes', 'ai-rescue-matches', 'shot-physics']
SCRIPTS = {
    'architecture-contracts': 'tools/test_architecture_contracts.gd',
    'match-lifecycle': 'tools/test_match_lifecycle.gd',
    'local-creatures': 'tools/test_local_creatures.gd',
    'creature-preview-refresh': 'tools/test_creature_preview_refresh.gd',
    'creature-element-fx': 'tools/test_creature_element_fx.gd',
    'stone-tide-fx': 'tools/test_creature_element_fx.gd',
    'sport-neck': 'tools/test_sport_neck.gd',
    'sport-style': 'tools/test_sport_style.gd',
    'wardrobe-fit': 'tools/test_wardrobe_fit.gd',
    'wardrobe-catalog-motion': 'tools/test_wardrobe_catalog_motion.gd',
    'wardrobe-palette': 'tools/test_wardrobe_palette.gd',
    'booth-outfits': 'tools/test_booth_outfits.gd',
    'startup-failure': 'tools/test_startup_failure.gd',
    'preview-refresh': 'tools/test_preview_refresh.gd',
    'optimization': 'tools/test_optimization_regression.gd',
    'location-reveal': 'tools/test_location_reveal.gd',
    'grifalon-fullset': 'tools/test_grifalon_fullset.gd',
    'kolossar-fullset': 'tools/test_kolossar_fullset.gd',
    'kolossar-runtime-pool': 'tools/perf_turn_pool.gd',
    'kolossar-common-master': 'tools/test_kolossar_master_motion.gd',
    'grifalon-common-master': 'tools/test_grifalon_master_motion.gd',
    'grifalon-runtime-pool': 'tools/perf_turn_pool.gd',
    'humanoid-motion': 'tools/test_humanoid_motion.gd',
    'ratnik-family': 'tools/test_humanoid_motion.gd',
    'hud-gdelta': 'tools/test_hud_gdelta.gd',
    'card-hover': 'tools/test_card_hover.gd',
    'battle-ui-followup': 'tools/test_battle_ui_followup.gd',
    'device-battle-hud': 'tools/test_device_battle_hud.gd',
    'portrait-client-smoke': 'tools/test_portrait_client_smoke.gd',
    'portrait-background': 'tools/test_portrait_background.gd',
    'portrait-standby': 'tools/test_portrait_standby.gd',
    'a03-anatomy': 'tools/test_model_a03_anatomy.gd',
    'cloth-rim-contract': 'tools/test_cloth_rim_contract.gd',
    'gpu-acceptance': 'tools/test_gpu_acceptance.gd',
    'ratnik-crown-reopen': 'tools/test_ratnik_crown_reopen.gd',
    'model-wind-import': 'tools/test_model_wind_import.gd',
    'sculpt-import': 'tools/test_model_sculpt_import.gd',
    'a03-material-import': 'tools/test_model_sculpt_import.gd',
    'sculpt-source-poses': 'tools/deformation_audit.gd',
    'sculpt-candidate-poses': 'tools/deformation_audit.gd',
    'a03-candidate-poses': 'tools/deformation_audit.gd',
    'career': 'tools/test_career.gd',
    'career-power': 'tools/test_career_power.gd',
    'career-ui': 'tools/test_career_ui.gd',
    'ui-audit-fixes': 'tools/test_ui_audit_fixes.gd',
    'ui-card-access': 'tools/test_ui_card_access.gd',
    'menu-access': 'tools/test_ui_menu_access.gd',
    'match-keyboard': 'tools/test_ui_match_keyboard.gd',
    'match-keyboard-combo': 'tools/test_ui_match_keyboard.gd',
    'portrait-crop': 'tools/test_portrait_crop.gd',
    'career-flow': 'tools/test_career_flow.gd',
    'device-ui': 'tools/test_device_ui.gd',
    'device-feedback': 'tools/test_device_feedback.gd',
    'opponent-panel': 'tools/test_opponent_panel.gd',
    'card-effect-edges': 'tests/card_effect_edge_tests.gd',
    'elemental-cards': 'tests/elemental_cards_tests.gd',
    'species-cards': 'tests/species_cards_tests.gd',
    'battle-lockout': 'tests/battle_lockout_tests.gd',
    'battle-lockout-ui': 'tests/battle_lockout_ui_tests.gd',
    'ai-swap-combo': 'tests/ai_swap_combo_strategy_tests.gd',
    'ai-fallen-call': 'tests/ai_fallen_call_strategy_tests.gd',
    'ai-formation': 'tools/ai_formation_positions.gd',
    'card-pact-price-ui': 'tests/card_price_ui_tests.gd',
    'card-leap-price-ui': 'tests/card_price_ui_tests.gd',
    'card-sure-price-ui': 'tests/card_price_ui_tests.gd',
    'card-price-rules': 'tests/card_price_rules_tests.gd',
    'card-price-ui': 'tests/card_price_ui_tests.gd',
    'ai-gust-risk': 'tests/ai_gust_risk_tests.gd',
    'standoff-notice': 'tests/standoff_notice_tests.gd',
    'last-rush-ui': 'tests/last_rush_ui_tests.gd',
    'standoff-lottery': 'tests/standoff_lottery_tests.gd',
    'last-rush': 'tests/last_rush_rules_tests.gd',
    'ai-interruption': 'tests/ai_interruption_strategy_tests.gd',
    'ai-material': 'tests/ai_material_strategy_tests.gd',
    'ai-forecast': 'tests/ai_forecast_strategy_tests.gd',
    'ai-target-flow': 'tests/ai_target_flow_tests.gd',
    'hd-material-retention': 'tests/hd_material_retention_tests.gd',
    'memory-catalog': 'tests/memory_catalog_tests.gd',
    'cloth-sharing': 'tests/cloth_gpu_sharing_tests.gd',
    'portrait-visibility': 'tests/portrait_visibility_tests.gd',
    'menu-music': 'tests/menu_music_tests.gd',
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
    'location-detail': 'tests/location_detail_tests.gd',
    'battle-card-hover': 'tests/battle_card_hover_tests.gd',
    'cards033': 'tests/cards033_tests.gd', 'cards033-ui': 'tests/new_cards_ui_tests.gd',
    'cards': 'tests/card_revision_tests.gd', 'cards-ui': 'tests/card_readability_tests.gd',
    'cards-art': 'tests/card_artwork_tests.gd', 'menu-environment': 'tools/menu_environment_review.gd',
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
    plan = ['import', *RULES, 'online-core', 'online-messages', 'online-physics', 'online-ui', 'startup-loading', 'turn-pool', 'duel-exit', 'campaign-flow', 'tournament-flow', 'career-flow', 'autoplay']
elif args.profile == 'presentation':
    plan = ['import', 'ui-audit-fixes', 'ui-card-access', 'menu-access', 'match-keyboard', 'match-keyboard-combo', 'portrait-crop', 'career-ui', 'device-ui', 'device-feedback', 'opponent-panel', 'battle-lockout-ui', 'card-pact-price-ui', 'card-leap-price-ui', 'card-sure-price-ui', 'card-price-ui', 'standoff-notice', 'last-rush-ui', 'duel-exit', 'online-ui', 'online-disconnect', 'online-gate-result', 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'npc-appearance', 'hand-placement', 'campaign-ui', 'tournament-ui', 'menu-lighting', 'sanctuary-mood', 'location-detail', 'shot-physics', 'sphere-pose', 'reveal-camera', 'ability-input', 'battle-card-hover', 'cards-ui', 'cards-art', 'cards033-ui', 'portrait-visibility', 'menu-music', 'menu-environment', 'window-lighting', 'high-graphics', 'experience']
elif args.profile == 'models':
    plan = ['import', *MODELS]
elif args.profile == 'full':
    plan = ['import', 'ui-audit-fixes', 'ui-card-access', 'menu-access', 'match-keyboard', 'match-keyboard-combo', 'portrait-crop', *RULES, 'online-core', 'online-messages', 'online-physics', 'online-ui', 'card-pact-price-ui', 'card-leap-price-ui', 'card-sure-price-ui', 'card-price-ui', 'standoff-notice', 'last-rush-ui', *MODELS, 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'npc-appearance', 'hand-placement', 'campaign-ui', 'tournament-ui', 'gpu-core', 'menu-lighting', 'sanctuary-mood', 'location-detail', 'sphere-pose', 'reveal-camera', 'ability-input', 'battle-card-hover', 'cards-ui', 'cards-art', 'cards033-ui', 'portrait-visibility', 'menu-music', 'menu-environment', 'window-lighting', 'high-graphics', 'experience', 'startup-loading', 'turn-pool', 'duel-exit', 'campaign-flow', 'tournament-flow', 'career-flow', 'autoplay']
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
if args.profile == 'gameplay' and args.checks and 'architecture-contracts' in args.checks:
    plan.append('architecture-contracts')
if args.profile == 'gameplay' and args.checks:
    for optional in ('match-lifecycle', 'local-creatures'):
        if optional in args.checks: plan.append(optional)
if args.profile == 'models' and args.checks:
    for optional in ['kolossar-runtime-pool', 'kolossar-common-master', 'kolossar-fullset', 'grifalon-common-master', 'grifalon-fullset', 'grifalon-runtime-pool', 'ratnik-family', 'humanoid-motion', 'a03-anatomy', 'cloth-rim-contract', 'gpu-acceptance', 'ratnik-crown-reopen', 'model-wind-import', 'sculpt-import', 'sculpt-candidate-poses', 'a03-material-import', 'sculpt-source-poses', 'a03-candidate-poses']:
        if optional in args.checks: plan.append(optional)
if args.profile == 'presentation' and args.checks:
    for optional in ['creature-element-fx', 'stone-tide-fx', 'device-battle-hud', 'portrait-client-smoke', 'wardrobe-catalog-motion']:
        if optional in args.checks: plan.append(optional)
    for optional in ['sport-neck', 'sport-style', 'wardrobe-fit', 'wardrobe-palette', 'booth-outfits', 'startup-failure', 'creature-preview-refresh', 'preview-refresh', 'optimization', 'location-reveal', 'hud-gdelta', 'card-hover', 'battle-ui-followup', 'portrait-background', 'portrait-standby']:
        if optional in args.checks: plan.append(optional)
if args.checks:
    unknown = set(args.checks) - set(plan)
    if unknown:
        parser.error('Проверки отсутствуют в выбранном профиле: ' + ', '.join(sorted(unknown)))
    plan = [name for name in plan if name in args.checks]
if args.logic_only:
    print('Headless checks: no rendered images or visual acceptance', flush=True)
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
    command = ['godot', '--path', str(ROOT), '--max-fps', '60', '--log-file', str(OUT/(name + '-engine.log'))]
    if name == 'import':
        command += ['--headless', '--editor', '--import']
    else:
        graphics = name in ['a03-material-import', 'a03-candidate-poses', 'sculpt-import', 'sculpt-source-poses', 'sculpt-candidate-poses', 'model-wind-import', 'ui-audit-fixes', 'ui-card-access', 'menu-access', 'match-keyboard', 'match-keyboard-combo', 'portrait-crop', 'career-ui', 'career-flow', 'device-ui', 'device-feedback', 'opponent-panel', 'location-detail', 'battle-lockout-ui', 'card-pact-price-ui', 'card-leap-price-ui', 'card-sure-price-ui', 'card-price-ui', 'standoff-notice', 'last-rush-ui', 'menu-music', 'memory-catalog', 'cloth-sharing', 'portrait-visibility', 'duel-exit', 'online-ui', 'online-disconnect', 'online-gate-result', 'motion-bank', 'fighter-lighting', 'vrm-fighter', 'wardrobe-wrists', 'street-set', 'sport-set', 'vrm-parts', 'vrm-preview', 'character-editor', 'battle-card-hover', 'cards-ui', 'cards-art', 'cards033-ui', 'menu-environment', 'menu-lighting', 'sanctuary-mood', 'startup-loading', 'experience', 'autoplay', 'gpu-core', 'ability-input', 'window-lighting', 'high-graphics', 'turn-pool', 'campaign-flow', 'campaign-flow', 'tournament-flow', 'tournament-ui', 'hand-placement', 'npc-appearance', 'campaign-ui'] or (name in MODELS and (args.visual or args.profile == 'full'))
        if name in ['ratnik-family', 'humanoid-motion', 'local-creatures']: graphics = True
        if name in ['grifalon-fullset', 'grifalon-runtime-pool']: graphics = True
        if name in ['kolossar-fullset', 'kolossar-runtime-pool']: graphics = True
        if name == 'ratnik-crown-reopen': graphics = True
        if name == 'a03-anatomy': graphics = True
        if name in ['gpu-acceptance']: graphics = True
        if name in ['creature-element-fx', 'stone-tide-fx', 'device-battle-hud', 'portrait-client-smoke', 'wardrobe-catalog-motion']: graphics = True
        if name in ['sport-neck', 'sport-style', 'wardrobe-fit', 'wardrobe-palette', 'booth-outfits', 'startup-failure', 'creature-preview-refresh', 'match-lifecycle', 'preview-refresh', 'optimization', 'location-reveal', 'hud-gdelta', 'card-hover', 'battle-ui-followup', 'portrait-background', 'portrait-standby']: graphics = True
        if not graphics or args.logic_only:
            command += ['--headless']
        script = SCRIPTS[name]
        if graphics:
            # Окно сначала создаётся вне рабочего стола, затем сразу сворачивается.
            # Wrapper наследует настоящий тест, сохраняя его команды и проверки.
            wrapper = OUT / ('background-' + name + '.gd')
            wrapper.write_text('extends "res://' + script + '"\nfunc _initialize() -> void:\n\tpreload("res://tools/test_window.gd").background(self)\n\tsuper._initialize()\nfunc _finalize() -> void:\n\tpreload("res://tools/test_window.gd").finish(self)\n')
            script = wrapper.relative_to(ROOT).as_posix()
            if not args.logic_only:
                command += ['--windowed', '--position', '-20000,-20000']
        command += ['-s', 'res://' + script]
        if name in ['creature-element-fx', 'stone-tide-fx', 'local-creatures']:
            command += ['--audio-driver', 'Dummy']
        if name in ['grifalon-runtime-pool', 'kolossar-runtime-pool']:
            command += ['--', str(OUT/(name + '.json')), 'kolossar' if name == 'kolossar-runtime-pool' else 'grifalon']
        elif name == 'ratnik-family':
            command += ['--', 'family-new']
        elif name in ['sculpt-source-poses', 'sculpt-candidate-poses', 'a03-candidate-poses']:
            variant = 'source' if name == 'sculpt-source-poses' else 'candidate'
            command += ['--', str(ROOT/'build/checks/sculpt-poses'/variant),
                        'creature_kolossar_shadow' if name == 'a03-candidate-poses' else 'creature_kolossar_shadow,creature_ratnik_light',
                        'source-dir=' + str(ROOT/'build/model_candidates/2026-11-06-sculpt'/variant),
                        'actions=idle,attack,hit', 'idle-seconds=2', 'sample-step=6']
        elif name == 'a03-material-import':
            command += ['--', 'a03-only']
        elif name == 'match-keyboard-combo':
            command += ['--', '--combo-only']
        elif name == 'card-pact-price-ui':
            command += ['--', 'pact-only']
        elif name == 'card-leap-price-ui':
            command += ['--', 'leap-only']
        elif name == 'card-sure-price-ui':
            command += ['--', 'sure-only']
        elif name in ['memory-catalog', 'cloth-sharing', 'portrait-visibility']:
            command += ['--', str(OUT/name)]
        elif name == 'online-ui':
            command += ['--', str(OUT/'ui')]
        elif name == 'rules':
            command += ['--', 'rules-only']
        elif name in ['location-detail', 'menu-lighting', 'sanctuary-mood', 'cards-art', 'menu-environment']:
            command += ['--', str(OUT/name)]
        elif name == 'startup-loading':
            command += ['--', str(OUT/'startup-loading')]
        elif name == 'experience':
            command += ['--', str(OUT/'experience')]
        elif name == 'stone-tide-fx':
            command += ['--', str(OUT/name), '--stone-tide']
        elif name in ['battle-card-hover', 'creature-element-fx', 'device-battle-hud', 'portrait-client-smoke']:
            command += ['--', str(OUT/name)]
        elif name == 'career-flow':
            command += ['--', str(OUT/name)]
        elif name in ['match-lifecycle', 'preview-refresh', 'optimization', 'career-ui', 'portrait-crop', 'portrait-background', 'card-hover']:
            command += ['--', '--out=' + str(OUT/name)]
        elif name in ['device-ui', 'device-feedback', 'opponent-panel', 'cards-ui', 'cards033-ui']:
            command += ['--', str(OUT/name)]
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
        elif name == 'local-creatures':
            command += ['--', str(OUT)]
    timeout = 60 if name == 'portrait-standby' else (1200 if name == 'card-audit-balance' else (600 if name in MODELS or name in ['autoplay', 'tournament-flow', 'online-ui'] else 360))
    run(name, command, timeout)

# Явные профили имеют собственную свежую сводку; результаты разных областей не смешиваются.
if args.only:
    previous = json.loads((OUT/'summary.json').read_text()) if (OUT/'summary.json').exists() else []
    replacement = {row['name']: row for row in results}
    current_names = {row['name'] for row in previous}
    results = [replacement.get(row['name'], row) for row in previous] + [row for row in results if row['name'] not in current_names]
(OUT/'summary.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
raise SystemExit(0 if all(row['ok'] for row in results) else 1)
