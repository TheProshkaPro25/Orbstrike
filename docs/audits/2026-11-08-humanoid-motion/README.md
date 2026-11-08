# Ратник Света: мечевой рубящий удар — 8 ноября 2026

Заменён generic jab только у `creature_ratnik_light`. Плечо/локоть ведут кисть
из высокого замаха в диагональный рез, затем в довод и возврат. Кисть поворачивает
весь меч, его отдельное покачивание в ладони убрано. Корпус участвует поворотом,
шея компенсирует его для читаемого взгляда. Контакт остаётся на clip phase1/3.

**Главное сравнение:** [реальные GPU до/после](ratnik-slash-gpu-before-after.gif),
[контакт](ratnik-slash-gpu-contact.png). Одинаковые камера, свет, материал, фазы.
Геометрия обеих сторон одна и та же; это изменение анимации, не новая модель.
Исходный GLB d51ab2dc…b97cbf5a70, rest/bind/UV/skin/принятые030–035 не изменены.
Остальные Ратники и Колоссары не изменены. Сервер/.codex не затронуты.

## Проверка

`python3 tools/check.py --profile models --checks humanoid-motion --visual`

Последний запуск: **32847 assertions /0 failures**, exit0. Реальная NVIDIA
RTX4070 Laptop GPU, Vulkan1.4.351/Forward+, штатный minimized/unfocusable/offscreen
wrapper и60FPS. Два19кадровых GPU ряда: build/checks/humanoid-motion/gpu-before/
и gpu-after/. Лог и summary: build/checks/models/selected-humanoid-motion/.
Проверены actual runtime конечные/граничные позы, один контакт на1/3, неизменность
нижних костей/root, idle/hit и шести контрольных Колоссаров, фиксированный хват
после входного blend. Старое ожидание сохранять independent sword wiggle было
заменено проверкой жёсткого хвата; промежуточный17FAIL не является финальным PASS.

Ось клинка/остриё найдены по реальной skin-геометрии GLB. Направление от рукояти
до вершины31056 меняется на110.77° между замахом/контактом. После контакта остриё
проходит ещё0.688sourceunits, рукоять0.261: это режущая дуга, не просто перенос кулака.
Независимый Sol high проверил код, длины плеча/предплечья (разброс<8e-7sourceunits),
лично осмотрел CPU последовательность и GPU012/028/044/068: scoped ART/CODE PASS.
Плащ на этих GPU кадрах без видимых новых выбросов/разрывов; это не полная
непрерывная приёмка ткани во всех боях.

[blade-body-bvh.json](blade-body-bvh.json):6реальных поз до и6после,0пар
2318distal blade triangles vs113172body triangles. Рукоять/намеренный хват исключены.
Это узкая проверка клинка против тела, не полная BVH всей брони/плаща/непрерывного движения.

Первая sandbox попытка GPU остановилась до сцены без доступа X11/Wayland.
Разрешённый запуск вне sandbox дал настоящий RTX4070 результат. Один повтор
после нового slash и один после исправления кадрирования меча относятся к новым
изменениям; массовые профили, матч, Windows, сборка и публикация не выполнялись.

## Источники приёмов и воспроизведение

Прочитаны предложенный автором [godot-animation](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-animation/SKILL.md)
и его reference: один владелец AnimationPlayer, подготовленные immutable clips,
контакт и переходы согласованы с существующим таймлайном. Прочитан [game-feel](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/disciplines/game-feel/SKILL.md):
применено плавное ускорение/возврат; shake/дополнительные эффекты не добавлялись.
Навыки не устанавливались, .codex не менялся.

`tools/models/render_humanoid_comparison.py` воспроизводит маленький CPU GIF
из runtime JSON (приближённый свет/CPU skin, неGPUcloth). Финальная GPU GIF выше
составлена из настоящих PNG, не из этих CPU кадров. `review_humanoid_runtime.py`
переносит экспортированные skin matrices в отдельные рабочие копии Blender;
`audit_ratnik_slash.py` воспроизводит узкий BVH в Blender Python.

Файлы ratnik-attack-before-after.gif и ratnik-contact-before-after.png —
отклонённая первая попытка освободить лицо; она не решала jab и не является итогом.
Актуальные артефакты имеют `ratnik-slash-` в имени.

Открыто: художественное качество исходной анатомии/деталей модели и остальных
клипов не переделывалось; другие Ратники и Колоссары ждут отдельного этапа.
Исходная пользовательская сцена Blender с Cube/Camera/Light сохранена; добавлены
только отдельные review-коллекции, production GLB из Blender не экспортировались.
