# Точное разделение текстур кожи Сакурады — 18 ноября 2026

В текущих локальных ресурсах клиента удалены восемь лишних `ImageTexture`:
albedo и normal кожи в четырёх подготовленных костюмах. Пиксели, формат
RGBA8, размер 2048², отсутствие mipmaps, все эффективные shader/material
параметры и геометрия сохранены точно. Исходные VRM/доноры/GLB не изменены.
Новый runtime-код, чтение карт или хеширование в Boot не добавлены.

## Реальный путь и изменение

`StartupCatalog.resource_paths()` перечисляет четыре доступных BOOTH roots,
а `GameLoading.resources` удерживает их до и после меню. `VrmParts.outfit_mesh`
загружает тот же путь через `WardrobeCatalog`. `VrmParts.material_for` сначала
читает `variant_materials`; при отсутствии override получает материал исходной
VRM по `part_source` и `surface_materials`. Этот fallback уже существовал.

Генератор `tools/avatars/build_booth_vrm.gd:260` помещал неизменённый source
skin material Сакурады в override. `ResourceSaver` повторно встраивал его
текстуры в каждый `.res`, несмотря на исходный путь вида `vrm::ImageTexture_*`.
Новый код после добавления Sakurada skin surface удаляет этот избыточный
override. Вита получает изменённый `vita_skin`, поэтому сохраняет override.
Основание sharing — прямой источник материала в коде генератора, а не
совпадение имени, размера карты или доверие к неизвестной будущей одежде.

Для нынешних четырёх derived `.res` выполнена та же структурная правка после
офлайн сравнения всего материала, shader, next_pass и Image payload. Во всех
остальных случаях сохраняется прежний путь. Материалы локализуются в
`VrmAvatar._copy_material` через `duplicate(false)` до индивидуальной палитры;
копии skin/Outline разделяют source textures. Новые внешние backing maps
не создаются, базовый материал остаётся единственным владельцем общих карт.

Обновлены только `deer_haori_0.res`, `fantasy_robe_0.res`, `orchid_armor_0.res`,
`orchid_uniform_0.res`. Совокупный размер файлов **58 996 203 → 27 195 796 B**,
−31 800 407 B. Точные старые/новые SHA и размер —
[текущий manifest](../../../assets/avatars/booth/prepared_skin_manifest.json)
и [installation.json](installation.json). Legacy backup находится вне проекта:
`/tmp/orbstrike-sakurada-skin-legacy-20261118/`; его файлы сверены со старыми SHA.
Большие экспериментальные копии из `build/` удалены после установки.

## Свежие проверки

- Headless подготовка: **100/0, exit 0**, [код](prepare-executed.gd),
  [лог](prepare.log), [отчёт](prepare.json). Сравнены effective materials,
  shader/next_pass, Texture2D Image bytes/размер/формат/mips, массивы всех
  поверхностей и metadata. Это подготовка проверенных производных ресурсов,
  не полная повторная конвертация доноров VRoid.
- Проверка уже установленного штатного пути: **161/0, exit 0**,
  [код](verify-installed.gd), [лог](installed.log), [отчёт](installed.json).
  Дополнительно точно сравнены все `ArrayMesh` STORAGE свойства, включая
  `_surfaces` с LOD/blendshape/state, кроме намеренно изменённого override map.
  JSON содержит old/new full-mesh signatures и per-slot arrays/material SHA.
  Для всех четырёх проверены включение в StartupCatalog, реальный outfit path,
  `VrmAvatar.apply_profile`, локальные skin materials и общие texture refs
  в основном/Outline проходах.
- Узкий Vulkan Forward+ / RTX 4070 Laptop probe: **11/0, exit 0, 5.83 с**,
  [лог](gpu.log), [raw](gpu.json), [runner summary](gpu-runner-summary.json).
  Изолированные четыре roots, общие source resources. Штатный
  `tools/check.py` runner с заменой только ROOT/BASE_OUT/script, общий
  `test_window.gd`: minimized, unfocusable, offscreen, 60 FPS.
- Новая версия генератора отдельно прошла `--headless --check-only`:
  [лог](generator-parse.log). Полный donor build не запускался.

| RenderingServer counter | Четыре прежних roots | Четыре новых roots | Разность |
|---|---:|---:|---:|
| Texture bytes | 1 023 419 904 | 889 202 176 | **−134 217 728 = −128 MiB** |
| Buffer bytes | 42 325 838 | 42 325 838 | 0 |
| Video bytes | 1 100 378 544 | 966 160 816 | −134 217 728 |

Между фазами прежние roots освобождены: все восемь старых Texture2D weakrefs
стали null, `ResourceLoader.has_cached` вернул false; texture/buffer/video
счётчики вернулись ровно к source-only значениям. Это подтверждает освобождение
зарегистрированных ресурсов, а не только замену активного material slot.
Исходный headless [probe](legacy-replacement-probe.json) также подтвердил,
что замена всех refs освобождает восемь старых объектов, а простой повторный
ResourceSaver.save без структурного fallback снова встраивает карты.

Первая GPU попытка не получила дисплей; её
[отдельный лог](gpu-display-unavailable.log) сохранён как ошибка окружения.
Успешный прогон получил доступ к сеансу через тот же штатный wrapper.
Первый standalone headless probe имел исправленные ошибки вывода типа;
[неуспешный parser log](initial-parser-failure.log) не считается PASS.

## Воспроизведение и пределы

[gpu-executed.gd](gpu-executed.gd) — точный исполненный вариант до установки:
тогда `assets/` содержал legacy, а `build/` — candidate copies. После установки
его старые пути не соответствуют прежним входам. Для текущего состояния
подготовлены [gpu-reproduce.gd](gpu-reproduce.gd) и
[runner](check_gpu_reproduce.py): legacy читается из проверенного `/tmp` backup,
candidate — из текущего `assets/`. Эти два файла не запускались повторно:
менялись только пути, успешный GPU результат не повторялся ради путей.

```sh
python docs/audits/2026-11-18-texture-sharing/check_gpu_reproduce.py --profile models --checks memory-catalog --list
python docs/audits/2026-11-18-texture-sharing/check_gpu_reproduce.py --profile models --checks memory-catalog
godot --headless --max-fps 60 --path . -s res://docs/audits/2026-11-18-texture-sharing/verify-installed.gd
```

Backup нужен для этих сравнений. До повторения сверить его SHA с manifest;
при переносе проекта восстановить legacy входы соответствующих SHA отдельно.
Не запускать графическую проверку одновременно с другими GPU стендами.
`verify-installed.gd` пишет отчёт в прежний build output; сохранённый здесь JSON
служит неизменяемым свидетельством исполненного прогона.

Подтверждено уменьшение counters зарегистрированных RenderingServer ресурсов
в описанном probe. Driver residency, peak memory, скорость Boot/FPS, новый
полный Boot/матч, картинка в PNG, Windows и прослушивание не измерялись.
Обычная загрузка текущих исходников достигает установленных roots; отдельный
послеустановочный полный Boot не запускался. EXE/PCK и опубликованный клиент
0.4.5 этим не обновлены. Сервер, cloth, `.codex/` и релиз не затронуты.

Исторический `tools/checkpoints/release045-inputs.json` сохранён побайтно:
он фиксирует старый SHA `fantasy_robe_0.res` для воспроизведения опубликованного
пакета и **не подходит для проверки нового локального подготовленного файла**.
Следующий отдельно порученный экспорт должен использовать текущий manifest
и новый release checkpoint; старый пакет по-прежнему проверяется историческим.

Независимый Sol high просмотрел incremental generator diff, полный install
probe, current/backup SHA и GPU raw/summary; существенных замечаний нет.
Техническое точное равенство входов рендера не выдаётся за новый визуальный матч.
