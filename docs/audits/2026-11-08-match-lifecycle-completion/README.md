# Завершение границы lifecycle/resources — 8 ноября 2026

По поручению «доделай что не доделал доконца» закрыты конкретные остатки предыдущего
[этапа](../2026-11-08-match-lifecycle/README.md). Помимо checkout/release теперь
владелец ресурсов управляет активацией и возвратом актёров во время матча. Закрыт
пробел проверки карьеры/кампании/турнира реальными адресными интеграциями.

## Что дополнено

- MatchResources сам создаёт active/reserve/fighters/timing registries. Main получает
  совместимые ссылки для presentation и инструментов, а не передаёт владельцу свои
  контейнеры. Единственный offline-путь activation — activate(), с ActorResult.
  При отсутствующем resident UID возвращается ERR_DOES_NOT_EXIST: новый GLB/setup
  не скрывает ошибку аренды. Standalone fallback находится только у владельца.
- begin_retire() переносит актёра в резерв до await vanish; finish_retire(ticket)
  сверяет revision, serial и актёра. Старое завершение не выключает новый lease
  или повторно активированного/ещё раз возвращаемого актёра. Остановка presentation
  и сам vanish остаются EventPlayer/Main; владение и park решает MatchResources.
- Terminal release запрещает поздние activate/prepare/select_arena, включая
  standalone fallback. release_match сохраняет возможность повторить отказный старт.
  Вспышка закрытия вызывается после восстановления launch-position, как до переноса.
- Offline _game_over — проекция coordinator stage, отдельного boolean больше нет.
  FINISHING блокирует новый игровой ввод, пока очередь завершает постановку;
  FINISHED закрывает действия через явный signal. released управляет process gate
  сцены. Общий UI cleanup используется и finish, и failed start.
- FAILED — отдельный исход нарушения живой аренды: останавливается очередь,
  возвращаются актёры, видны объяснение, повтор и выход. Это не ничья. Турнирный retry
  сохраняет in_progress и не записывает вымышленный результат. Принять результат
  можно только при настоящем Controller.GAME_OVER. Сетевой клиент продолжает иметь
  свой snapshot-driven boolean: offline coordinator им не управляет.

Новые компоненты не получают game/Main и не вызывают его внутренние методы.
Main сохраняет построение Controller/AI, маршрутизацию режимов и UI/event adapters.
Это завершение конкретной границы владения и жизненного цикла, не переписывание
всей игры. Main **2475→2507 строк**: добавлены явные recovery/UI adapters вместо
молчаливого отказа. Количество строк не выдаётся за сокращение сложности; из Main
убраны все creature instantiate/setup и прямые active↔reserve transfers.
Предэтапный исходник и SHA сохранены в build/checks/lifecycle-completion-before.

## Проверки

Штатные tools/check.py/test_window, minimized/unfocusable/offscreen/60FPS,
Godot4.7.2/Linux/Vulkan1.4/Forward+/RTX4070 Laptop. Пользовательские сохранения
не затронуты: XDG_DATA_HOME направлен в build/checks.

| Выбранный сценарий | Фактический результат | Проверенная область |
|---|---|---|
| match-lifecycle | **109/0,exit0,ERROR0,39.47s** | activate/retire/reactivate/serial, реальный vanish→release→new lease→late finish, resident-missing, fallback/release, finish/input authority, видимая ошибка Main и настоящие обычный/турнирный retry, прежние start/intro/failure/exit |
| campaign-flow | **49/0,exit0,ERROR0,112.78s** | Регистрация, interrupted physical match, сохранение/продолжение той же встречи, полный физический матч, результат→табло→следующая встреча |
| tournament-flow | **49/0,exit0,ERROR0,88.87s** | Тот же реальный interrupted/resume/result/return/next path для турнира |
| career-flow | **52/0,exit0,ERROR0,82.45s** | Создание/регистрация, power snapshot/actor label/cloth identity, полный физический матч, сохранение награды один раз, возврат, следующая лига |

Каталог во всех путях сохранён: preparation1/creatures98/arenas3/fighters4/audio158.
В report старых flow counters идут как1/98/3/158/4 — это другой порядок полей.
Смена кадра/интро не заменена ускоренной подготовкой: стенды ждут ctrl._started и
завершения _preparing до15s wall time, вместо устаревшего ожидания одного кадра.
Обычный матч/restart/exit закрыт последним109/0; ранее успешный двухматчевый autoplay
автоматически не повторялся, поскольку новые физические mode flows исполняют
затронутые transfers/finish/result paths.

Campaign counters охватывают прерванную, завершённую и следующую начатую встречи:
13 выборов существа,11 попаданий,1 промах,1 ещё ожидающий бросок/приземление.
Это не13 завершённых физических бросков одного матча. Полный результат наPNG —
18ходов; в карьерном результате15ходов, в турнирном12. Остальные встречи карьерного
кубка завершены явно обозначенными fixtures для проверки перехода лиги — они не
выдаются за дополнительные физические матчи.

## Сохранённые ошибки стендов

Первый расширенный lifecycle script не распарсился из-за7 неявных типов результата
динамического Main в fixture. Добавлены явные Resources.ActorResult/Retirement;
ошибочный log сохранён в selected-match-lifecycle/completion-parse-failure.
Промежуточный91/0 сохранён отдельно; финальная приёмка —109/0 после всех правок.

Первый campaign-flow остановился на180s ожидании полного матча (wrapper229.37s).
Собственный старый driver не вызывал существующий Autoplay.choose_pending_target:
после открытия AbilityTargetPicker он не мог продолжить игру. Добавлен общий
обработчик, диагностический snapshot/aborted replay и счётчики. Повторён только
failed campaign: финальный PASS обслужил **target_actions=1**, подтвердив эту ветвь.
Первый FAIL не удалён; успешные tournament/career не повторялись.

## Артефакты и независимая проверка

- [Финальные campaign/lifecycle summary](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/summary.json),
  [lifecycle log](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/match-lifecycle.log),
  [lifecycle result](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/match-lifecycle/result.json).
- [Campaign report](../../../build/checks/campaign-flow/report.json),
  [полный campaign log](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/campaign-flow.log).
- [Первый combined summary, включая сохранённый campaign FAIL и два PASS](../../../build/checks/gameplay/selected-campaign-flow-tournament-flow-career-flow/summary.json),
  [career report](../../../build/checks/gameplay/selected-campaign-flow-tournament-flow-career-flow/career-flow/report.json),
  [tournament report](../../../build/checks/tournament-flow/report.json).
- [Ошибка активации с повтором](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/match-lifecycle/activation-failure.png),
  [восстановленный HUD](../../../build/checks/gameplay/selected-campaign-flow-match-lifecycle/match-lifecycle/restart-ready.png),
  [campaign result](../../../build/checks/campaign-flow/05-result.png),
  [career result](../../../build/checks/gameplay/selected-campaign-flow-tournament-flow-career-flow/career-flow/02-career-result.png),
  [tournament result](../../../build/checks/tournament-flow/05-result.png).

Sol лично просмотрел8новыхPNG: остановленный матч/retry, восстановленный HUD,
результаты трёх режимов и их возвратные экраны. Независимый Sol high read-only review
**PASS без существенных замечаний**: итоговый код,109/0, три mode-flow reports и
отдельный просмотр6lifecycle PNG/3result PNG. Его ранние terminal/error замечания
включены в109/0. Новых запусков reviewer не делал. Parse/Python compile/diff-check
пройдены. Массовые профили не выполнялись.

Core/правила,49GLB/скелеты/качество, Boot/resident, сервер и .codex не менялись;
Tracy не включался. Прежний dirty полностью сохранён. Windows, прослушивание,
пакет/выпуск/публикация не заявляются; публичный0.4.2.6 прежний. Этот этап не даёт
новой оценки FPS/RAM и не является полным художественным аудитом всех экранов.
