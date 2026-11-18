# Ресурсы и лишняя работа renderer — 18 ноября 2026

Продолжение адресной диагностики клиента 0.4.5 после
[аудита проходов GPU](../2026-11-18-render-pass/README.md).
Найдены повторные текстурные payload, крупные несжатые карты,
избыточно одинаковая плотность островов и конкретная лишняя compute-работа
grid-плащей. Приоритет по памяти — переиспользование одинаковых текстур
персонажей: только две проверенные группы содержат **128 MiB повторного
Image payload**. Это пока не измеренная экономия allocations/FPS.
Production, модели, пользовательские настройки и пакеты этим этапом не менялись.

## Память: повторные текстуры и несжатые карты

Один новый настоящий Boot → меню: Linux/X11/Vulkan Forward+, Godot 4.7.2,
RTX 4070 Laptop, HIGH, root 1280×720, штатный minimized/unfocusable/offscreen
wrapper, cap 60. Каталог штатно построен один раз: **134 actors, 4 арены,
4 бойца, 225 retained resource roots**. Требование готового каталога сохранено.

В двух menu snapshots с интервалом около секунды RenderingServer/Performance
texture counter одинаков: **2 824 876 544 B (2.631 GiB)**,
buffer 807 346 402 B, video 3 806 295 728 B. Linux RSS 2.389–2.391 GiB — отдельная
величина. Эти категории нельзя складывать или называть всей residency GPU.
Протокольный список одновременно содержит **738 textures / 2 059 295 877 B
logical Image payload** и **868 meshes / 546 582 150 B buffers**.
Два menu reply массива побайтно одинаковы; это короткая стабильная выборка,
не проверка серии матчей/утечек. 508 texture rows без path не приписаны
аватарам автоматически.

Проверен и исходный resource graph без GPU: **385 texture objects** во всех
68 доступных avatar `.res/.vrm`. Никакие размеры файлов не подменяют payload:
хешируются Image data с format/dimensions/mips. По `resource_path` с живым
обходом `GameLoading.resources` совпали 259 objects: **977.179 MiB payload**,
в том числе **246.760 MiB повторных содержимых**. Это подтверждённые сильные
resource refs для данного подмножества; точное соответствие blank debugger
rows/physical allocations протокол не предоставляет.

Две крупные группы подтверждены отдельным узким material-role обходом:

| Набор | Объекты | Повторный payload сверх одной копии |
|---|---:|---:|
| Sakurada skin color: base + deer_haori/fantasy_robe/orchid_armor/orchid_uniform | 5×16 MiB | 64 MiB |
| Skin normal в тех же пяти roots | 5×16 MiB | 64 MiB |

Внутри каждой группы Image bytes точно совпадают по SHA-256; все карты
2048² RGBA8 без mipmaps. Цвет связан с `_MainTex`/`_ShadeTexture`, normal с
`_BumpMap`; между семантическими ролями карты не смешиваются. Материалы,
их параметры/палитры и геометрия должны остаться отдельными.
Узкий следующий шаг — единый Texture2D для каждого такого набора в
подготовке/генераторе, сохраняя весь каталог и исходные модели. Фактический
выигрыш требует парного memory snapshot после реализации.

Дополнительно в текущем меню по path подтверждены крупные несжатые карты:
один исправленный атлас Рогожука Камня 4096² RGBA8 **85.333 MiB**,
Флорис 6×2048² RGB8 **96 MiB**, Армат такой же **96 MiB**,
Окто 6×1024² RGB8 **24 MiB**, 67 портретов 512² RGBA8 **89.333 MiB**.
Класс `CompressedTexture2D` сам не означает GPU-compressed Image format:
в указанных строках format RGB8/RGBA8. Адресный BPTC/BC7 эксперимент требует
проверки альфы, мелких краёв и принятой расцветки. Выгоды по формуле нельзя
выдавать за измеренную экономию или автоматически уменьшать resolution.

**Весь memory runner не является clean PASS:** exit 0, 42.92 с, runner FAIL.
Три memory replies и итоговый snapshot записаны до `DONE` (log 239);
первые teardown ошибки — log 252+. Fixture сразу вызвал quit, пропустив
установленный порядок возврата/освобождения и кадров для render-thread
cleanup. Исправлен только будущий fixture по существующему порядку;
исправление не запускалось. Это не доказательство дефекта штатного выхода
клиента. Ранние parser/API-пробы и один unsupported typed-array packet
сохранены; все memory replies полны. Повтор ради зелёного teardown не делали.

[Сохранённая подробная сводка](resources-report.md) ·
[Live counters, duplicate paths/hashes и группы](resources-summary.json) ·
[Runner status](resources-runner-summary.json) ·
[Независимый пересчёт и границы](review-resources.json).
Полные raw/команды/скрипты остаются в
[build resource audit](../../../build/audit-resource-path-20261118/README.md).
Before-capture production SHA manifest эта часть не снимала;
[проверенные after-capture SHA](resources-evidence-sha256.json) так и помечены.

## Плащ: подтверждённое лишнее вычисление

У нынешнего Trellis Ratnik отображаемый shader GridVertex и owner-rim
читают только position texture. Полные GPU normals и welded lookup
привязаны к simulation proxy, у которого layers=0 и тени выключены.
Debug читает только позиции/скорости; все шесть текущих Ratnik имеют
готовый PNG портрета и не включают общий live fallback.

На активный update одного такого плаща приходится **один лишний normal
dispatch + barrier**, 1040 face-normal invocations и 567 normal gathers
внутри всё ещё необходимого output dispatch; суммарно 3120 adjacency
contributions и **25 712 байт логических vec4-записей** нормалей.
Ненужный для текущего grid renderer перечисленный instance payload —
**34 784 байта/solver**; normal-path immutable payload — **29 496 байт на
unique content set**, разделяемый по hash, а не заново на каждого actor.
Это декларативные размеры без alignment/driver overhead и не измерение
DRAM трафика или экономии FPS.

Решётка 21×27, 567 частиц, 1040 triangles и 3120 adjacency подтверждены
текущими источниками и прежним GPU init log. Прежний лог не выдаётся за
новый прогон. [Полная цепочка consumers, строки и lifecycle](static-flow.md) ·
[SHA и точная арифметика](grid-output-accounting.json).

Узкое возможное исправление — отдельный position-only-grid output mode,
с сохранением non-grid normal pipeline и контракта shared GPU resources.
Перед внедрением нужны парные позы/силуэты, rim/flash, аренда/возврат,
reparent/warm start/refcounts и GPU timestamps вокруг custom compute.
Отключать физику только по видимости simulation proxy нельзя: он всегда
имеет layers=0, а потребителем служит другая сетка.

## Каменная бухта: геометрия важнее одного водного mesh

Отдельный новый LOW A/B в настоящем широком ракурсе ID 3:
в runtime-копии менялись только subdivisions воды 192×192 → 96×96.
Вода **74 498 → 18 818 triangles** (−74.74%), но весь кадр лишь
**2 458 145 → 2 402 465 primitives** (−2.265%), draw calls **53 → 53**.
Renderer GPU timings непоследовательны при меняющейся DVFS; ускорение
не доказано. Редкая сетка меняет пену/блики на отмели и в production
не переносилась.

Сцена имеет 30 островов, каждый создаётся одинаковой решёткой
112×256 ячеек, **57 344 triangles/остров**, независимо от размера и
дистанции (`scenes/locations/coastal_arena.gd:9–19,41–49,93–120`).
Даже остров с радиусами 31×21 имеет эту плотность. Суммарно это
**1 720 320 triangles до frustum culling**; distance LOD в данном
конструкторе не задаётся. Это более содержательный следующий кандидат,
чем автоматически объявлять воду основным geometry bottleneck.
Измеренного выигрыша от LOD пока нет.

Один успешный scenic run: **3/0, exit 0, 53.79 с**, Godot 4.7.2/Vulkan/
RTX 4070 Laptop, root 1280×720, scale 0.75, штатный minimized/unfocusable/
offscreen wrapper, cap 60. Без Boot, матча и актёров; shader TIME заморожен
одинаково в паре. Сохранена ранняя неудачная parser-попытка fixture.
Независимо проверены counters, одинаковая wide camera, SHA и пять PNG.
[Полный A/B, данные, кадры и повторение](../2026-11-18-coastal-water-ab/README.md) ·
[Независимый пересчёт](review-water.json).

## Как читать сведения о памяти

Размер PNG/CTEX на диске, распакованный Image payload, process RSS,
registered renderer bytes и физическая residency драйвера отвечают на
разные вопросы. Нельзя складывать все импортированные sidecar-ресурсы
и называть полученную сумму текущим VRAM клиента: часть недостижима из
Boot, часть исключена из export, а embedded texture внутри `.res`/`.scn`
не входит в такой inventory.

Для точной версии движка в этой среде (Godot 4.7.2,
`ed1daf0bf001b61586d9930840f2f1394092c079`) штатный debugger memory report
выдаёт path/format/type/bytes для текстур и meshes. Он **не передаёт RID**,
несмотря на заполнение ID внутри C++, поэтому одинаковые paths нельзя
просто дедуплицировать как одну allocation. Mesh bytes — сумма шести
категорий mesh buffers; custom RD, render targets и driver overhead
не становятся автоматически этой таблицей.
[Первичный код протокола и расчёта](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/debugger/servers_debugger.cpp#L403-L463) ·
[Сериализация четырёх полей](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/debugger/servers_debugger.cpp#L42-L52).

## Границы этого этапа

Старые жалобы не заменены общим выводом «Godot плохо использует GPU».
Полный non-grid shader действительно потребляет normals; его pipeline
удалять нельзя. Уход камеры от актёра сам не останавливает compute, но
может требовать непрерывной симуляции и отбрасывания тени — это отдельная
гипотеза, а не установленный дефект. Каталог после Boot, arena picker,
переход на карточный preview и редакторы имеют явные guards; найденной
утечки hidden-catalog callbacks нет.

Сервер, EXE/PCK, Windows, прослушивание и публикация не выполнялись.
Полный матч/профили, слабое оборудование и глобальный поиск bottleneck
не входят в эту диагностику.

Память и прибрежный A/B независимо перепроверены другим Sol high по raw,
арифметике, SHA и кадрам; grid finding также независимо проверил Sol high
по 13 source SHA и всей цепочке потребителей. Уверенность относится к
перечисленным фактам, а не к ещё не внедрённым оптимизациям.
[Независимая source-сверка grid](../2026-11-18-coastal-water-ab/independent-grid-review.md).

## Воспроизведение статической части

```sh
python docs/audits/2026-11-18-render-resources/count_grid_output.py
```

Команда читает исходники и исторический init log, пересчитывает payload,
проверяет локальные предпосылки и обновляет только accounting JSON.
Новый Godot или графическое окно она не открывает.
