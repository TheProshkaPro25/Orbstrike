> Текущий A03: geometry69b159… установлен вместо прежнего material-only ca2580…;
> low rounded shoulders, source exact135753faces/rig/UV/8weights, ART PASS,
> ordinary15448/0 и реальное движение. [Актуальный отчёт/до-после](audits/2026-11-06-model-a03-anatomy/README.md).
> R01 material contract исправлен29/0; GPU visual заблокирован. Старые inherited
> wind/material/A04 moving/witness claims UNVERIFIED; ниже сохранена история.
> [Границы и отозванные claims](audits/2026-11-06-gpu-acceptance/motion-claims-revoked.json).

# Адресный модельный ремонт — 6 ноября 2026

> **Актуальный A04 после замечания автора:** установленd51ab2dc… вместо отвергнутого
> b209. Убраны лепёшка/задний обод/тёмный клин; exactcontract+reproduction+ARTPASS,
> installedordinary27745/0,20poses/12witnessheadrelativeΔ0. Raw0self/3лобныхконтакта,
> неzeroPASS. Все прежние A04результаты31408/43BVH0 ниже относятся к старомуb209.
> [Крупное до/после и полный актуальный факт](audits/2026-11-06-model-a04-reopen/README.md).


Автор поручил завершить изменения через существующий конвейер. Применена его
адресная ветка: immutable source → отдельный кандидат → точные GLB-контракты и
маски → узкий Godot import/CreatureBall → backup/promotion → проверка обычного
ресурсного пути. TRELLIS/Hunyuan/массовый ICP-rerig не запускались: новая генерация
не нужна для удаления отделённых исходных ветровых объёмов и потеряла бы 030–035.

## Установлено

[Общийдо/после CPU-лист](audits/2026-11-06-model-repairs-summary.png): A01/A02/A04
исправлены по заявленному объёму; A03установлено частичное улучшение материала.
[Финальный checkpoint4SHA](../tools/checkpoints/model-repairs-2026-11-06.json),
[45остальныхGLB безизменений](audits/2026-11-06-model-sculpt-runtime/catalog-sha-continuity-final.json).

| Пункт | Изменение | Source SHA → установленный SHA256 |
|---|---|---|
| A01, Клыкарь Бури | Удалены три отдельно замкнутых ветровых фрагмента: 13572+2304+1974=17850 tri; 132146 tri тела точны | `f16e61d615e7897ed513d3abb73aa941cb335827d7f43c07961fd8e277ab4c28` → `1c2855cee29711dc61eaedd108a0368158ca5d488f03e15796257eaf63dff0cc` |
| A02, Левиан Бури | Удалён отдельный белый обрывок 2538 tri; 141826 tri тела+530 принятого tail repair точны | `fe5c04377285353b7a95bdb723612464824aaaed05f9b499acb732e858db2ddc` → `c4359efccb27e465c6bd2be8bec3badf567dff0f8991e700a2ddfbf4539fbfb9` |
| A03, Колоссар Тени — частично | Только10443плечевыхэффектныхtri получают приглушённый фиолетовыйматериал;139551остальнойбронипрежние, всягеометрия/UV/skin точны. Формаостаётсяоткрыта | `6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c` → `ca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f` |
| A04, Ратник Света | Повторно по замечанию автора: округлый шлем и раздельные рога; прежний нимб, CapeGPU/rig/sourceUV/skin точны | `b209b4bad3ec5e2a4b02104993b7de1adbbdd1b59dba565c7f1e14270fe13df8` → `d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70` |

У A01/A02 сохранены все non-index bytes и JSON, кроме одного accessor count.
Не менялись POSITION/NORMAL/UV/JOINTS/WEIGHTS, skeleton/rest/binds, клипы,
материалы и картинки; caps/движений вершин нет. Тела замкнуты. Независимый Sol high
лично осмотрел компоненты/маски/до-после с четырёх сторон и проверил контракты.
У Клыкаря малые завитки внутри основной компоненты за щекой/на холке сохранены:
их анатомическая неоднозначность не позволяет удалять их по белому цвету.

Проверенные исходники и прежние `.import` sidecars сохранены до установки в
`build/model_candidates/2026-11-06-a0{1,2}/source/`. Promotion делает
`tools/models/promote_wind_candidates.py`: все SHA/backup/контракты проверяются
до первой атомарной замены. Точные пути — [promotion.json](audits/2026-11-06-model-wind-runtime/promotion.json).
Цепочка 035 продолжается новым [checkpoint](../tools/checkpoints/model-wind-2026-11-06.json),
исторический manifest035 не переписан. На этапе A01/A02 остальные47GLB совпали
с исходным аудитом поSHA256 — [контроль](audits/2026-11-06-model-wind-runtime/catalog-sha-continuity.json).

## Реальный импорт, масштаб и движение

Свежий `python3 tools/check.py --profile models --checks model-wind-import --logic-only`
через штатный wrapper: **24602 утверждения, 0 ошибок**, exit0, без engineERROR/leaks.
Это настоящий Godot4.7.2/GLTFDocument и CreatureBall/CreatureModels/CreatureAnim;
рендерер headless, не GPU-кадры. Проверены idle/attack/hit в кадрах 0/12/24/48/90,
skin-палитры и 16/32 совпадающие вершины сохранённой поверхности после skin/world
transform. Новый обычный `load(assets/creatures_hd/…)` и `CreatureBall.setup`
получают исправленные 132146/142356 tri, не старые `.godot/imported` сцены.

| Модель | Масштаб исходника/обычного пути | Δ world source→direct candidate | Δ world direct→обычный путь |
|---|---|---|---|
| Клыкарь Бури | 11.9439964294434 / 11.9439964294434 | 0 | ≤3.425e-7 |
| Левиан Бури | 10.3164615631104 / 10.3164615631104 | 0 | 0 |

Центр сохранён. Godot действительно уплотняет неиспользуемые вершины: без
исправления Клыкарь увеличивался в 1.25964 раза. `CreatureModels` сохраняет прежнюю
рамку нормализации только для `hd:klykar_gale` при совпадении reviewed active AABB
и числа 132146 tri; другие key/bounds/topology отвергаются отдельными тестами.
Живые визуальные bounds продолжают измеряться по фактической поверхности.
Числа/пределы: [installed.json](audits/2026-11-06-model-wind-runtime/installed.json),
[журнал](audits/2026-11-06-model-wind-runtime/installed.log).

Первый editor/import остановился на Blender-файле доказательств и оставил старые
SCN: узкий тест правильно обнаружил несоответствие исходного SHA и geometry count.
Добавлен `docs/audits/.gdignore`; production не ссылается на эти файлы. Повторный
штатный import реально пересоздал обе GLB-сцены, после чего обычный путь прошёл.
Команда import формально **FAIL** из-за запрещённого sandbox TCP listen, её общий
статус не выдаётся за PASS: [журнал](audits/2026-11-06-model-wind-runtime/import-with-tcp-errors.log).
Ограничение не обходилось.

Графический probe `models/review-state --visual` снова не создал X11/Wayland
DisplayServer. Художественные исходные листы — CPU raw-rest; GPU-композиция,
настоящее освещение и cloth остаются непроверенными. Запусков Windows, звука,
физического 3D-матча, сборки, сервера или публикации здесь нет.

## Остальная работа

**Актуальный A04:** прежняя художественная приёмка b209 отозвана после жалобы
«лепёшка между рогов». Установленd51ab2dc…: округлый шлем, раздельные сужающиеся
верхние рога, тонкий нимб; исходные84900streams/CapeGPU/rig/UV/skinточны.
Exactcontract/reproduction полногоSHA и независимыйART — PASS. Raw0self/3лобных
микроконтакта, неzeroPASS;12witnessheadrelativeΔ0в20actualпозах.
[Крупное до/после, installedruntime и границы](audits/2026-11-06-model-a04-reopen/README.md).

**Ниже история первого A04 b209, не актуальная приёмка нового d51.**
A04 был установлен после отдельной реконструкции, а не первого плоского cap-прототипа.
Изменены только315source POSITION/NORMAL вершин узкого стыка (≤0.0030001);
114060сохранённыхиндексов, sourceUV/skin/rig/CapeGPU34599tri точны. Новые5403crowntri
имеют201точную boundaryпозицию/8weights и2605interiorhead1вершин; кольцо2304tri.
Нормальное завершение920новыхundersideNORMAL доказано отдельным побайтовым этапом,
geometry/UV/weights точны к d389. Raw-BVH0 и43реальные импортированные позы после
support:0пересечений изменённых граней. Cape исключён по имени, не порядку поверхностей.
`sculpt-import`31408/0 проверил обычный новый ресурс156366tri, scale/центр/height и
paletteΔ≤5.96e-8. Старую motion-height8.28535 сохраняет адресный frameguard; новая
высота нимба иначе меняла support/actions. Backup/sidecar сохранены до замены в
build/model_candidates/2026-11-06-sculpt/source/; [ordinarypath](audits/2026-11-06-model-sculpt-runtime/installed-a04.json).
[Шесть видов и точный контракт](audits/2026-11-06-model-a04/README.md).
R01 не закрыт: headless не запускает GPUcloth, sourceCape/bindконтракт не доказывает
живую симуляцию/rim. **CapeGPUточность не равна неизменностиcollisionproxy:** телоMesh_0выше, поэтому
шагегоvoxelgrid меняется0.08591982→0.08999928. Живаяclothдинамика не проверена;
новоговидимогосбоя не утверждаем. [CPUimpactscope](audits/2026-11-06-model-sculpt-runtime/cloth-impact-scope.json).
PreparationStore включает GLBSHA/.import/импортный stamp в ключ,
поэтому прежняя подготовка не подставляется к новому asset; массовая регенерация
каталога не запускалась.

A03: геометрические кандидаты не установлены. Первый хорошийraw-rest845daf
провалил46реальныхпоз:443genuinelynewпары(441cap+2clip) и607доказанноунаследованных.
Адресные0430/0415/Steinerварианты тоже отклонены. Независимыйdoubleprecision
witness показал строгое проникновение настоящегоfixedboundarysegment внутрь
sourcebody приattack24(t=.5826395,bary=.102692/.303552/.593756), не погрешность
float32/валидноекасание. Interior-onlyвыпуклостьприfixedboundaryне может это
исправить. [Заключение](audits/2026-11-06-model-sculpt-runtime/contact-witness-conclusion.json).
Нужна отдельнаяattachment/collarретопология; угловатая форма/непрозрачность и
унаследованныеsourceконтакты остаются открытыми.

Вместо небезопаснойгеометрии установлен согласованныйконсервативныйmaterialэтап:
muted_violet[.38,.22,.52] только10443точныхpaleeffectfaces (6323слева/4120справа),
139551остальнойброни/шеи/головы имеют прежнийматериал. Послеосмотра3палитр×4вида
выбран приглушённыйфиолетовый: убранабелаяконкуренциясглазом,детальтекстурыосталась.
Все270sourceaccessor/BINprefix/UV/позиции/нормали/8weights/skeleton/rest/binds/clips
точны; все149994sourcefacesприсутствуютровно1раз, originalmaterial/maps/alphaexact,
новыйclonedmaterialотличаетсятолькоname/RGBfactor. Пересечениягеометрическине
могут добавиться при техже boneматрицах. [Точныйконтракт](audits/2026-11-06-model-a03/material/integrity.json).

Новыйузкий `a03-material-import --logic-only` — **11473/0**, exit0безERROR/leaks:
проверены actualGLTF/CreatureBall,15idle/attack/hitпоз,16общихskinnedworldpoints,
scale/центр/height. Source/candidate/ordinarypalette+worlddelta0. Обычный
productionresource действительноразделён на139551white/10443violettexturedtri;
егоShaderMaterialtint совпадаетс импортированнымкандидатом, поэтому старыйSCN с
одним149994triматериаломне мог быдатьложныйPASS. [ordinaryreport](audits/2026-11-06-model-sculpt-runtime/material-installed.json).
ПрежнийA03graftnormalizationguardубран: material-only геометрия не требует его.
НезависимыйSolhighличноосмотрелмаски/3палитры/до-послеикодконтрактов, подтвердил
именночастичнуюматериалкоррекцию. Повторных46BVHпрогоновнаидентичнойгеометрии нет.

Blender+Tripo как второй эксперимент подготовлен отдельно с тем же 2D Левианом,
но генерация не выполнена: нет доступа к Tripo Premium/подключённому провайдеру,
BlenderMCP timeout, браузер управления недоступен. Кредитов не потрачено; baseline
и `.blend` стенд не объявляются новой Tripo-моделью. Проверены14addonmodules/9enabled/extensions: отдельногоTripoaddon/authнет; локальныхTripoSR/SGвесов/workflowтоже нет, кодTripoSplatбез4весовне являетсяполигональнымpipelineдлярига. [Сравнение и подготовка](BLENDER_TRIPO_COMPARISON_2026-11-06.md).
