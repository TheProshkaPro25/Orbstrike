# Проходы GPU — 18 ноября 2026

На текущем клиенте 0.4.5 подтверждены заметные затраты HIGH на SSIL,
непрозрачный проход и тени. В одной фиксированной сцене матча отключение
только солнечных теней дало измеренный GPU span **6.078 → 4.967 → 4.754 →
5.797 мс** при обратном включении. Это полезный адресный результат для
следующей оптимизации; утверждение о чрезмерной нагрузке всей игры или
сравнение с другой игрой этим стендом не доказаны. Production не менялась.

## Что запущено

Один Linux/Vulkan Forward+ процесс Godot **4.7.2 ed1daf0bf**, RTX 4070 Laptop,
драйвер 620.70.06. Настоящие Boot → меню → матч ID 3, броски/рост/бой →
неподвижный обзор следующего хода с двумя раскрытыми существами. Seed
команд/AI 777/12345/778; фактический controller match seed **1515351406**.
Симуляция 1×, физика 60 Гц. Задан размер 1920×1080, фактический viewport/PNG
**1920×1050**. Размер берётся из результата, а не пожелания стенда.

Штатный `check.py`/`test_window.gd`: свёрнуто, нефокусируемо, offscreen,
`Engine.max_fps=60`. **4/0, exit 0, 168.59 с**. По 90 process кадров прогрева
и 180 выборок в 16 окнах. В матчевых окнах post_draw=180/180; в меню
post_draw=270/180: меню не доказывает ровно 60 GPU draws/s, несмотря cap60.
Камера/история действий матча сохранены, анимации и shader time живые.
В меню дневная фаза фиксирована, но камера/трафик продолжают меняться.
Полный матч и шесть одновременно раскрытых существ не проверялись.

Внешний Python collector через 127.0.0.1:6038 включает штатный
`profiler:visual`, без редактора и второго Godot. **7284 сообщения** Visual
Profiler, 50 меток, incomplete bytes=0. Все 192 debugger `error` packets
имеют warning=true и `GDScript::reload`; runtime ERROR/FAIL/leaks в новых
логах нет. Один typed-array пакет 484 байта collector не декодировал;
все Visual packets разобраны. Метаданные 512 functions в исходном collector
унаследованы от script profiler и к этому visual захвату не относятся.

## Свежие результаты

Ниже mean длительности renderer timestamp span, а не hardware utilization.
Независимый парсер оставляет внутренние 2.5 с каждого 3-секундного окна
(0.25 с с обоих краёв) по host receive-time; 149–152 сообщений на окно.
Два тождественных inclusive/leaf времени не складываются.

| Сцена | GPU span, мс | GPU clock, MHz | Мощность всей GPU, W |
|---|---:|---:|---:|
| Меню HIGH A / B | 3.327 / 3.859 | 1825 / 1750 | 25.95 / 25.68 |
| Меню LOW A / B | 2.759 / 2.604 | 845 / 830 | 9.99 / 11.86 |
| Матч HIGH: тени A | 6.078 | 2550 | 53.59 |
| Матч HIGH: без теней A / B | 4.967 / 4.754 | 2348 / 2335 | 42.09 / 42.98 |
| Матч HIGH: тени B | 5.797 | 2463 | 51.14 |

Clock/power — шесть device-wide отсчётов `nvidia-smi` с шагом 500 мс на
каждое полное окно. Они независимо пересчитаны из CSV; это не watts процесса.
В фоне остаются KWin/Xwayland/Codex и другие приложения. После Godot
54 отсчёта: mean **23.22%**, **5.90 W**, clock674 MHz. Даже без игры процент
не нулевой. Вычитать этот меняющийся фон из короткого игрового окна как
точное потребление игры нельзя. Проценты HIGH с тенями 42.17/37.67%, без
37.33/34.83%; это занятость устройства за окно драйвера, не насыщение шейдеров.
Смысл счётчиков описан в [документации NVIDIA](https://docs.nvidia.com/deploy/nvidia-smi/index.html).

В HIGH с тенями крупные измеренные проходы:

| Проход | A / B, мс | Доля измеренного GPU span A / B |
|---|---:|---:|
| Render Opaque Pass | 1.666 / 1.601 | 27.4% / 27.6% |
| Process SSIL | 1.415 / 1.355 | 23.3% / 23.4% |
| Render Directional/SpotLight Shadows | 0.603 / 0.537 | 9.9% / 9.3% |
| Process SSAO | 0.443 / 0.452 | 7.3% / 7.8% |
| Render Depth Pre-Pass | 0.406 / 0.408 | 6.7% / 7.0% |

Без теней SSIL остаётся 1.490/1.467 мс. Уменьшается не только shadow pass,
но и Opaque (0.959/0.903 мс): работа выборки теней есть и при освещении
материалов. Весь выигрыш переключения нельзя приписать одному shadow pass.
На этом основании разумно отдельно измерять качество/радиус теней и SSIL.
Точная экономия SSIL при выключении здесь не измерялась.
В существующих настройках «Экранные эффекты: Умеренные» выключают SSIL/SSR,
сохраняя SSAO/свечение; отдельное «Разрешение 3D» и текст этим выбором
не меняются. Это рекомендация по текущему коду, а не новая измеренная пара.

LOW water ABBA: span **1.917 → 2.437 → 3.454 → 2.913 мс**; отключение
terrain **2.705**, восстановление **1.483 мс**. Эти полные времена не дают
надёжной цены воды/terrain: частоты сильно менялись, а обзор почти целиком
показывает пол/карты, без берегового пейзажа. Зато измеренная работа Copy
Screen/Depth Texture с водой составляет **0.145/0.034** и **0.174/0.054 мс**;
без воды оба интервала равны нулю. Шейдер прямо запрашивает screen/depth
textures (`scenes/locations/coastal_water.gdshader:4–5`). Draw calls 203→201,
primitives 1660051→1585545. Это конкретный кандидат для более простого LOW
пути воды, а не доказательство общей стоимости материала или отсутствия
других затрат. Terrain removal 203→195 draw calls не изолирует его shader cost.

## Как читается Visual Profiler

`visual:profile_frame` содержит cumulative CPU/GPU timestamps. Длительность
интервала = следующий GPU timestamp минус текущий; `>`/`<` задают вложенные
категории. Сумма leaf + opening/closing gaps совпала с полным span во всех
7284 сообщениях, max floating error 1.78e-15 мс. Отдельные доли относятся к
этому span, не к максимальной мощности GPU. Метод сверён с exact
[Godot debugger protocol](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/debugger/servers_debugger.cpp#L159-L184)
и [Visual Profiler](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/debugger/editor_visual_profiler.cpp#L354-L412).

В offscreen `force_draw(false)` frame IDs не уникальны: 1799 ID на 7284
сообщения, 5485 повторных ID, в 5476 меняются timestamps; только 9 соседних
payload тождественны. Поэтому глобальная дедупликация по ID выбросила бы
актуальные данные. Сводка сохраняет сообщения и явно считает эти случаи;
это выборка readouts, не доказанные 7284 уникальных представленных кадра.
GPU readback/debugger доставка запаздывают; edge trim уменьшает, но не
устраняет неопределённость соответствия мгновенной метке.

Span начинается внутри `RenderingServerDefault::_draw` после begin_frame.
Custom GPU cloth использует main RenderingDevice и render-thread очередь
без своих timestamp markers; его работа до начала этого span может не
попасть в измерение. Visual totals не названы whole GPU cost. Script profiler
предыдущего аудита измерял CPU callback cloth, а не его GPU shader время.
См. [точный renderer](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/rendering_server_default.cpp#L79-L165).

## Данные и повторение

[Сводка проходов](visual-summary.json), [сводка внешней телеметрии](raw/telemetry-summary.json),
[результат стенда](raw/results-report.json), [новый runner](raw/runner-summary.json),
[review manifest](review-manifest.json). Полные raw packet/report и покадровые
выборки сохранены gzip в `raw/`; decoded profiler report сохраняет receive-time.
Свежие PNG лежат в `build/render-diagnostic-20261118/results/`. Независимый Sol
просмотрел menu HIGH/no-shadow и match HIGH/LOW-no-water: реальный HUD/сцена
присутствуют; тени меню меняются, берег в матчевом обзоре не виден.

Из корня проекта скопировать `bench/*` в `build/render-diagnostic-20261118/`.
В отдельных терминалах сначала запустить collector и телеметрию, затем runner:

```sh
python build/render-diagnostic-20261118/visual_profiler.py --port 6038 --out build/render-diagnostic-20261118/profiler
nvidia-smi --query-gpu=timestamp,pstate,utilization.gpu,utilization.memory,clocks.current.graphics,clocks.current.memory,power.draw,temperature.gpu --format=csv -lms 500 > build/render-diagnostic-20261118/nvidia-series.csv
python build/render-diagnostic-20261118/run.py
python build/render-diagnostic-20261118/summarize_telemetry.py build/render-diagnostic-20261118 > build/render-diagnostic-20261118/telemetry-summary.json
python docs/audits/2026-11-18-render-pass/summarize_visual.py build/render-diagnostic-20261118/profiler/report.json --out docs/audits/2026-11-18-render-pass/visual-summary.json
```

Остановить только свой `nvidia-smi` после фоновой выборки. Не открывать второй
Godot. Новый launcher задаёт отдельный BASE_OUT, сохраняя общий wrapper.
Исторические summary/stdout/engine предыдущего CPU/GPU аудита временно были
перезаписаны; восстановлены из его immutable manifest/raw output и независимо
сверены **byte-identical по трём прежним SHA**. Свежие 168.59 с артефакты сохранены
отдельно. [Доказательство восстановления](raw/history-recovery.json).

До/после production snapshot нет: reviewer снял SHA во время работающего
стенда, затем подтвердил их неизменность после него. Все итоговые SHA и
точный измеренный diagnostic script зафиксированы в review manifest.
Полный профиль, другие арены, слабое оборудование/Windows, прослушивание,
сервер, EXE/PCK, сборка и публикация не выполнялись. Графика не оптимизировалась.
