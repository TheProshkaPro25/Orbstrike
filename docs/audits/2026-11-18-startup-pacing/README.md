# Ранний лимит кадров — 18 ноября 2026

Исправлен поздний момент применения FPS/VSync в обычном запуске клиента.
Раньше `project.godot` не задавал `application/run/max_fps`, Boot не применял
pacing, а `GraphicsSettings.load_settings()` только читал значение. Первый
`apply_world()` наступал после подготовки каталога. На высокочастотном мониторе
VSync сам по себе не ограничивает этот этап до пользовательских 60 кадров.
Сохранённый VSync off тоже восстанавливался только позднее, а не до каталога.

Теперь `run/max_fps=60` задаёт исходное значение до main scene, а первая строка
Boot `_ready()` применяет сохранённые FPS/VSync через `apply_frame_pacing()`.
Пользовательские 0/90/120/144 и выключенный VSync сохраняются. Новый helper
не вызывает world/atlas/viewport/quality setters; обычный `apply_world()`
использует его же. Чтение настроек остаётся ленивым и кешируется статическими
полями. Тест не доказывает сокращение времени Boot, watts или GPU time.

## Узкая проверка Sol high

Godot `4.7.2.stable.arch_linux.ed1daf0bf`, headless, обязательный CLI cap 60.
[Тест](pacing.gd), [полный маленький лог](run.log): **63/0, exit 0**, 5.02 с,
без SCRIPT ERROR/ERROR/утечек. Настройки изолированы через XDG. Фактически
исполняется настоящий Boot `_ready()`, но `_load_game()` заменён пустой
пробой: каталог, Main, сервер и GPU не запускаются.

Проверены все FPS_OPTIONS и invalid 17 → 60, восстановление VSync off в
настройках до каталога, сохранение HIGH, отсутствие повторной записи cfg,
отсутствие GameLoading, headless entry point стандартной test_window обёртки.
Значения 0/90/120/144 проверяются синхронно; перед любым yield возвращается60.
После первой пробы62/0 уточнён fixture: перед wrapper теперь явно применяется0,
чтобы проверить его синхронное перекрытие60. Production после62/0 не менялся.
Графический callback обёртки не запускался: его восстановление60 перед
`force_draw()` подтверждено чтением `tools/test_window.gd`, а не новым GPU
прогоном. `git diff --check` трёх затронутых production файлов чистый.
Независимый Sol high прочёл production diff и fixture; дефектов в раннем
применении сохранённых0/highFPS/VSync off и кешировании настроек не найдено.

Воспроизведение из корня (каждый frame остаётся60, пользовательский cfg не
затрагивается; свежий лог не перезаписывает сохранённый выше):

```sh
mkdir -p build/startup-pacing-20261118
XDG_CONFIG_HOME="$PWD/build/startup-pacing-20261118/config" \
XDG_DATA_HOME="$PWD/build/startup-pacing-20261118/data" \
godot --headless --max-fps 60 --path . \
  --log-file "$PWD/build/startup-pacing-20261118/engine.log" \
  -s res://docs/audits/2026-11-18-startup-pacing/pacing.gd \
  > build/startup-pacing-20261118/run.log 2>&1
```

## Сверка с официальными исходниками Godot

Установленный engine commit — `ed1daf0bf001b61586d9930840f2f1394092c079`.
Читались официальные raw C++ этого hash через web, не только текущая документация:

- [main.cpp L2119–2126](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/main/main.cpp#L2119-L2126):
  исходный max_fps default0, CLI перекрывает project setting на старте.
  Runtime Engine setter позже может изменить CLI value — прежний apply_world
  делал то же самое. Никакой per-platform override cap в проекте нет.
- [os.cpp L655–701](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/os/os.cpp#L655-L701):
  max_fps добавляет delay один раз на main-loop iteration. `force_draw()`
  внутри callback не получает отдельного FPS budget.
- [main.cpp L4705–4721](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/main/main.cpp#L4705-L4721):
  low_processor_mode лишь проверяет `has_changed()`. MenuCity меняет shaders,
  env и transforms каждый кадр, поэтому глобальный low mode не является
  подтверждённым ускорением. Остановка этих анимаций меняет видимое поведение.
- [renderer_viewport.cpp L741–775](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_viewport.cpp#L741-L775):
  ALWAYS/ONCE делают viewport видимым для draw, DISABLED пропускается.
  Уже существующий PreviewActivity выключает скрытые preview; FighterPortrait
  использует ONCE для статичного standby и ALWAYS для animated materials.
  Boot warm callback нужен только minimized, отсоединяется до меню и не
  подключается при test wrapper. Нет нового доказательства лишнего ordinary
  menu viewport или повторного GPU прохода за main iteration.
- [Engine.max_fps](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-fps):
  VSync ограничивает по refresh rate, cap0 означает без лимита; это не
  измерение конкретного окна/платформы.

До `_ready()` остаётся исходный cap60, включая выбор0/highFPS; он не обещает
ограничить длительность синхронной загрузки или отдельный engine splash draw.
Фактические presentation/VSync/high-Hz, обычный Boot и energy не измерялись.
Windows/слабая GPU, полный матч, EXE/PCK, публикация/прослушивание не проверялись.
