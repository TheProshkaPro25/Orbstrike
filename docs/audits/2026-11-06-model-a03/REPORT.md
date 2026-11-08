# Текущий результат A03 — PARTIAL material-only

**Выбран muted_violet SHAca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f.**
Текущий отчёт: [MATERIAL_REPORT.md](MATERIAL_REPORT.md). Геометрия/UV/skin исходные exact,
каждая149994sourcefaceровно1раз;10443подтверждённых бледных effecttri используют
фиолетовый материал,139551остальныхtri — исходный. Форма A03 остаётся открыта.
Все геометрические cap-кандидаты ниже отклонены; production ими не заменять.

---

Ниже сохранена история ранних попыток, не актуальное разрешение установки.

# Текущий статус A03

**Sloped graft845daf прошёл raw-rest CPU PASS, но actual46poses дали FAIL.**
Точный разбор: `posed-scope.json`; локальная коррекция левого root продолжается.
Кандидат: `build/model_candidates/2026-11-06-a03/final/kolossar_shadow.glb`,
SHA256 `845dafef53e0cb4476de6a9561a28a903f6bb4692dcf1569c93c19d1971c05a2`.
Текущий отчёт/whitelist/команды: [FINAL_REPORT.md](FINAL_REPORT.md).
Финальные свидетельства: `final-before-after-mask.png`, `final-integrity.json`,
`final-intersections.json`. Импорт/позы/support принимает общий этап.

---

Ниже история двух отклонённых попыток; она не описывает новый final-кандидат.

# A03 — Колоссар Тени: исследование плечевого дыма

**Статус: оба прототипа отклонены. Готового к установке кандидата нет. A03 открыт.**
Production `assets/creatures_hd/kolossar_shadow.glb` не изменён. Его SHA256:
`6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c`.

Sol high лично рассмотрел concept, source и четыре CPU raw-rest вида маски/результата.
Белые жёсткие завитки и плоские листы действительно перекрывают силуэт обоих плеч.
В source это часть единой связной поверхности149994треугольников: дымовые корни,
серые нижние стенки и фиолетовые верхние детали брони переплетены. Часть серой зоны
участвует в форме плеча; одну цветовую маску нельзя объявить анатомически точной.
Простые пространственные срезы также захватывали верхние детали либо оставляли
белые основания; они не были приняты.

## Что сделано

Локализация ограничена двумя плечевыми областями, затем выбраны только две крупные
связные нейтральные области10052+4940треугольников.177внутренних цветных фрагментов
также исключены;134825исходных треугольников тела сохранены в исходном порядке.
Это адресная исследовательская маска, а не принятый анатомический контур.

| Прототип | SHA256 | Итог |
|---|---|---|
| `build/model_candidates/2026-11-06-a03/kolossar_shadow.glb` | `db71c6a103e80826fcce5fcd4b1730bb637e3d22f156430bece96fd08a135e05` | Отклонён:387cap-tri,13контуров,48новых не-соседних cap/body-пересечений,23новых неманифолдных ребра. |
| `build/model_candidates/2026-11-06-a03/kolossar_shadow_sculpt.glb` | `9e1f09609b6c8dc4df2cb8172352773a6f1ffed4c2ea10749000278529bc8c93` | Отклонён: гармоническая скульптура15169tri,174пересечения (64body/cap+110cap/cap). |

Первый прототип использует закрытие ear clipping по13обратным реальным контурам.
Ноль открытых рёбер не означает корректную наружную поверхность. Узкая BVH-проверка
обнаружила пересечения; отдельный obstacle-aware ear clipping не смог завершить
главный контур (18оставшихся вершин не имеют допустимого уха). Сам снимок с тёмными
панелями не является доказательством качественной брони.

Второй прототип решает дискретную гармоническую поверхность исходного участка с
фиксированными всеми границами (CG336итераций, остаток<1e-18), затем задаёт тёмную
палитру. На CPU-изображении он визуально мягче, но110внутренних самопересечений
показывают, что сложную связность корня сглаживанием не исправить. Внутренние skin
weights экспериментально скопированы от ближайшего крепления: движения этим не приняты.

## Что доказано узким контрактом первого прототипа

`integrity.json`: PASS относится **только к сохранению исходных данных**.
Все270исходных accessor, исходный binary-prefix, nodes/rest/binds/skin/clips,
UV/изображения/material/extras точны. Все134825оставленных граней точны. Новые413
cap-вершины копируют позиции/восемь весов действительных границ. Source имел3
неманифолдных ребра, прототип имеет26; это явная регрессия. `geometry_safety=REJECTED`,
`approved_for_installation=false`.

Все исходные вершины сохранены, включая более не используемые дымовые точки:
это удерживает прежний accessor AABB/нормализацию. Активная верхняя граница после
удаления уменьшается с0.431995511до0.410550416. Это не доказательство поведения
Godot import: движок может пересобрать индексируемую поверхность. Без отдельной
приёмки импортировать/устанавливать прототип нельзя.

## Воспроизведение

Из корня проекта, без production-записи:

```bash
python tools/models/remove_kolossar_shadow_smoke.py --source assets/creatures_hd/kolossar_shadow.glb --output build/model_candidates/2026-11-06-a03/kolossar_shadow.glb
python tools/models/review_kolossar_shadow_smoke.py --source assets/creatures_hd/kolossar_shadow.glb --candidate build/model_candidates/2026-11-06-a03/kolossar_shadow.glb --output docs/audits/2026-11-06-model-a03
blender -b --factory-startup -P tools/models/check_kolossar_shadow_caps.py -- build/model_candidates/2026-11-06-a03/kolossar_shadow.glb docs/audits/2026-11-06-model-a03/cap-intersections.json
python tests/kolossar_shadow_smoke_integrity.py assets/creatures_hd/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/kolossar_shadow.glb build/model_candidates/2026-11-06-a03/kolossar_shadow.removal.json docs/audits/2026-11-06-model-a03/cap-intersections.json docs/audits/2026-11-06-model-a03/integrity.json
python tools/models/sculpt_kolossar_shadow_smoke.py --source assets/creatures_hd/kolossar_shadow.glb --output build/model_candidates/2026-11-06-a03/kolossar_shadow_sculpt.glb
blender -b --factory-startup -P tools/models/check_kolossar_shadow_caps.py -- build/model_candidates/2026-11-06-a03/kolossar_shadow_sculpt.glb docs/audits/2026-11-06-model-a03/sculpt-intersections.json
```

BVH проверяет только новые caps против тела/друг друга, исключая соседей с общей
геометрической вершиной. Blender запускался как CPU-утилита, без рендера/GUI.
PipeWire-backend вывел ограничение соединения; геометрические JSON завершены,
процессы завершены. Godot, GPU, support/cloth, импорт, Windows, матч, сервер,
сборка/публикация не запускались. Исходные accepted030–035 не менялись.

Дальше нужен ручной локальный контур реконструкции плечевой стенки с явным
разделением дымового корня и фиолетовой брони, контролируемой наружной сеткой и
проверкой пересечений. Сначала ноль новых пересечений/неманифолдных рёбер и новая
художественная multi-view-приёмка, затем импорт/движение настоящего CreatureBall
через штатный minimized/nonfocusable wrapper60FPS. Прозрачный VFX этим этапом не создан.
