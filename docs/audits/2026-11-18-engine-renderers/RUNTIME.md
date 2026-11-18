# Godot renderer / depth prepass — реальные проверки 18 ноября 2026

Production-игра, project.godot, настройки автора, сервер и выпуск не изменены.
Проверял Sol high. Все пять Godot launches — `tools/check.py` и штатный
`tools/test_window.gd`: окно за рабочим столом, minimized/unfocusable, offscreen,
лимит 60 FPS. Публичного окна/Boot/матча нет. Успешные проверки не повторялись
автоматически: первые две попытки имели ошибки диагностического fixture, затем
добавлен отдельный узкий причинный тест неожиданного исчезновения геометрии.

## Что подтверждено

1. Встроенный Mobile/Vulkan способен отрисовать реальную Каменную бухту с водой
   и островами на общем LOW feature subset. Это не готовая замена Forward+:
   широкий кадр Mobile показывает полосатый муар поверхности арены и более тёмную
   сушу. Геометрия/Multimesh buffers, camera/projection и effective settings обеих
   final сторон совпадают точно.
2. Динамическое **ON→OFF** `rendering/driver/depth_prepass/enable` в этой версии
   убирает opaque-геометрию. Вода и небо остаются; `draw_calls/primitives` при этом
   прежние. Эти OFF timings исключены из любых выводов об ускорении.
3. **OFF до построения сцены** работает: его широкий кадр имеет **0 отличающихся
   пикселей** относительно исходного Forward+ ON. Острова/арена видны также при
   скрытой воде. Значит найденный дефект относится к runtime pipeline state,
   а не к необходимости depth prepass для этой воды. Exact-source объяснение —
   в основном отчёте расследования движка; этот стенд подтверждает поведение.
4. Процент ускорения ни от Mobile, ни от static OFF не доказан. GPU DVFS сильно
   менялся, а cold-OFF диагностический тест не собирал timing distribution.

## Одинаковая постановка

Godot `4.7.2.stable.arch_linux.ed1daf0bf`, один `/usr/bin/godot`, Vulkan 1.4.357,
NVIDIA RTX 4070 Laptop, driver 620.70.06. SHA executable и всех исходников
на момент каждого запуска лежат в его `manifest.json`.

Настоящий `Stage._build_world` из `scenes/main.gd`, location ID3, без Boot и
персонажей; фиксированные seed18112026 и все найденные mesh ShaderMaterial TIME10.
Scene processing disabled. 1280×720, 3D scale1, bilinear scaling, LOW detail,
без MSAA/TAA/FXAA, shadows/SSAO/SSIL/SSR/glow; одинаковые fog/tonemap/lights.
Два фиксированных camera transforms/FOV52/near/far/projection записаны в raw JSON.
Геометрия включает реальные MeshInstance и MultiMesh: raw byte SHA256 vertices,
indices и instance buffers. Оба final `geometry.json` имеют SHA256
`340df20e4501f713689c8fd4f6abb4eb71da01c71f4e42cf1caf8f2ff4a9045a`.

На timing окно: 120 warmup кадров, затем 300 process_frame samples (~5s).
Root viewport `get_measured_render_time_gpu/cpu` — rendering spans, не whole-frame
latency/whole-CPU/GPU power. Профиль CPU не включает всё время приложения.
Штатный `--gpu-profile` включён одинаково у обеих final сторон; его rolling means
не смешиваются с точными 300sample quantiles. При wrapper force_draw глобальный
`Engine.get_frames_drawn()` остаётся повторяющимся, поэтому frame ID не считают
уникальными. На 300samples записан301 post_draw; интервалы подтверждают ход рендера.

## Описательные числа, не speedup

| Renderer / view | GPU p50 / p95 ms | root CPU p50 / p95 ms | graphics clock p50 (range), MHz | scene draws / primitives |
|---|---:|---:|---:|---:|
| Forward+ wide ON | 2.5535 / 4.0544 | .3080 / .4301 |1230 (975–1350)|53 /2,458,145|
| Forward+ shallows ON |2.7385 /4.2024|.2680 /.3793|817.5 (675–1605)|28 /2,038,287|
| Forward+ wide return ON |3.2250 /5.7276|.3250 /.4567|1200 (690–1395)|53 /2,458,145|
| Mobile wide |2.4750 /4.0326|.2690 /.3702|855 (525–1245)|53 /2,458,145|
| Mobile shallows |1.7875 /5.8236|.2310 /.4723|1260 (495–1605)|28 /2,038,287|

Возврат ON сам сильно отличается от первого ON; сравнение процентов неверно.
Полные root metrics, CSV250ms clocks/utilization/power/device memory и procfs
CPU/RSS/конкуренты сохранены. В final timing окнах был только один Godot process;
desktop/background процессы оставались активны. Device-wide nvidia counters
не являются потреблением только клиента. Особенно в Mobile wide сохранялся
нагруженный CPU хвост загрузки/компиляции; RSS/CPU не дают честной экономии.

Стабильные RenderingServer counters для изолированного stage:

| Renderer | video counter MiB | texture counter MiB | buffer counter MiB |
|---|---:|---:|---:|
| Forward+ |1100.816|976.970|78.942|
| Mobile |1062.057|948.026|68.742|

Mobile counters ниже на38.758/28.943/10.201MiB соответственно. Это счётчики
аллоцированных ресурсов этого стенда, не resident VRAM и не Boot memory saving.
Сцена без существ не доказывает cloth/avatars/полный матч/другие арены/Windows.

## Состояние запусков и raw

Все пути относительно корня проекта, каталоги уникальны и прежние audit runner
не перезаписывались.

- `build/engine-renderers-20261118/forward_plus-initial/`: runner FAIL,
  geometry helper вызвал `.size()` у null unindexed ARRAY_INDEX; плюс Remote
  Debugger connection error. Из итогового timing comparison исключён.
- `.../forward_plus-clean/`: runner FAIL, шесть `HashingContext.update(empty)`
  ошибок до warmup. Timing/visual records сохранены как diagnostic evidence.
  Collector на этот раз подключился и подтвердил отсутствие Depth Pre-Pass OFF.
- `.../forward_plus-final/`: **6 PASS/0 FAIL**, runner PASS, exit0, **56.82s**,
  чистый лог, raw samples/пять PNG/geometry/effective settings/telemetry/procfs.
- `.../mobile-final/`: **6 PASS/0 FAIL**, runner PASS, exit0, **38.16s**,
  чистый лог, те же raw/two PNG/counters/settings.
- `.../forward_plus-depth-diagnostic/`: **3 PASS/0 FAIL**, runner PASS, exit0,
  **30.05s**, четыре PNG/`depth-report.json`, cold OFF → water hidden → ON →
  water hidden,90warm frames per snapshot. Timing distribution намеренно нет.

`runner/checks/presentation/selected-match-bottleneck/` каждого launch содержит
`summary.json`, stdout/stderr лог, engine лог, фактическую background wrapper.
`effective-check.py` сохраняет точный runner source в памяти с изолированным
BASE_OUT и выбранными renderer/driver, без изменения `tools/check.py` на диске.

## Воспроизведение

Текущий `run.py` поддерживает обе final-постановки и отдельную диагностику.
Каждый новый запуск требует нового `--tag` и `work.mkdir(exist_ok=False)`
защищает прежние данные. GPU требует разрешённого графического сеанса.

```sh
python docs/audits/2026-11-18-engine-renderers/run.py forward_plus --tag NEW
python docs/audits/2026-11-18-engine-renderers/run.py mobile --tag NEW
python docs/audits/2026-11-18-engine-renderers/run.py forward_plus --tag NEWDEPTH --probe depth-probe.gd
python docs/audits/2026-11-18-engine-renderers/analyze.py forward_plus-NEW mobile-NEW
```

`run-final-v2.py` — byte-identical сохранённый harness фактических final запусков
(SHA совпадает с их manifests). `run-loopback-v1.py` сохраняет прежний harness
диагностических attempts; fixture каждого запуска скопирован в его workdir.
`analyze.py` считает p95 линейной интерполяцией, timezone nvidia CSV — Europe/Moscow
как у host; итоговые полные числа в `summary.json` и per-launch
`summary-derived.json`. Независимый reviewer отдельно проверяет raw и изображения;
его вывод не заменяется этим операторским отчётом.

Durable копия только трёх successful/final runs находится в `evidence/`: PNG,
fixture/effective-check/wrapper/logs сохранены без изменения; JSON/CSV/procfs
сжаты gzip. `evidence/manifest.json` индексирует original и archive SHA256.
Прежние failed compressed streams не копируются; их raw остаются в build.
