# Ограниченный пилот Blender Asset QA — 9 ноября 2026

Проверяющая модель: Sol, high. Навык применён к диагностическим копиям;
глобальной установки навыка, автоматического исправления моделей и изменений
пользовательской Blender-сцены/настроек не было. **Пилот выполнен, model QA PASS
не получен.** Два фоновых запуска Blender завершились exit 0, но оба raw-отчёта
финального запуска имеют `pass: false`. Exit 0 означает успешное выполнение
диагностического скрипта, а не отсутствие дефектов.

## Scope и происхождение

- Один male avatar в двух вариантах: принятый street как контроль и **заведомо
  дефектный sport-neck candidate1**, замороженный до последующих исправлений.
  Это оценка возможностей инструмента на известном дефекте, не проверка последних
  production sport .res. Финальный candidate3 проверен отдельно:
  [Godot sport-neck](../2026-11-09-sport-neck/README.md).
- Два ансамбля содержат Face, ModularHair, ModularCostume и исходную skin/rig
  привязку. Street использует hairstyle 9, sport — hairstyle 0; различие hair counts
  ожидаемо. Female, остальные костюмы и 49 creature GLB не проверялись.
- Исходные снимки и SHA находятся в [source-manifest.json](source-manifest.json).
  Sport .res SHA `e433b3f67d5e5508cfcee39f5180f5c551bf3b8f136a4a91886847d1a80e7e51`;
  street .res SHA `5669cb1d6c227467ffc879d2f0c1985173ec8b5dfbcb630a31ebf80c40daee8f`.
- Применены полный [blender-asset-qa SKILL.md](upstream/skills/blender-asset-qa/SKILL.md)
  и [blender-core SKILL.md](upstream/skills/blender-core/SKILL.md).
  [Официальный upstream](https://github.com/EL4CTEO/blender-skills/tree/389f28addc79b87b28764898e38e7bf408d14b77),
  commit `389f28addc79b87b28764898e38e7bf408d14b77`, MIT.
  Семь скачанных файлов сверены по [upstream-manifest.json](upstream-manifest.json).
  Сторонние скрипты не изменялись; запускались без `--fix`, rebind, decimate,
  пересчёта нормалей и UV repack.
- Godot 4.7.2, Blender 5.2.3 LTS. Экспорт сделан headless из изолированного
  VrmAvatar с фактическими профилем и surface overrides, подменён только mesh
  костюма на снимок. Штатный test_window задавал background/60 FPS; никакого
  видимого окна игры. Существующая живая Blender-сцена не использовалась.

## Фактические результаты

| Копия | Треугольники | Первоначальный raw | Финальный raw | Время QA |
|---|---:|---|---|---:|
| accepted male street | 41 779 | FAIL, 10 errors / 10 warnings | **FAIL, 9 / 9** | 6,729 с |
| known-bad male sport candidate1 | 36 895 | FAIL, 11 / 10 | **FAIL, 10 / 9** | 3,672 с |

[Финальная матрица](results/summary.json), [street raw](results/street/qa-raw.json),
[sport raw](results/sport/qa-raw.json), [Blender log](blender.log),
[экспортный log](export-engine.log), [окружение](results/environment.json).

Первый harness ошибочно выбрал все MESH, включая созданную импортёром служебную
bone custom-shape `Icosphere` (+80 triangles, missing-material error и ground
warning). Это **ошибка harness/import artifact**, а не костюма. Исходные FAIL и
кадры сохранены в [results-initial](results-initial/summary.json), stdout —
[blender-initial.log](blender-initial.log). Единственный корректирующий запуск
выбирал ровно три исходных node/mesh имени из GLB, исключая Icosphere. Повтор был
нужен из-за влияния сферы на общие floating/ground проверки. QA-код не менялся.

## Разбор всех error-категорий

| Raw errors | Street | Sport candidate1 | Классификация и предел вывода |
|---|---:|---:|---|
| zero-area UV, ModularHair | 778 faces | 332 faces | Метрика подтверждена QA; назначение каждого hair cap/island не установлено. Не объявлено дефектом причёски и не разрешено исправление UV. Нужна адресная диагностика только при симптоме в Godot. |
| zero-area UV, ModularCostume | 177 faces | 899 faces | Подтверждены статическим чтением GLB: street primitive 4 имеет одну UV-точку на 177 triangles; sport primitives 4/5 — одну точку на 76+823 triangles. Это процедурная однотонная отделка, **ожидаемая постоянная UV**, не доказанная ошибка atlas. |
| zero-area UV, Face | 2 faces | 2 faces | Общая исходная геометрия лица; метрика реальна, видимый дефект не подтверждён. Оставлено на адресную проверку, никаких изменений лица. |
| degenerate faces, ModularHair | 2 faces | 2 faces | В GLB есть те же два **ненулевых**, но очень малых треугольника: площадь около 1,23e-11 м² при пороге QA 1e-10. Это подтверждённый геометрический факт, не установленный видимый баг. |
| degenerate faces, ModularCostume | 0 | 1 face | Sport Accent primitive5, triangle 562, площадь 2,85e-11 м²: малый угол clipped trim. Подтверждено GLB, влияние на картинку не доказано. |
| z-fighting: Hair / Face / Costume / Hair↔Costume / Hair↔Face | 187 / 66 / 32 / 35 / 20 pairs | 146 / 66 / 86 / 20 / 20 pairs | Пять error-сообщений на каждый ансамбль. Эвристика параллельных близких треугольников с eps=1 мм; **реальное мерцание не подтверждено**. Hair cards, outline/pass и body/cloth слои могут попадать в этот поиск. Нужны соответствующий материал и runtime view перед заключением. |

Итого street: 3 UV-сообщения + 1 degenerate + 5 z-fighting = **9 errors**;
sport: 3 UV + 2 degenerate + 5 z-fighting = **10**. Никакие категории не сняты
из raw-результата ради PASS. [Статическая проверка GLB](exports/glb-static-inventory.json)
и [координаты малых треугольников](exports/glb-degenerate-audit.json) сохранены.

Все 9 warnings каждого ансамбля: три UV overlap, три duplicate vertices,
три back-to-back face сообщения (Hair/Costume/Face). Split UV/normal seams,
зеркальные/сложенные UV, открытые края одежды и двусторонние hair cards допустимы;
однако **не каждый конкретный duplicate/overlap автоматически признан намеренным**.
Предложение raw-кода «delete to save tris» в проекте не выполнялось.

Nonmanifold edges, inconsistent-normal edges, inside-out islands и loose vertices
равны нулю в импортированных мешах. Это локальные метрики, не доказательство
отсутствия дыры: профиль `game` считает boundary edges, но не делает их FAIL.
Число costume boundary edges: street 3035, sport 5173. Они включают разрезы и швы;
инструмент не отличает нужную горловину от неверной.

У импортированных skinned Costume/Face нет unweighted vertices и >4 influences;
максимум соответственно 4/3. Hair жёстко привязан к кости и не имеет Armature
modifier: его нулевое число vertex weights не означает потерю привязки. **Кейс
допустимых проектом 8 weights здесь не испытан**; hardcoded QA-ошибку >4 нельзя
переносить на остальные модели как баг. Движение/деформация rig не проверялись.

## Известный реальный дефект и пропуск инструмента

В снимке sport candidate1 добавлены 120 вершин воротника, но 40 новых треугольников
не попали в INDEX. Источник и GLB сохраняют этот признак: Top street 1743 vertices /
6906 indices, sport 1863 / 6906; неиспользуемых Top vertices 411 и 531.
Это **реальный известный дефект candidate1**, подтверждённый inventory/INDEX,
а не новый дефект текущего исправленного sport.

Blender glTF importer отбросил все неиспользуемые вершины. Costume street:
8371→6314 vertices (−2057), sport 10657→8051 (−2606); разности точно равны
unused counts из skin+top. QA получил `loose_verts: 0` и **не обнаружил отсутствие
треугольников воротника как таковое**. Прочие исходные unused skin/top vertices
сами по себе не баг: они остались после намеренного скрытия/clip.
[GLB INDEX audit](exports/glb-index-audit.json),
[Godot inventory](exports/export-inventory.json),
[Blender street inventory](results/street/import-inventory.json),
[Blender sport inventory](results/sport/import-inventory.json).

Sol лично просмотрел четыре финальных random/wire sheets и четыре neck closeups.
В [sport front](results/sport/neck-front.png) и
[sport angle](results/sport/neck-angle.png) хорошо виден открытый зубчатый край
вместо законченного воротника. Автоматический raw его не локализует.
[Street front](results/street/neck-front.png) и
[street angle](results/street/neck-angle.png) служат сравнением; видимые в
Workbench границы/углы не объявлены новой runtime-регрессией принятого street.

[Random street](results/street/random-sheet.png) и
[random sport](results/sport/random-sheet.png) полезны для общей формы и
разделения объектов. Полный кадр слишком мелок для надёжной оценки горловины.
[Wire street](results/street/wire-sheet.png) и
[wire sport](results/sport/wire-sheet.png) имеют длинные иглы даже на frozen
evaluated render copies: upstream создаёт геометрию WIREFRAME modifier толщиной
0,006×radius. Эти иглы отсутствуют на solid/random кадрах и не доказывают
геометрические иглы модели. Точный механизм удлинений не расследован;
wire-изображения сохранены с этим ограничением, новых прогонов нет.

## Что применять в проекте

Навык полезен как **дополнительный структурный список подозрительных мест и
генератор обзорных кадров**. Полезные реальные измерения: треугольники, маленькие
грани, UV, веса, material slots и нормали. Он не дал надёжного автоматического
критерия готовности наших VRM-костюмов; внешний raw FAIL нельзя приравнять к
списку подтверждённых игровых багов или обойти молчаливым whitelist.

Для нашей конкретной ошибки нужен Godot/source INDEX inventory до импорта,
плюс крупные планы фактической модели в Godot. В GLB **нет images**: собственный
Godot MToon ShaderMaterial передаётся неполно. Здесь не проверены реальные
atlas/alpha/culling, палитра, освещение, z-fighting в движении, cloth GPU,
анимация, экстремальные позы, матч и физика. Bone/rest/UV/source rig не исправлялись;
сохранённые .blend — только диагностические импортные копии.

## Воспроизведение и архив

Все входные GLB, исходные snapshot .res, upstream scripts/лицензия, harness,
raw первоначального и финального запусков, .blend-копии и PNG лежат в этой папке.
[evidence-sha256.json](evidence-sha256.json) фиксирует SHA доказательств.
Скрипты используют `/tmp/orbstrike-blender-asset-qa-pilot`: для повторного анализа
достаточно скопировать содержимое этой папки туда. **Не запускать повторно без
причины**; приведённая команда — журнал уже выполненного запуска:

```bash
timeout --signal=TERM --kill-after=5s 180s blender --background -noaudio --factory-startup --disable-autoexec --python-exit-code 1 --python /tmp/orbstrike-blender-asset-qa-pilot/run_pilot.py > /tmp/orbstrike-blender-asset-qa-pilot/blender.log 2>&1
```

`--factory-startup` применялся только в отдельном background-процессе; save_userpref
не вызывался. Фактические GLB можно проверить без движка:

```bash
python3 /tmp/orbstrike-blender-asset-qa-pilot/inspect_glb.py
```

[export_avatars.gd](export_avatars.gd) сохранён для происхождения. Его запуск
на нынешнем проекте использует нынешние зависимости VrmAvatar; **побайтовая
воспроизводимость зафиксированного случая обеспечена архивными GLB**, не обещана
повторной сборкой после изменения проекта. Экспортная команда была:

```bash
env XDG_CONFIG_HOME=/tmp/orbstrike-blender-asset-qa-pilot/config XDG_DATA_HOME=/tmp/orbstrike-blender-asset-qa-pilot/data godot --headless --path /home/loq/Документы/game/sfery_stikhiy --log-file /tmp/orbstrike-blender-asset-qa-pilot/export-engine.log -s /tmp/orbstrike-blender-asset-qa-pilot/export_avatars.gd
```

Сервер, пользовательская Blender-сцена, HairMesh, .codex, исходные GLB и модели
не менялись; новых пакетов, выпуска, Windows-проверки и полного набора тестов нет.
