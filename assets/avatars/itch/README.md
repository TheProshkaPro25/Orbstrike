# Дополнительные детали с itch.io

Получены без аккаунта и оплаты: Kai (Fox Jump), modular parts (hiamBoz),
Denim Jeans (ScaerieTale). Официальные ссылки и SHA исходных4файлов находятся
в tools/avatars/itch_character_sources.json, авторство/условия — CREDITS.md.
Исходные архивы и полная .blend-библиотека лежат только в build/itch-character-source.
Mari исключена: актуальный download_url требует покупки, хотя кэш описания был free.

## Что включено

Две прежние основы/скелеты сохранены. Добавлены source Kai для материалов,
производное контрастное худи обеим основам и 2 причёски: короткие Kai и каре
hiamBoz. Итого 9 причёсок/5мужских/6женских костюмов. Старые ID0..6
волос/0..3 и0..4костюмов сохранены. Новые ID append7..8 и4male/5female.
Одежда Kai привязана к целевому ригу офлайн; кожа/пальцы принадлежат прежней
основе. Сегменты рукава подогнаны к обеим целевым костям, сохраняется LowerArm
под манжетой. Дополнительные bone/rest/bind исходных фигур не менялись.

Boz short/pony/twins подготовлены в parts, но не доступны в UI: посадка прядей на
наши головы неудовлетворительна. Остальная библиотека тел/одежды не имеет
скелета и не объявляется готовыми игровыми костюмами. Используемое каре
имеет внутреннюю непрерывную шапочку, чтобы кожа не просвечивала между прядями.
Все новые волосы жёстко следуют Head, вторичной физики не добавлено.

Джинсы — отдельное поле vrm_denim0..14 профиляv2,14PNG из original Denim_ALL.
Палитра адаптирована prepare_denim.py: исходный шум оказался очень цветным,
подавлен по яркости, применены спокойные оттенки, пояс/пряжка сохранены.
0восстанавливает исходный материал. Работает на брюках; при выборе женского
платья сбрасывается в0 и блокируется. Отдельной памяти для каждого костюма нет.
StartupCatalog прогревает все9styles/5+6body и14denim до меню.

## Воспроизведение

Из корня проекта (headless import — без окна):

```sh
python tools/avatars/fetch_itch_characters.py
python tools/avatars/prepare_denim.py
blender --factory-startup -b build/itch-character-source/modular/character_modular_mesh_ftype.blend --disable-autoexec --python-exit-code 1 -P tools/avatars/export_modular_hair.py
godot --headless --path . --editor --import --log-file /tmp/itch-import.log
godot --headless --path . --log-file /tmp/itch-parts.log -s res://tools/avatars/prepare_itch_parts.gd
python tools/avatars/verify_itch_parts.py
```

Исходники скачиваются только с pinned free uploads, несовпадение SHA — ошибка.
`fetch_itch_characters.py --verify` офлайн проверяет исходные4файла.
`verify_itch_parts.py` офлайн проверяет35подготовленных файлов и генераторы;
`--record` допустим только после новой генерации/проверки. Исходные5VRM и прежние
части дополнительно проверяются через tools/avatars/wardrobe_manifest.py.

Узкие свёрнутые проверки: `python tools/check.py --profile presentation --checks
vrm-fighter wardrobe-wrists vrm-parts character-editor` (одной строкой).
Новые кадры: build/checks/vrm-parts и build/checks/wardrobe-wrists.
Это не новый релиз и не проверка полного матча/Windows.
