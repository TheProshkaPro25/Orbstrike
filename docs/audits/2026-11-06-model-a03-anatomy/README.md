# A03 — локальная форма плеч, 6 ноября 2026

Принят ограниченный практический результат: удалены чужеродные высокие
прямоугольные дымовые листы вместе с их розовыми корнями; сохранены исходные
дельты и руки. Низкое закрытие продолжает плечевую броню; два небольших
неравных объёма расположены снаружи и позади плеч. Лицо и рога свободны.

**Frozen SHA256:** `69b159a0e8763ef85c1e78b951255deb5e75d3939643af71c1abb8357d7e9a5c`.
Кандидат: `build/model_candidates/2026-11-06-a03-anatomy/rounded_smoke22.glb`.
Whitelist/точные source face IDs: соседний `rounded_smoke22.json`.
Установку выполняет отдельный владелец promotion; этот этап сам GLB не ставил.

![До и после, один верхний игровой ракурс; CPU raw-rest](before-after-game.png)

## Что доказано

- `integrity.json`: все исходные BIN/accessor/rig/rest/bind/клипы/UV/8 weights,
  исходные изображения и материалы точны. Из 149994 исходных faces удалены
  только 14241 перечисленных ornamental faces; 135753 сохранены точно.
- Новые 35403 tri / 17797 vertices, итого 171156 tri. Все 185 collar vertices
  копируют исходные POSITION и восемь skin weights точно. Новых дыр и
  вырожденных граней нет. Новый цветовой atlas добавлен отдельно.
- `raw-intersections.json`: локальная raw-rest BVH — 0 новых nonadjacent pairs
  cap/body и cap/self. Это не утверждение о движении.
- `independent-art-review.json`: независимый Sol high лично осмотрел SHA и
  пять ракурсов, ART PASS по практической авторской цели. Небольшая асимметрия
  не является блокером; идеальное количество завитков не требовалось.
- `reproduction.json`: `tools/models/repair_kolossar_shadow_anatomy.py`
  вместе с `kolossar_shadow_attachment.py` воспроизвели полный SHA кандидата.
- Исправленный видимый runtime fixture действительно меняет bone palettes
  (delta 1.070407748; экспорт 0.933885619). В 15 idle/attack/hit samples
  direct source/candidate palettes и 32 сохранённые world points имеют delta 0;
  прежние scale 13.3923769, height 11.3535052 и центр сохранены keyed guard.

![Критические позы из настоящих Godot palettes; CPU skin, не GPU](actual-critical-game.png)

`actual-critical-review.json`: автор реализации и независимый Sol high лично
осмотрели idle0/attack24. Существенной видимой новой дыры или крупного
проникновения плеча нет; силуэт сохраняется при поднятой руке. Это два
CPU-skinned кадра с реальными clip/support palettes, приближённым CPU-светом
и текстурой; не GPU и не доказательство всей непрерывной анимации.

## Установленный ordinary результат

Свежий postpromotion `a03-anatomy` — **15448 assertions / 0 failures**,
`installed=true`, обычный ресурс действительно содержит 171156 tri. Новые
ordinary анимации и 32 retained world points совпали с immutable старым
ordinary SCN: обе delta 0. Direct source/candidate движущиеся palettes/world
также delta 0; nonzero motion 1.070407748 доказано. Старое diagnostic отличие
ordinary от direct сохранено отдельно и не исправлялось изменением анимаций.
Актуальный полный отчёт — `actual-import.json`; установка/import/backup —
`promotion.json` и `source/ordinary-backup.json`.

## Явные пределы и исправление стенда

Первый 11495/0 не доказывал движение: общий actor helper оставлял фигуру
скрытой, а CreatureAnim намеренно пропускал `_process`. Отчёт сохранён в
`static-rest-import-not-motion.json` и явно отозван как motion evidence.
Тот экспорт дал одни и те же palettes во всех 46 записях. Его BVH обнаружила
2 body/cap и 524 self pairs в каждом bind-положении; это сохранено в
`static-bind-intersections.json`. Они не объявлены численной погрешностью,
нулём пересечений или полным PASS движения.

После исправления fixture source/candidate действительно двигались и
совпали точно. Общий prepromotion runtime дал 11499 assertions / 2 failures:
только существовавшее отличие ordinary старого SCN от direct GLTF анимаций,
Δ palette 0.01351276 / world 0.02987867. Этот исход сохранён в
`corrected-prepromotion-legacy-direct.json`, не выдан за общий PASS. Правильный
postpromotion ordinary baseline — immutable старый ordinary SCN из
`source/ordinary-backup.json`, а не другой direct importer. Тест теперь
сравнивает ordinary с этим baseline, diagnostic direct delta сохраняется.

По прямому указанию автора закончить без новых циклов после критических
визуальных кадров не запускали новую полную 46-pose BVH серию и не меняли
принятую геометрию. Отсутствие всех скрытых микроконтактов/всех динамических
самопересечений не заявляется. Сервер, Windows, релиз, публикация и GPU
этим модельным этапом не проверялись.

## Повтор

```bash
python3 tools/models/repair_kolossar_shadow_anatomy.py --original build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb --source build/model_candidates/2026-11-06-a03-anatomy/source/kolossar_shadow.glb --output build/model_candidates/2026-11-06-a03-anatomy/reproduction.glb
python3 tests/kolossar_shadow_anatomy_integrity.py build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb build/model_candidates/2026-11-06-a03-anatomy/source/kolossar_shadow.glb build/model_candidates/2026-11-06-a03-anatomy/rounded_smoke22.glb build/model_candidates/2026-11-06-a03-anatomy/rounded_smoke22.json docs/audits/2026-11-06-model-a03-anatomy/raw-intersections.json docs/audits/2026-11-06-model-a03-anatomy/integrity.json
python3 tools/check.py --profile models --checks a03-anatomy --logic-only
```

Последняя команда использует штатный minimized/nonfocus/60 FPS wrapper;
headless результат не является GPU/визуальной проверкой. Actual export хранится
отдельно в `actual-source/` и `actual-candidate/`. Старые rejected cap/planar/
0430/0415/Steiner и compression/TPS прототипы не устанавливать.
