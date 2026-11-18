# Воспроизведение графического аудита Orbstrike

[Основной отчёт](../../GRAPHICS_AUDIT_2026-11-15.md).
Команды выполняются из корня проекта с импортированными ресурсами именно
этой рабочей копии. Версия движка в журнале прогона — Godot 4.7.2.
Графические пробы требуют подходящего графического сеанса. `tools/check.py`
и отдельные сценарии используют `tools/test_window.gd`, который
сворачивает окно, запрещает ему фокус и рисует в текстуру при 60 FPS.
Сценарии запускаются последовательно.

Команды каталога существ и гардероба находятся в [отчёте по моделям](MODELS.md),
команды полёта и контакта — в [отчёте по эффектам](EFFECTS.md).

## Освещение, локации и вступление

```sh
ORBSTRIKE_LOCATION_CAPTURE_SET=audit-20261115-full python tools/check.py \
    --profile presentation \
    --checks sanctuary-mood location-detail menu-environment window-lighting high-graphics

base="$PWD/build/checks/presentation/graphics-audit-20261115-full"
out="$base/location-reveal"
mkdir -p "$out"
XDG_CONFIG_HOME="$out/config" XDG_DATA_HOME="$out/data" \
    godot --path . --max-fps 60 --windowed --position -20000,-20000 \
    --audio-driver Dummy --log-file "$out/engine.log" \
    -s res://docs/audits/2026-11-15-graphics/location_probe.gd -- "$out" \
    > "$out/run.log" 2>&1
```

Первая команда сохраняет сводку и графику в
[`build/checks/presentation/selected-sanctuary-mood-location-detail-menu-environment-window-lighting-high-graphics/`](../../../build/checks/presentation/selected-sanctuary-mood-location-detail-menu-environment-window-lighting-high-graphics/).
Адресная обёртка запускает штатный `tools/test_location_reveal.gd` с другим
путём вывода, чтобы сохранить результаты предыдущего аудита.
[Итог прогона вступлений](../../../build/checks/presentation/graphics-audit-20261115-full/location-reveal/run.log).

## Замер горизонта Гавани

Исходный кадр `location-detail/audit-20261115-full/location2-reverse.png`
имеет 1280×720 px. Для каждой области усреднено
`(0.2126 × R + 0.7152 × G + 0.0722 × B) / 255` по RGB из PNG.
Координаты в таблице даны включительно от верхнего левого угла.

| Область | X | Y | Средний RGB | Средняя величина |
|---|---:|---:|---:|---:|
| Небо | 520–556 | 163–170 | 35,38 / 86,12 / 129,75 | 0,3078 |
| Дальняя вода | 520–556 | 180–187 | 0,00 / 16,61 / 41,56 | 0,0584 |

Это разница отображённых пикселей в одном ракурсе. На другие сектора неба,
яркость монитора и видимость интерфейса она не переносится.
