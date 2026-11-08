> Исправление доказательств: прежние20moving poses/12witness head-relativeΔ0
> НЕ ПОДТВЕРЖДЕНЫ: inherited actor оставался скрытым, _process не двигал skeleton.
> Geometry/hash/import/reproduction/ART факты сохранены; dynamic witness/GPU OPEN.
> Исторические повторы не выполнялись по указанию автора.
> [Подробности](../2026-11-06-gpu-acceptance/motion-claims-revoked.json).

# A04 — исправление «лепёшки между рогов», 6 ноября 2026

Установлен `assets/creatures_hd/ratnik_light.glb`, SHA256
`d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70`.
Прежняя художественная приёмка `b209b4…` отозвана после замечания автора.
Новый независимый Sol high принял крупные фронт/четверть/бок/верх/игровой вид:
лепёшка и открытая чаша исчезли, тёмный клин не читается отдельным листом.
Более светлые концы рогов и небольшая гранёность переходов отмечены как неблокирующие.

[До / после — фронт](before-after-front.png) · [До / после — игровой 3/4 сверху](before-after-game.png) · [Исходный 2D-концепт](original-concept.png).
Это CPU baseColor + normals в raw rest; изображения не являются GPU/cloth/игровой приёмкой.

## Причина и исправление

Первый ремонт заполнил двумя широкими крышками контуры бывшего диска и сохранил
золотую заднюю перемычку обода. Поэтому между настоящими рогами получился широкий
нависающий овал. Однородный atlas footprint и неверный переход нормалей усиливали
вид наклеенной лепёшки. Цветовая маска brown1335 пропустила золотой обод.

Теперь над настоящей головой находится округлая продольная крыша; две верхние
ветви рогов имеют компактное сечение и постепенно сходятся к свободным концам.
696 исходных треугольников верхней дисковой области удалены; передние ребристые
изгибы, лицо, тело и тонкий нимб сохранены. Крыша и два корня построены как три
согласованных участка одного граничного контура, без прежней ошибочной DP-полосы.
Триангуляция, FEM и подъём крыши используют одну непересекающуюся проекцию.

Оставшийся тёмный клин локализован face-ID рендером: 22 треугольника старой
тёмной подложки и ошибочные блики соседнего нового шва. Их точная геометрия и
все восемь весов скопированы с локальной золотой палитрой/нормалями; соседние новые
нормали согласованы с крышей. Это отделка стыка, а не изменение лица или текстурных
картинок. Исходные UV/skin/POSITION/NORMAL streams 84900 вершин побайтово прежние.

## Контракт и проверки

- [Точный контракт PASS](geometry-contract.json): исходный BIN-prefix 33360576 байт,
  rig/rest/binds/clips/images/materials, самостоятельное кольцо и CapeGPU точны;
  113342 retained source-tri точны, новые 3387 tri/1833 вершины, 225 seam/palette
  вершин сохраняют source POSITION + все 8 influences, 1608 interiors head11/weight1.
  Новых внешних незамкнутых рёбер нет.
- Воспроизводимый `tools/models/build_ratnik_light_helmet.py` заново получил
  **тот же полный d51ab2… SHA**, не только эквивалентные активные массивы.
  Geometry identity отделки с проверенным `23403d…` доказана для каждого треугольника.
- [Raw BVH](raw-bvh.json): cap/self **0**, cap/body **3**. Его машинный статус
  **FAIL**, нулевого PASS нет. Это три коротких пересечения двух новых треугольников
  с тремя исходными треугольниками лобного перехода. Длины сегментов в source units:
  0.00048820 / 0.00024832 / 0.00023500. [Точные вершины/веса/сегменты](witness.json).
- Эти контакты приняты только в указанном ограниченном объёме: независимый осмотр
  крупных изображений не обнаружил внешнего артефакта; actual Godot 20 поз
  idle/attack/hit/appear измеряют именно 12 involved вершин относительно головы.
  Измеренная head-relative дельта **0 в Godot float32**; сохранены20поз/1уникальный bitdigest, ordinarywitnessdelta0. Raw веса не абсолютно
  одинаковы: head >=0.99982667, поэтому это измерение поз, не непрерывное доказательство
  жёсткости всех возможных анимаций.
- Pre-promotion CreatureBall/import: **18080/0**, 20 поз, source/candidate palettes
  и 64 защищённых body/cape world points delta0. Нормализация scale/offset/height/extent
  сохранена. Ordinary resource/SCN: **27745/0**, exit0 без ERROR/leaks;153632tri/3surfaces.
  Ориентированные triangle-position fingerprints всех поверхностей совпадают с
  frozen direct GLTF; editor переупорядочил vertices и разрешил named skins.
  Ordinary palette delta5.96e-8, 64body/cape world delta2.3842e-7; source/candidate0.
  [Установленный runtime](../2026-11-06-model-a04-reopen-runtime/installed.json) ·
  [Факт импорта/SCN](../2026-11-06-model-a04-reopen-runtime/import-evidence.json).

Production установлен атомарно после immutable b209 backup в
`build/model_candidates/2026-11-06-a04-reopen/source/ratnik_light.glb`.
Штатный editor фактически выполнил reimport/save ratnik_light и записал новый SCN;
формальный import check остаётся FAIL из-за sandbox TCP служебного socket.
Обычный UID не менялся. Guard нормализации принимает новый count153632 и прежний
156366 только при прежнем exact active AABB; source body/motion frame сохранён.

CapeGPU byte identity не означает неизменную GPU cloth/collider симуляцию.
R01 cloth/rim/освещение остаётся открытым; GPU, Windows, звук, физический матч,
сервер, сборка и публикация этим этапом не проверялись. A03 форма и Tripo доступ
этим исправлением не закрываются.

## Воспроизведение

```bash
python tools/models/build_ratnik_light_helmet.py --source build/model_candidates/2026-11-06-a04-reopen/source/ratnik_light.glb --original build/model_candidates/2026-11-06-sculpt/source/ratnik_light.glb --output build/model_candidates/2026-11-06-a04-reopen/reproduced.glb
python tests/ratnik_light_helmet_integrity.py build/model_candidates/2026-11-06-a04-reopen/source/ratnik_light.glb build/model_candidates/2026-11-06-a04-reopen/accepted.glb build/model_candidates/2026-11-06-a04-reopen/graph-root.glb build/model_candidates/2026-11-06-a04-reopen/reproduced.manifest.json docs/audits/2026-11-06-model-a04-reopen/geometry-contract.json
python tools/check.py --profile models --checks ratnik-crown-reopen --logic-only
```

Успешные проверки не повторять без нового изменения/конкретной причины.
