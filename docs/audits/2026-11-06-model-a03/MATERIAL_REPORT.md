# A03 — частичная коррекция материала; форма открыта

**Интеграция:** выбранныйca2580установленпослеbackup; ordinaryCreatureBall/ShaderMaterial
split139551/10443,pose/world0,11473/0. [Отчёт](../2026-11-06-model-sculpt-runtime/material-installed.json).
ФормаA03остаётсяоткрыта,небезопасныеgeometryвариантыне установлены.


**Текущий выбранный кандидат: material-only PARTIAL. Полный ремонт формы A03 не выполнен.**
Белые плечевые эффекты получили сдержанный фиолетовый оттенок. Их исходные угловатые
листы/завитки сохранены. Это безопасное улучшение цветовой иерархии с тождественными
исходными геометрией, UV и skin; отклонённые cap-кандидаты не устанавливаются.

Кандидат: `build/model_candidates/2026-11-06-a03/material/muted_violet.glb`.
SHA256: `ca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f`.
База: `build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb`,
SHA256 `6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c`.

## Художественный выбор и маска

Sol high лично рассмотрел concept, исходник, четыре вида точной маски и все3×4вида
палитр. `muted_violet` сохраняет светотеневые складки/микродетали собственного атласа,
но убирает резкий белый контраст рядом с глазом. `soft_lavender` сильнее перетягивает
внимание вверх; `smoky_violet` сливает складки в тяжёлые тёмные пятна.
Силуэт исходных угловатых эффектов остаётся заметен во всех вариантах.

| Палитра | multiplier RGB | Решение |
|---|---|---|
| soft_lavender |0.58,0.38,0.72 | Верх слишком активен. |
| muted_violet |0.38,0.22,0.52 | Выбран сдержанный фиолетовый. |
| smoky_violet |0.24,0.14,0.34 | Слишком тёмный, хуже читаются складки. |

Свидетельства: `material/tint-comparison-four-views.png`, отдельные полосы
`material/{palette}-four-views.png` и `material/exact_material_mask-four-views.png`.
Это CPU raw-rest техническая оценка, без GPU/игрового освещения.

Маска сужена относительно прежней маски геометрического эксперимента15169tri.
Теперь выбраны только две крупные связные бледные области эффекта:
6323слева+4120справа=10443tri. Условия: value>.24,saturation<.30, локальные bounds
слеваx<−.13,z>.06 и справаx>.23,z<.06. Остальные тёмные корни/паулдроны,
шея и мелкие отдельные бледные блики брони исключены. Вся остальная броня/тело
139551tri сохраняет исходный материал. Полный whitelist face-ID находится в
`material/muted_violet.tint.json`.

## Строгий контракт

`material/integrity.json` — PASS полного source-контракта:

- Все270исходных accessor и весь исходный binary-prefix byte exact.
- POSITION/NORMAL/UV/JOINTS0/1/WEIGHTS0/1, nodes/rest/bind/clips/images точны.
- Обе primitive ссылаются на те же исходные attribute-accessor; новых вершин нет.
- Все149994исходных треугольника присутствуют ровно один раз, с точными индексами;
 139551tri используют исходный материал,10443tri — его фиолетовый дубликат.
- Исходный материал неизменен. В новом отличаются только имя и RGB baseColorFactor;
 alpha, собственные atlas/PBR/normal textures и doubleSided точны.
- Проверен целиком ожидаемый JSON и весь BIN. Разрешены только два дописанных
 index-stream, partition primitive и один material duplicate. Никаких UV-перезаписей.

Из тождественности всех треугольников и skin следует тождественная поверхность при
любой одинаковой bone palette. Новых геометрических пересечений этот материал-only
вариант создать не может; старые source-контакты сохранены. Повтор46BVH не нужен.
Проверку фактического обычного Godot resource path и shader tint выполняет общий этап.
`CreatureModels._fix_hd_materials()` передаёт `src.albedo_color` в shader `tint`,
поэтому новый материал имеет рабочий путь к аниме-материалу, без правки runtime.

## Почему cap-ремонт отклонён

| Геометрическая попытка | Результат |
|---|---|
| Старый planar prototype |48raw пересечений,23новых неманифолдных ребра. |
| Harmonic prototype |174raw пересечения. |
| Sloped845daf | Raw-rest PASS, но46фактически экспортированных Godot поз дали443новых pair-instance:441caps+2clipped;607точно унаследованных source-пар. |
| Plane0430 |53новых pair-instance в46CPU-проекциях actual source palettes;2унаследованных. |
| Plane0415 |127новых pair-instance;0унаследованных. |
|0430+Steiner/bulge.002 |690новых pair-instance;2унаследованных. Отклонён. |

`posed-scope.json` сохраняет точный FAIL845daf с сопоставлением каждой пары source
face-ID и реальной source-проверкой в той же позе. Новый cap не может «унаследовать»
source-пересечение. Ни критерий соседства, ни near-zero threshold не ослаблялись.
Следующие варианты честно обозначены CPU-проекциями, не новым запуском Godot.
Projection tool доказал bone-name mapping, исходные binds/frame и точное правило
Godot8weight packing на всех111734source и15165actual845dafновых вершинах:
последовательная float32-сумма8весов, normalization, floor(weight*65535)/65535.

`boundary-witness0430.json` доказывает, что interior-only исправление невозможно:
в attack24 истинный неизменяемый cap/body boundary segment пересекает внутренность
nonadjacent body(sourceface23143):segment t=.5826395,bary=(.102692,.303552,.593756).
Это строгое пересечение, без порога глубины. Все418старых cap-точек лежали на
реальном seam, свободных внутренних вершин не было. Steiner попытка добавляла
только внутренние точки, оставляя433истинных seam-edge точными, и тоже отклонена.

Независимый Sol high пересчитал witness и подтвердил вывод. Отдельный idle0 контакт
cap764/body101 — тоже ненулевое пересечение, длина около1.28e−5 и signed distances
к cap-plane от−5.24e−6до+6.66e−6; это не объявлено «погрешностью».
Независимые данные: `../2026-11-06-model-sculpt-runtime/contact-witness-review.json`
и `contact-witness-conclusion.json` в том же каталоге.

## Воспроизведение выбранного материала

```bash
python tools/models/tint_kolossar_shadow_smoke.py --source build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb --output build/model_candidates/2026-11-06-a03/material/muted_violet.glb --palette muted_violet
python tests/kolossar_shadow_tint_integrity.py build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/material/muted_violet.glb build/model_candidates/2026-11-06-a03/material/muted_violet.tint.json docs/audits/2026-11-06-model-a03/material/integrity.json
python tools/models/review_kolossar_shadow_tints.py --source build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb --candidates build/model_candidates/2026-11-06-a03/material/soft_lavender.glb build/model_candidates/2026-11-06-a03/material/muted_violet.glb build/model_candidates/2026-11-06-a03/material/smoky_violet.glb --output docs/audits/2026-11-06-model-a03/material
```

Сервер/релиз и принятые030–035 не затронуты. В этом подзадании production GLB не
заменялся; обычную интеграцию выбранного материала ведёт общий этап.
