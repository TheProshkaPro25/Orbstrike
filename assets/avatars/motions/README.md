# Полнотелые клипы бойцов

Текущий локальный вариант — Kevin Iglesias FREE: отдельный бумеранг, бросок сферы
и выбранный автором короткий жест способности. Установка/лицензия/ограничения:
[KEVIN.md](KEVIN.md). Ниже — запасная CC0-библиотека без локальной установки.

## Quaternius (резерв)

Официальные Standard-наборы Universal Animation Library 1/2, CC0-1.0.
Оригинальная лицензия в LICENSE.txt; URL, ID загрузок и SHA в sources.json.
UAL1.glb / UAL2.glb — неизменённые исходники с Root Motion. Они нужны для подготовки,
а матч использует только заранее созданные fighter_0.res / fighter_1.res.

Подготовка:
1. python tools/avatars/fetch_quaternius.py (или --verify без сети).
2. python tools/check.py --profile presentation --checks import
3. godot --headless --path . --log-file /tmp/retarget-quaternius.log -s res://tools/avatars/retarget_quaternius.gd
4. python tools/check.py --profile presentation --checks vrm-fighter
5. При изменениях постановки: python tools/check.py --profile gameplay --checks autoplay

Ретаргетинг переносит мировые разницы вращений относительно rest в локальные
повороты целевых костей, а движение Hips масштабируется отношением высоты таза.
Обход целевой иерархии учитывает родителей, а не индекс кости.
52 кости, 30 кадров/с: обе ноги/стопы, таз, корпус, плечи, руки, пальцы.
Исходные VRM, их bind/rest и модульные меши не изменяются.

Клипы:
- Idle_Loop — ожидание;
- OverhandThrow — бросок сферы и текущий вариант броска карты;
- Spell_Simple_Enter / Idle_Loop / Shoot / Exit — стойка и активация;
- Interact — открытие ворот.

Godot удаляет суффикс _Loop при импорте; подготовка восстанавливает исходные имена.
На старте/выходе игровых действий добавлены переходы к Idle_Loop.
Резервный бросок карты использует overhead-клип; боковой бумеранг доступен
с установленным Kevin bank. Рот — отдельные исходные VRM-морфы, аудио/лицевых клипов в UAL нет.
Графические проверки выполняются только свёрнутым wrapper tools/check.py.
