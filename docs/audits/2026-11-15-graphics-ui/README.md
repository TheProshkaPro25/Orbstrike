# Воспроизведение аудита клиента Orbstrike

[Итоговый отчёт](../../GRAPHICS_UI_AUDIT_2026-11-15.md). JSON в этой папке
содержит замеры свежих прогонов. Полные логи, исходные PNG и контактные листы
остаются в `build/checks/`. Диагностическое поле `aim_view` исключено из
`graphics.json`: этот ракурс используется только утилитами, выбор ворот
в матче проверен отдельно на штатном общем плане в `field.json`.

## Штатные команды

```sh
python tools/check.py --profile gameplay --checks startup-loading
python tools/check.py --profile presentation --checks menu-environment high-graphics
ORBSTRIKE_LOCATION_CAPTURE_SET=audit-20261115 python tools/check.py --profile presentation --checks location-detail sphere-pose reveal-camera experience creature-element-fx
python tools/check.py --profile presentation --checks experience
```

## Адресные пробы

Из корня проекта. Каждый сценарий сам включает `tools/test_window.gd` до
первого кадра. XDG изолирует данные игрока. Для отдельного headless-прогона
добавьте `--headless` и уберите `--windowed --position -20000,-20000`.
Визуальные пробы графики используют GPU. На диске можно сохранить новый
выход отдельно, чтобы прежние кадры оставались доступными.

```sh
scripts=docs/audits/2026-11-15-graphics-ui
run_probe() {
    name=$1
    output=$2
    shift 2
    mkdir -p "$output"
    XDG_CONFIG_HOME="$output/config" XDG_DATA_HOME="$output/data" \
        godot --path . --max-fps 60 --windowed --position -20000,-20000 \
        --audio-driver Dummy --log-file "$output/engine.log" \
        -s "res://$scripts/$name.gd" -- "$@"
}

base="$PWD/build/checks/presentation/graphics-ui-audit-20261115/reproduction"
mkdir -p build/checks/ui-audit-20261115-front build/checks/presentation/match-ui-audit-2026-11-15
run_probe menu_probe "$base/menu" "--out=$base/menu"
run_probe duel_entry_probe "$base/duel-entry"
run_probe match_ui_probe "$base/match"
run_probe match_input_probe "$base/match-input"
run_probe graphics_probe "$base/graphics" "$base/graphics"
run_probe graphics_probe "$base/field" "$base/field" --field-only
run_probe graphics_probe "$base/catalog" "$base/catalog" --catalog-only
run_probe p2_match_probe "$base/p2-match" "--out=$base/p2-match"
run_probe p2_result_intro_probe "$base/p2-result-intro" "--out=$base/p2-result-intro"
run_probe p3_arena_probe "$base/p3-arena" "--out=$base/p3-arena"
run_probe p3_controls_probe "$base/p3-controls" "--out=$base/p3-controls"
run_probe p3_graphics_probe "$base/p3-graphics" "$base/p3-graphics"
run_probe p3_graphics_probe "$base/p3-field" "$base/p3-field" --field-only
```

Исходные пробы `duel_entry_probe`, `match_ui_probe` и `match_input_probe`
сохраняют кадры и JSON по фиксированным путям. `match_ui_probe` воспроизводит
поведение до исправлений, архивные JSON сохраняют исходные наблюдения.
Пробы с аргументом `--out=` пишут в указанный каталог. Клиентский JSON Codec проверяется
без сокета и рендера скриптом `p2_codec_probe.gd` с `--headless --max-fps 60`.
Графическая проба P3 принимает путь первым аргументом. `--field-only`
открывает Main с шестью воротами и панелью перед броском без загрузки Комнаты.
Для адресной проверки удержания стрелки используйте `p3_arena_probe.gd` с
`--headless --max-fps 60` и пользовательскими аргументами `--out=… --echo-only`.
