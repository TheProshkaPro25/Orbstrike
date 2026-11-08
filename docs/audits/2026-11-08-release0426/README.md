# Клиент Orbstrike0.4.2.6 — 8 ноября 2026

Автор принял исправления подсказок/турнирного выхода и standby/полных портретов: «все отлично можно считать версией 0.4.2.6». Затем отдельное поручение «выложи ее» разрешило новый клиентский выпуск. Старый draft0.4.2.5/tag сохранён.

Новый Windows client export: exit0/ERROR0,11.64с. Настоящий новый PCK без игровых source overlays, Linux/Vulkan1.4/Forward+/RTX4070 Laptop, штатный tools/test_window.gd/minimized/unfocusable/offscreen/60FPS:

- Boot/cache/карточныйUI:505/0,93.63с;98живых актёров/3арены,49mattes и12backdrops до меню; warmUI не создаёт дополнительные маски, реальные hover/focus/cancel/dialog/handlers.
- Standby/full silhouettes:270/0,13.39с; герои отдельно от ареновых действий, слои18/19 сохранены,36проверок реальных пикселей,49полных статичных монстров.
- Уточнённый боевойUI:58/0,10.33с; pointer-dismissal/Esc/new-hover, общий слот выхода в двух стилях/размерах/фазах.

Все3прогона exit0/ERROR0. Sol high лично просмотрел19actualPCKPNG:9портретных (включая все49монстров),8вариантов выхода и2русских подтверждения. ScopedPASS: портреты standby, силуэты целые/фон мягкий; выход отделён от соседей. Условные magenta-портреты в exitfixture не являются продуктовым дефектом. Прежние пересечения других плашек в малом fixture не переоцениваются как новый полный HUD-аудит. [PNG SHA](packed-png-manifest.json), [UI report](packed-ui-report.json).

Независимый Sol high: PACKAGE PASS —12ZIPCRC/exactSHA,1563PCKMD5/privacy0,PE+ECFG0.4.2.6,155current clientGDC+2immutable0425serverGDC,49GLB/imports/49PNG/14animation.res/68pdat/9docs-license. Новый пакет:1035655235байт, SHA256 `9cbf7f1c8ad35d8b4df94dfe625933710f440f009d1d044a1df88b9c75e42cde`.

[Checkpoint](../../../tools/checkpoints/release0426-validation.json), [frozen sources](../../../tools/checkpoints/release0426-sources.json). Публикация пока ожидается. NativeWindows/полный матч/прослушивание не заявляются. Сервер/Delta/.codex/исходные49GLB/анимации не менялись; серверrules10 остаётся несовместим сclientrules11. Существующие пользовательские артефакты/dirty сохранены.
