# Текущий результат A03 — PARTIAL material-only

**Выбран muted_violet SHAca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f.**
Текущий отчёт: [MATERIAL_REPORT.md](MATERIAL_REPORT.md). Геометрия/UV/skin исходные exact,
каждая149994sourcefaceровно1раз;10443подтверждённых бледных effecttri используют
фиолетовый материал,139551остальныхtri — исходный. Форма A03 остаётся открыта.
Все геометрические cap-кандидаты ниже отклонены; production ими не заменять.

---

Ниже сохранена история ранних попыток, не актуальное разрешение установки.

# A03 — локальный shoulder graft и pose-followup

> **Обязательный pose-followup:**845daf не прошёл actual Godot46pose-проверку:
>443новых pair-instance (441caps и2clipped-only),607доказанноунаследованных
>source-пар;0неопределённых adjacent. `posed-scope.json` имеет FAIL.
>Этот файл ниже описывает raw-rest приёмку старого кандидата, не разрешение установки.
>Идёт локальная коррекция границы левого graft под переплетённым корнем.

**Текущий результат: CPU-геометрия и сохранение данных PASS; кандидат подготовлен
для отдельной приёмки импорта/поз/support.** Предыдущие два прототипа отклонены;
их результаты сохранены в `REPORT.md` ниже текущего статуса.

Кандидат: `build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb`.
SHA256: `845dafef53e0cb4476de6a9561a28a903f6bb4692dcf1569c93c19d1971c05a2`.
Исходник сохранён отдельно: `build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb`,
SHA256 `6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c`.
В этом подзадании production не заменялся. Установка/импорт принадлежат общему этапу.

> Следующие узкие плоскости также отклонены:0430 —53новых pair-instance,
>0415 —127. Перебор плоскостей остановлен. Текущая попытка: новые внутренние
>Steiner-вершины и малый выпуклый cap-interior при точном истинном seam; PENDING.

## Изменение и художественная оценка

Sol high лично рассмотрел concept, исходник, пространственные маски, промежуточные
результаты и финальные четыре CPU-вида из `final-before-after-mask.png`.
Белые непрозрачные листы/завитки устранены. Вместо них обе плечевые стенки закрыты
наклонными тёмными поверхностями, продолжающими бронированный силуэт. Лицо/глаз,
рога и шея читаются отдельно; задняя и нижняя броня сохраняют исходные детали.
Низкие остатки корня сохраняют исходную форму и skin, но получают тёмную броневую
палитру, чтобы белые основания больше не выглядели обломками дыма.

Прямоугольный Boolean-cut уже был математически корректен, но создавал высокий
плоский брусок со стороны шеи. Он отвергнут художественно. Финальный резак следует
плечевому скату: выше возле шеи, ниже к наружному краю. Полупрозрачный VFX не добавлен.
Оценка относится к техническому CPU raw-rest виду, без игрового освещения/шейдера.

## Локальная операция и точный whitelist

Геометрическая область слева: `x<−.13,z>.06,y>max(.205,.445+.6*x−.5*z)`;
справа: `x>.225,z<.06,y>max(.205,.42−.6*x+.5*z)`.
За пределами этих областей исходные грани возвращаются из GLB, даже если Blender
Boolean попытался пересечь существующие self-intersections в другой части тела.
Это существенно: глобальная выдача Boolean целиком не используется.

Полный whitelist и соответствия находятся в
`final/kolossar_shadow.graft.json`:

- `roi_source_face_ids` — все исходные грани, чьи AABB касаются локального резака;
- `retained_source_face_ids` —134261неизменная исходная грань в исходном порядке;
- `removed_source_face_ids` —11713вырезанных/разделённых граней плюс4020UV-корней;
- `recolored_original_face_ids` —4020точных исходных треугольников корня;
- `new_surface_source_face_ids` — source face для каждого нового треугольника,
  `−1` только для412новых cap-граней.

Новая surface содержит5055tri:623клиппированных исходных,412cap и4020исходных
корней с изменением только UV. Итог139316tri вместо149994.
UV корней и caps выбирают существующий тёмный участок собственного атласа; сами
изображения/материалы не меняются. Вершины на пересечённых source-треугольниках
получают барицентрически перенесённые UV/нормали/skin influences. Совпадающие новые
позиции получают один канонический набор восьми skin-влияний; исходные вершины
копируют исходные данные точно. Внутренние углы резака получают локальную смесь
ближайших исходных shoulder-весов. Новых костей или клипов нет.

## Доказательства

`final-integrity.json` и `final-intersections.json` относятся точно к SHA выше:

| Контракт | Результат |
|---|---|
| Исходные270accessor и binary-prefix | byte exact |
| nodes/rest/skin/binds/clips/images/material/extras | exact |
| Вне whitelist | исходные faces/attributes exact |
|4020UV-корней | POSITION/NORMAL/JOINTS0/1/WEIGHTS0/1 exact; UV only |
| Открытые рёбра / компоненты |0 /1 |
| Исходные неманифолдные рёбра |3сохранены exact;0новых |
| Новые вырожденные треугольники |0 |
| Новые не-соседние BVH-пересечения |0 |
| Body/new seam skin influence delta |0.0 |
| Повторённые направленные рёбра | исходные6, итог6; новых нет |

Нулевые boundary/BVH не заменяют позы. Наборы skin обеих сторон нового шва совпадают,
поэтому при одинаковых bone matrices шов не расходится; новые поверхности ещё должны
проверяться в фактических импортированных позах/support.

Все исходные stored POSITION сохранены, включая уже не индексируемый верхний дым:
accessor-AABB прежний. Это не предположение о Godot importer: его фактическая
нормализация/skin/imported poses принимаются отдельно общим этапом.

## Воспроизведение

Из корня проекта (все пути кандидатов отдельные):

```bash
blender -b --factory-startup -P tools/models/export_kolossar_shadow_graft.py -- build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/boolean-sloped-patch.npz
python tools/models/build_kolossar_shadow_graft.py --source build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb --geometry build/model_candidates/2026-11-06-a03/boolean-sloped-patch.npz --output build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb
blender -b --factory-startup -P tools/models/check_kolossar_shadow_caps.py -- build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb docs/audits/2026-11-06-model-a03/final-intersections.json
python tests/kolossar_shadow_graft_integrity.py build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/final/kolossar_shadow.graft.json docs/audits/2026-11-06-model-a03/final-intersections.json docs/audits/2026-11-06-model-a03/final-integrity.json
python tools/models/review_kolossar_shadow_graft.py --source build/model_candidates/2026-11-06-a03/baseline/kolossar_shadow.glb --candidate build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb --manifest build/model_candidates/2026-11-06-a03/final/kolossar_shadow.graft.json --output docs/audits/2026-11-06-model-a03
```

Blender использован как CPU geometry/BVH-утилита без рендера/окна. Узкая BVH проверяет
новую surface против оставленного тела и самой себя, исключая геометрических соседей.
Старые отклонённые прототипы не устанавливать. Сервер/релиз не затронуты.
