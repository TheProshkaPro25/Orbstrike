# Каменная бухта: плотность воды, 18 ноября 2026

Реальный широкий ракурс с водой и дальними островами проверен новым
single-variable A/B. Уменьшение плотности воды вдвое по каждой оси сокращает
её геометрию на 74.74%, но всего 2.265% от примитивов этого кадра. Ускорение
GPU не доказано: частоты менялись. На отмели меняются пена и блики, поэтому
этот вариант не перенесён в production.

## Постановка и результат

- Godot 4.7.2 / Vulkan Forward+ / RTX 4070 Laptop, Linux.
- Настоящий `Stage._build_world()` из `main.gd`, локация 3; без Boot,
  каталога существ, матча и актёров. Это сценический рендер, не игровой матч.
- LOW, viewport 1280×720, фактический `scaling_3d_scale=0.75` (3D 960×540).
- Штатный `tools/check.py` и `tools/test_window.gd`: окно вне экрана,
  свёрнутое, нефокусируемое, offscreen, cap 60. Пользовательские настройки
  обычной игры не изменены.
- В runtime-копии PlaneMesh только subdivisions: 192×192 → 96×96.
  Размер 2400×2400, положение, материал и внешний водный пояс одинаковы.
  Незначительная разница float AABB от вычисления сетки сохранена в JSON.
- Обработка Stage отключена, shader TIME воды заморожен одинаково для A/B:
  10 секунд для wide/первой отмели, 12 для второй отмели. Сам шейдер не упрощён.
- Wide ABBA BAAB: 60 warmup +120 samples на окно, те же камера/фаза,
  121 post_draw на 120 samples (включая ожидание кадра для PNG).
  Затем по одному PNG/вариант на отмели при двух фазах; их единичные тайминги
  не используются как benchmark.
- Успешный запуск **53.79 с, exit 0, 3/0**, без runtime ошибок/утечек.
  Предыдущий pre-render attempt остановился на ошибке типа fixture
  (`main.gd` — Control, не Node3D), исправлен, headless `--check-only` exit 0;
  исходные failed логи сохранены отдельно. Он не считается успешным GPU-прогоном.

| Счётчик wide | A, штатная вода | B, редкая вода |
|---|---:|---:|
| Вершины воды | 37 636 | 9 604 |
| Индексы воды | 223 494 | 56 454 |
| Треугольники воды | 74 498 | 18 818 |
| Примитивы кадра, median | 2 458 145 | 2 402 465 |
| Draw calls кадра, median | 53 | 53 |

Индексы и вершины взяты из `surface_get_arrays(0)`, не из оценки размера файла.
Уменьшение примитивов кадра **55 680**, ровно равно разнице треугольников воды.
Это не устраняет screen/depth copies или fragment-работу воды. В штатном
`coastal_arena.gd` все 30 островов используют одинаковые 112×256 ячеек
(57 344 треугольника каждый, 1 720 320 суммарно до frustum culling), даже
небольшой остров с радиусами 31×21. Distance LOD островов остаётся более
содержательным следующим кандидатом; его качество и ускорение здесь не проверялись.

## Время GPU и частоты

Штатный Visual Profiler: cumulative GPU timestamps переведены в интервалы
прежним `summarize_visual.py`, края каждого окна обрезаны на 0.25 с.
В таблице p50 измеренного renderer GPU span; это не utilization всего устройства.

| Окно | GPU span p50, мс | Graphics clock внутри обрезанного окна, MHz |
|---|---:|---:|
| A1 | 1.610 | 1020–1440 |
| B1 | 2.408 | 720–1275 |
| B2 | 1.943 | 1035–1170 |
| A2 | 2.998 | 795–900 |
| B3 | 1.816 | 1230–1485 |
| A3 | 1.911 | 1215–1230 |
| A4 | 1.658 | 1125–1605 |
| B4 | 1.714 | 1065–1605 |

Порядок ABBA BAAB не компенсировал DVFS и фоновые процессы. Процент ускорения
из этих чисел не выводится. Root viewport GPU/CPU samples сохранены отдельно;
они также неоднозначны. В обоих вариантах остаются Opaque/Depth Pre-Pass,
Transparent и Copy Screen Texture; редкая вода не выключает проходы.

1450 visual packets полностью декодированы. Frame ID в force_draw здесь
постоянный: они сохранены все, без глобальной дедупликации. Единственная
неразобранная typed-array запись, 484 байта, — `performance:profile_names`,
не visual timestamps. Исходный binary stream сохранён для проверки.

## Картинка и границы

![Штатная вода, широкий ракурс](wide-a1.png)

Wide A1 и A4 **побитно одинаковы** по RGB. Это подтверждает стабильность сцены
для сравнения с B. Wide A1/B1 MAE 0.2531/255; 0.2871% пикселей имеют разницу
хотя бы одного канала >8. На отмели phase10/12 MAE 1.8738/1.2587,
36.31%/37.24% пикселей отличаются, а >8 — 8.283%/4.770%.
Это метрика различия, не метрика качества.

Sol high и независимый Sol high осмотрели широкий ракурс и обе пары отмели.
Крупного разрыва/исчезновения берега не видно, но пена и блики местами заметно
сдвигаются. Паритет качества и временная стабильность в движении не доказаны.
Волны вершин имеют длину около 30.6 м при максимальной фазовой частоте,
новый шаг сетки ≈24.74 м вместо ≈12.44 м может искажать их форму; амплитуда
до ±0.19 м не делает это автоматически безопасным.

[Отмель, фаза10 A](shallows-phase10-a.png) · [B](shallows-phase10-b.png) ·
[Фаза12 A](shallows-phase12-a.png) · [B](shallows-phase12-b.png) ·
[Редкая вода wide](wide-b1.png).

Здесь не проверялись HIGH, полный матч, Boot residency, Windows, слабая GPU,
общая мощность клиента или новая production-оптимизация. Сервер, EXE/PCK,
выпуск и production исходники не изменены.

## Воспроизведение и файлы

Из корня проекта (при доступной настоящей GPU/desktop session):

```sh
python docs/audits/2026-11-18-coastal-water-ab/run.py
python docs/audits/2026-11-18-render-pass/summarize_visual.py build/coastal-water-ab-20261118/visual/report.json --out build/coastal-water-ab-20261118/visual-summary.json
```

Launcher копирует [probe.gd](probe.gd) в `build/coastal-water-ab-20261118`,
исполняет исходный check.py с двумя заменами только в памяти: opt-in script
и **уникальный BASE_OUT** `build/checks/coastal-water-ab-20261118/runner`.
Production check.py не редактируется. Не запускать одновременно с другим
GPU benchmark. На этой машине sandbox скрывает GPU; read-only nvidia-smi и
данный GPU запуск получили узкий `require_escalated` после проверки разрешений.

[report.json](report.json) — исходные counters/root query samples/камера;
[summary.json](summary.json) — пересчёт [summarize.py](summarize.py);
[visual-summary.json](visual-summary.json) — интервалы GPU pass;
[visual-report.json.gz](visual-report.json.gz) и
[visual-packets.bin.gz](visual-packets.bin.gz) — raw provenance;
[telemetry.csv](telemetry.csv) — device-wide clocks/pstate каждые250мс;
[runner summary](runner-summary.json), [лог](runner-match-bottleneck.log).
SHA исходников на момент запуска — [source-sha256.json](source-sha256.json);
SHA сохранённых артефактов — [sha256.json](sha256.json).

Для независимого пересчёта сохранённого успешного запуска без Godot:

```sh
python docs/audits/2026-11-18-coastal-water-ab/summarize.py
```
