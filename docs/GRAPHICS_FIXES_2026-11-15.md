# Orbstrike — исправления после аудита графики

Проверка исходников клиента 0.4.5 на Linux и Godot 4.7.2 с Vulkan Forward+.
Графические стенды работали в свёрнутом нефокусируемом окне при 60 FPS.
[Исходный аудит](GRAPHICS_AUDIT_2026-11-15.md).

## Ворота, полёт и качение

- **FX-01.** Первое раскрытие переворачивает изображение ворот, поверхность
  и коллайдер остаются на поле. Повторные снимки состояния во время
  анимации и на следующем ходу сохраняют прежнее открытие. Замена карты
  позволяет новому ID сыграть своё раскрытие, закрытый снимок сбрасывает
  вид и вспышку. [Открытые ворота на следующем ходу](../build/checks/presentation/selected-match-fx/match-fx/online-open-gate-later-turn.png).
- **FX-02.** Воспроизведённый бросок получает стихийный шлейф, эффект отскока,
  искры и дорожку качения. Стенд подтвердил остановку в последней переданной
  точке с сохранённой ориентацией оболочки, повторную аренду шлейфа и возврат
  актёра после разрыва соединения. В прямой погоне огненная лента видна
  тонкой линией. [Полёт](../build/checks/presentation/selected-match-fx/match-fx/online-flight-airborne.png) ·
  [Качение](../build/checks/presentation/selected-match-fx/match-fx/online-flight-rolling.png).
- **FX-03.** При повторной аренде одного актёра пресеты низкий → высокий →
  средний → низкий меняли число искр и отметок как 11/31 → 30/90 → 21/62 →
  11/31. Возврат в каталог останавливал оба эмиттера.

На двух аренах независимый Sol сверил четыре шлейфа в фазе около 0,43 с.
Бирюзовая Буря визуально отделяется от синего Прилива, золотистый Свет от
медного Камня. `match-fx` прошёл **56/0**, снято 11 PNG. Headless-проверки
`online-gate-result`, `online-disconnect` и `sphere-pose` прошли **20/0**,
**15/0** и **201/0**.
[Сравнение шлейфов](../build/checks/presentation/selected-match-fx/match-fx/flight-pairs.webp) ·
[Лог FX](../build/checks/presentation/selected-match-fx/match-fx.log) ·
[Ворота](../build/checks/presentation/selected-online-gate-result/online-gate-result.log) ·
[Разрыв соединения](../build/checks/presentation/selected-online-disconnect/online-disconnect.log) ·
[Поза сферы](../build/checks/presentation/selected-sphere-pose/sphere-pose.log).

## Модели и гардероб

### MOD-01 — опора Рогожуков

Решатель опоры Камня и Света учитывает выступающие края правых жёстких
лап при наклоне и при необходимости немного поднимает лапу поворотом
в её сочленении. Измерена вся деформированная сетка в тех же положениях,
что и при аудите. Кадры с плоскостью и без неё сняты с одной точки.

| Существо и фаза | Низ проблемной правой лапы, доля роста | Вершины всей сетки глубже 2,5% роста | Кадры |
|---|---:|---:|---|
| Камень, замах 0,417 с | −7,018% → +0,221% | 928 → 0 | [Четыре ракурса](../build/checks/models/graphics-fixes-20261115/rogozhuk_stone-windup-floor-comparison.webp) |
| Свет, замах 0,383 с | −5,133% → +0,106% | 313 → 0 | [Четыре ракурса](../build/checks/models/graphics-fixes-20261115/rogozhuk_light-windup-floor-comparison.webp) |
| Свет, реакция 0,383 с | −3,876% → −0,055% | 241 → 0 | [Четыре ракурса](../build/checks/models/graphics-fixes-20261115/rogozhuk_light-hit-floor-comparison.webp) |

У Света в реакции правая задняя лапа проходит на 0,134% роста ниже пола.
Самая низкая точка всей сетки остаётся на левой задней бронепластине
в замахе и реакции, на 1,052% и 1,501% роста соответственно. В снятых
ракурсах независимый Sol подтвердил читаемый контур правых лап. На Приливе
минимумы сетки и обеих правых групп совпали в трёх контрольных фазах.
[Замеры до](../build/checks/models/graphics-fixes-20261115/beetles-before/runtime.json) ·
[Замеры после](../build/checks/models/graphics-fixes-20261115/beetles-after/runtime.json).

`support` проверяет 66 моделей и учитывает авторский полёт Грифалона,
клиповое движение лап особых ригов и допуск авторской опоры Колоссара.
Добавлена проверка высоты всей сетки и правых лап по четырём позам, включая
восстановление Света. Штатные `support` и `preparation-cache` прошли
**1775/0** и **1380/0**. На прежнем решателе все восемь новых утверждений
воспроизвели провалы.
[Логи](../build/checks/models/selected-support-preparation-cache/) ·
[Регрессия на прежнем решателе](../build/checks/models/graphics-fixes-20261115/regression-baseline/engine.log).

### MOD-02 — перепонки Горгула Тени

Смягчили свет на перепонках и уточнили цвет кромки и жилки. В сравнении
фронта, профиля, спины и реакции ослабли угловатые светлые островки
у оснований крыльев. Независимый Sol подтвердил, что сохраняются силуэт,
палитра, глаз, рога и нагрудник. В профиле и со спины перепонки выглядят
более плоскими, а прожилки и кромка слабее выражены, чем на исходном листе.
[До и после](../build/checks/models/graphics-fixes-20261115/gorgul-wings-comparison.webp) ·
[Эталон](../art/models/new_creatures/2026-11-15/gorgul-trellis-refinement/comparison.webp).

В игровом GLB поменялся только атрибут `COLOR_0` основной поверхности.
Сетка, веса, кости, rest и bind, клипы и параметры импорта совпали. Стенд
`gorgul-trellis` прошёл **82/0** через Boot и обычный вход в матч, с одним
анимационным контактом.
[Сравнение данных GLB](../build/checks/models/graphics-fixes-20261115/gorgul-material-verification.json) ·
[Лог и кадры матча](../build/checks/models/selected-gorgul-trellis/).

### MOD-03 — бомберы Виты и Сакурады

Молния и карманы теперь рисуются на ткани куртки. Выступы исчезли из
профиля и при открытии ворот, молния сохраняет цельную линию в победе.
Независимый Sol сверил обе основы в трёх парных фазах. Стенды редактора,
палитры и уличного комплекта прошли **18/0**, **136/0** и **2091/0**.
Сравнение ресурсов дало **137/0**, включая проверку весов, UV и геометрии пояса.
При повторной сборке файлы `.res` различаются побайтово, а загруженные
поверхности, метаданные, материалы и текстуры совпадают.
[Сакурада](../build/checks/graphics-fixes-20261115/comparisons/bomber-sakurada.webp) ·
[Вита](../build/checks/graphics-fixes-20261115/comparisons/bomber-vita.webp) ·
[Логи стендов](../build/checks/presentation/selected-street-set-wardrobe-catalog-motion-wardrobe-palette/) ·
[Сравнение ресурсов](../build/checks/graphics-fixes-20261115/bomber-build/compare.log) ·
[Повторная сборка](../build/checks/graphics-fixes-20261115/bomber-build/rebuild-compare.log).

## Локации

В Лунной гавани дальняя вода плавнее переходит в небо. Максимальный
скачок яркости на первом плане вступления снизился с 0,160 до 0,029,
на обратном плане с 0,136 до 0,030 по шкале 0–1. Граница остаётся
различимой, в ночной сцене лучше читаются маяк, фасады, паруса и скалы.
`location-detail` прошёл **169/0**, проба вступления Гавани **17/0**.
[Вступление](../build/checks/graphics-fixes-20261115/comparisons/harbor-intro.webp) ·
[Обратный план](../build/checks/graphics-fixes-20261115/comparisons/harbor-reverse.webp) ·
[Лог локаций](../build/checks/presentation/selected-location-detail/location-detail.log) ·
[Проба вступления](../build/checks/graphics-fixes-20261115/intro-after/run.log).

В Янтарном каньоне смягчили тёплый свет поля. У Клыкаря Тени лучше видна
фиолетовая гамма, светлые концы шипов Колоссара Пламени сохраняют форму.
Художественно сверены игровые кадры, отдельная проба прошла **48/0**.
[Игровой план](../build/checks/graphics-fixes-20261115/comparisons/canyon-play.webp) ·
[Клыкарь](../build/checks/graphics-fixes-20261115/comparisons/canyon-klykar.webp) ·
[Колоссар](../build/checks/graphics-fixes-20261115/comparisons/canyon-kolossar.webp) ·
[Лог](../build/checks/graphics-fixes-20261115/trials/run.log).

## Команды

```sh
python tools/check.py --profile models --checks import
python tools/check.py --profile models --logic-only --checks support preparation-cache
python tools/check.py --profile models --visual --checks gorgul-trellis
python tools/check.py --profile presentation --checks match-fx
python tools/check.py --profile presentation --logic-only --checks online-gate-result online-disconnect sphere-pose
ORBSTRIKE_LOCATION_CAPTURE_SET=graphics-fixes-20261115-after \
  python tools/check.py --profile presentation --checks location-detail
SFERY_WARDROBE_CATALOG_STAGE=graphics-fixes-20261115-after \
  SFERY_WARDROBE_CATALOG_SLOTS=0-06,1-07 \
  python tools/check.py --profile presentation --checks wardrobe-catalog-motion wardrobe-palette street-set
```

Сетевые сценарии подавали снимки и траекторию напрямую в клиент. Живой
сетевой матч, Windows, прослушивание и выпуск пакетов остаются вне этой
проверки.
