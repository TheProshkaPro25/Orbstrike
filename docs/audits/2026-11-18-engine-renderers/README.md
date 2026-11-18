# Внутренние пути Godot — 18 ноября 2026

На Godot 4.7.2 проверены два адресных пути: **Mobile/Vulkan** и отключение
**depth prepass Forward+**. Готовой оптимизации без изменения результата
пока нет: Mobile меняет изображение, а переключение prepass в уже созданной
сцене теряет непрозрачную геометрию. Выключение до создания сцены её сохраняет,
но его скорость не измерялась. Production, движок, модели и пакеты не менялись.

## Одна сцена и одинаковые входы

Linux, RTX 4070 Laptop, Vulkan 1.4.357, Godot **4.7.2 ed1daf0bf**;
SHA-256 бинарника `c1a553261b7921e64907e97ba001e7c1fd53a0ffca4c46f68de58161a06c5b1d`.
Настоящий `Stage._build_world` Каменной бухты ID 3, без Boot/актёров/матча.
LOW, **1280×720, scale 1.0**, одинаковые bilinear scaling/filter/LOD,
MSAA/FXAA/TAA и SSAO/SSIL/SSR/glow/солнечные тени выключены. Это общий
набор возможностей; он не доказывает перенос HIGH на Mobile без потерь.
Seed 18112026, processing сцены выключен, shader TIME заменён на 10.0.
Обе камеры, projection, effective environment/lights/options и geometry
совпали точно между backend. Geometry JSON SHA `340df20e4501f713689c8fd4f6abb4eb71da01c71f4e42cf1caf8f2ff4a9045a`.

Два последовательных финальных процесса через штатный `check.py`/
`test_window.gd`, minimized/unfocusable/offscreen, cap **60 FPS**.
Forward+ **6/0, exit 0, 56.82 с**; Mobile **6/0, exit 0, 38.16 с**,
ERROR/утечек нет. У Mobile есть один ожидаемый warning SSAO при исходном
построении Environment; во всех измеренных effective snapshots SSAO=false.
В каждом окне 120 process кадров прогрева и 300 выборок (~5 с), post_draw=301.
`Engine.get_frames_drawn()` здесь неизменен из-за `force_draw(false)`;
его нельзя выдавать за один фактически отрисованный кадр.

## Mobile: меньше registered memory, другой пол и освещение

Ниже root viewport GPU p50 и mean CPU render time; это не FPS, не полная цена
всей GPU и не hardware utilization. Частоты/мощность — device-wide CSV,
20 отсчётов на окно, с другими приложениями в фоне.

| Ракурс | GPU p50 F+ / Mobile, мс | CPU render mean F+ / Mobile, мс | GPU clock mean F+ / Mobile, MHz | Вся GPU F+ / Mobile, W |
|---|---:|---:|---:|---:|
| Широкий | 2.5535 / 2.4750 | 0.328 / 0.285 | 1217 / 902 | 14.21 / 11.03 |
| Отмель | 2.7385 / 1.7875 | 0.288 / 0.254 | 876 / 1087 | 10.25 / 11.14 |

GPU mean: широкий 2.751/2.447 мс, отмель 2.858/2.278 мс.
GPU p95: широкий **4.053 / 4.019 мс**, отмель **4.202 / 5.814 мс**
(нижний эмпирический quantile reviewer). При возврате Forward+ в тот же
широкий ракурс mean уже **3.479 мс**, clock 1033 MHz. DVFS и фон заметны;
единственная последовательная пара не устанавливает устойчивый процент
ускорения/эффективность. Меньшие watts не означают тот же визуальный результат.

Во всех windows каждого backend registered video counter стабилен:
**1 154 288 960 → 1 113 647 968 B** (1100.82→1062.06 MiB),
разница **38.758 MiB**;
texture counter −30 349 312 B, buffer counter −10 696 032 B.
Это counters данной изолированной сцены, не вся residency драйвера и не
разница полного резидентного каталога. Категории не складываются.

Лично просмотрены все семь финальных PNG: Mobile сохраняет острова/воду,
но на широком ракурсе вместо читаемых плиток поля появляется выраженный
полосатый муар, земля темнее. RGB MAE 5.755/4.032 на шкале 0–255 в двух
ракурсах подтверждает различие, а не художественную приёмку.
[Forward+ и Mobile рядом, исходные пиксели без ресайза](mobile-wide-comparison.png).
Универсальная замена renderer пока не принимается.

## Prepass: runtime-пара не является измерением корректной оптимизации

В Forward+ проход действительно исчезает при OFF и возвращается при ON.
Однако в обоих OFF PNG исчезают острова и поле — остаются небо и вода.
Возврат ON восстанавливает сцену (469 слегка отличающихся пикселей из
921600, RGB MAE 0.000278). Поэтому времена OFF **исключены из оценки
ускорения**. [ON → runtime OFF → ON рядом](prepass-wide-comparison.png).

Отдельная узкая диагностика **3/0, exit 0, 30.05 с** задала OFF до
создания Stage, затем скрыла воду и вернула ON. Все четыре PNG независимо
просмотрены: геометрия видима с водой и без неё; внутри каждой пары
OFF-first/ON PNG и decoded RGB bytes совпадают точно; cold OFF также побайтно совпал с
широким PNG отдельного финального Forward+ ON. Это опровергает общий вывод
«prepass=false всегда ломает сцену». Цена корректного OFF-first здесь не
измерялась; новых timing-прогонов ради процента не делали.
[Диагностика, SHA и независимый осмотр](depth-independent-review.json).
Поле fixture `image_rgba_sha256` названо неточно: Image/PNG здесь RGB8;
metadata совпадает с decoded RGB, добавление alpha меняет hash. Паритет
самих PNG от этого не зависит.

В точном C++ `ed1daf0bf` render loop читает обновляемую настройку, но
**создание opaque pipeline при ON выбирает EQUAL и выключает запись depth**.
Reuse такого pipeline после runtime OFF согласуется с потерей opaque:
это объяснение по коду/контролю порядка создания, не захват GPU pipeline
state и не доказательство дефекта всех сцен/GPU.
[Render-loop gate](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L1898-L1909) ·
[Pipeline creation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp#L371-L415).
В коде официальной 4.8 beta3 `c51ff06e8` настройка уже объявлена требующей
перезапуска; beta этим не запускалась и её ускорение не заявляется.
[Регистрация настройки](https://github.com/godotengine/godot/blob/c51ff06e8/servers/rendering/rendering_server.cpp#L3388).

Контрольные counters постоянны: широкий **53 draws / 2 458 145 primitives**,
отмель **28 / 2 038 287** — F+ ON/OFF/return и Mobile. Это счётчики
подготовленных render lists с instancing, не точное число hardware-команд
во всех проходах: depth pass повторно использует уже посчитанный opaque list.
Их равенство не доказывает сохранение изображения или отсутствия лишнего
прохода. [Подсчёт draws/повторов](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L787-L800) ·
[Подсчёт primitives](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L999-L1017).

## Что относится к движку, а что к проекту

Forward+ и Mobile — разные rendering methods над RenderingDevice; в этой
паре driver остаётся Vulkan. Mobile поддерживает custom compute и запросы
screen/depth воды, но отличается эффектами/точностью/лимитами света.
Смена метода не исправляет лишний вызов cloth solver и повторные textures.
[Официальное сопоставление](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) ·
[Screen/depth copies Mobile](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L1206-L1238).

Внутренний валидатор этой версии постоянно переводит RGB8 sample textures
в RGBA8. Это объясняет одну разницу с logical Image payload прежней таблицы,
но не измеряет driver residency. Удаление safeguard в своём движке не
проверялось; GPU-компрессия, texture sharing, LOD и position-only cloth —
проектные эксперименты. Они сохраняют приоритет из
[предыдущего аудита](../2026-11-18-render-resources/README.md).
[RGB8 fallback C++](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp#L2133-L2147).

Для отдельного будущего исследования Godot 4.8 полезен mip-level texture
streaming: требует включения и импорта `Texture2D Streamed`. `.res`, runtime
ImageTexture и наш резидентный каталог автоматически не мигрируют; сохранение
деталей/задержки/память требуют своей пары. Движок здесь не обновлялся.
[Первичное описание условий](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-5/#rendering-mip-level-texture-streaming).

## Доказательства и границы

[Raw-summary автора стенда](summary.json), [независимый пересчёт](independent-review.json),
[exact-source review](source-review.json), [запуски/воспроизведение](RUNTIME.md),
[сохранённые raw/PNG/logs и SHA](evidence/manifest.json).
Reviewer отдельно пересчитал все raw viewport samples/CSV, camera/projection/
effective/geometry identity, engine/source/artifact SHA и все 11 новых PNG.
`review.py` выполняет только offline-пересчёт, Godot не открывает.

Ранние Forward+ initial/clean — **diagnostic FAIL**, несмотря exit0:
null index array и затем empty HashingContext update в instrumentation до
прогрева. Они сохранены; финальные процессы исправляют fixture, а не production.
Remote Visual Profiler в clean попытке подтвердил исчезновение prepass
(0 OFF против 271/270 ON сообщений), но не делает ту попытку clean PASS.
Один typed-array 484 пакет не разобран; все visual records разобраны.
[Отдельный независимый пересчёт той попытки](forward-review.json).

Слабое оборудование, Windows, Boot/полный каталог, полный матч, все арены,
GPU cloth lifecycle, прослушивание, сервер, EXE/PCK и публикация не проверялись.
Улучшение на GPU без RenderingDevice/Vulkan из Mobile-пары не следует.
