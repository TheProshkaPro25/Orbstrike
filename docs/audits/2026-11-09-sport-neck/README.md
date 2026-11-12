# Спортивная горловина — 9 ноября 2026

Пользователь указал на цвет/дефект шеи спортивного образа. Новый стенд воспроизвёл
его на обеих основах через настоящую кнопку «Спортивный образ»: юноша UI7/index6,
девушка UI8/index7. Прежняя fullbody/palette/denim приёмка sport не подтверждала
качество горловины; соответствующее уточнение добавлено в [старый отчёт](../2026-11-09-wardrobe-fit/README.md).

## Причина и исправление

`build_sport_set.gd` скрывал полосу Body.skin, затем копировал широкие участки
Body и Face в приподнятую на 8 мм поверхность CLOTH. Получалась зубчатая тёмная
накладка: смена skin tone её не меняла, палитра одежды меняла. Это не кожа.

Вместо обеих копий построен короткий ворот из материала самого верха. Его нижние
20 точек — настоящий замкнутый контур уже деформированной куртки. Верхнее кольцо
охватывает сечение Body и Face, получает интерполированные исходные веса кожи,
имеет зазор 4 мм и высоту neck+23 мм. Прежняя скрытая полоса Body.skin заканчивается
на neck+15 мм, поэтому её граница прикрыта воротом. Новых skin sheets/atlas fill нет.

Собственные нормали воротника направлены наружу; нормали старого верха не
пересчитываются. Все 120 новых вершин включены в INDEX, добавлены 40 треугольников.
Ворот использует ту же ткань/палитру, что верх. Брюки, обувь и полосы сохранили
точные массивы; материалы брюк/полос прежние. Bomber и волосы побайтово прежние.
Исходные VRM, скелеты, bind/rest, 49 creature GLB и source UV не изменены.

## Проверки и честная хронология

- Before GPU: 19/0, exit 0, 14 PNG обеих основ. Широкая накладка лично подтверждена
  автором правки и независимым Sol.
- Candidate1 GPU: counters 19/0, ART FAIL. Объединение индексированного Top и
  неиндексированного collar оставило 120 новых вершин без индексов; ворот не рисовался,
  а старый whole-triangle skin cutoff стал виден. Исправлено явным `tool.index()`.
- Candidate2 GPU: 19/0, ART FAIL. Широкая накладка устранена, но на самой кромке
  осталось несколько небольших skin V-пиков. Posed ray показал Body.skin впереди
  воротника на 0,7–1,2 мм; Face не являлся причиной этих пиков.
- Candidate3: поднята только верхняя кромка с пересчётом сечения/весов. Те же четыре
  проблемных луча сначала пересекают ворот; кожа позади на 3,3–7,3 мм.
- Headless генерация обоих костюмов и [проверка сохранности](preservation.json):
  exit 0, failures 0; все 120/120 новых вершин каждого воротника используются.
  [Контур](boundary-probe.json), [ray юноши](candidate3-edge-0-ray.json),
  [ray девушки](candidate3-edge-1-ray.json), [неизменные assets](unchanged-assets.json).

Финальный candidate3 GPU: **19/0, exit 0/ERROR 0, 10,58 с**, RTX4070/Vulkan.
Автор правки Sol лично осмотрел все 14 итоговых PNG; независимый Sol также лично
осмотрел все 14 и дал **CODE + scoped ART PASS**. Кромка чистая на обеих основах,
тон кожи/палитра/reset согласованы, default/far без новых накладок. [Final log](after-sport-neck.log),
[summary](after-summary.json), [PNG SHA256](png-sha256.json).
[Sport manifest](manifest-verification.txt) записан после ART и отдельно проверен.
Все GPU запуски выполнялись только через
`tools/check.py` и штатный свёрнутый нефокусируемый offscreen wrapper, 60 FPS.

## Воспроизведение

```bash
SFERY_SPORT_NECK_STAGE=candidate3 python3 tools/check.py --profile presentation --checks sport-neck
```

Стенд охватывает default/full, neck front/angle, skin tone, палитру, reset и far
обеих основ. Кадры: [до](before/), [итог](after/), [отказ candidate1](candidate1/),
[отказ candidate2](candidate2/).

| Основа | До | Итог |
|---|---|---|
| Юноша | [front](before/0-sport-neck.png) | [front](after/0-sport-neck.png), [angle](after/0-sport-neck-angle.png) |
| Девушка | [front](before/1-sport-neck.png) | [front](after/1-sport-neck.png), [angle](after/1-sport-neck-angle.png) |

Headless геометрические helper scripts сохранены
рядом с отчётом; исходный task baseline — `/tmp/orbstrike-sport-neck-baseline`.

Анимации и движения горловины в матче не проверялись. Сервер, новые матчи, весь
каталог, Windows, прослушивание, сборка и публикация не запускались. Внешний Blender QA-пилот — отдельная задача и не входит в эти PASS.

## Изменённые файлы

Production: `tools/avatars/build_sport_set.gd`, `assets/avatars/sport/tracksuit_0.res`,
`tracksuit_1.res`, `manifest.json`. Узкий стенд: `tools/test_sport_neck.gd` и адресная
регистрация в `tools/check.py`. Обновлены TODO/NEXT_SESSION/CHANGELOG/SESSION_LOG и
уточнение старого отчёта. [Изолированный text patch](task-only.patch),
[SHA изменённых файлов](task-files.json). Большой прежний dirty tree сохранён. `git diff --check` — PASS; коммитов и релиза нет.
