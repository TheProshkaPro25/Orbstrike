# RAM/GPU — четыре оптимизации, 4 ноября 2026

Поручение автора: выполнить пункты 1–4, сохранить быстрый старт матчей.
Реализация, измерения, визуальная оценка и перекрёстный независимый review — Sol high.
Публичный выпуск остаётся **0.3.2**; сборка, экспорт, push/tag/release не выполнялись.
Предшествующие незакоммиченные UI/арт/семь карт/online-rules-4 сохранены.

## Что изменено

1. **Анимации.** Одна подготовленная библиотека на исходную библиотеку/модель/вид;
   независимые AnimationPlayer, часы, blend/seek/действия. Ключ удерживает source и
   original Resource и учитывает полные rest-преобразования tail2/3/4 Грифона.
   Старые исправления и плотность idle 120 ключей/с сохранены. Кривые готовятся
   до публикации в кэше; runtime их не меняет. Кэш ограничен прежним лимитом
   64/6 и очищается вместе с нерезидентными ресурсами; Node в нём нет.
2. **Подтверждённо лишние PBR-карты.** Только HD-путь CreatureModels до замены
   BaseMaterial3D на ANIME_SHADER очищает normal/roughness/metallic/AO. Их не читает
   ни основной шейдер, ни cape-вариант CreatureCloth, добавляющий vertex/flash.
   PackedScene, GameLoading.resources и preparation_source держат тот же материал,
   поэтому очистка снимает ссылки исходного импортированного ресурса, а не только
   невидимого override. GLB/импортные файлы не переписываются. Сохранены albedo
   целиком с alpha, emission и любые неизвестные слоты. Native material_override,
   overlay, непереводимые custom-материалы, цепочки next_pass и все анимационные
   назначения Material/Mesh (включая METHOD args) защищаются рекурсивно. Старый
   _recolor/fallback-архетип не очищается. Полные 49 исходных сцен после прогрева:
   62 материала, 55 albedo-слотов, 49 уникальных текстур; четыре лишних слота пусты.
3. **Портреты.** PreviewActivity ориентируется на настоящий TextureRect/consumer,
   родителей/CanvasLayer и боевое перекрытие HUD (alpha=0). Отключаются update
   viewport и его обработка; портрет не приостанавливает общего бойца на арене.
   Редакторы сохраняют ручное sampling/паузу/время. Восстановление обновляет камеру
   до первого draw; смена скрытого бойца и скрытие старого редактора проверены.
4. **GPU cloth.** На render thread разделяются только readonly storage buffers:
   constraints, rest, bone indices/weights, cloth weights, indices/peer indices,
   adjacency, bindings при их наличии. Ключ — kind + allocation size + SHA256
   реальных packed bytes. Positions/predicted/velocities/lambda/bone transforms/
   skin targets/colliders/normals/output textures/pin overrides остаются отдельны.
   Refcount не меняется при reparent; последний владелец освобождает RID после
   descriptor sets. Точный SHA allocator-only vendor-правки признан CPU-совместимым
   с прежним SHA, поскольку canonical/GPU bytes совпали; любой другой SHA снова
   инвалидирует pdat. Шесть disk-cache hits узкого стенда, промахов нет.

## Методика и измерения

Godot 4.7.2, Linux/Vulkan Forward+, RTX 4070 Laptop. Одинаковый каталог 49×2,
3 арены, исходные настройки качества. tools/check.py → tools/test_window.gd:
60 FPS, свёрнутое нефокусируемое окно, offscreen rendering. Не менялись resolution,
MSAA, тени, SSAO/SSIL/SSR, модели, skeleton/rest/bind/UV и пользовательские FPS.

Первый baseline снят до production-правок (149/0). Исправленный baseline schema2
выполнен на изолированной компактной копии прежних исходников HEAD + сохранённый
preexisting.diff; assets/imports использовались без изменения. Причина повтора:
первое сравнение поз оставляло 0.2s blend от случайной Boot-фазы. Принятый стенд
сбрасывает кости/stop/play(blend=0)/advance(0)/seek и даёт точные одинаковые позы.
Первый диагностический FAIL и исходные результаты сохранены отдельно в build/checks/
memory-optimization-20261104/, а не названы приёмкой. В /tmp остаётся только малая
исходная копия; ошибочно захваченные временные инструменты удалены без изменения проекта.

Память берётся сразу после готовности каталога и возврата preview, до дорогого
хеширования ключей. Время кадра — последние 90 из 180 установившихся кадров
скрытого каталога. GPU frame counters включены явно. Это один контрольный
before/after, не статистическое доказательство ускорения FPS/боя.

| Показатель | До | После | Разница |
|---|---:|---:|---:|
| Подготовленные библиотеки | 98 | 49 | −49 |
| Анимации / уникальные ключи | 490 / 536500 | 245 / 268250 | ровно половина |
| Уникальные исходные HD-текстуры | 145 | 49 | −96 |
| RSS процесса, KiB | 2132176 | 2028444 | −103732 KiB ≈ 101.3 MiB |
| Выделения движка, bytes | 373487017 | 357096530 | −16390487 ≈ 15.6 MiB |
| Renderer texture resources, bytes | 2304038400 | 1901426176 | −402612224 ≈ 384.0 MiB |
| Renderer buffer resources, bytes | 822460468 | 801870916 | −20589552 ≈ 19.6 MiB |
| Process time, ms | 1.107 | 1.119 | практически одинаково |
| Root render CPU / GPU, ms | 0.212 / 2.018 | 0.206 / 1.527 | короткая выборка, без вывода о speedup |
| Подготовка Boot, s | 14.726 | 13.105 | единичные замеры, не гарантия |

RSS — точечное значение `/proc/<pid>/status`, не пик. Выделения движка и renderer
счётчики учитывают разные/пересекающиеся области; **их нельзя складывать в общий
выигрыш RAM**. Renderer resources не равны фактически занятой VRAM драйвера.
Число FPS ограничено 60, ускорение FPS не заявляется. Новые результаты заменяют
только этот замер; старый исторический 34.7→13.3s из README остаётся историей.

У всех 12 реальных cloth-акторов каталога: 120 logical immutable allocations
**41179104 B → 60 общих allocations, 20589552 B**. Это соответствует разнице
renderer buffers. У контрольной пары Ratnik Tide: **5555128 → 2777564 B**
immutable, mutable storage **1635460 B на актёра** без изменений. Размеры
cloth не относятся ко всем 98 существам; cloth есть только у Ratnik.

## Что проверено

- memory-catalog **155/0**: все 49 SHA полного содержимого анимационных кривых
  (время/значение/transition/interpolation/loop/path) и канонические позы совпали;
  у двух одинаковых существ независимы player и seek; каталог 98/3 не достраивается.
- animation **435/0**, idle **374/0**, preparation-cache **497/0**:
  контакты/прерывания/непрерывная фаза/idle-шов и канонические samples/опора.
- hd-material-retention **99/0**: четыре разрешённых слота удаляются; alpha/emission/
  неизвестные карты/override/overlay/native+custom next_pass/анимационные Material,
  Mesh и METHOD назначения сохраняются. Два замечания review закрыты этими fixtures.
- cloth-sharing **68/0**: все 21 GPU-buffer SHA двух фиксированных актёров и после
  движения совпали прежнему коду; rest/moved PNG pixel-exact и просмотрены Sol.
  Другой actor не двигается, все mutable RID/output textures различны; reparent/reset,
  free первого, жизнь второго и lastfree 0 buffers/0 bytes подтверждены.
- portrait-visibility **77/0**: hidden/covered/rebind/editor/CanvasLayer дают
  **0 ticks** вместо **24 на 12 samples**, UPDATE_DISABLED и frozen pixels.
  Visible/resume: 24 ticks, изображение живое. Первый кадр/новый боец/paused manual
  sampling сохранены; PNG реально просмотрены. Cached draw calls не выданы за render.
- startup-loading **183/0**: настоящий Boot→меню→команда→два старта→«Ещё раз»;
  counts **[1,98,3,151] → [1,98,3,151]**, UI/звук/арены готовы до меню.
  Team→match **422/375 ms**, возврат к команде **138 ms**. Новые match-ready PNG
  просмотрены: портреты видны после повтора; первый menu PNG захватил fade-in.
- turn-pool **0 failures**: 6 uid × 2 активации, те же актёры/animator, исправные
  collider/slot/closed pose, резерв скрыт/disabled. Активация max **0.311 ms**,
  mean **0.223 ms**, без setup/GLB/cloth после меню.

Независимые Sol cross-review проверили ключи/immutable publication, material
fallback, portrait visibility/manual process и readonly GPU/refcount/lifetime.
После закрытия material overlay/next_pass/METHOD замечаний блокеров нет.
Полные физические матчи/онлайн, все 49 моделей художественно, Windows,
прослушивание, экспорт и публикация этой задачей не проверялись.

Машинная сводка и provenance: `memory-gpu-2026-11-04.json` рядом.
Raw JSON/logs: build/checks/memory-optimization-20261104/{baseline-v2,after-v2}.*.
Кадры/логи: build/checks/models/selected-cloth-sharing/;
build/checks/presentation/selected-portrait-visibility/portrait-visibility/;
build/checks/gameplay/selected-startup-loading-turn-pool/;
build/checks/models/selected-animation-idle-preparation-cache-hd-material-retention/.

Для повторной текущей проверки: `python tools/check.py --profile models --checks
memory-catalog` (режим current, не перезаписывает baseline); адресные проверки
выбирать по именам выше. Для настоящего before/after нужен source snapshot до
оптимизации и одинаковый `tests/memory_catalog_tests.gd`: baseline сохраняется с
SFERY_MEMORY_PHASE=baseline, после — SFERY_MEMORY_PHASE=after в том же output.
Не повторять успешные прогоны без новых изменений/конкретной причины.
