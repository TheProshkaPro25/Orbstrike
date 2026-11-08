# A02: отдельный кандидат Левиана Бури — 6 ноября 2026

**Текущий статус: A02 установлен в production после авторского поручения завершить
модельную работу.** Исходник сохранён до замены; реальный Godot import и обычный
CreatureBall подтвердили142356tri, scale/центр и skinnedworldsurface. Узкий wrapper
`model-wind-import --logic-only`:24602/0 дляA01/A02. Независимый Sol high:0blockers.
[Общий итог/пределы](MODEL_REPAIRS_2026-11-06.md), [ordinary-path report](audits/2026-11-06-model-wind-runtime/installed.json).
GPU-визуальная приёмка отдельно не выполнена; прежний безусловный GPU-gate ниже
заменён достаточными контрактами и текущим поручением автора. Далее сохранены
точные свидетельства подготовки кандидата.

| Объект | SHA256 |
|---|---|
| Принятый исходник 035 | `fe5c04377285353b7a95bdb723612464824aaaed05f9b499acb732e858db2ddc` |
| Кандидат `build/model_candidates/2026-11-06-a02/levian_gale.glb` | `c4359efccb27e465c6bd2be8bec3badf567dff0f8991e700a2ddfbf4539fbfb9` |

Свежий [лист локализации](audits/2026-11-06-model-a02/component-localization.png)
показывает source / magenta / отдельную компоненту с четырёх сторон. Лично
осмотрено: выделены только 2538 треугольников белого обрывка воздуха над кольцом
тела. Шея, крылья, грива, чешуя и хвост не выделены. Компонента замкнута,
не имеет общих сваренных точек с телом или принятой хвостовой repair-поверхностью.
Поэтому нужны только удаление её индексов, без срезов/caps/движения вершин.

[До/маска/после с четырёх сторон](audits/2026-11-06-model-a02/before-after-mask.png)
сняты CPU raw-rest в одной исходной системе координат, с одинаковым светом,
масштабом и камерой. Это albedo/normal-light технический рендер, не кадры Godot.

`tools/models/remove_levian_gale_wind.py` принимает только полный source SHA выше
и запрещает запись в assets. Сохранены размер файла 22696188 байт, JSON-форматирование
и весь бинарный layout. Единственное изменение JSON — accessor218 `count`:
433092→425478. В начало его исходного index-buffer записана исходная последовательность
оставшихся граней. Неактивный хвост старого буфера и неиспользуемые вершины остаются
в файле; уплотнение/переэкспорт намеренно не выполняются.

Узкий [побайтовый контракт](audits/2026-11-06-model-a02/integrity.json) — **PASS**:

- Удалены ровно 2538 треугольников;141826 настоящих main-треугольников сохранены
  точно и в прежнем порядке;530 треугольников принятого хвостового ремонта неизменны.
- Все 224 остальных accessor сохранены побайтово, включая tail-index219,
  POSITION/NORMAL/UV, JOINTS/WEIGHTS, bind matrices и animation streams.
- Все байты файла вне точных цифр count и активного index-prefix совпадают.
  JSON nodes/rest/skins/clips/materials/images/extras и текстуры сохранены точно.
- Тело вместе с 530 repair-треугольниками имеет 0 boundary edges; caps и перемещений
  вершин 0. Все 141826 сохранённых main-треугольников невырожденные, координаты конечны.
- [Повторное построение](audits/2026-11-06-model-a02/reproducibility.json) побайтово
  идентично; неверный SHA и выход в assets отклонены до записи. На подготовительном этапе production SHA был сохранён; текущая установка указана выше.

[Локализация и CPU-нормализация](audits/2026-11-06-model-a02/localization.json):
все хранимые позиции и отдельно вершины активных треугольников имеют одинаковые AABB
до/после: min `[-0.3889813721,-0.3943557441,-0.4918295145]`,
max `[0.3906663060,0.4250559211,0.3739994764]`.
CPU-копия текущей формулы `CreatureModels.build/_bounds` даёт scale
`10.316461749574334`, position `[-0.0086912781,4.0683559500,0.6077945404]`;
изменение масштаба 0, смещение `[0,0,0]`. Godot-import этим вычислением не проверяется.

Независимый Sol (`gpt-6.1-sol`, high) лично просмотрел оба PNG-листа, прочитал
инструмент/контракт/JSON и сверил актуальные SHA. Блокирующих замечаний к подготовленному
CPU-кандидату нет; [границы review](audits/2026-11-06-model-a02/independent-review.json).
Успешные проверки reviewer не повторял. Сохранение настоящей поверхности при тех же
skin-матрицах следует из точных треугольников/атрибутов/костей; фактическое движение
и runtime support отдельно не запускались.

Воспроизведение из корня проекта (Python3, NumPy/Pillow, без SciPy/Godot):

```bash
python3 tools/models/remove_levian_gale_wind.py --source build/model_candidates/2026-11-06-a02/source/levian_gale.glb --output build/model_candidates/2026-11-06-a02/levian_gale.glb
python3 tests/levian_gale_wind_integrity.py build/model_candidates/2026-11-06-a02/source/levian_gale.glb build/model_candidates/2026-11-06-a02/levian_gale.glb build/model_candidates/2026-11-06-a02/levian_gale.manifest.json docs/audits/2026-11-06-model-a02/integrity.json
python3 tools/models/review_levian_gale_wind.py --source build/model_candidates/2026-11-06-a02/source/levian_gale.glb --candidate build/model_candidates/2026-11-06-a02/levian_gale.glb --output docs/audits/2026-11-06-model-a02
```

После установки отдельная GPU-приёмка остаётся полезным следующим свидетельством:
узкий стенд через tools/check.py/test_window.gd с рабочим X11/Wayland, свёрнутым
нефокусируемым окном, render-to-texture и60FPS. Фактические idle/attack/hit уже
выполнены headless на настоящем CreatureBall; palette/worlddelta0, обычный импорт
новой геометрии проверен. Это не GPU-кадры, cloth, Windows, звук или матч.
X11/Wayland снова недоступны; ограничения не обходились. До установки сохранены
source SHA и importsidecar. Команда общего editor/import имеет FAIL из-за sandbox
TCP-listen, но оба GLB-import/save завершились и обычный ресурсный путь после них
отдельно прошёл. A01 тоже установлен, A03/A04 описаны в общем текущем отчёте.
