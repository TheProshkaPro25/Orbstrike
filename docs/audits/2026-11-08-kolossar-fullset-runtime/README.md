# Колоссар: полный комплект шести стихий — 8 ноября 2026

Astra medium создала пять ручных клипов на исходном21-костном риге; Sol подключил шесть библиотек и узкий Light heel overlay, независимый Sol выполнил CODE/ART review. Исходные49 GLB/rest/bind/UV сохранены; уже dirty Kolossar Shadow не перезаписан. Финальное сравнение готово автору; авторское принятие не подменяется техническим verdict.

## Результат и просмотр

- [OLD слева / NEW справа, все пять клипов MP4](../../../build/experiments/kolossar-fullset-2026-11-08/old-new-comparison/kolossar-stone-old-vs-new-five.mp4), [GIF](../../../build/experiments/kolossar-fullset-2026-11-08/old-new-comparison/kolossar-stone-old-vs-new-five.gif), [кадры](../../../build/experiments/kolossar-fullset-2026-11-08/old-new-comparison/five-clips-old-new.jpg).
- Native source/candidate, одинаковые camera/light/scale/floor; исходное время, короткая сторона HOLD END без speed normalization. Это native сравнение, не полный игровой матч.
- [Независимый CODE PASS/scoped ART GO и ограничения](independent-review.md), [контрольные SHA](manifest.json).

## Подключение

`KolossarMotion` валидирует и устанавливает5×63TRS до prepare/cache; sourcePackedScene identity сохранена. StartupCatalog/GameLoading требуют все шесть библиотек и heel overlay до49×2 и меню; повреждённый пакет не уходит в silent legacy fallback.
`AuthoredGroundSupport` сохраняет авторские ankleXZ/knee-plane/heel-pitch, исправляет только малый sole gap без шага/приседания/root offset. Старый CreatureSupport не изменён. Element tempo нового набора1, BattleTempo/контакт1/3/hold/hitstop сохранены.
Light overlay3012вершин переносит только thigh.R→foot.R на immutable mesh clone. Исходные raw non-skin/LODs/materials и skin других вершин/влияний точны после encoding; shadow использует обновлённый fullmesh. Кэш ресурсов без Node, bounded64; source identity+actual payload digest, адресный новый sole cache без старых disk weights. В этой Godot4.7.2 использовано проверенное serialized storage `_surfaces` с guarded schema, не заявляется универсальный public raw replacement API.

## Необходимые проверки

Все Godot-запуски через check.py / свёрнутый нефокусируемый wrapper60FPS.

- `--profile models --checks kolossar-fullset --visual`: **13658/0**, все6×5, stepped живой idle→contact, cold/warmcache, interrupts/hold/tempo/contact. [Report](../../../build/checks/kolossar-fullset/report.json).
- Actual CPU skin150sampledposes: **0floor/frustum failures, crop0**, minfloor+.0000559914world. [Bounds](../../../build/checks/kolossar-fullset/bounds-report.json). Это sampling, не continuous collision proof.
- `--checks kolossar-common-master --logic-only`: actual loaded6resources, timing/legacy controls и203TOTALфазы на вариант×21кость×6. [Actual proof](../../../build/experiments/kolossar-fullset-2026-11-08/retarget-six/actual-godot-common-master-proof.json): max canonical rotation3.22939e−5°, root1.65817e−8sourceunit. Fixed yaw/scale и один constant sole adapter, без per-frame fitting. Это общий bone-motion master, не95%actual mesh/joint trajectories.
- `--checks kolossar-runtime-pool --visual`: **0fail, contact1, 12borrow/return**, обычный required-resource Boot49×2/три арены, без late loading. [Pool](../../../build/checks/models/selected-kolossar-runtime-pool/kolossar-runtime-pool.json); историческое поле `grifalon_contacts` в этом отчёте относится к `kolossar_mode=true`. Один Linux запуск startup19.714s, не benchmark.
- Stone physical contact совпал с независимым native master: Rhand перед грудью+.299957source/перед головой+.172956; matrix error≤1.46e−6.

## Границы

Замах компактный waistguard, не точная overhand-копия рисунка. Исходные полости ботинка Света сохранены; heel stretch max4.55× остаётся ограничением, scoped ART GO не сертификат геометрии. Нет проверки Windows, полного матча, выпуска/сервера; прочие виды и принятый Грифалон сохранены. Следующий вид не начат.
