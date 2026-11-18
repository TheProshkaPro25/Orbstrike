# Статическая проверка render/compute data flow

Проверена текущая грязная рабочая копия клиента, без изменения production.
Новый Godot для этой части не запускался. Точные SHA входов и арифметика —
[grid-output-accounting.json](grid-output-accounting.json), воспроизводимый
read-only расчёт — [count_grid_output.py](count_grid_output.py).

## Новая конкретная работа без потребителя: нормали grid-плаща

Для всех шести нынешних Ратников `CreatureModels.uses_ratnik_trellis()`
выбирает общую модель Trellis (`scenes/creature_models.gd:115–128`).
`CreatureCloth.attach()` использует для неё `output_skin_delta=true` и
решётку вместо полной сетки плаща (`scenes/creature_cloth.gd:147–153`).

Отображаемый плащ получает shader `GRID_VERTEX`: четыре выборки из
`positions_tex` и добавление смещения к исходному `VERTEX`.
Этот vertex hook не присваивает `NORMAL` и не объявляет `normals_tex` или
`welded_index_tex` (`scenes/creature_cloth.gd:27–49`). Поэтому его освещение
использует штатные нормали исходного skinned mesh; последующий `fragment()`
меняет только знак NORMAL обратной стороны (`scenes/creature_models.gd:83`).
Это описание нынешней подачи, а не предложение изменить её освещение.

`_apply_grid()` связывает только позиции, размер решётки и transform
(`scenes/creature_cloth.gd:210–232`). Owner-rim получает тот же grid hook
и `GRID_PARAMETERS` (`scenes/creature_cloth.gd:60–78`), поэтому также не
читает вычисленные нормали. Shader полного substrate прикреплён к
`CapeSimulationMesh`, но этот proxy имеет `layers=0` и `cast_shadow=OFF`
(`scenes/creature_cloth.gd:198–206`). Он создаётся внутри `CreatureAnim.set_model`
после прохода назначения figure light layer в `CreatureBall.setup`
(`scenes/creature_ball.gd:238–250`), а `_set_rim` пропускает mesh с нулевыми
layers (`scenes/creature_ball.gd:315–320`).

Несмотря на это, `_dispatch_output_passes()` безусловно делает:

1. `cloth_normals.glsl` — face normals в `_face_normals_buffer`, затем barrier;
2. `cloth_output.glsl` — необходимые позиции, а затем сбор и нормализацию
   normals по adjacency и запись в `_normals_img_rid`.

Ветка `output_skin_delta` меняет только позиции; нормали не отключает.
Вызов есть и при normal update, и при warm start
(`addons/godot_gpu_cloth/src/gpu_cloth_solver.gd:1739,2027,2032–2048`;
`addons/godot_gpu_cloth/shaders/compute/cloth_output.glsl:36–51`).
Это адресная неэффективность интеграции общего solver с новым grid renderer,
не установленное ограничение Godot 4.7.2 и не доказательство, что именно
она определяет общий FPS.

## Количество работы и storage

`cape_grid.tres` задаёт 21×27 узлов: **567 частиц, 1040 треугольников,
3120 adjacency entries**. Текущий генератор mesh и assert подтверждают
эту размерность. Прежний графический лог от 18 ноября независимо содержит
те же размеры, 567×1 output и lookup. Он использован только как историческое
свидетельство размерности, а не новый запуск/результат производительности:
`build/render-diagnostic-20261118/runner/match-bottleneck.log:7–21`,
SHA-256 `19b9df630efc8038d91fdc5f1be1bb4af46eb2ded262603d0a747f3a2c131285`.

На каждый активный update такого плаща:

| Работа | Количество |
|---|---:|
| Лишний normal dispatch | 1, 17 групп по 64 потока |
| Рабочие normal shader invocations, исключая padding | 1040 |
| Лишний barrier между normals/output | 1 |
| Normal gathers внутри необходимого position-output dispatch | 567 |
| Слагаемые face normals по adjacency | 3120 |
| Ненужные логические vec4 записи face normals + normal image | 16 640 + 9 072 = **25 712 байт/update** |

Position-output dispatch остаётся нужен: 9 групп по 64. При будущем отдельном
position-only output его нельзя просто удалить вместе с normal pass.
Эти числа — операции и payload, **не измеренные миллисекунды, bandwidth
DRAM или обещанный выигрыш FPS**. Один update не равен одной отрисовке:
solver работает на process callback, а отрисовка viewport имеет свой цикл.

Объявленные ресурсы без потребителя grid renderer:

| Storage | Логические байты |
|---|---:|
| Face normals, mutable на один solver | 16 640 |
| Normal RGBA32F texture 567×1, на один solver | 9 072 |
| Welded-index RGBA32F lookup 567×1, на один solver | 9 072 |
| Итого перечисленных instance payload | **34 784** |
| Indices 1040×3×u32 | 12 480 |
| Adjacency counts/offsets, по 567×u32 | 2 268 + 2 268 |
| Adjacency list 3120×u32 | 12 480 |
| Итого перечисленных immutable payload на unique content set | **29 496** |

Последние четыре ресурса объединяются `resident_cloth_solver` по content
hash и refs; умножать их на число актёров нельзя. Индексы также нужны
optional peer/self collision, если этот режим включить. Стандартный
`CreatureCloth.attach()` peers/self collision не включает. Для будущей
оптимизации нужен явный mode contract, а не глобальное удаление индексов.
Здесь не посчитаны alignment, descriptor/pipeline/driver overhead или
полный объём GPU cloth.

## Проверка других потребителей и жизненного цикла

- Полный non-grid `GPU_VERTEX`, vendor `cloth_surface*.gdshader` действительно
  читают normals/lookup. Для этого пути normal output обязателен; вывод
  относится только к нынешнему Trellis GridVertex.
- `_debug_readback()` читает позиции/скорости; wireframe, velocity и collider
  debug строятся из них/CPU данных (`gpu_cloth_solver.gd:3302–3310`).
  Normal texture/face-normal buffer debug не читает.
- Fallback `CreaturePortrait._collect()` способен добавить portrait layer
  даже proxy mesh, но для всех шести нынешних Ratnik ID существует заранее
  загруженная `RENDERED_TEXTURES`; `_can_render()` требует отсутствие такого
  изображения (`scenes/ui/creature_portrait.gd:50–55,239–240`). Этот редкий
  общий fallback не является текущим Ratnik render path; будущие новые ID
  должны учитывать нулевые layers при добавлении portrait layer.
- Resident catalog viewport после Boot — UPDATE_DISABLED;
  `_park_ball()` скрывает actor и ставит PROCESS_MODE_DISABLED. Сохранённые
  GPU буферы сами по себе не доказывают постоянный compute скрытого каталога
  (`scenes/loading/game_loading.gd:154,334–354`).
- Preview `show_card`, `show_hint`, `release` возвращают actor; открытие
  выбора арены **сначала** вызывает `_preview.release()`
  (`scenes/ui/creature_preview.gd:291–297,329–340,383–389`;
  `scenes/ui/team_menu.gd:1026–1033`). Подозрение о невидимом compute под
  arena picker снято после полного чтения текущего кода.
- Полноэкранные редакторы приостанавливают processing MenuCity и выключают
  root 3D, сохраняя их собственные SubViewport
  (`scenes/menu/main_menu.gd:420–450`). Старое исправление подтверждено
  чтением кода, заново его GPU выигрыш не измерялся.
- Solver проверяет только `mesh.is_visible_in_tree()`, затем пакует collider
  triangles и ставит compute в main RenderingDevice через render-thread
  callback (`gpu_cloth_solver.gd:589–612,1750–1757,1844–1846`). Уход камеры,
  cull mask или остановка viewport draw сами не останавливают эту ветку.
  Это граница измерений/возможный кандидат для culling, а не доказанный баг:
  off-camera cloth может сохранять непрерывность симуляции и видимые тени.
  Отсечение требует знания всех камер и света; для grid proxy с layers=0
  проверять его видимость камерой бессмысленно — потребителем служит другой mesh.
- В `resident_cloth_solver` mutable output/poses/colliders принадлежат actor,
  а immutable buffers объединяются по SHA; reparent сбрасывает warm start,
  не освобождая GPU ресурсы, cleanup выполняется только при PREDELETE.
  Новая утечка из этого кода не установлена.

## Узкий следующий шаг

Отдельный output mode **position-only-grid**, оставив общий non-grid путь
неизменным. Он может не создавать normals shader/pipeline/face/adjacency/
normal image/lookup и сохранять нужный position output. Не привязывать
это автоматически к `output_skin_delta`: delta-потребитель в будущем может
потребовать нормали или другой lookup.

Перед внедрением необходимы парные снимки/позиции и силуэт grid-плаща
при standby/выходе/броске/атаке, owner rim/flash, сохранение фактической
landing pose, а также проверка **всех** затронутых правил аренды/возврата,
reparent/warm start и refcounts immutable GPU sharing. После этого — один
узкий измеренный cloth A/B с GPU timestamps вокруг custom compute,
отдельно от viewport timings. Здесь выполнена только диагностика.
