# Position-only output плаща Ratnik — 18 ноября 2026

В клиенте изменён только вывод GPU cloth для невидимого Trellis Ratnik grid.
Симуляция, topology, skin targets, colliders, constraints и исходные модели не
менялись. `CreatureCloth.attach()` включает отдельный `output_positions_only`
только для Trellis; необязательный `position_only_grid=false` сохраняет полный
вывод для парного контроля. Обычный non-grid CapeGPU по умолчанию сохраняет
нормали, lookup и оба output passes. `output_skin_delta` сам по себе не включает
оптимизацию. Режим выбирается до инициализации и не переключается на живом solver.

## Потребители и удалённая работа

Основной grid vertex shader и его owner-rim вариант читают только позиции;
fragment/light используют штатные skinned normals. Обе стороны и flash сохраняют
прежний код. Simulation proxy имеет layers0 и shadows OFF; его полный substrate
материал не является отображаемым потребителем. Новая позиционная GLSL программа
повторяет операции позиции `cloth_output.glsl`, включая `.w` и subtraction
`skinned_targets`, без normal gather. Ни render shader, ни normal lighting модели
не менялись. Исходная цепочка потребителей разобрана в
[static-flow](../2026-11-18-render-resources/static-flow.md).

На grid567 particles /1040triangles проверены отсутствующие валидные GPU RID:

| Ресурс | Логические байты полного пути | Position-only |
|---|---:|---:|
| Mutable face normals | 16 640 | 0 |
| Normal RGBA32F image | 9 072 | 0 |
| Welded-index RGBA32F lookup | 9 072 | 0 |
| Immutable adjacency counts/offsets/list | 17 016 | 0 |
| Итого перечисленного payload | **51 800** | **0** |

Из них34 784B принадлежат одному actor,17 016B — общий immutable content set,
поэтому51 800 нельзя умножать на число существ. Driver allocation/alignment не
измерялись. Индексы12 480B и peer proxy сохранены для collision consumers;
это осознанно меньше первоначального статического списка возможной экономии.

Реальные нормальные shader/pipeline/uniform set тоже не создаются. На каждый
output update исчезает один normals dispatch (17groups×64), его barrier и normal
часть второго dispatch:567gathers/3120adjacency entries. Нужный position dispatch
(9groups×64) остаётся. Это следует из исполняемой ветки и инвентаря RID, а не из
счётчика GPU hardware invocations. Барьеры после simulation update и warm start
сохранены: отсутствие output-normal barrier не удаляет dependency, защищающую
чтение positions/skinned targets. Output shaders не записывают simulation buffers.

## Узкие проверки на Linux/Vulkan

Godot4.7.2, Forward+, RTX4070Laptop. Оба графических стенда запускались через
`tools/check.py`/`test_window.gd`: свёрнуто, нефокусируемо, offscreen, cap60,
изолированные XDG. Полные профили и выпуск не запускались.

- [Paired report](../../../build/checks/models/selected-cloth-position-only/cloth-position-only/report.json),
  [runner](../../../build/checks/models/selected-cloth-position-only/summary.json):
  **239/0, exit0,10.23с**. Два настоящих Trellis display mesh, явный full/full
  контроль, manual native idle/stance/attack/hit/roar, фиксированные gust и позы.
  **17проверок position output побитово совпали на одних и тех же GPU input
  buffers** через отдельный descriptor set; оба paths оставили simulation
  positions неизменными. Третий full actor получает те же explicit steps,
  временно показываясь только до `_process`, без draw.
- На финальном прогоне все17×3 динамических buffer comparison тоже побитово
  совпали (full/only и full/full);15различных position states. **9пар PNG**
  совпали во всех каналах: warm start, idle, четыре native actions, owner-rim
  +flash, задняя сторона и reparent/warm start. В fixture shader TIME заменён
  одинаковым1.25 только для rim; production `RIM_SHADER` сохранён.
  [Idle](../../../build/checks/models/selected-cloth-position-only/cloth-position-only/idle-only.png),
  [attack](../../../build/checks/models/selected-cloth-position-only/cloth-position-only/attack-0.45-only.png),
  [rear rim/flash](../../../build/checks/models/selected-cloth-position-only/cloth-position-only/rear-rim-flash-only.png).
- Reparent сохраняет GPU RIDs и refcounts, запускает warm start; parked actor
  не меняет positions. Удаление полного actor оставляет optimized survivor;
  после последнего actor общий pool пуст. Отдельный non-grid fixture сохраняет
  normals shader/image/lookup (13418particles) и корректно освобождается.
  Его прежнее предупреждение об одном non-manifold edge остаётся предупреждением.
- [Реальный lifecycle](../../../build/checks/models/selected-ratnik-trellis/result.json),
  [runner](../../../build/checks/models/selected-ratnik-trellis/summary.json):
  **384/0, exit0,55.02с**. Boot→134actors/4arenas→меню→аренда шести стихийных
  Ratnik→раскрытие/атака/guard/battle→возврат. Boot30.015с, lease310ms — это
  одиночные новые времена, без парной базы для ускорения загрузки. Проверены
 12подготовленных Ratnik, фактическая shell landing pose через
  `hold_landing_pose`, повторное раскрытие, collider/pose/uid и identity GPU
  storage при возврате. Battle подтвердил hit/hitstop/sword effect/result close;
  cloth samples opened/strike/hit сохранили pins, bounded offsets и отсутствие
  proxy crossings. Это узкий lifecycle, а не полный матч до победителя.

Независимый Sol high сверил incremental production diff, raw buffers/SHA и числа,
посмотрел idle/attack/rear-rim изображения; вывод — PASS в указанных границах.

## Output-only GPU timestamps

Четыре парных окна AB/BA/AB/BA,100повторений output на неизменных GPU inputs,
RenderingDevice GPU timestamps строго вокруг custom output lists. Raw находятся
в paired report, расчёт — [measurements.json](measurements.json).

- full:4.62848/7.78240/8.00768/8.29440µs на output, median7.89504µs;
- position-only:1.59744/1.59744/2.74432/2.82624µs, median2.17088µs.

Это batched repeated output с тёплыми данными и меняющейся частотой GPU. Whole
simulation, whole frame, watts и выигрыш FPS не измерялись; переносить эти
микросекунды или отношение на обычный матч/слабую GPU нельзя.

## Сохранённые неуспешные попытки и границы

В `build/checks/cloth-position-only/` сохранены четыре ранних попытки:
неимпортированный новый GLSL/null pipeline; асинхронный TIME rim; длинная trace
с небольшим float drift; ошибка typed-array в новом control fixture (собственный
зависший процесс остановлен по точному PID). Это FAIL, не дополнительные PASS.
После первого сбоя выполнен необходимый headless editor import нового GLSL.
Production алгоритм симуляции между этими попытками не менялся.

В attempt3 hit/roar накопили максимум порядка3.3e-7 в positions; это не скрывается
допуском и не объявляется доказанной общей недетерминированностью Godot. Причина
различий полностью не локализована. Поэтому итоговый fixture отдельно доказывает
точную функцию output на **одних** input buffers и сохраняет full/full контроль
и raw trace; диагностический предел trace1e-5 не заменяет exact-output checks.
Финальный measured drift0 не обещает побитовый whole-match trace для любых GPU.

Peer/self collisions не включались отдельным новым runtime сценарием (их
index/topology buffers сохранены), Windows/слабая GPU, все визуальные эффекты
полного матча и прослушивание не проверялись. Для точного vendor SHA сохранена совместимость canonical CPU cache;
имеющиеся .pdat не переписываются. Порядок подтверждения описан ниже.
Модели, сервер, EXE/PCK и выпуск не затронуты.

## Совместимость подготовленных CPU кэшей

Независимый review обнаружил риск: без точного исключения нового vendor SHA
старые .pdat промахивались бы на каждом Boot, поскольку обычный PreparationStore
только читает, а canonical memory cache живёт один процесс. Риск устранён в
`ResidentClothSolver`: **только** d484d7e65fad1e65467e8515a8961f650f294db85d18d747cdb33cb4b27899da
нормализуется в прежний CPU_COMPATIBLE_VENDOR_SHA. Неизвестные будущие SHA
сохраняют обычную инвалидацию. Структура содержимого/версия/ключи .pdat не менялись.

[Static parity](cpu-method-parity.json) подтверждает идентичность всех восьми
канонических CPU методов между исходным dirty baseline и новым vendor, включая
adjacency, constraints/group order, body collider и peer proxy. Изменения
`_initialize()` пропускают adjacency/lookup лишь для opt-in grid и не меняют
геометрию или CPU cache payload остальных методов.

[Узкий headless probe](cache_keys.gd),
[лог](../../../build/checks/cloth-position-only/cache-compat.log),
[report](../../../build/checks/cloth-position-only/cache-compat-report.json):
**33/0, exit0**, без GPU и перезапуска парного графического прогона. Для прежней
Ratnik Tide и текущей Trellis source keys всех шести семейств в точности равны
прежней формуле, parameterized extract/weld keys тоже равны. Неизвестный future
stamp даёт другой ключ и сохраняется дословно. Обычные `_prepare_mesh_data()` и
`_prepare_weld()` прочитали реальные прежние Tide .pdat с одним disk hit каждый:
`cloth-extract-5557953c…` и `cloth-weld-4e0e818d…`; возвращённые payload совпали
с файлами. Для Trellis соответствующих файлов нет: это прежнее отсутствие,
явно записанное как miss, а не заявленный disk hit. Store writes=0.
Эта финальная правка касается только нормализации ключа; GPU compute code,
shader и исходные inputs пройденных графических тестов не менялись.

## Воспроизведение и входы

```sh
godot --headless --max-fps 60 --path . -s res://docs/audits/2026-11-18-cloth-position-only/cache_keys.gd
python tools/check.py --profile models --checks import
python tools/check.py --profile models --visual --checks cloth-position-only
python tools/check.py --profile models --visual --checks ratnik-trellis
```

Запускать GPU стенды последовательно. [Incremental patch](incremental.patch)
сопоставлен с исходной dirty рабочей копией, snapshot которой сохранён в
`build/checks/cloth-position-only/source-before/`; он не включает старые чужие
правки. [Manifest](manifest.json) фиксирует production/fixtures и свежие
доказательства. Новый shader+.import входит в обычный all_resources экспорт;
новый export/package не выполнялся.
