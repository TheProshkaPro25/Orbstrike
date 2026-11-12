# Исправлены шея street и исходный sport —9ноября2026

## Уточнение области sport ART — 9 ноября 2026

После пользовательского замечания отдельные крупные планы спортивной шеи
подтвердили широкую зубчатую CLOTH-накладку на обеих основах. Прежнее принятие
sport в этом отчёте относилось к общему виду, согласованности ткани, палитре и
переходу denim; оно оказалось недостаточным для качества горловины. Даже
существующие sport closeup PNG содержали этот дефект: старое scoped ART PASS
не означает принятую спортивную шею. Исторические результаты ниже сохранены;
отдельное исправление и новая приёмка — [sport neck](../2026-11-09-sport-neck/README.md).


Новый пользовательский симптом воспроизведён через реальные кнопки образов и
селекторы, отдельно от прежней проверки выбранной палитры. Закрыт scoped
независимым Sol CODE+ART review после фактического осмотра итоговых PNG.

| Основа | UI6/index5 | UI7/index6 | Спорт кнопкой |
|---|---|---|---|
| Юноша | Бомбер | Спортивный костюм | UI7/index6 |
| Девушка | Контрастное худи | Бомбер | UI8/index7 |

## Итоговое исправление

Street наследовал неуместный высокий цилиндрический ворот и skin-shaped накладку
в CLOTH. Они удалены из trim; нижние молния/пояс/карманы сохранены.

У юноши donorSkin прежде обрезалась whole triangles для закрытого худи. Финальный
вариант восстанавливает **840 отсутствовавших исходных triangles из body_0_1**
в том же surface0 через INDEX union с точной winding-aware дедупликацией.
Все прежние triangles сохранены. Позиции/UV/bones/weights совпадают с тем же
донором; прежние normal/tangent buffers и руки не заменяются. Нет второй skin
поверхности, другой skin atlas, глобального texture fill или новой большой sheet.
Именно соответствующий донор устранил и цветовые заплаты, и пересечение с курткой.

У девушки сохранена отдельно проверенная targetSKINlining из body_1_0 с настоящими
UV/skin material/bones/weights. Новые значения на клипе интерполируются, низ уходит
под куртку. Guard в builder задаётся явно model==0, не общим part_source==2.

Sport исходно имел разные base/shade и фактуры верха/брюк. Теперь оба слота
используют одинаковую **однотонную спортивную ткань** (existingwhite material,
697f94/shade); складки, карманы, молния, лампасы сохраняются геометрией. Это
намеренное упрощение принта, а не перенос hoodie UV atlas на брюки. Существующие
UV, геометрия, bones/weights спорткостюма не меняются. Палитра/reset и отдельно
выбранные джинсы продолжают работать.

Изменены только4derived costume .res и их адресные offline builders. Исходные
VRM/текстуры/49существ, skeleton/rest/bind и .codex не менялись. Hair/case не
перегенерировались. [Финальные размеры/SHA](final-asset-sha.json).

## Инструменты и доказательства

По просьбе автора изучены инструменты. Использованы
[Godot MeshDataTool](https://docs.godotengine.org/en/4.7/tutorials/3d/procedural_geometry/meshdatatool.html),
ArrayMesh и CPU ray/triangle inspection с фактической позой, barycentric UV и
отдельным sampling Main/Shade. Blender MCP не подключался; live сцена не менялась.

- [Matching donor neck](matching-donor-neck-ray-hits.json): donor точно совпадает
  с retainedSkin по позиции/UV/Main/Shade; в обоих прежних orange points alpha1,
  естественный skinRGB. [Matching donor full](matching-donor-full-ray-hits.json):
  в трёх прежних butterfly points skin **за cloth на8–12мм**.
- Те же проверки **фактически сохранённого финального mesh**:
  [neck](candidate4-neck-ray-hits.json), [full](candidate4-full-ray-hits.json).
  [Итоговый builder log](final-male-builder.log):840 restored triangles.
- [Candidate2 array/MeshDataTool report](candidate2-mesh-array-comparison.json)
  остаётся исторической проверкой женской lining/общей геометрии: все12sport
  surface arrays совпали с исходными; прежние0–3bomber surfaces тогда совпали.
  Финальный male отличается от этого кандидата **только восстановлением INDEX
  вskin0 и отсутствием чужой lining**; сам builder проверяет соответствие donor
  position/UV/bone/weight buffers до восстановления. UV/weight vertices не создаются.
- [Женский bomber и sport SHA](candidate3-unchanged-female-sport.json) побайтово
  сохранены после принятого candidate2; повторных их GPU прогонов не делалось.

## Фактические проверки

| Проверка | Результат | Границы |
|---|---|---|
| Изолированный client online_gate_result |17/0,exit0/ERROR0,4.77с|headless, безсервера |
| Candidate2 actual preset/selector/neck/default/palette/reset/denim |57/0,exit0/ERROR0,10.90с|GPU: female+sport ART приняты, male ART отклонён |
| Финальный male candidate4 |14/0,exit0/ERROR0,6.61с|GPU: selector/default/front/angle/tone/reset/palette/far |
| Финальный male candidate4 logic |6/0,exit0/ERROR0|headless, перед GPU |
| Street/sport manifests |record послеART, затем оба verifyPASS|только адресные SHA inputs/outputs |

Онлайн test исправляет undeclared state локальным alias presentation.state и
готовит недостающие HelpPolicy/AbilityTargetPicker только в fixture.
[Лог17/0](online-final-online-gate-result.log). Сервер/полныйonline suite не запускались.

Итоговые GPU:
[общий accepted female/sport log](gpu-candidate2-wardrobe-fit.log),
[финальный male log](gpu-male-final-wardrobe-fit.log),
[male summary](gpu-male-final-summary.json), [headless6/0](headless-male-candidate4-wardrobe-fit.log).
Все графические запуски RTX4070/Vulkan, tools/check.py/test_window:
немедленно свёрнутые, нефокусируемые, rendertexture,60FPS. Не было показа игры
поверх рабочего стола. Sol лично просмотрел итоговые8male и принятые female/sport
кадры; независимый Sol повторно просмотрел все8male и подтвердил scoped ART PASS.
Проверялись указанные фронт/ракурс, не все движения/все костюмы.

## Ключевые кадры

| Область | До | Итог |
|---|---|---|
| Шея юноши |[до](before/0-street-neck.png)|[front](after/0-street-neck.png), [angle](after/0-street-neck-angle.png) |
| Шея девушки |[до](before/1-street-neck.png)|[front](after/1-street-neck.png), [angle](after/1-street-neck-angle.png) |
| Sport юноши |[до](before/0-sport-default.png)|[исходный](after/0-sport-default.png), [палитра](after/0-sport-palette.png) |
| Sport девушки |[до](before/1-sport-default.png)|[исходный](after/1-sport-default.png), [палитра](after/1-sport-palette.png) |

[Тон кожи](after/0-street-skin-neck.png), [reset](after/0-street-reset-neck.png),
[full](after/0-street-default.png), [far](after/0-street-far.png),
[переход изdenim юноша](after/0-sport-after-denim.png),
[девушка](after/1-sport-after-denim.png).

## Честная хронология отказов

Before GPU создал26PNG/49assertions безFAIL, но общий запуск FAIL из-за удержания
ресурсов fixture. Runtime-load/release parts/sound исправил именно compile graph
стенда. Этот before не объявляется общим PASS.

Candidate1: снятая одна накладка оставила ворот/skin gap; перенос hoodie atlas на
pants дал лоскуты. Counters могли проходить, ART FAIL сохранён (candidate1/).
Candidate2: female/sport приняты, male другая target-body lining сохранила alpha
mask другого атласа — ART FAIL. Candidate3 nearest opaque fill убрал дырки, но
появились orange charts и skin butterfly перед cloth — ART FAIL (candidate3/),
логи gpu-male-candidate3-*. Эти обходы полностью удалены из финального кода.
Методичное matching-donor исследование дало финальный candidate4.

Предыдущий dirty сохранён. Нет новых полных профилей/матчей/Windows/прослушивания,
общегоFPS/RAM измерения, сборки/публикации. Версия и публичный клиент0.4.2.6 прежние.
