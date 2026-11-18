# Независимая сверка grid cloth, 18 ноября 2026

Sol high, source-only, без дополнительного Godot/GPU запуска. Проверены
`../2026-11-18-render-resources/static-flow.md` и
`grid-output-accounting.json` против нынешних исходников, а не только против
расчётного скрипта автора. Все 13 записанных SHA совпали с файлами.

Подтверждено:

- `GRID_VERTEX` делает четыре выборки positions и сдвигает VERTEX; не объявляет
  normals_tex/lookup и не пишет NORMAL. `_apply_grid`, `GRID_PARAMETERS` и
  grid owner-rim передают только positions/grid transform. Базовый ANIME
  fragment использует обычный NORMAL и лишь меняет знак на обратной стороне.
- `CapeSimulationMesh` layers=0 и shadow casting OFF; создаётся через
  `CreatureAnim.set_model` после figure light-layer обхода в CreatureBall.setup.
  `_set_rim` пропускает layers=0. Существующие шесть Ratnik portrait PNG
  блокируют fallback viewport через `_can_render`/reference texture.
- `_dispatch_output_passes` безусловно выполняет normals pipeline, barrier,
  затем output. В output `output_skin_delta` меняет позиции, но не отменяет
  adjacency normal gather/imageStore. Прямой потребитель normals отсутствует
  именно в нынешнем grid renderer.
- Общий non-grid GPU_VERTEX и оба vendor cloth_surface shaders действительно
  выбирают normals_tex и welded lookup. Вывод нельзя расширять на весь cloth.
- Независимая арифметика: 21×27=567 particles,20×26×2=1040triangles,
  3120adjacency; ceil(1040/64)=17normal groups,ceil(567/64)=9output groups.
  Логические записи1040×16+567×16=25712байт/update;
  listed instance payload1040×16+567×32=34784байта;
  immutable12480+2268+2268+12480=29496байт/content set.
  Resident sharing относится к immutable buffers; output/normal images и
  welded lookup texture создаются отдельными ресурсами экземпляра.

Замечаний, меняющих основной вывод или числа отчёта, нет. Это установленный
избыточный output path интеграции, а не измеренный выигрыш GPU/FPS. Ограничения
по optional peer/self collision и future portrait fallback в отчёте необходимы
и верны. Проверка не доказывает непрерывный compute скрытого каталога и не
позволяет автоматически отсекать off-camera cloth, влияющий на тени/состояние.
