# Исправления клиентского аудита загрузки и preview — 9 ноября 2026

Изменения выполнены Sol high; независимый Sol high проверил код относительно
снимка исходного dirty, существенных замечаний не нашёл. Прежние локальные
изменения сохранены. Это исправления исходников, версия/опубликованный клиент
0.4.2.6 прежние; сборка и выпуск не поручались.

## Поведение

- StartupCatalog явно перечисляет обязательные корневые сцены: исчезнувший из
  обхода файл остаётся в manifest. Отсутствующий/не загруженный ресурс возвращает
  LoadResult с путём ошибки и пустым словарём; обязательные PackedScene проверяют
  can_instantiate и корневой script до выполнения _ready.
- GameLoading при управляемом отказе останавливает warm draw и viewport, удаляет
  частичные Main/menu, затем весь storage/viewport с героями, текущей сферой,
  прогреваемой партией и припаркованными сферами. Сцены сначала возвращают свои
  аренды; после этого очищаются registries/caches/references/counts, preparing и
  ready. last_error и callback сохраняют причину; повторная prepare допустима.
- ready_to_play публикуется после подготовки Main и главного меню. Внутренняя
  has_prepared_catalog позволяет скрытой Main брать уже созданные арену/preview,
  сохраняя Boot/resident контракт и отсутствие нового setup после каталога.
- Повтор той же CreatureDef в том же context/style обновляет note/in_team/pose,
  сохраняя Labels, список карт и позицию чтения. Новый Resource/context/style
  обновляет описание; resized пересчитывает размер имени без нового наведения.

## Узкие проверки и хронология

1. Baseline до изменения show_creature:
   `SFERY_CREATURE_PREVIEW_BASELINE=1 python3 tools/check.py --profile presentation --checks creature-preview-refresh --logic-only`
   — **5/0**, exit0. Для30 повторных запросов: **90 новых Labels,30 измерений имени,
   0 запросов модели**. [Лог](preview-before.log).
2. GPU after, RTX4070/Vulkan:
   `python3 tools/check.py --profile presentation --checks startup-failure creature-preview-refresh`
   — `creature-preview-refresh` **15/0**, exit0,4.96с.30повторов:
   **0 новых Labels,0 измерений имени,0 запросов модели**. Проверены status/pose,
   Resource с тем же id, resize, возврат из hint/card, другой вид.
   [Лог](creature-preview-refresh-first-gpu.log).
3. Тот же GPU запуск `startup-failure`: **66 проверок,4 FAIL**, exit1,38.84с.
   Отказы missing/animation/main/menu, cleanup/cache/flags/retry и один настоящий
   normal Boot49×2/3арены/4героя выполнялись; ошибки относились только к четырём
   ожиданиям текста callback в fixture. Локальный String в lambda захватывался
   по значению и оставался пустым у проверяющего. Заменён на Array[String].
   Остальные62assertion прошли, включая11 normal Boot проверок: readiness ещё
   false при подготовке интерфейса, resident аренда preview,98/3/4, отключённый
   viewport, наличие обеих сцен и отсутствие повторной подготовки после успеха.
   [Исходный FAIL лог](startup-failure-first-gpu.log),
   [summary](first-gpu-summary.json). Не объявляется общим PASS этого запуска.
4. Повторён **только исправленный отказный стенд**, без успешного normal Boot и preview:
   `SFERY_STARTUP_FAILURES_ONLY=1 python3 tools/check.py --profile presentation --checks startup-failure --logic-only`
   — **55/0**, exit0/ERROR0,15.09с. Проверены missing path, обязательные roots,
   неправильный type/script, четыре отказные ветки, освобождение weakrefs всех
   частичных узлов, пустые registries/caches, флаги и повторные попытки.
   [Финальный лог](failure-only-final-startup-failure.log),
   [summary](failure-only-final-summary.json).

Все запуски используют tools/check.py/test_window, лимит60FPS. Графический прогон
свёрнутый, нефокусируемый, offscreen; экран/фокус автора не захватывался.
Первый графический sandbox запуск не получил X11/Wayland; разрешённый повтор
получил графический сеанс. Первый вариант preview fixture имел неверную сигнатуру
appear(bool); исправлен до baseline. [Сохранённый parse error](preview-fixture-initial-parse-error.log).
Эти проблемы стенда/окружения не являются дефектами продукта.

## Границы

Никаких выводов об общем FPS/RAM или обычной утечке нет. CPU timings baseline и
после получены в разных headless/GPU условиях и не сравниваются; вывод основан
на количестве выполненной работы. Самостоятельный визуальный просмотр/PNG,
прослушивание, полный матч, Windows, сборка/публикация не проводились. Сервер,
49GLB/skeleton/rest/bind/UV и .codex не изменялись и не проверялись.
Управляемые отказы ресурсов/анимации и неудачное создание сцен проверены;
универсальный перехват любого runtime exception внутри произвольного _ready
не заявляется. Автоматического UI retry нет: Boot остаётся на тексте ошибки,
а программная повторная prepare работает после устранения причины.
