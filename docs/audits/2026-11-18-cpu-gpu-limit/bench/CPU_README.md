# CPU probe — 18 ноября 2026

Один текущий клиентский логический матч, production MatchController и AIPlayer,
HARD/HARD, seed 777, CardDB.Pool.SPECIES. Linux, Godot 4.7.2, Ryzen 7 7435HS.
Сервер, Windows, обычное окно игры и production-исходники не менялись.

Запуск из корня проекта:

```sh
godot --headless --max-fps 60 --path . --log-file /home/loq/Документы/game/sfery_stikhiy/build/checks/cpu-probe-20261118/engine.log -s res://docs/audits/2026-11-18-cpu-gpu-limit/bench/cpu_probe.gd
```

Исторический успешный запуск использовал копию probe.gd в build/. Стабильный
cpu_probe.gd меняет только путь preload, удаляет неиспользуемый массив и
создаёт каталог отчёта после очистки build/. Матч повторно не запускался.
Хэши текущих стендов, использованных стендов и raw report сохранены
в cpu_summary.json.

Фактически выполнен один запуск: exit 0, 32 шага, 14 ходов, terminal knockout,
28 внешних решений, failures []. Лог без SCRIPT ERROR/ERROR/WARNING.
Один актуальный матч вместо исторических prefix fixtures. Все команды и
полные ID колод записаны в build/checks/cpu-probe-20261118/report.json. 7 SHA production до/после совпали
(исходные SHA и компактные результаты — cpu_summary.json).

| Решение | n | Медиана, мс | Максимум, мс |
|---|---:|---:|---:|
| choose_setup | 8 | 53.5875 | 230.598 |
| choose_ability | 7 | 32.045 | 44.865 |
| choose_attach | 8 | 0.008 | 0.014 |
| choose_ability_target | 3 | 0.008 | 0.009 |
| should_open_gate | 2 | 0.4005 | 0.511 |

Максимальное боевое решение: ход 11, игрок 1, 4 допустимые способности,
своя/чужая рука 4/5, живых 2/3, сила 440:340, ответ после stone_firm,
выбран пас; prefix_commands 26. В этой последовательности обычного
choose_throw не было: все 8 бросков выполнялись через throw_with_gate.

Метод: Time.get_ticks_usec вокруг super публичного метода AIPlayer.
Создание view/legal API, metadata и запись отчёта снаружи. Вложенные публичные
вызовы обходят timer/metadata и добавляют только малую стоимость guard.
Это synchronous wall latency алгоритма, включая вытеснение планировщиком,
а не exclusive CPU profiler. Synchronous controller actions тоже измерены:
максимум play_ability 2.739 мс, pass_ability 1.246 мс в этом матче.

Физика не симулируется: report_landing получает выбранные ворота точно.
Это достижимые последовательности логических правил при допустимом попадании,
но не результат фактического физического матча. Нет GLB/setup/render, эффектов,
await и игровых пауз; Engine.max_fps=60 задан и через CLI, и в стенде.
Не устанавливает диапазон всех матчей, слабых CPU или худший возможный случай.
HARD разовые 32–230 мс могут давать паузу на решении; постоянное время кадра
стабильного поля этим не объяснено. Графический NORMAL NPC из другого прогона
и состояния не является A/B сравнением сложности.

Дополнительная read-only запись первого графического benchmark:
external-proc-samples.jsonl, clock-anchor.json, external-proc-summary.json.
0.5s интервалы /proc PID106351 и внешнего клиента PID106280, process/main
utime+stime, CLOCK_MONOTONIC и wall. Запись началась после старта bench,
между 120s блоками есть небольшая дырка. Процесс завершился сам.
Clock offset в Godot не калиброван напрямую: только грубое сопоставление по
process starttime и monotonic/boottime. Нельзя выдавать это за frame CPU trace
или автоматически заменять нулевые внутренние proc metrics первого bench.

Проверка синтаксиса без исполнения матча:

```sh
godot --headless --max-fps 60 --path . --check-only -s res://docs/audits/2026-11-18-cpu-gpu-limit/bench/cpu_probe.gd
```

Стабильный путь прошёл Godot --check-only: exit 0, 0.82 с, stderr пуст.
SHA исходного raw report до/после одинаков: матч не исполнялся повторно.
Команда и результат — syntax-check.json.
