# Полный комплект Грифалона: шесть стихий в клиенте

Автор принял новый полный набор Света после сравнения старых/новых клипов:
«да новый набор значительно лучше». Astra medium адаптировала пять ручных клипов
к шести исходным ригам; Sol подключил ресурсы и проверил runtime. Исходные49 GLB,
rest/bind/UV/weights, принятые030–035 и движения других видов сохранены.

**Финальный статус: CODE PASS / scoped ART GO**, включая Бурю после локального skin overlay.

## Что подключено

- Шесть [animation-only ресурсов](../../../assets/animations/grifalon/README.md),
  суммарно около400 KB: `idle/stance/roar/attack/hit`, без новых GLB. Ещё152485 bytes — отдельный локальный skin overlay Бури.
- StartupCatalog/CreatureModels читают их до меню; GameLoading не публикует
  каталог/меню при неполном или невалидном комплекте/overlay либо неудачной установке на реальный актёр. Проверяются ID/version,
  пять имён, 63 уникальных канала21×TRS, диапазоны времени/конечные ключи и bounds.
- CreatureAnim ставит библиотеку до общего immutable prepare/cache. Только
  NodePaths и playback flags меняются; источник подготовки — прежний PackedScene.
  У каждого актёра свой AnimationPlayer. Кэш опор/лимит64 и Boot49×2 сохранены.
- Для нового Grifalon отключены legacy torso/tail/flight и additive hover/bob/
  lunge/recoil. Ручные root motion и позы проигрываются один раз; общий контакт
  в1/3, пауза0.07 с, tempo/override, hitstop/flash и возврат в idle сохранены.
  Дальность нового движения задана клипом: старые аргументы dist/counter*.45
  не масштабируют авторские ключи. Согласование дистанции — отдельное ограничение.
- Camera/label envelope вычисляется из precomputed skinned bounds с учётом
  исходного normalization scale/minY; статический mesh AABB не выдаётся за позу.

## Реально выполненные проверки

1. `python tools/check.py --profile models --checks grifalon-fullset --visual`:
   **13188/0**, RTX4070Laptop/Vulkan/Forward+, общий offscreen/minimized/unfocusable
   wrapper60FPS. Шесть реальных source meshes × пять клипов, 25 поз на вариант,
   actual `_process`1/120 от живого idle, contact30/60/120-step, clash override,
   hitstop, прерывание roar→hit, возврат, неизменность ключей/interpolation,
   warm shared curves и неизменённые Gorgul/Ratnik-cape controls.
2. Light сравнен с **независимым принятым fullset GLB** в0/.3/.4/.5/1.2 с:
   21 сустав root-relative error≤9.43e−7; физическое root displacement error
   ≤1.54e−8 source units после удаления normalization scale. Native object motion
   и root-bone fold сравниваются физически, не по разным encoded origins.
   Контактный наклон hips→chest77.225356° от vertical сохранён.
3. `python tools/models/check_grifalon_runtime_bounds.py`: полное CPU skin исходных
   вершин с8 influences по фактическим150 runtime-позам. **0 failures**;
   минимальный зазор2.44012 world units, все верхи внутри camera/label envelope,
   0 cropped vertex samples. Это sampled floor/frustum, не непрерывный collision.
4. `python tools/check.py --profile models --checks grifalon-runtime-pool --visual`:
   **0 failures**, настоящий Boot49×2/три арены, затем main/deck Fire и арендованный
   Grifalon через обычные Ball brace→lunge/contact→hit. Один контакт, возврат,
   12 borrow/return cycles с теми же uid/animator; поздней подготовки/загрузки нет.
   После добавления обязательного overlay проверка повторена один раз по новой зависимости:0fail/contact1, overlayload1/meshcache1, без поздней загрузки/пересборки. Это контролируемый runtime бой двух Ball-актёров, не полный матч правил.

[Шесть видов окраски × пять клипов](../../../build/checks/grifalon-fullset/six-variants-five-clips.jpg),
[runtime report](../../../build/checks/grifalon-fullset/report.json),
[bounds report](../../../build/checks/grifalon-fullset/bounds-report.json),
[Light SIDE contact](../../../build/checks/grifalon-fullset/light-contact-proof/light-contact-side.png),
[pool report](../../../build/checks/models/selected-grifalon-runtime-pool/grifalon-runtime-pool.json).

## Локальный skin overlay Бури

Source R-крыло почти целиком было привязано к wing.R; одно изменение угла не исправляло трёхзвенную артикуляцию. Astra medium создала continuous Gaussian field в9873из97837импортных вершин, оставив прочие87964 и non-R влияния точными. Ключи/кости/rest/source weights не менялись. Финальная UNORM16 allocation сохраняет исходную R-chain массу.

Sol consumer создаёт новый ArrayMesh: временный engine encode даёт skin_data и свежие bone_aabbs; штатный serialized `_surfaces` property установлен из исходного raw surface с заменой только этих двух полей. Это проверенный storage layout Godot4.7.2, не заявление о публичном generic surface-replace API. Non-skin buffers/LOD/material/name/format сохранены byte-exact; CPU metadata/renderer согласованы, source shadow_mesh фактически null. Кэш содержит только ресурсы и привязан к actual payload digest.

Отдельный Gale-only прогон **2210/0**, пять клипов/contact/warm clone; post-encoding outside/non-R changed0. CPU25поз0fail: minfloor2.44012world, maxY11.74701≤envelope12.38609, crop0. [Gale runtime report](../../../build/checks/grifalon-fullset/gale-correction/report.json), [bounds](../../../build/checks/grifalon-fullset/gale-correction/bounds-report.json), [происхождение/ART12views](../../../build/experiments/unirig-unimate-2026-11-08/grifalon-retarget-six/gale-skin-overlay/README.md).

## Один master для шести стихий

По новому правилу автора отключён legacy element TEMPO только новому Грифалону (`_tempo=1`); общий BattleTempo и старые Dragnar/Ratnik controls сохранены. Headless actual-resource/timing **62/0**: одинаковые пять action timings, idle speed, counter/contact/clash/hold. Все шесть ресурсов имеют общий master SHA `f323ba…d342c`. Их file SHA изменились от metadata-only записи; подписи ключей/интерполяции/времени до/после равны.

Actual загруженные `.res` и imported rest: **203 фазы суммарно по пяти клипам на вариант ×21кость×6**. Canonical rotation max2.7608e−5°, root3.6662e−8sourceunit; это Float32 runtime evidence, не меньший authoring-JSON roundoff. Raw joint residual после одного yaw/size6.5–29.3%height НЕ выдаётся за пройденный5%actual-path/силуэтный тест. Fixed-rest-segment signature — отдельная производная характеристика общего движения, не реальные точки меша.

[Actual dump/timing](../../../build/checks/grifalon-fullset/common-master-runtime.json), [метод и оба вида метрик](../../../build/experiments/unirig-unimate-2026-11-08/grifalon-retarget-six/COMMON_MASTER.md), [actual proof](../../../build/experiments/unirig-unimate-2026-11-08/grifalon-retarget-six/actual-godot-common-master-proof.json), [metadata-only signatures](../../../build/experiments/unirig-unimate-2026-11-08/grifalon-retarget-six/master-metadata-only-proof.json). GPU/Boot после этой metadata/timing правки повторно не запускались.

## Найденная ошибка стенда и границы

Первые30 PNG/bounds **невалидны**: один `advance(target)` сразу после начала
blend давал clock=0.4, но ещё смешанную idle-позу (24° вместо77°). Ключи были
верны. Исправлен только sampler: фактическое пошаговое проигрывание от idle;
матрицы того же актёра проверены до/после draw. Старый лист сохранён как
`INVALID-one-shot-blend-sampling.jpg`, причина — `INVALID-SAMPLING.md` рядом с
runtime report. Старые13073/0 не являются художественным доказательством.
Boot/pool использовал реальные кадры/сигнал и этой ошибкой не затронут.

[Независимый финальный review](independent-review.md): CODE PASS/scoped ART GO; прежнее Gale concern закрыто после12nativeviews и исправленного runtime case. Это ограниченная приёмка просмотренных поз, не универсальный сертификат rig/collision качества.
Не заявляются полный игровой матч/все непрерывные self-collisions/Windows/
прослушивание/новый выпуск или публикация. Принятые hover/fullset GLB остаются
неизменными; старые эксперименты UniRig/UniMate не внедрялись.
