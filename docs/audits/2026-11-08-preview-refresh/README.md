# Повторные запросы полного preview карты — 8 ноября 2026

Следующий законченный клиентский шаг по поручению «продолжай работу по оптимизации».
Перед изменением измерен реальный путь TeamMenu: наведение, получение фокуса и
нажатие вызывают show_card одной карты трижды. Каждый вызов заново создавал полный
CardView с материалом и заново раскладывал текст. Выбран этот подтверждённый CPU/UI
расход; пулы FX/HLOD и новые внешние зависимости без замеров не добавлялись.

## Изменение

CreaturePreview сохраняет видимый полный CardView, если совпадают сам CardDef
Resource, тема, ширина и контекст карты. Меняется только статус выбора/пояснение;
позиция чтения остаётся прежней. Новая карта, новый Resource того же ID, тема или
возврат из hint/creature идут по полному пути. Resize пересобирает композицию того
же узла из сохранённого определения, включая переданный отдельно CardDef.
Добавлен встроенный счётчик orbstrike/preview_card_reuses; покадрового опроса нет.

CardDB определения в текущем production-коде создаются при load_all и не изменяются
на месте после загрузки. Это предпосылка reuse: если будущий редактор станет менять
поля того же Resource, ему потребуется явная инвалидация/новое определение. В текущем
клиенте такой writer не найден. Не вводился глобальный кэш всех карт/материалов.

## Адресное измерение

Один Linux/Vulkan A/B, Godot4.7.2, RTX4070 Laptop, Forward+,1280×720, seed771,
одинаковые карты Поле Тени/Алтарь силы. Первый настоящий замер до правки подтвердил
три создания на каждый из шести кликов. Для сопоставимых CPU-данных стенд повторяет
прежнюю unconditional-build policy в тестовом subclass: перед каждым запросом
сбрасывается только ключ reuse. Production-файлы для A/B не переключались и
диагностический флаг в игру не добавлялся. Это реконструкция прежней политики,
а не запуск старого релизного бинаря; обе стороны используют остальные текущие
клиентские исходники.

| Работа | Прежняя политика | Текущий reuse |
|---|---:|---:|
| Создано полных CardView на 6 реальных кликов |18|6|
| Сумма синхронного CPU шести input rows |103.028ms|73.867ms|
| CPU 30 одинаковых запросов preview |55.655ms|2.582ms|
| Новые CardView за клики + 30 запросов |48|6|

CPU input rows включает обработку настоящих pointer/focus/button событий и
остальной синхронный UI-код, исключает await/render. Сумма рассчитана по click_rows,
а не общему input_cpu_usec, включающему также движения указателя между сценариями
и boundary-ввод. Один A/B не измеряет общий FPS, RAM, тяжёлый кадр матча или Windows;
проценты игрового ускорения не заявляются. Первый случайный exploratory baseline
имел другую команду и не использован для точного CPU-сравнения.

## Проверка

`python tools/check.py --profile presentation --checks preview-refresh`:
**GPU36/0,exit0,ERROR0,9.38s**. Штатный wrapper test_window: minimized/unfocusable,
offscreen force_draw(false),60FPS; пользовательские настройки игры не менялись.
Проверены настоящие hover/focus/click, выбранная карта и статус, сохранение scroll,
новый Resource с тем же ID/новым текстом, смена темы, resize с сохранённым текстом,
возврат из hint/creature, другая карта, keyboard disclosure/Esc/reopen. Creature
boundary подменяет только запрос 3D-модели: GLB/Boot не запускаются этим UI-стендом.
Baseline-policy14/0; Python compile check.py и git diff --check прошли.

Sol лично просмотрел3PNG: до/после настоящего gate-menu и resized-card. Состав,
читаемость и полный preview сохранены; небольшая разница бликов соответствует
живому shader-времени. Независимый Sol high read-only review: PASS без блокирующих/
существенных замечаний. Проверены lifecycle/invalidation, immutable CardDB
предпосылка, code/test diff, logs/summary и одинаковые fixedseed clickrows; reviewer
лично просмотрел те же3PNG и подтвердил сохранение UI. Повторных прогонов не было.

Артефакты:

- [Baseline metrics](../../../build/checks/presentation/selected-preview-refresh/preview-refresh/baseline/metrics.json),
  [baseline logs/summary](../../../build/checks/presentation/selected-preview-refresh/baseline-fixedseed-run/summary.json).
- [Final metrics](../../../build/checks/presentation/selected-preview-refresh/preview-refresh/after/metrics.json),
  [summary](../../../build/checks/presentation/selected-preview-refresh/summary.json),
  [engine/output log](../../../build/checks/presentation/selected-preview-refresh/preview-refresh.log).
- [До](../../../build/checks/presentation/selected-preview-refresh/preview-refresh/baseline/gate-menu.png),
  [после](../../../build/checks/presentation/selected-preview-refresh/preview-refresh/after/gate-menu.png),
  [boundary resize](../../../build/checks/presentation/selected-preview-refresh/preview-refresh/after/resized-card.png).

Промежуточный enhanced test32/1 сохранён в invalidation-first-run. Он ожидал shrink
ниже установленного CardView minimum; фактический Control не принимал заданную
ширину. Исправлена fixture на настоящий grow-resize, дополнительно проверен
сохранённый текст Resource; production minsize/layout ради теста не менялись.
Ранее успешные профили портретов/Boot/матчей не повторялись: их код этим шагом не
менялся. Все прежние dirty, Delta/intro/career и предыдущие оптимизации сохранены.
Tracy, сервер, .codex,49GLB, сборка/публикация, Windows и прослушивание не затрагивались.
