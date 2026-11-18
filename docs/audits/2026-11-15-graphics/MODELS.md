# Игровые модели Orbstrike · 15 ноября 2026

Проверена рабочая копия клиента 0.4.5 под Linux, Godot 4.7.2, Vulkan Forward+,
RTX 4070 Laptop GPU. Стенд использует фактический каталог, подготовку мешей,
материалы, клипы и коррекцию опоры клиента. Существа поставлены в одинаковом
нейтральном свете на плоскости `y = 0`, с камерой сравнения. Игровой пол и верх
карты соответствуют нулю модели после компенсации радиуса оболочки. Сценарий
не включает перемещение по воротам, игровой свет, время постановки удара и
эффекты владельца. [Нулевая точка фигуры](../../../scenes/creature_ball.gd#L246) ·
[Сводка прогона](../../../build/checks/models/graphics-audit-20261115/catalog/runtime.json) ·
[Лог GPU](../../../build/checks/models/graphics-audit-20261115/catalog/engine.log).

## Подтверждённые замечания

| Код | Наблюдение | Локализация и доказательства |
|---|---|---|
| **MOD-01 · P2** | **У Рогожуков Камня и Света плоскость срезает части лап.** У Камня в замахе на 0,417 с исчезает нижний край правой задней лапы. Самая низкая вершина на 7,02% роста ниже пола, 928 из 115 369 вершин ниже 2,5% роста. У Света на 0,383 с замаха нога обрезана на 5,13% роста, 313 из 91 410 вершин ниже 2,5%. В реакции Света на 0,383 с низ правой опорной лапы уходит под пол на 3,88%, 241 вершина ниже 2,5%. Снятие плоскости возвращает срезанные части в тех же позах. | У крайних вершин замаха обеих моделей вес `rear_thigh.R = 1.0`, в реакции Света — `foot.R ≈ 0.899` и `shin.R ≈ 0.101`. Коррекция ориентируется на выборки подошв. Для Камня и Прилива они расширены, для Света действует общая выборка. [Коррекция](../../../scenes/creature_support.gd#L184) · [Выборка вершин](../../../scenes/creature_support.gd#L262) · [Камень, замах](../../../build/checks/models/graphics-audit-20261115/sheets/rogozhuk_stone-windup-witness.webp) · [Свет, замах](../../../build/checks/models/graphics-audit-20261115/sheets/rogozhuk_light-windup-witness.webp) · [Свет, реакция](../../../build/checks/models/graphics-audit-20261115/sheets/rogozhuk_light-hit-witness.webp) · [Точные координаты и веса](../../../build/checks/models/graphics-audit-20261115/floor-witness/runtime.json). |
| **MOD-02 · P3** | **У игрового Горгула Тени у оснований крыльев заметны ломаные пятна.** Во фронтальном ожидании и при виде сзади в реакции рисунок светлых и тёмных участков ломается возле соединения крыла с телом. В исходном листе перепонка читается цельной, с тёмной кромкой и непрерывными прожилками. Глаз, рога, раскрытые крылья и хвост сохраняют узнаваемость. | В текущем `gorgul_trellis/gorgul_shadow.glb` пять поверхностей получают цвет из вершин. По одному снимку нельзя отнести границу между цветом вершин, фасетками и светом. Ломаные пятна заметны и в ранее снятом ракурсе Каньона. [Подключение](../../../scenes/creature_models.gd#L111) · [Материал](../../../scenes/creature_models.gd#L382) · [Фронт](../../../build/checks/models/graphics-audit-20261115/catalog/frames/gorgul_shadow-idle-front.png) · [Реакция сзади](../../../build/checks/models/graphics-audit-20261115/catalog/frames/gorgul_shadow-hit-rear-three-quarter.png) · [Каньон](../../../build/checks/presentation/graphics-ui-audit-20261115/catalog-probe/creature_gorgul_shadow.png) · [Исходный лист и нейтральный мастер](../../../art/models/new_creatures/2026-11-15/gorgul-trellis-refinement/comparison.webp). |
| **MOD-03 · P3** | **На бомбере обеих основ видны мелкие выступы, у Виты заметнее.** В профиль в ожидании у Виты № 7 и Сакурады № 6 перед торсом торчат короткие угловатые фрагменты. На 0,68 с «Победы» у Виты из зелёной ткани груди и живота проступают тёмные раздельные линии, а в открытии ворот виден треугольник сбоку. | Генератор утолщает торс, сохраняет нижнюю часть донорской молнии и добавляет отдельные кромки карманов. Начальная локализация — совмещение отделки с тканью в деформированной позе. Принадлежность каждого фрагмента конкретному слою не измерялась. [Ресурсы обеих основ](../../../scenes/avatar/vrm_parts.gd#L16) · [Построение отделки](../../../tools/avatars/build_street_set.gd#L67) · [Профиль Виты](../../../build/checks/wardrobe-catalog-motion/audit-20261115-graphics-models/1-07-side.png) · [Ворота Виты](../../../build/checks/wardrobe-catalog-motion/audit-20261115-graphics-models/1-07-gate-62.png) · [Победа Виты](../../../build/checks/wardrobe-catalog-motion/audit-20261115-graphics-models/1-07-victory-68.png) · [Профиль Сакурады](../../../build/checks/wardrobe-catalog-motion/audit-20261115-graphics-models/0-06-side.png). |

В реакции Рогожуков Камня и Прилива сохраняются меньшие пересечения. Камень
0,383 с — 1,16% роста, Прилив 0,383 с — 1,29%. В этой фазе ни одна вершина
этих двух моделей не проходит глубже 2,5% роста. У Левиана Прилива зазор
опорного витка около 0,0001 единицы мира во всех пяти точно измеренных фазах.
Горгул Тени остаётся в воздухе, с измеренным зазором 27,1% роста в ожидании.
[Точные измерения](../../../build/checks/models/graphics-audit-20261115/exact-headless/runtime.json).

## Что просмотрено

| Группа | Визуальная выборка |
|---|---|
| Драгнар, Горгул, Грифалон | Крылья, сочленения, ноги на парении и в контакте. У Драгнара профиль показывает цельную линию голени в кадре ожидания. В сравнении Грифалонов перья явно раскрываются к контакту у всех шести стихий. У Горгула Тени более тяжёлые ноги, круглый глаз и сплошные пурпурные поверхности заметно отличают новую версию от остальных пяти. [Драгнар](../../../build/checks/models/graphics-audit-20261115/sheets/dragnar.webp) · [Горгул](../../../build/checks/models/graphics-audit-20261115/sheets/gorgul.webp) · [Грифалон](../../../build/checks/models/graphics-audit-20261115/sheets/grifalon.webp). |
| Клыкарь, Рогожук, Левиан | Клыкарь сохраняет форму четырёхногого зверя с читаемой мордой. Прежние отдельные ветровые щитки перед лицом Клыкаря Бури и толстый обрывок за шеей Левиана Бури не видны в свежих ракурсах. У всех Левианов читаются виток, высокая шея и крылья. Кадры Рогожука уточнены отдельным проходом MOD-01. [Клыкарь](../../../build/checks/models/graphics-audit-20261115/sheets/klykar.webp) · [Рогожук](../../../build/checks/models/graphics-audit-20261115/sheets/rogozhuk.webp) · [Левиан](../../../build/checks/models/graphics-audit-20261115/sheets/levian.webp) · [Прежние A01/A02](../../MODEL_REPAIRS_2026-11-06.md). |
| Колоссар, Ратник, Ликорез | Колоссар Тени имеет различимый фиолетовый глаз и остаётся в своей гамме на плечах. Ратник во всех стихиях сохраняет меч, отдельные рога и свободный нимб; в ракурсе сзади видна GPU-ткань. Фронтальный ракурс контакта укорачивает видимый клинок перспективой. Ликорез в покое читается по шести рукам, клинкам и нескольким маскам, в профиле руки перекрывают друг друга. [Колоссар](../../../build/checks/models/graphics-audit-20261115/sheets/kolossar.webp) · [Ратник](../../../build/checks/models/graphics-audit-20261115/sheets/ratnik.webp) · [Ликорез](../../../build/checks/models/graphics-audit-20261115/sheets/likorez.webp). |
| Армат, Флорис, Окто | Узнаются по низкому панцирю и булаве, раскрывающимся створкам и общему силуэту щупалец. У всех вариантов силуэт и ключевые позы соответствуют внутри семейства, различается окраска. Для Армата кадры общего каталога подтверждают видимость конечностей под панцирем в четырёх ракурсах. Задние суставы в пике рыка ими не оценивались. [Армат](../../../build/checks/models/graphics-audit-20261115/sheets/armat.webp) · [Флорис](../../../build/checks/models/graphics-audit-20261115/sheets/floris.webp) · [Окто](../../../build/checks/models/graphics-audit-20261115/sheets/octo.webp). |
| Сакурада и Вита | Просмотрены стандартные материалы 25 доступных локальных костюмов: профиль и спина ожидания, две фазы открытия ворот и две фазы победы. У мантии Сакурады № 9 в осмотренных фазах победы нет прежнего крупного разрыва под левым рукавом. Бомбер — MOD-03. [Листы 1](../../../build/checks/models/graphics-audit-20261115/sheets/wardrobe-1.webp), [2](../../../build/checks/models/graphics-audit-20261115/sheets/wardrobe-2.webp), [3](../../../build/checks/models/graphics-audit-20261115/sheets/wardrobe-3.webp), [4](../../../build/checks/models/graphics-audit-20261115/sheets/wardrobe-4.webp), [5](../../../build/checks/models/graphics-audit-20261115/sheets/wardrobe-5.webp) · [Состав и фазы](../../../build/checks/wardrobe-catalog-motion/audit-20261115-graphics-models/summary.json). |

Рабочие исходники используют один меш TRELLIS.2 с шестью палитрами Ратника
и единственный новый меш для Горгула Тени. В PCK 0.4.5 refresh записаны
прежние шесть файлов Ратника и прежний Горгул Тени. Все игровые Левианы
по-прежнему используют `assets/creatures_hd/levian_*.glb`. Студийные пробы
Левиана, Флориса и Ликореза лежат в `art/`. В локальном редакторе
25 костюмов, по checkpoint Windows-пакет содержит 24; дирндль Виты
намеренно исключён из экспорта. [Выбор модели](../../../scenes/creature_models.gd#L111) ·
[Состав PCK](../../../build/checks/release045-refresh-independent/static.json) ·
[Состав гардероба в пакете](../../../tools/checkpoints/release045-inputs.json).

## Воспроизведение и результаты

- Полный замер каталога — **67 существ, 536 поз, 268 PNG, 0 ошибок**. На существо
  проверены грузящийся меш, все пять клипов, конечные трансформы костей и отклик
  сигнала контакта. Измерены восемь состояний: ожидание, поза появления, рёв,
  замах, контакт, восстановление, реакция, возврат в ожидание. Графическая
  выборка — фронт и профиль ожидания, три четверти у контакта, задние три четверти
  реакции. Меши дали 250 активных поверхностей, 125 с albedo-картой, пять
  поверхностей Горгула Тени с цветом вершин и шесть актёров с GPU-плащом.
  В широком замере бралась каждая седьмая вершина, GPU-плащ оценивался по кадрам.
  [Код пробы](creature_probe.gd) · [Результат](../../../build/checks/models/graphics-audit-20261115/catalog/runtime.json).
- Камень, Свет и Прилив — **6 точных поз, 55 PNG, 0 ошибок**. Измерена каждая
  вершина, у выявленных пересечений сняты четыре пары кадров с полом
  и без. Дополнительный headless-проход по трём Рогожукам, Левиану Прилива
  и Горгулу Тени — **25 точных поз, 0 ошибок**. [GPU](../../../build/checks/models/graphics-audit-20261115/floor-witness/runtime.json) ·
  [Headless](../../../build/checks/models/graphics-audit-20261115/exact-headless/runtime.json).
- Штатный редактор — **202/0, 25 костюмов, 150 PNG**. Он использует `VrmFighter`
  и штатный сэмплер движения. Сочетания каждой одежды с каждой причёской и
  аксессуаром, все палитры, все моменты клипов и постановка героев на разных
  аренах остаются вне этого прогона. [Тип экземпляра](../../../scenes/ui/character_editor.gd#L38) ·
  [Лог редактора](../../../build/checks/presentation/selected-wardrobe-catalog-motion/wardrobe-catalog-motion.log).
- Штатный `vrm-fighter` — **15 800/0**. Осмотрены карты способностей и ворот
  в руках обеих основ, стойка, бросок, команда, победа и поражение. Лицевую
  сторону удерживают четыре пальца, край карты не пересекает кисть в
  просмотренных крупных кадрах. Стенд проходит 15 штатных костюмов в цикле
  проверки кистей и использует оба банка анимации. Копия штатного сценария
  перенаправляла только пути PNG в каталог аудита. [Лог](../../../build/checks/models/graphics-audit-20261115/vrm-fighter/run.log) ·
  [Движения](../../../build/checks/models/graphics-audit-20261115/vrm-fighter/motions.png) ·
  [Реакции](../../../build/checks/models/graphics-audit-20261115/vrm-fighter/reactions.png) ·
  [Карта способности, Сакурада](../../../build/checks/models/graphics-audit-20261115/vrm-fighter/grip-0-0.png) ·
  [Карта ворот, Вита](../../../build/checks/models/graphics-audit-20261115/vrm-fighter/gate-grip-1-6-front.png).
- Headless `animation` завершился **597/0**. Подпись «48 моделей» в логе
  захардкожена, цикл проходит `CardDB.all_creatures()`, отдельно от редкого
  Ликореза. `hd-material-retention` — **99/0**, проверка контрактов материала
  на фикстуре. [Анимации](../../../build/checks/models/selected-animation-support-hd-material-retention/animation.log) ·
  [Материалы](../../../build/checks/models/selected-hd-material-retention/hd-material-retention.log).
- **Штатный `support` падает на первом Грифалоне.** У `grifalon_fire` с
  авторским воздушным комплектом `_support == null` по штатной ветке
  `CreatureAnim`. Стенд сначала регистрирует ошибку, потом читает
  `support.limbs` и перестаёт продвигаться. Сеанс ограничен тайм-аутом 95 с.
  Это дефект самого стенда и дыра в штатном профиле, поэтому свидетельства
  MOD-01 собраны отдельной пробой. [Условие создания опоры](../../../scenes/creature_anim.gd#L164) ·
  [Обращение к null](../../../tests/support_tests.gd#L18) ·
  [Ошибка движка](../../../build/checks/models/selected-animation-support-hd-material-retention/support-engine.log).

Команды из корня проекта. Папки вывода уникальны для аудита.

```sh
audit="$PWD/build/checks/models/graphics-audit-20261115"
run_model_probe() {
    out="$audit/$1"
    mode="$2"
    shift 2
    mkdir -p "$out"
    window_flags=(--windowed --position -20000,-20000)
    if [ "$mode" = headless ]; then window_flags=(--headless); fi
    XDG_CONFIG_HOME="$out/config" XDG_DATA_HOME="$out/data" \
        godot --path . --max-fps 60 "${window_flags[@]}" --audio-driver Dummy \
        --log-file "$out/engine.log" \
        -s res://docs/audits/2026-11-15-graphics/creature_probe.gd -- "$out" "$@"
}

run_model_probe catalog gpu
run_model_probe floor-witness gpu \
    --detail --floor-witness --poses=windup,hit rogozhuk_light,rogozhuk_stone,rogozhuk_tide
run_model_probe exact-headless headless \
    --detail --poses=idle,windup,attack,recovery,hit rogozhuk_light,rogozhuk_stone,rogozhuk_tide,levian_tide,gorgul_shadow

SFERY_WARDROBE_CATALOG_STAGE=audit-20261115-graphics-models \
    python tools/check.py --profile presentation --checks wardrobe-catalog-motion
python tools/check.py --profile presentation --checks vrm-fighter
timeout 95s python tools/check.py --profile models --logic-only --checks animation support hd-material-retention
python tools/check.py --profile models --logic-only --checks hd-material-retention
```

Графические пробы прогонялись в свёрнутом нефокусируемом окне c ограничением
60 FPS, через `tools/test_window.gd`. Измерения относятся к конечным позам
в перечисленных фазах, без непрерывного поиска пересечений сетки и проверки
каждой промежуточной фазы, коллизий ткани, полного физического матча и Windows.
