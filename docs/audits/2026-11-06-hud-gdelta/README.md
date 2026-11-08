# UI G-delta: продолжение заблокировано до сцены — 6 ноября 2026

Последняя незавершённая работа из NEXT_SESSION.md и SESSION_LOG.md — короткая
графическая перепроверка HUD после исправления тестового capture/fixture.
Модельная приёмка A03/R01/RTX4070 завершена ранее и не повторялась.

Один свежий запуск `python3 tools/check.py --profile presentation --checks hud-gdelta --visual`
завершился **exit1 за 0.09с до сцены**. X11 не создал DisplayServer, Wayland fallback
тоже не подключился. Сценарий UI, pixel anchors и PNG не выполнялись.
Шесть ObjectDB startup leaks в engine log относятся к неудачной инициализации
DisplayServer; это не результат выполнения HUD-сценария.

- [Лог попытки](visual-attempt.log), [engine log](visual-attempt-engine.log), [summary](visual-attempt-summary.json).
- [Свежая граница доступа](resume-environment-probe.json): DISPLAY/Wayland заданы,
  X0/X1 существуют, connect обоих возвращает EPERM/errno1;
  `/dev/dri`, `/dev/nvidia0`, `/dev/nvidiactl` отсутствуют.
- [Checkpoint](checkpoint.json), прежний [headless95/0](headless-report.json).
  Headless PASS не повторяли и не выдаём за визуальную приёмку.

Godot connector не предоставляет запуск check.py с его wrapper; проект через него
не запускался. Чтение host terminal завершилось ошибкой инструмента. Окружение,
Xauth и права не меняли; обходов sandbox и повторных GUI-попыток не было.
Причина разницы между доступом обычного терминала пользователя и исполнителя
**не установлена**. Продуктовый UI и тесты при этом продолжении не менялись.
Проверены код стенда и его opt-in маршрут: `frame_post_draw`, обновление обеих
публичных сил, actual normal/reduced tweens, 6 карт + 2 pass chips, финальные680/390,
штатный minimized/unfocusable/offscreen/60FPS wrapper. Это source review, не новый
результат графического запуска. Причина исходного неполного кадра остаётся открытой.

Для продолжения из обычного терминала пользователя с доступом к дисплею/GPU,
в корне проекта выполнить один раз:

```bash
python3 tools/check.py --profile presentation --checks hud-gdelta --visual
```

Результат сценария: `build/checks/presentation/hud-gdelta/report.json` и четыре PNG
`reducedfalse-settled.png`, `reducedfalse-delta.png`, `reducedtrue-settled.png`,
`reducedtrue-delta.png`. Логи: `build/checks/presentation/selected-hud-gdelta/`.
После успешного запуска Sol должен осмотреть новые PNG и отдельно принять normal
и reduced HUD. Повторный gpu-acceptance, модели, Boot и массовые профили не нужны.
Сервер/.codex, сборки, коммиты и публикации не затронуты.
