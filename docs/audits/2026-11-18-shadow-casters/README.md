# Тени Каменной бухты без снижения качества — 18 ноября 2026

В `scenes/arena.gd` изменён только теневой проход четырёх тяжёлых статических
наборов Каменной бухты ID 3: стволы и три материала крон. Прежние цветные
MultiMesh сохранены. Тени тех же **4213 экземпляров** собираются один раз
в **270 пространственных групп по 256 м**, с теми же mesh/material/matrix.
Godot может отсеять целую группу вне объёма света/каскада. Ручной проверки
видимости камерой, удаления дальних объектов или упрощения силуэтов нет.

Размеры атласов, фильтр, каскады, дальность, PCSS/угловой размер, bias,
настройки и значения по умолчанию **не менялись**. Модели, сервер и пакеты
не изменены. Это локальное изменение исходников, не обновление старого EXE.

## Почему это работало впустую

Раньше каждый из четырёх MultiMesh покрывал почти весь архипелаг — около
2.6 × 2.5 км. В одном наборе стволов 220608 треугольников, в каждом из трёх
наборов крон около 225 тысяч. MultiMesh не отсекает отдельные экземпляры:
пересечение общего AABB с каскадом отправляло в него весь набор.
Предыдущий настоящий матч той же арены ID 3 имел дополнительные **4750286**
submitted primitives при включении теней (6504617 против1754331).
Новая узкая сцена воспроизводит главную статическую причину; состояние того
старого матча здесь не воспроизводилось побайтно.

[Документация MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
подтверждает общий spatial index. Разделение на несколько MultiMesh для
отсечения рекомендовано в
[документации Godot](https://docs.godotengine.org/en/4.4/tutorials/3d/mesh_lod.html#using-mesh-lod-with-multimesh-and-particles).

Копии имеют `SHADOWS_ONLY`, `GI_MODE_DISABLED` и общий материал/mesh.
Прежняя цветная геометрия продолжает поставлять GI. Нет нового шейдера или
приближённой теневой геометрии. Матрицы остаются относительно того же Decor;
его скрытие и reparent действуют на обе части. Эти статические материалы —
StandardMaterial3D, без `INSTANCE_ID`, цвета/пользовательские данные MultiMesh
выключены, LOD и vertex displacement у четырёх сеток отсутствуют. Другие
арены и лёгкие наборы сохраняют прежнее построение.

Группы создаются в существующем `_flush_static()` во время построения арены,
до меню, а не каждый кадр или матч. Резидентная арена хранит те же узлы.
`apply_quality()` скрывает их при `shadow_enabled=false`, включая LOW по
умолчанию; независимый выбор высоких теней на LOW снова их показывает.
Синхронизировать анимацию экземпляров не требуется: эти наборы неподвижны.

## Проверка final production

Linux, RTX4070 Laptop, Vulkan1.4.357, Godot4.7.2 `ed1daf0bf`.
Настоящий `Stage._build_world` ID3 HIGH, фактически **1920×1050**, scale1,
MSAA4×, атлас8192/4каскада/filter4/distance120. Shader TIME=10,
обработка сцены остановлена; один настоящий раскрытый CreatureBall/Драгнар
и одна настоящая закрытая оболочка подготовлены изолированно без Boot.
Это не физический матч, не проверка всего каталога или Windows.

Шесть пар ракурсов: обзор, широкий пролёт, маяк, низкий край поля,
крупный Драгнар и крупная сфера. Baseline возвращает прежний cast ON четырём
цветным наборам и скрывает только новые копии; candidate включает production
копии. Камера/projection/effective settings всех пар совпали точно.

Итог **554 PASS / 0 FAIL / 0 ERROR, exit0, 58.38с**. Проверены все4213
матрицы полным sorted multiset, ссылки mesh/material, режимSHADOWS_ONLY,
GI disabled и отсутствие custom/color data. LOW → отдельные HIGH-тени наLOW
→ HIGH → OFF → HIGH, затем временный reparent арены сохраняют270узлов с теми
же instance IDs. Перестроения групп не произошло. Сообщений об утечках в логе нет.
Все GPU-запуски использовали `tools/check.py` + `tools/test_window.gd`,
minimized/unfocusable/offscreen, cap60; последовательные, без показа игры.

## Результат и его границы

Ниже final production, медианы по90viewport samples на окно, 60кадров прогрева.
Число primitives — submitted render primitives, с повторными проходами;
это не количество уникальных треугольников мира. Теневой map-pass — отдельная
медиана штатного VisualProfiler с обрезкой. Все значения «до → после».

| Ракурс | Submitted primitives | Draw calls | CPU render p50 / p95, мс | Shadow map GPU p50, мс |
|---|---:|---:|---:|---:|
| Обзор |5997549 →2418797|74 →58|.630/.792 →.644/.828|.518 →.272|
| Широкий |6549531 →2970779|92 →76|.620/.820 →.681/.966|.354 →.069|
| Маяк |5936355 →2473699|67 →68|.627/.767 →.627/.827|.417 →.170|
| Низкий край |6324419 →2745667|80 →64|.577/.806 →.574/.757|.462 →.280|
| Драгнар вблизи |6505183 →2926431|89 →73|.604/.794 →.636/.878|.569 →.327|
| Сфера вблизи |6504965 →2926213|77 →61|.592/.791 →.608/.829|.696 →.476|

Экономия повторных submissions стабильна. В отдельной V3-паре с теми же
актёрами выключение солнца даёт одинаковые24draws/1558239primitives для обоих
вариантов: основной проход не раздроблен. В этом обзоре добавка теней
4439310 →860558primitives, **−80.6%**. Это счётчик проходов, не процент FPS.

Штатная метка Godot называется `Render Directional/SpotLight Shadows`; точный
Forward+ source `render_forward_clustered.cpp` включает в этот участок
`_render_shadow_begin/pass/process/end`, в том числе directional shadow maps.
**PCSS sampling на получателях входит в opaque shading и здесь не измерен
отдельно.** Эта строка не означает полную цену всех теней.

Общий GPU результат неоднороден: viewport p50 обзор5.338 →5.240мс,
широкий12.010 →11.459, Драгнар5.523 →5.990. Частоты всейGPU за final прогон
375…2550MHz; фон и DVFS не контролировались. Поэтому общий FPS, мощность,
ускорение слабойGPU и универсальный процент экономии не доказаны.
CPU p95 в отдельных видах слегка вырос; постоянного CPU-ускорения не заявляем.

Ранее проверены128/256м группы **для обоих проходов**:128 создавал929узлов,
wide CPU p50.601 →1.3425мс и89 →520drawcalls;256 создавал493узла и
wide .5985 →.9105мс/89 →289drawcalls. Эти варианты не оставлены в production.
Именно этот измеренный недостаток привёл к финальному shadow-only варианту.
Прогоны: V1 93.28с, V2 73.88с, V3shadow-only92.76с; все exit0/FAIL0/ERROR0.

Цена финального хранения — **+270Node/+270MultiMesh**, повторные4213матрицы,
**202224байта сырого float32 transform payload**. Mesh/material/текстуры общие.
Это не полная цена driver allocation/RSS: накладные расходы узлов, GPU structures
и residency отдельно не изолированы. LOW/OFF скрывают копии, но память
резидентного каталога сохраняется. В final Stage372узла/3719objects,
`Performance.MEMORY_STATIC`192084341байт; построениеStage10.539с включает
весь процедурный ландшафт и не имеет парной baseline: влияния на загрузку
из этих чисел выводить нельзя. Чтение `/proc/self/status` из fixture вернуло
пустую строку; RSS этим измерением не подтверждён.

## Изображение

В финале обзор и низкий край совпали побайтно. Маяк:390pixels max4,
Драгнар:2844pixels max1, сфера:6803pixels max1 на2016000pixels. Широкий вид:
6339pixels(0.314%), лишь21pixel с maxRGB>3, max50,
MAE.001275 на канал. Эти малые разницы воспроизводятся и при shadow-only,
поэтому все кадры не называем pixel-exact; наличие иной shadow order/depth
fit/вычислений renderer не доказывает причину каждого пикселя.

Sol high и независимый Sol high просмотрели полные пары, тень фигуры/сферы,
край поля и пролёт. Потери видимых теней, изменения мягкости и новых квадратов
в этих видах не обнаружено. Это оценка перечисленных кадров, не обещание
отсутствия всех артефактов в любой камере. После quality/reparent картинка
Драгнара имеет4627изменённыхpixels/max16/MAE.003659 при той же камере и
настройках; визуальная тень сохранена, число submissions и узлы прежние.

[Драгнар до](evidence/production-final/actor-close-original.png) ·
[после](evidence/production-final/actor-close-partition.png) ·
[после quality/reparent](evidence/production-final/actor-close-after-quality-reparent.png) ·
[сфера](evidence/production-final/sphere-close-partition.png) ·
[широкий до](evidence/production-final/wide-original.png) ·
[после](evidence/production-final/wide-partition.png).

[Независимая сверка SHA/матриц/камер/PNG](independent-review.json) ·
[Край тени Драгнара до/после, исходные пиксели](independent-actor-close-shadow-crop.png) ·
[Край тени дерева до/после, исходные пиксели](independent-lighthouse-shadow-crop.png).

## Доказательства и воспроизведение

[Офлайн-пересчёт четырёх прогонов](summary.json), [полные4213матрицы поSHA](evidence/production-final/structural-proof.json),
[final runner](evidence/production-final/runner-summary.json),
[final log](evidence/production-final/runner-match-bottleneck.log),
[VisualProfiler summary](evidence/production-final/profiler-summary.json),
[все SHA/размеры архива](evidence/manifest.json). Сырые JSON/packets сохранены
рядом с `.gz`; decode в каждом профайлере не разобрал один typed-array484пакет.
В финале сохранены1962visual messages; frame IDs могут
повторяться приforce_draw(false), записи не глобально дедуплицированы.

[Dirty baseline arena](baseline/arena.gd.txt) и [его прежний diff](baseline/arena-preexisting.patch)
сохранены; baselineSHA `65f889db…`, final `b87444dc…`. Все13входов final
manifest (включая arena.gd) независимо сверены с текущими файлами. Существующие авторские
правки не стёрты; новые production-изменения ограничены `scenes/arena.gd`.

Для повторения используйте новый уникальный tag и каталог profiler, запустив
loopback listener перед runner (в отдельном терминале):

```sh
python docs/audits/2026-11-18-render-pass/bench/visual_profiler.py --port 6041 --out build/shadow-casters-20261118/profiler-recheck --timeout 180
python docs/audits/2026-11-18-shadow-casters/run.py forward_plus --tag production-recheck
```

Runner подменяет только opt-in script, isolatedBASE_OUT и GPU/renderer-флаги
штатного `check.py` в памяти. Сам `tools/check.py` не изменён. Сеанс должен
иметь доступ к GPU/дисплею и127.0.0.1; обычное окно игры не требуется.
`analyze.py` пересчитывает сохранённые исходные tags изbuild без Godot.
Полный профиль, Boot-каталог, физический матч, Windows, слабаяGPU,
прослушивание, сервер, EXE/PCK и публикация не выполнялись.
