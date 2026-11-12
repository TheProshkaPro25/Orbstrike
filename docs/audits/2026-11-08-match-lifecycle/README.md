> Дополнение по следующему поручению автора: оставшиеся actor transfers/state authority
> и mode-flow проверки завершены в [отдельном этапе](../2026-11-08-match-lifecycle-completion/README.md).
> Ниже сохранён исходный отчёт и его тогдашние границы76/0.

# Жизненный цикл матча и владение арендой — 8 ноября 2026

По разрешению автора выделены две самостоятельные обязанности из main.gd.
Это рефакторинг с сохранением обычного игрового пути и исправлением отказов старта,
а не замер ускорения или новый выпуск. Прежние Delta/intro/career, оптимизации и
остальной незакоммиченный код сохранены.

## Границы

- [MatchResources](../../../scenes/match_resources.gd) получает явно world, каталог,
  registries активных/резервных существ, героев и времён, PackedScene для изолированного
  пути. Он арендует шесть существ и двух героев, выбирает арену, возвращает частичную
  аренду при отказе и освобождает всю аренду при выходе. Замена арены сначала получает
  новую: отказ сохраняет прежнюю. Повторный release безопасен; дубликат актёра в двух
  registries возвращается один раз. GameLoading продолжает владеть резидентным каталогом.
- [MatchLifecycle](../../../scenes/match_lifecycle.gd) получает этот lease, CameraRig
  и CanvasLayer. Он владеет SELECTING→PREPARING→INTRO→PLAYING→FINISHED→RELEASED,
  скрытием/восстановлением прежних видимых Controls, созданием LocationIntro, ожиданием
  его завершения и единственным ctrl.start после интро. Generation/revision отменяют
  позднее продолжение после release, включая синхронный release из prepared subscriber.
- [MatchStartResult](../../../scenes/match_start_result.gd) передаёт код Error и
  сообщение: вызывающая сторона видит успех, отказ или отмену явно.
- Main остаётся точкой сборки Controller/AI, правил/сигналов, пользовательских
  профилей и roster/HUD/portrait presentation. prepared/started — узкие сигналы
  координатора; ни один новый компонент не получает game/self Main и не вызывает
  его внутренние методы. Старые registries сохранены как общие ссылки с presentation,
  чтобы перенос active↔reserve и существующие инструменты не меняли семантику.
  Подключения UI теперь однократны на сцену; callbacks текущей арены подключаются
  отдельно. Смена арены не оставляет hover callback на прежнем экземпляре.

## Отказы

Раньше null take_ball делал return после скрытия UI и оставлял уже выданных героев/
существ в сцене. Теперь отказ возвращает partial lease, восстанавливает controls,
сбрасывает незапущенные controller/AI и показывает объяснение в выборе команды или
на турнирном табло. Повторная попытка в той же сцене не дублирует подключения ввода.
Турнир сохраняет in_progress для прежней встречи: begin_match уже идемпотентен.

При недоступности арены обычный picker сохраняет фактическую арену, сохранённый
выбор и подпись кнопки. Турнир/кампания/карьера получают false и видимое сообщение,
не начинают матч на прежней локации. Отмена во время интро или из prepared не
создаёт поздний intro/controller.start после возврата аренды.

Обычный путь с ready_to_play берёт только готовые ресурсы. Fallback setup существует
только для изолированных сцен без готового каталога; он также отменяется на первом
process_frame. После меню production не добавляет GLB/setup/cloth. Startup49×2,
три арены, resident_catalog и штатные GameLoading return/reset сохранены.
В core/ изменений нет; Node/await туда не перенесены. Идентичность mesh/cloth и
сама физика не переписывались.

## Новые проверки

Все GPU-пуски через tools/check.py/test_window, minimized/unfocusable/offscreen,
force_draw(false),60FPS, Godot4.7.2/Linux/Vulkan1.4/Forward+/RTX4070 Laptop.

| Проверка | Итог | Область |
|---|---|---|
| gameplay --checks match-lifecycle | **76/0,exit0,ERROR0,35.75s** | Настоящий Boot, second-fighter/partial-actor failure, UI restore/retry, actual arena-picker rollback, unavailable tournament arena, tournament actor failure/resume, intro/prepared cancellation, repeat release, обычный старт/«Ещё раз»/выход |
| gameplay --checks autoplay | **PASS,exit0,ERROR0,123.96s** | Два настоящих физических матча и реальный restart:17/10ходов,8боёв,18бросков,17попаданий и1физическийпромах |
| check-only / Python / diff | PASS | Godot parse Main/нового стенда, py_compile check.py, git diff --check |

Каталог в scoped сценарии остался **1/98/3/4/158**: preparation/creatures/arenas/
fighters/audio paths. После rollback/exit нет actor leases; четыре героя и три арены
возвращены. Резерв проверен по uid, коллайдеру, видимости/process_mode; после
restart актёры принадлежат исходному каталогу и соответствуют тем же определениям.
Внутри отдельно выделенного fixture без resident catalog cancellation достигает
первого await до ball.setup, освобождает двух fallback-героев и не продолжает setup.
Этот намеренный изолированный constructor test не является игровым путём после меню.

Autoplay выполнен после переноса основной цепи, до последних guard-поправок только
отказных/cancellation ветвей; нормальные ветви после него не менялись. Последний
76/0 выполнен после всех production-правок. Полные профили не запускались и прежние
успешные model/portrait/UI тесты автоматически не повторялись.

Sol лично просмотрел5финальныхPNG: два отказа обычного старта, интро после retry,
возвращённое турнирное табло и HUD после restart. Сообщения читаются, UI возвращён;
интро сохраняет прежнюю постановку. Художественная переоценка всех FX/моделей и
всего меню этим переносом не заявляется.

## Артефакты и review

- [Финальный scoped summary](../../../build/checks/gameplay/selected-match-lifecycle/summary.json),
  [result](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/result.json),
  [log](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle.log).
- [Autoplay summary](../../../build/checks/gameplay/selected-autoplay/summary.json),
  [полный output](../../../build/checks/gameplay/selected-autoplay/autoplay.log).
- [Failure hero](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/fighter-failure.png),
  [failure creature](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/actor-failure.png),
  [intro](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/retry-intro.png),
  [tournament](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/tournament-failure.png),
  [restart HUD](../../../build/checks/gameplay/selected-match-lifecycle/match-lifecycle/restart-ready.png).

Финальный независимый Sol high read-only review — **PASS без существенных замечаний**:
проверены итоговый diff, новый76/0log/metrics и лично5финальныхPNG. Reviewer не
повторял запуски. В ходе раннего review выявлены propagation отказа арены в турнир, rollback
подписи picker и reentrant prepared cancellation. Исправления включены в финальный
76/0; fallback cancellation дополнительно проверен по рекомендации reviewer.
Первый53/3 не был production FAIL: fixture захватывала удалённый Node в lambda и
ожидала одинаковые uid→instance при разных случайных соперниках. Исправлены
integer instance capture, фиксированный seed и проверка принадлежности исходному
каталогу/определения. Логи ошибки сохранены в first-fixture-failures; промежуточные
PASS53/0 и66/0 также сохранены отдельно, не подменяют финальную проверку.

Сервер не проверялся/не собирался/не менялся; online client inheritance просмотрен
только по коду. Новый полный career/campaign flow не запускался: их доменные
snapshot/result/first-side пути сохранены; общая турнирная ветвь проверена адресно.
Windows, прослушивание, пакет и публикация не проверялись/не выполнялись.49GLB,
скелеты, качество, .codex и Tracy не затронуты. Версия/публичный0.4.2.6 прежние.
