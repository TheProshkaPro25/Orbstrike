# Цельная палитра одежды —9ноября2026

Пользователь уточнил симптом: изменение цвета верха меняло только часть костюма,
создавая впечатление наложения разных фактур. В интерфейсе этот контроль уже
называется «Палитра костюма», но прежняя классификация материалов включала только
Tops_/AccessoryNeck_. У sport обеих основ окрашивался1из5 CLOTH-слотов, у bomber —
1из4. Остальные брюки, обувь и отдельная отделка оставались исходными.
Это подтверждено real editor signal и [исходным material dump](material-slots-before.log).
Дублирование mesh, изменение UV или общая мутация материалов не были обнаружены;
исправление не меняет геометрию/UV, исходные VRM или текстуры.

## Исправление

VrmAvatar присваивает роль outfit всем CLOTH-поверхностям именно modular body,
включая дополнительные material passes. Локальные копии разделены по роли,
поэтому hidden source body и costume не переиспользуют несовместимые overrides.
Hair/skin/eyes/case сохраняют отдельные настройки. Выбранный denim сохраняет свою
текстуру и цвет во всех passes; при снятии отдельного выбора брюки возвращаются
к палитре костюма. «Исходная» восстанавливает оригинальные параметры/фактуры.
Tooltip редактора объясняет цельную палитру и независимый выбор джинсов.
Существующий контракт denim reset для женских платьев не менялся.

## Узкие проверки

Новый optional `wardrobe-palette` запускается только явно через tools/check.py;
полные профили не запускались. Fixture использует настоящий CharacterEditor,
штатный item_selected палитры, sport/bomber обеих основ, повтор/сброс цвета,
переход через sport с запомненными джинсами, возврат к palette после denim0,
изоляцию skin/hair/eyes/case и отдельного второго avatar, включая его outfit.

- Baseline27/0,exit0/ERROR0: прежние3material функции воспроизведены только
  в fixture подклассе, обязательный assert colored_surfaces==1 проверен на всех
  четырёх сочетаниях. [Лог](headless-before-wardrobe-palette.log),
  [summary](headless-before-summary.json), [счётчики](before-surface-counts.json).
- Production after45/0,exit0/ERROR0: sport5/5,bomber4/4 на обеих основах.
  [Лог](headless-after-wardrobe-palette.log), [summary](headless-after-summary.json),
  [счётчики](after-surface-counts.json).
- Все выполненные проверки60FPS. Эти headless результаты подтверждают параметры
  материалов/контролы, но не являются визуальной приёмкой.
- Независимый Sol high code review и scoped ART PASS: reviewer лично просмотрел
  14PNG (sport/bomber до/после обеих основ, denim до/после и2original), сверил
  final counts/logs. Новых пятен/стыков/перекрашивания кожи не обнаружено в этих
  фронтальных кадрах. Его уточнение snapshot второго outfit включено в fixture;
  остальные фасоны/цвета/движения этим review не проверялись.

Воспроизведение headless:

```bash
SFERY_WARDROBE_BASELINE=1 python3 tools/check.py --profile presentation --checks wardrobe-palette --logic-only
python3 tools/check.py --profile presentation --checks wardrobe-palette --logic-only
```

Графика выполнена после запроса display доступа из основного turn. Оба реальных
GPU прогона RTX4070/Vulkan используют tools/check.py/test_window:
minimized/unfocusable/offscreen/60FPS, без показа окна/захвата рабочего стола.

- GPU before: **57/0**,exit0/ERROR0,10.13с;18PNG,
  [лог](gpu-before-wardrobe-palette.log), [summary](gpu-before-summary.json).
- GPU production after: **75/0**,exit0/ERROR0,9.52с;18PNG,
  [лог](gpu-after-wardrobe-palette.log), [summary](gpu-after-summary.json).
  Реальный render меняется, повтор выбранного цвета и возврат к «Исходной»
  дают в точности прежние PNG. Оба запуска проверяют те же4сочетания.
- Все4original PNG before/after побайтово одинаковы:
  [SHA256 и сравнение](original-before-after-hashes.json). Без выбора палитры
  оригинальный вид костюма не изменился.
- Sol лично просмотрел4before+6afterPNG: спорткостюм теперь получает цельную
  бордовую гамму верха/брюк/обуви/отделки; bomber согласованно окрашивает брюки и
  отделку, сохраняя рисунок/складки и тональный контраст. Skin/hair/case не меняются.
  В denim14 кадрах отдельно выбранные жёлтые джинсы сохраняют свою фактуру и цвет
  при синей палитре остального костюма. Это scoped visual PASS для показанных
  sport/bomber обеих основ, не визуальная проверка остальных фасонов.

Ключевые кадры:

| Сочетание | До | После |
|---|---|---|
| Юноша, спорт | [До](before/0-sport-burgundy.png) | [После](after/0-sport-burgundy.png) |
| Девушка, спорт | [До](before/1-sport-burgundy.png) | [После](after/1-sport-burgundy.png) |
| Юноша, бомбер | [До](before/0-bomber-burgundy.png) | [После](after/0-bomber-burgundy.png) |
| Девушка, бомбер | [До](before/1-bomber-burgundy.png) | [После](after/1-bomber-burgundy.png) |

Отдельный denim:
[юноша](after/0-bomber-denim.png), [девушка](after/1-bomber-denim.png).

Перед разрешённой графикой sandbox запуск завершился X11/Wayland unavailable,
а вложенный require_escalated запрос был прерван до старта Godot. Затем автор
попросил повторить запрос; основной turn получил доступ и выполнил оба прогона.
Эти промежуточные проблемы окружения не являются дефектами продукта.

## Промежуточные ошибки и границы

Первый fixture не указал тип texture из Variant, что дало parse error; исправлено.
Его ранние headless assertions23/0 завершились с RID/resources warnings:
lookup VrmParts в самостоятельном стенде оставался закреплённым при выходе.
Fixture теперь очищает lookup и убирает лишний CardDB preload перед выходом;
финальные27/0 и45/0 не имеют этих предупреждений. Логи сохранены как
fixture-parse-initial.log и fixture-headless-initial.log. Diagnostic повтор после
production patch, но до подключения baseline subclass, перезаписал промежуточный
before/summary.json счётчиками5/5+4/4: он не принят как baseline; финальный baseline
с защитным assert и отдельными копиями логов подтверждает1/5+1/4.

Не заявляются визуальная проверка всех фасонов, полный матч, Windows, сборка,
публикация илиFPS/память.49моделей существ, сервер и .codex не затрагивались;
версия/публичный0.4.2.6 прежние. Предыдущий dirty сохранён.
