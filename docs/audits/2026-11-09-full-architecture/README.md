# Завершение архитектурного плана — 9 ноября 2026

Завершён оговорённый план: режимы, взаимодействие, presentation/Director и типизированные запросы выделены вслед за MatchResources/MatchLifecycle. Это продолжение [ресурсного этапа](../2026-11-08-match-lifecycle-completion/README.md), а не выпуск. Main стал composition root с явным wiring и тонкими адаптерами существующих инструментов/наследника online: **2507 → 1200 строк** относительно сохранённого `build/checks/architecture-full-before/main.gd`. Это уменьшение ответственности и размера файла; ускорение FPS/RAM не заявляется.

## Границы и единственные владельцы

| Область | Владелец | Контракт |
|---|---|---|
| Актёры, active/reserve, arena, fallback | [MatchResources](../../../scenes/match_resources.gd) | Типизированный ActorResult; activate/retire tickets, revision+serial, terminal release. Resident missing не создаёт модель. |
| Prepare → intro → play → finish/fail/release | [MatchLifecycle](../../../scenes/match_lifecycle.gd) | Единая offline stage authority; отмена, rollback и восстановление UI через наблюдателей. |
| Обычный режим, турнир, кампания, карьера | [GameModes](../../../scenes/modes/game_modes.gd) | Владеет mode/fixture/registration и панелями, persistence/result/entry/restart/exit. Передаёт MatchSpec и принимает явный accepted/rejected. |
| Выбор, подтверждение, target, ожидание/полёт | [InteractionController](../../../scenes/interaction/interaction_controller.gd) | Явные состояния, единственные pending/gate/target данные. STOPPED терминален до bind_controller; поздний request/cancel не оживляет ввод. |
| Видимые события, FX, портреты, tooltip/result | [MatchPresentation](../../../scenes/presentation/match_presentation.gd) | Конкретные зависимости и сигналы, собственное presentation state; не владеет правилами/режимом/lease. |
| Постановка/размещение/физический бросок | [ArenaDirector](../../../scenes/presentation/arena_director.gd) | Конкретные Resources/State/world/camera/UI; сигналы вместо обратного указателя game/Main. |
| Сборка графа и соединение компонентов | [Main](../../../scenes/main.gd) | Создаёт мир/UI/controller/AI, передаёт зависимости, соединяет публичные порты и навигацию. Совместимые старые свойства делегируют владельцам. |

Новые компоненты не получают Main и не вызывают `game._private`. Старые адаптеры Main не содержат копии решений, реестров или жизненного цикла. Ссылка на controller передаётся явно; допустимость действий остаётся у MatchController, сила — PowerCalc. Display flags Presenter и UI request handshake Modes не заменяют lifecycle stage. Сетевой snapshot state остаётся отдельным клиентским fallback, без изменения online-протокола.

Типизированы [InteractionRequest](../../../scenes/interaction/interaction_request.gd), [CardAction](../../../scenes/interaction/card_action.gd), [AbilityTarget](../../../scenes/interaction/ability_target.gd), [GateThrowSelection](../../../scenes/interaction/gate_throw_selection.gd), [InteractionView](../../../scenes/interaction/interaction_view.gd), [MatchSpec](../../../scenes/modes/match_spec.gd), ModeResult и критичные uid→definition/owner/actor/card dictionaries. Legacy Dictionary преобразуется на краю. MatchSpec используется один раз: обычный RNG не делает второй выбор соперника/seed. AI target DTO принимает метаданные `label`, но в core передаёт только семантический target.

## Сохранённое поведение и исправления интеграции

- Boot/resident 49×2, три арены, шесть арендованных актёров; финальные counts **1/98/3/4/158**. Production после меню не возвращает GLB/setup/cloth; standalone fallback остаётся у owner.
- EventPlayer сохраняет последовательность. Director сохраняет физический полёт, фактический settled point и hold_landing_pose без переноса шара в центр. Intro/FX/редкие controller events перенесены с прежним порядком awaited действий.
- GameModes сохраняет регистрацию/cancel/backup, стороны/first-side, league arenas, campaign AI preferences, career power snapshots, result/reward-once, повтор/выход и failure без ложного результата. Атомарный отказ арены возвращает подпись фактически сохранённой арены.
- Cancel target возвращает исходный pre_throw/after_landing/battle момент; compound gate throw сохраняет порядок аргументов. Late request после stop отбрасывается.
- Shared online client получает отдельную [OnlineHelpPolicy](../../../scenes/presentation/online_help_policy.gd), сохраняющую own/opponent подсказки и seat1 mapping без Main backpointer; смена snapshot инвалидирует tooltip cache. Сервер не запускался и не менялся.
- Fixtures, раньше напрямую меняющие Main/Director internals, переведены на явные component ports. В ModelLifetime пустые deferred releases пропускаются, непустые используют уникальные closures: освобождение нескольких shared-material копий не создаёт duplicate connection.

## Проверки и воспроизводимые артефакты

Все графические проверки выполнены через `tools/check.py`/`tools/test_window.gd`: minimized, unfocusable, offscreen, **60FPS**; Linux, RTX4070 Laptop, Vulkan/Forward+. Headless указан отдельно и не выдаётся за графическую приёмку. Указано время wrapper из summary, не FPS.

| Проверка | Результат | Время | Summary |
|---|---:|---:|---|
| Финальный autoplay | PASS, exit0/ERROR0 | 129.71с | [autoplay/lifecycle](../../../build/checks/gameplay/selected-autoplay-match-lifecycle/summary.json) |
| Финальный match-lifecycle | 109/0, exit0/ERROR0 | 42.21с | тот же summary |
| architecture-contracts, headless | 19/0, exit0/ERROR0 | 6.08с | [summary](../../../build/checks/gameplay/selected-architecture-contracts/summary.json) |
| ai-target-flow, headless | 220/0, exit0/ERROR0 | 4.41с | [summary](../../../build/checks/gameplay/selected-ai-target-flow/summary.json) |
| optimization GPU | 167/0, exit0/ERROR0 | 8.61с | [UI summary](../../../build/checks/presentation/selected-optimization-card-hover-battle-ui-followup/summary.json) |
| card-hover GPU | 401/0, exit0/ERROR0 | 18.06с | тот же summary |
| battle-ui-followup GPU | 58/0, exit0/ERROR0 | 13.10с | тот же summary |
| match-keyboard, headless | 225/0, exit0/ERROR0 | 22.74с | [summary](../../../build/checks/presentation/selected-match-keyboard-match-keyboard-combo/summary.json) |
| match-keyboard-combo, headless | 54/0, exit0/ERROR0 | 11.09с | тот же summary |
| campaign-flow GPU | 49/0, exit0/ERROR0 | 87.58с | [mode summary](../../../build/checks/gameplay/selected-campaign-flow-tournament-flow-career-flow-autoplay/summary.json) |
| tournament-flow GPU | 49/0, exit0/ERROR0 | 103.81с | тот же summary |
| career-flow GPU | 54/0, exit0/ERROR0 | 77.03с | тот же summary |

Финальный autoplay: **два полных физических матча, 13/12 ходов, 9 боёв, 19 бросков = 18 попаданий + 1 физический промах**, настоящий restart/reuse. Финальный lifecycle покрывает prepare/intro/start/finish/restart/exit, partial/fallback cancellation, terminal release, stale retirement, resident activation error и обычный/турнирный recovery. Контрактный стенд проверяет typed requests/commands/targets, STOPPED, target cancel, RNG once, shared materials и отсутствие backpointer/решений в root. AI220 использует настоящие core target descriptors для обеих сторон и двух сложностей.

**Хронология:** mode flows выполнялись после извлечения компонентов, campaign/tournament — до последних type/schema уточнений. Они не выдаются за повторный прогон самого последнего исходника. После уточнений выполнены финальные autoplay/lifecycle, contracts19, AI220 и UI167/401/58; затронутые target/cancel paths покрыты ими. Успешные mode scenarios без новой mode-логики не повторялись.

Промежуточные ошибки сохранены: первый autoplay в mode summary имеет FAIL/exit-15 после ошибочного отклонения target с `label`; исправлено DTO, затем новый autoplay и AI-flow чистые. Первый AI fixture имел deferred-focus cleanup ERROR после успешных assertions — сохранён в `selected-ai-target-flow/initial-fixture-cleanup/`, исправлен queue_free, финальный прогон чистый. Ранние fixture `.dismiss()`/shared-material callback ошибки также исправлены и keyboard повторён чисто. Исторические FAIL не заменены итоговыми PASS.

Sol лично просмотрел 8 итоговых PNG: [полная карта](../../../build/checks/presentation/selected-optimization-card-hover-battle-ui-followup/optimization/full-card.png), [classic960](../../../build/checks/presentation/selected-optimization-card-hover-battle-ui-followup/card-hover/classic-960-true.png), [device1280](../../../build/checks/presentation/selected-optimization-card-hover-battle-ui-followup/card-hover/device-1280-true.png), [видимая runtime ошибка](../../../build/checks/gameplay/selected-autoplay-match-lifecycle/match-lifecycle/activation-failure.png), [campaign result](../../../build/checks/campaign-flow/05-result.png), [tournament return](../../../build/checks/tournament-flow/06-hub-after-result.png), [career reward/result](../../../build/checks/gameplay/selected-campaign-flow-tournament-flow-career-flow-autoplay/career-flow/02-career-result.png), [бросок](../../../build/checks/vrm-fighter/match-throw.png). Проверены наличие/читаемость состояния, подсказки/карт/результата и recovery; это scoped просмотр, не новая полная художественная приёмка. Розовые тестовые портреты в изолированном card-hover fixture не являются портретами production матча.

Независимый финальный **Sol high read-only review PASS**, без существенных незакрытых замечаний: чужой автор проверил root composition, owners/guards, mode mapping/RNG/persistence, interaction и presentation, исходники и свежие артефакты. Дополнительно авторы модулей перекрёстно проверили чужие области. Reviewer не запускал дублирующие тесты.

## Границы результата

Закрыт весь перечисленный архитектурный scope, а не весь backlog игры и не требование абсолютной идеальной архитектуры. Main сохраняет сборку мира/UI, сигнальный wiring и тонкие совместимые adapters; дальнейшее дробление без отдельной задачи не требуется. core/правила, PowerCalc/EventPlayer, 49GLB и качество сохранены; весь прежний dirty оставлен. Сервер, .codex, Tracy, новая сборка и публикация не затрагивались. Windows/пакет, полноценная online runtime сессия, субъективное прослушивание и общий FPS/RAM прирост этим этапом не подтверждались. Версия/публичный пакет 0.4.2.6 прежние.
