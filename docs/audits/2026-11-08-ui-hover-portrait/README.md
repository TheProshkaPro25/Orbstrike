# Hotfix0.4.2.5: карты, портреты и турнирный UI

По пользовательским замечаниям исправлены накоплениеfocuspopup и гигантская карта-подсказка, фон портретов49существ, тема турнирных кнопок/подтверждений и announcement поверх портрета. Клиентский пакет проверен; публикация пока ожидается.

- [Независимая sourceCODE/scopedART оценка](independent-review.md), [JSON](independent-review.json).
- [Release checkpoint, artifact SHA и границы](../../../tools/checkpoints/release0425-validation.json), [runtime/source pin](../../../tools/checkpoints/release0425-sources.json), [портретный source proof](../../../tools/checkpoints/portrait-matte-2026-11-08.json).

## Что подтверждено

Before:30focusциклов за один кадр накапливали31→60→89слоёв/353→672→991nodes; послеgeneration/singleactiveguard1→1→1. Blur возвращает0. Это реальный UI allocation spike до потери фокуса, а не доказательство бесконечной остановки всего процесса. Новыйcompacttexttooltip не строит вложенныйCardView/материал и не компонует его дважды; полный эффект, время и динамические ограничения сохранены, длинный текст доступенPgUp/PgDn.

SourceUI401/0+cardaccess138/0;30actualpointerenter/exit, nativehoverdwell ровно1factory/no stationary rebuild, hidepending callback, chainPgDn/mouseleave,8classic/device/960/1280/normal/reduced layouts и реальныеMainregistration/exitcancelhandlers. Последняя локализация exit проверена на actualPCK: «Выход из турнира»/«Назад».

Portrait649/0:49cachedtextures/12backdrops,49loadingframes, warmgeneration49, source98PNG и42crops/7fullbody сохранены. Только4лично проверенных просвета двухShadow удалены поRGBfingerprint/точнымseeds; белая броня/перья/клинки сохранены. НезначительныйAA-шум при256px остаётся,72pxкомпозиции приняты. Source модели/анимации и правила не менялись.

## Реальный новый пакет

Actualexport0.4.2.5 PCK, внешнийтолькоtestdriver/wrapper, без игровыхsourceoverlays: **505/0/ERROR0**, Boot98/3,49matte до меню→49послеwarm UI resize/style/getters,12backdrops. [Outerresult](../../../build/release0425/runtime/result.json), [UI+packed_boot](../../../build/release0425/runtime/captures/report.json). Наследованный scope-string fixture«sourceUIonly/noBoot» не описывает этот запуск: действительные scope/command — вouterresult иpacked_boot. Menu/model lifecycle запуск необходим из-за нового Boot cache; два полных матча не повторяли, правила не менялись.

НезависимыйpackagePASS:12ZIPCRC/12memberSHA,1563PCKMD5,157currentGDCbyte-equal,49models/49sourceportraits/14прежнихanimationresources/newhelpers+shader; PE/ECFG0.4.2.5. ZIP SHA256`2e4a805eab6046602f00f71fa9275bfe325740c1ccdd71f201e87d5679655a75`.

НативнаяWindows/субъективное прослушивание не заявляются. Wine0.4.2 NOTPASS сохранён как ограничение, новых попыток нет. Сервер не проверялся/не обновлялся, online-rules10/11 остаются несовместимыми. Старый0.4.2 не перезаписывается.
