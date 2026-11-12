# Клиентские оптимизации без Tracy — 8 ноября 2026

Разрешённый автором адресный этап после интернет-сопоставления. Изменены только
клиентские исходники и необходимые стенды. Версия0.4.2.6/опубликованный пакет прежние;
сборки, публикации, сервер,49GLB и .codex не затрагивались. Предыдущие Delta/intro и
переработка карьеры сохранены в рабочем дереве.

## Реализация

- FighterPortrait больше не ищет Head/не переставляет неизменную камеру каждый кадр.
  Статичная standby-копия рисуется UPDATE_ONCE при bind/resume. Движущиеся UV
  принятого MToon остаются UPDATE_ALWAYS; неизвестные TIME/include-шейдеры и
  анимированный next_pass также сохраняют постоянную отрисовку. Исключение для
  нулевых UV-speed проверяет точную идентичность ресурсов VrmPaletteShaders.SHADERS,
  а не только имена uniforms. Материалы/mesh/skin и поза не переписываются.
- PreviewActivity получил необязательную render policy. Прежний UPDATE_ALWAYS
  по умолчанию сохранён для живого редактора/preview; hidden/covered всегда выключены.
- Подсказки поля кэшируют скрытый MatchState/текст по controller/event/action revision
  и теме. Геометрия отдельно инвалидируется по позиции мыши, эффективному camera
  transform (включая h/v shake), projection/FOV, viewport и фактической позиции/
  видимости/высоте каждого шара. Дрейф камеры не порождает новые копии MatchState.
- CreaturePreview.show_card больше не собирает малую карточку и Labels, которые
  раньше тут же прятались. Настоящая крупная карта/scroll/hover сохранены.
- Из нормального StartupCatalog исключены старый fighter_mpfb.glb и сборка
  FighterAvatar. LegacyCharacterEditor доступен отдельным тестам; источники VRM
  HairSample/Vivi, материалы текущего гардероба и подготовка49×2/3арен сохранены.
- Добавлены8 встроенных Performance custom monitors orbstrike/* для query/cache/
  snapshot/rebuild CPU/portrait refresh/card builds. Нет внешнего addon, overlay
  или нового покадрового опроса. snapshot() читает доступные pipeline/object/render
  counters; CPU/GPU viewport timing включается явно через measure_render_time().
  Object/resource gauges не названы счётчиком всех аллокаций или выделенных байтов.
- Старые tools/perf.gd и loading_fps_benchmark.gd больше не снимают60FPS;
  perf.gd защищает самостоятельный запуск тем же test_window helper. Исправлен
  двойной перевод microseconds→milliseconds в печати GPU timestamps. Это parse-
  проверка инструмента, не новый замер его полного режима/матчей.

## Новые проверки

Все GPU-пуски через tools/check.py → test_window.gd: minimized/unfocusable,
offscreen force_draw(false),60FPS,RTX4070 Laptop/Vulkan1.4/Forward+.

| Адресный сценарий | Фактический итог | Область |
|---|---|---|
| optimization |167/0,exit0,ERROR0,7.65s|Реальные tooltip projection/cache invalidation, видимая крупная карта, custom monitors и ненулевой GPU timing|
| portrait-standby |286/0,exit0,ERROR0,16.71s|Обе standby-реплики, cached pixels, zero per-frame camera work, animatedUV→hide→resume→static, unknown TIME/next_pass|
| portrait-visibility |77/0,exit0,ERROR0,19.66s|HUD/canvas/consumer/rebind плюс сохранённая живая обработка editor/legacy/VRM previews|
| startup-loading |183/0,exit0,ERROR0,46.78s|Настоящий Boot→menu→team→два старта/«Ещё раз», каталог/UID/ареновые preview|

Финальные логи/JSON:

- [optimization](../../../build/checks/presentation/selected-optimization/summary.json),
  [адресные метрики](../../../build/checks/presentation/selected-optimization/optimization/metrics.json).
- [standby](../../../build/checks/presentation/selected-portrait-standby/summary.json),
  [visibility](../../../build/checks/presentation/selected-portrait-visibility/summary.json).
- [startup](../../../build/checks/gameplay/selected-startup-loading/summary.json),
  [Boot/checkout/restart/memory](../../../build/checks/gameplay/selected-startup-loading/startup-loading/result.json).

500 последовательных запросов одного tooltip в одном GPU fixture: **34.447ms
uncached →1.927ms cached**.120 неизменных запросов создают1 snapshot;20 сдвигов
камеры не создают новых snapshots. Это стоимость синхронного batch в узком стенде,
не увеличение общего FPS. Динамическая камера продолжает обновлять hit geometry.
В видимом card fixture измерены root render CPU0.134ms/GPU0.063ms; эти маленькие
значения подтверждают работу timing API, не представляют тяжёлый игровой кадр.

Boot текущего запуска22.639s, шесть актёров готовы за315.668/618.753ms; два старта
7.477/7.435s включают намеренное7.2s intro. Каталог до/после **1/98/3/158**
(preparation/actors/arenas/audio paths), без повторного GLB/setup. Restart342.165ms.
Это одиночный текущий замер; сопоставимого старого Boot/RSS baseline не делали,
поэтому экономия RAM/времени Boot в процентах не заявляется.

Sol лично просмотрел2 новых144px portrait PNG и исправленный видимый full-card
PNG.286/0 также повторно проверяет прежние49 panel silhouettes, но их художественная
переоценка/полный визуальный аудит моделей в этот этап не заявляются.

## Ошибки промежуточных вариантов и независимый review

Независимый Sol high выявил пропущенные camera h/v offsets и слишком широкое
распознавание MToon по uniforms. Оба замечания исправлены; добавлены regression
cases. Synthetic material test дополнительно обнаружил null default UV uniforms,
который теперь трактуется как known-zero только у принятых shader resources.
Консервативный неполный список6shaderfiles сначала сохранял transparent MToon
живым; окончательно используется точная карта всех12 принятых ресурсов.

Первый startup183/2 выявил прежний timeout120frames, несовместимый с уже принятым
7.2s intro. Стенд теперь отдельно измеряет checkout и ждёт настоящий ctrl.start
до15s real time. Игровое intro не сокращено/не выключено ради проверки.
Промежуточные FAIL/parse logs сохранены в initial-failures,
synthetic-null-failure,conservative-whitelist-failure и obsolete-intro-wait-failure
под соответствующими build/checks каталогами. Финальные PASS их не отменяют.

## Что обоснованно не внедрено

Tracy исключён автором. RenderDoc не установлен; обычный capture hotkey требует
Present, тогда как тесты рисуют без Present. Устанавливать его/менять защиту окна
ради отметки не стали: встроенные GPU timings доступны и проверены.

FX pool,HLOD/impostors и spatial chunks остаются кандидатами после адресного
профилирования: подтверждённого bottleneck/измеренного выигрыша здесь нет. Они
добавляют память/сложность reset или риск качества/culling. Копировать framework,
менять49GLB или снижать качество без оснований не стали. NativeWindows, пакет,
субъективное аудио и новый полный физический матч этим этапом не проверены.
