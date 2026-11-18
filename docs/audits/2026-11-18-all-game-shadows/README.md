# Тени всего клиента: общая геометрия и меню — 18 ноября 2026

Продолжение [оптимизации деревьев Каменной бухты](../2026-11-18-shadow-casters/README.md).
Обследован клиентский путь от Boot и меню до четырёх арен, предпросмотров и
комнаты анимаций. Качество теней, их силуэты и независимые настройки сохранены:
атлас, фильтр, каскады, дальность, PCSS и bias не понижались. Это локальные
исходники, прежний EXE/PCK не обновлён. Работу и независимую сверку выполнили
Sol high; сервер не запускался, не проверялся и не менялся.

## Что изменено

- Общая `BallShell`: закрытая оболочка и 11 частей раскрытия используют
  индексы вместо повторяющихся полных вершин. Это действует на сферы в любой
  арене и в комнате анимаций. Части становятся видимы во время раскрытия и
  сворачивания; после раскрытия видимая фигура существа остаётся прежней.
  Положение, нормали, UV/UV2 каждой вершины каждого треугольника и шарниры
  сохранены точно. Нет замены оболочки грубой сферой или упрощения щелей.
- В Святилище так же индексированы свод, розетка, арки и стены окон.
  Витражные SpotLight-проекторы и лунный источник сохранены. `shadow_mesh`
  не прикреплялся: точный Forward+ gate требует backface culling, а оболочка
  использует `cull_disabled`.
- В активной панораме `MenuCity` только две тяжёлые группы деревьев получили
  десять пространственных `SHADOWS_ONLY` групп по 512 единиц. Все 4119
  transforms/custom colors точны; видимые MultiMesh, материалы и ветер общие.
  Границы групп учитывают максимальное отклонение веток. Копии отключены для
  GI и скрываются при выключении теней или LOW-детализации деревьев.
  Здания, крыши, башни и другие цветовые проходы не делились.

## Охват путей

| Путь клиента | Тени и применение |
|---|---|
| Дуэль, карьера, кампания, турнир; выбор арены | Общий `Main` / `Arena`, четыре арены. `BallShell` общая; архитектура изменена только в ID 0. |
| Online client | Наследует `Main`, использует ID 0. Это статическая проверка renderer reuse, без сети или серверных тестов. |
| Комната анимаций | Собственный SubViewport и directional light через `GraphicsSettings.apply_world`; арендует те же Arena/CreatureBall из каталога. Общая оболочка и ID 0 применяются автоматически. Сам UI комнаты новым прогоном не проверялся. |
| Активное главное меню | `MenuCity`, directional light, две группы деревьев. Остальные деревья/здания/traffic/orbs сохраняют прежнюю политику теней. |
| `MenuOverlook` | Существующий файл террасы не инстанцируется текущими MainMenu/MenuCity или активной сценой. Не менялся; ускорение этой неактивной поверхности не заявляется. |
| CreaturePreview, VrmPreview/CharacterEditor, FighterPortrait | Создаваемые источники сохраняют Godot default `shadow_enabled=false`; отдельного shadow raster здесь уже нет. |
| CreaturePortrait | Отдельный portrait world/layer, positional atlas 0; shadow light не включён. |
| Boot warm catalog | Неотбрасывающий тени warm light. После подготовки viewport выключен, актёры скрыты. Индексация общих ресурсов не возвращает подготовку после меню. Новый Boot не запускался. |

В ID 1/2 неподвижный декор уже имел `CAST_OFF`; актёры продолжают отбрасывать
тени. В ID 0/3 декор и актёры имеют прежние флаги. Проекторы окон ID 0 держат
shadow maps даже на LOW с `caster_mask=0` для матрицы проекции; это сохранено.
Невидимый cloth proxy, VFX, следы, кольца, menu traffic и сферы меню уже
исключены из отбрасывания теней. MToon outline/alpha-cutout не удалялись:
они входят в силуэт. [Статическая карта путей](independent/coverage-map.json).

## Независимая проверка геометрии и кадров

Новый независимый headless-контракт через изолированные `check.py` и wrapper:
**630/0, exit 0, 1.23 с**. Проверены все ordered complete-attribute streams
закрытой оболочки, 11 частей и пяти вариантов архитектуры, primitive/material,
AABB и metadata шарниров. [Raw контракт](independent/report.json),
[runner summary](independent/contract-summary.json),
[исходники и diff](independent/source-review.json).

Core GPU probe: настоящий Stage ID 0–3, шесть CreatureBall в закрытой,
раскрывающейся и раскрытой формах, два VRM-бойца; 12 пар камер. Raw runner
содержит **123 успешных проверки и 8 FAIL строгого равенства image hash**.
Ошибки скриптов/движка не обнаружены. Эти FAIL сохранены и не выдаются за PASS.
Четыре обзора пиксельно точны; восемь ближних пар отличаются максимум на
**1/255** в канале. Независимый Sol пересчитал все пары и лично просмотрел их:
новых квадратных или ступенчатых краёв, потерянных теней и щелей не видно.
Повтор GPU только ради строгого hash-критерия не выполнялся.
[Независимая сверка](independent/core-runtime-review.json) ·
[Все 12 пар](independent/orbstrike-global-shadow-review.png) ·
[Raw core](core/results/report.json.gz) ·
[Структурные данные](core/structural.json) ·
[SHA всех 24 PNG](core/all24-image-manifest.json) ·
[SHA закреплённых core-копий](core-evidence-manifest.json).
Полные пиксели трёх отобранных пар также закреплены в `core/`: край актёра
ID 0, обзор и раскрывающаяся оболочка ID 3. Остальные исходные PNG сохранены
в `build/all-game-shadows-20261118/forward_plus-runtime-v1/results/`;
все 12 пар представлены на независимом контактном листе.

Menu trees512: **67/0, exit 0, 22.65 с**, пять фаз суток и один близкий вид,
все шесть пар PNG пиксельно точны; камеры/свет/настройки совпали. Проверены
OFF/LOW/HIGH, HIGH-тени при LOW-декоре и повторное использование тех же групп.
Независимый Sol просмотрел все пары и аналитически проверил границы ветра:
`|sway| <= .75`, `|dx| <= .0135*y²`, `|dz| <= .0075*y²`; локальное расширение
AABB с последующим transform/union консервативно покрывает деформацию.
[Сверка меню](independent/menu-runtime-review.json) ·
[Все шесть пар](independent/orbstrike-menu-shadow-review.png).

Отдельный узкий close-tree run **69/0, exit 0, 13.32 с** проверил три состояния
ветра: ещё три пары PNG точны. Во всех семи видимых исходных MultiMesh
сохранены те же resource ID, формат, длина и данные буфера до/после; два
tree buffers имеют 41840/24064 float32, 167360/96256 B. Независимый Sol повторно
сверил decoded RGB и просмотрел три пары. Основные timings не повторялись.
[Сверка ветра/буферов](independent/menu-wind-review.json) ·
[Три пары](independent/orbstrike-menu-shadow-wind-review.png) ·
[Raw меню](menu-trees512/report.json.gz) ·
[Raw wind](menu-wind/report.json) ·
[SHA закреплённых копий](menu-evidence-manifest.json).

## Цена и границы результата

| Структурный результат | До → после |
|---|---|
| Закрытая оболочка | 4464 → 980 полных вершин; число треугольников прежнее |
| Закрытая оболочка + 11 частей, 12 общих ресурсов | Packed mesh payload 321408 → 88416 B, включая новые индексы |
| Пять вариантов архитектуры ID 0 | 12042 → 2275 вершин; payload 242040 → 70016 B |
| Дополнительные menu caster buffers | +263616 B: 4119 × (12 transform + 4 custom) × 4 B; +10 MultiMeshInstance3D узлов и 10 MultiMesh ресурсов |

Это размер packed mesh/instance payload общих ресурсов, не экономия на
каждого актёра и не измерение общей VRAM, driver residency или peak RAM.
Индексация уменьшает повторную вершинную работу, но не число треугольников.

В меню при фазе .66 primitives 1580784 → 1180032, draws 31 → 35;
в близком виде primitives → 997872, draws 31 → 31. Независимый timestamp
fold с обрезкой .1 с у краёв даёт shadow-map p50 .66 **.430 → .338 мс**,
закат **.392 → .272 мс**, близкий вид **.539 → .264 мс**. Утро хуже:
**.293 → .360 мс**, при сильной DVFS. CPU viewport p50 .66
**.3235 → .3235 мс**; утро **.3325 → .3525 мс**, близкий вид
**.382 → .349 мс**. Все значения относятся к одному Linux/Vulkan/RTX 4070
Laptop прогону; это не универсальные проценты ускорения.

Core total GPU и atlas depth меняются разнонаправленно; устойчивое ускорение
целого кадра не доказано. Named shadow timestamp охватывает depth-проход
атласа; PCSS receiver sampling остаётся в opaque. Profiler readouts имеют
задержку и повторные frame ID, не считаются уникальными кадрами. В core
profiler сохранено одно необработанное typed-array сообщение, у menu decode
errors 0; все visual records целы. Рост FPS и снижение потребления не заявляются.

Raw GPU fingerprints `pixels_sha256`/`color_buffer_sha256`/`source_buffers.sha256`
считаются от UTF-8 hex-текста payload; это точные fingerprints сравнения, а
не SHA бинарного payload. Независимые PNG-сравнения выполнены по decoded RGB.
Исходный timing script закреплён отдельно от дополненного close-tree script;
оба запуска повторимы без подмены старого SHA текущим файлом. В core manifest
изменился только runner `tools/check.py` при регистрации menu check; frozen
effective runner и все production-входы соответствуют своему прогону.

Все графические запуски выполнены штатной minimized/unfocusable/offscreen
обёрткой с cap 60; GPU прогоны последовательны. Не запускались полный профиль,
новый Boot/физический матч, Windows или слабая GPU. Сборки/публикации нет;
EXE/PCK, сервер, исходные GLB/риги и прежний dirty сохранены. Ранний вариант
пяти menu caster sets отвергнут из-за лишних draws/CPU, хотя его PNG совпали.

## Воспроизведение

Узкие проверки работают с Godot 4.7.2/ed1daf0bf. Сначала достаточно
прочитать закреплённые raw/summary и SHA; успешные проверки не требуется
повторять без затрагивающей их правки. Для нового адресного запуска:

```sh
python build/all-game-shadows-20261118/independent-contract/run.py
python build/all-game-shadows-20261118/run.py forward_plus --tag=new-unique-tag
python tools/check.py --profile presentation --checks menu-shadows
ORBSTRIKE_MENU_SHADOWS_TREE_CLOSE_ONLY=1 python tools/check.py --profile presentation --checks menu-shadows
```

GPU-команды выполняются последовательно, через сохранённые штатные wrapper
и FPS cap. Core probe сохраняет строгие image-hash assertions и может снова
завершиться raw FAIL при разнице 1/255; принятие таких кадров требует
независимой проверки, а не удаления неудачного результата.

В `core/` закреплены [probe](core/probe.gd.txt),
[runner](core/run.py.txt), [effective check](core/effective-check.py.txt),
исходные и нормализованные baseline-файлы в `core/source/`, engine source
gate, raw profiler report/packets и telemetry. Точные source snapshots
меню лежат в `menu-trees512/` и `menu-wind/`; для повторения первоначального
67/0 нужен его сохранённый timing script, текущий script дополнен wind mode.
При восстановлении после удаления `build/` `.txt`-копии кладутся обратно
по исходным путям из manifest; `*.gd.source.txt` — нормализованный GDScript,
`*.gd.txt` baseline — первоначальный текст до удаления `class_name`.
Независимый [headless probe](independent/probe.gd.txt) и
[его runner](independent/run.py.txt) также закреплены. Все эти файлы служат
воспроизведению и не входят в runtime каталога клиента.
