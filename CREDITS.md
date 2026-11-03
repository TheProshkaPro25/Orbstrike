# Авторы и лицензии

## Звуковые эффекты

Все звуки собраны скриптом `tools/audio/build_sfx.py` из записанных паков ниже (обработка: обрезка, сдвиг высоты,
фильтры, реверберация, слоение, нормализация громкости, OGG Vorbis). Часть звуков содержит синтезированные слои
(`tools/audio/gen_sfx.py`, собственная разработка проекта). Музыка — отдельно (делается автором игры).

### Паки-источники

| Пак | Автор | Лицензия | Ссылка |
|---|---|---|---|
| 100 CC0 SFX | rubberduck | CC0 | https://opengameart.org/content/100-cc0-sfx |
| 80 CC0 creature SFX | rubberduck | CC0 | https://opengameart.org/content/80-cc0-creature-sfx |
| Fantasy Sound Effects Library | Little Robot Sound Factory (www.littlerobotsoundfactory.com) | CC-BY 3.0 | https://opengameart.org/content/fantasy-sound-effects-library |
| Magic SFX Sample | ViRiX (David McKee) | CC-BY 3.0 | https://opengameart.org/content/magic-sfx-sample |
| 51 UI sound effects | Kenney (www.kenney.nl) | CC0 | https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks |
| Interface Sounds | Kenney (www.kenney.nl) | CC0 | https://opengameart.org/content/interface-sounds |
| RPG Sound Pack | artisticdude | CC0 | https://opengameart.org/content/rpg-sound-pack |
| 100 CC0 SFX #2 | rubberduck | CC0 | https://opengameart.org/content/100-cc0-sfx-2 |
| 75 CC0 breaking / falling / hit sfx | rubberduck | CC0 | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx |

CC-BY 3.0 требует указания автора: Little Robot Sound Factory (www.littlerobotsoundfactory.com) — Fantasy Sound
Effects Library; ViRiX (David McKee) — Magic SFX Sample. Лицензия: https://creativecommons.org/licenses/by/3.0/.
CC0 — авторство не обязательно, указано из уважения.

### Файл в игре → источники

| Файл | Источник (пак / файл) | Автор | Лицензия | Синт. слой |
|---|---|---|---|---|
| assets/audio/sfx/ui_hover.ogg | 51 UI sound effects / rollover2.wav | Kenney | CC0 | — |
| assets/audio/sfx/ui_click.ogg | Interface Sounds / click_001.ogg; 51 UI sound effects / click3.wav | Kenney | CC0 | — |
| assets/audio/sfx/card_select.ogg | Interface Sounds / select_003.ogg; RPG Sound Pack / cloth.wav | Kenney, artisticdude | CC0 | — |
| assets/audio/sfx/card_place.ogg | 100 CC0 SFX / paper_01.ogg; 100 CC0 SFX / wooden_02.ogg; Interface Sounds / drop_002.ogg | rubberduck, Kenney | CC0 | — |
| assets/audio/sfx/card_flip.ogg | 100 CC0 SFX / gong_02.ogg; RPG Sound Pack / door.wav; Magic SFX Sample / Misc 02.wav; 100 CC0 SFX / paper_02.ogg | rubberduck, artisticdude, ViRiX | CC0, CC-BY 3.0 | — |
| assets/audio/sfx/card_capture.ogg | 100 CC0 SFX / paper_03.ogg; 100 CC0 SFX / gong_01.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/turn_start.ogg |  |  |  | да |
| assets/audio/sfx/ball_throw.ogg | 100 CC0 SFX #2 / sfx100v2_air_03.ogg; RPG Sound Pack / swing2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/sfx/ball_bounce_1.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_rock_hit_01.ogg | rubberduck | CC0 | — |
| assets/audio/sfx/ball_bounce_2.ogg | 100 CC0 SFX #2 / sfx100v2_stones_01.ogg | rubberduck | CC0 | — |
| assets/audio/sfx/ball_bounce_3.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_hit_05.ogg | rubberduck | CC0 | — |
| assets/audio/sfx/ball_roll_loop.ogg | 100 CC0 SFX #2 / sfx100v2_stones_02.ogg; 100 CC0 SFX #2 / sfx100v2_stones_03.ogg; 100 CC0 SFX #2 / sfx100v2_stones_01.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/ball_land.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg; 100 CC0 SFX / slam_02.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/capsule_open.ogg | RPG Sound Pack / metal-small2.wav; Fantasy Sound Effects Library / Spell_00.wav; Magic SFX Sample / Healing Full.wav; Magic SFX Sample / Fire impact 1.wav | artisticdude, Little Robot Sound Factory, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/sfx/battle_start.ogg | 100 CC0 SFX / gong_01.ogg; Fantasy Sound Effects Library / Trap_01.wav; 100 CC0 SFX / gong_02.ogg | rubberduck, Little Robot Sound Factory | CC0, CC-BY 3.0 | да |
| assets/audio/sfx/clash.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_hit_01.ogg; 100 CC0 SFX / slam_01.ogg; RPG Sound Pack / metal-ringing.wav; 100 CC0 SFX #2 / sfx100v2_air_03.ogg | rubberduck, artisticdude | CC0 | да |
| assets/audio/sfx/power_up.ogg | Fantasy Sound Effects Library / Spell_01.wav; Magic SFX Sample / Ice attack 2.wav | Little Robot Sound Factory, ViRiX | CC-BY 3.0 | — |
| assets/audio/sfx/power_down.ogg | Fantasy Sound Effects Library / Spell_01.wav; Magic SFX Sample / Wind effects 5.wav | Little Robot Sound Factory, ViRiX | CC-BY 3.0 | — |
| assets/audio/sfx/miss.ogg | 100 CC0 SFX #2 / sfx100v2_air_02.ogg; RPG Sound Pack / swing3.wav | rubberduck, artisticdude | CC0 | — |
| assets/audio/sfx/vanish.ogg | Magic SFX Sample / Wind effects 5.wav; Fantasy Sound Effects Library / Spell_00.wav | ViRiX, Little Robot Sound Factory | CC-BY 3.0 | — |
| assets/audio/sfx/eliminated.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg; Magic SFX Sample / Fire impact 1.wav; RPG Sound Pack / shade8.wav | rubberduck, ViRiX, artisticdude | CC0, CC-BY 3.0 | да |
| assets/audio/sfx/battle_win.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg; 100 CC0 SFX / gong_02.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/battle_lose.ogg | 100 CC0 SFX / gong_02.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/victory.ogg | 100 CC0 SFX / explosion.ogg; 100 CC0 SFX / gong_02.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/defeat.ogg | 100 CC0 SFX / gong_02.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_01.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/gate_trap.ogg | Fantasy Sound Effects Library / Trap_00.wav; Fantasy Sound Effects Library / Trap_02.wav; 75 CC0 breaking / falling / hit sfx / bfh1_breaking_02.ogg; Fantasy Sound Effects Library / Spell_01.wav | Little Robot Sound Factory, rubberduck | CC-BY 3.0, CC0 | — |
| assets/audio/sfx/ability_play.ogg | Fantasy Sound Effects Library / Spell_04.wav; Magic SFX Sample / Misc 02.wav | Little Robot Sound Factory, ViRiX | CC-BY 3.0 | — |
| assets/audio/sfx/ability_cancel.ogg | Fantasy Sound Effects Library / Spell_00.wav; Interface Sounds / error_006.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_glass_breaking_02.ogg | Little Robot Sound Factory, Kenney, rubberduck | CC-BY 3.0, CC0 | — |
| assets/audio/sfx/ability_fusion.ogg | Fantasy Sound Effects Library / Spell_02.wav; Magic SFX Sample / Healing Full.wav | Little Robot Sound Factory, ViRiX | CC-BY 3.0 | — |
| assets/audio/sfx/ability_fire.ogg | Magic SFX Sample / Fire impact 1.wav | ViRiX | CC-BY 3.0 | да |
| assets/audio/sfx/ability_gale.ogg | Magic SFX Sample / Wind effects 5.wav; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | ViRiX, rubberduck | CC-BY 3.0, CC0 | — |
| assets/audio/sfx/ability_light.ogg | Magic SFX Sample / Healing Full.wav | ViRiX | CC-BY 3.0 | да |
| assets/audio/sfx/ability_stone.ogg | 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_02.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_01.ogg | rubberduck | CC0 | да |
| assets/audio/sfx/ability_shadow.ogg | RPG Sound Pack / shade12.wav; Fantasy Sound Effects Library / Spell_00.wav | artisticdude, Little Robot Sound Factory | CC0, CC-BY 3.0 | — |
| assets/audio/sfx/ability_tide.ogg | 100 CC0 SFX / splash_01.ogg; RPG Sound Pack / bubble3.wav; Magic SFX Sample / Ice attack 2.wav | rubberduck, artisticdude, ViRiX | CC0, CC-BY 3.0 | — |
| assets/audio/creatures/dragnar_fire_appear.ogg | Fantasy Sound Effects Library / Dragon_Growl_00.wav; Magic SFX Sample / Fire impact 1.wav | Little Robot Sound Factory, ViRiX | CC-BY 3.0 | да |
| assets/audio/creatures/dragnar_fire_attack.ogg | 80 CC0 creature SFX / roar_03.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/dragnar_gale_appear.ogg | Fantasy Sound Effects Library / Dragon_Growl_01.wav; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | Little Robot Sound Factory, rubberduck | CC-BY 3.0, CC0 | да |
| assets/audio/creatures/dragnar_gale_attack.ogg | 80 CC0 creature SFX / monster_06.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/dragnar_light_appear.ogg | 80 CC0 creature SFX / roar_02.ogg; 80 CC0 creature SFX / monster_07.ogg; Magic SFX Sample / Healing Full.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/dragnar_light_attack.ogg | 80 CC0 creature SFX / monster_01.ogg; Magic SFX Sample / Misc 02.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/dragnar_stone_appear.ogg | Fantasy Sound Effects Library / Dragon_Growl_00.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | Little Robot Sound Factory, rubberduck | CC-BY 3.0, CC0 | да |
| assets/audio/creatures/dragnar_stone_attack.ogg | 80 CC0 creature SFX / roar_03.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/dragnar_shadow_appear.ogg | Fantasy Sound Effects Library / Dragon_Growl_01.wav; RPG Sound Pack / shade7.wav | Little Robot Sound Factory, artisticdude | CC-BY 3.0, CC0 | да |
| assets/audio/creatures/dragnar_shadow_attack.ogg | 80 CC0 creature SFX / monster_06.ogg; RPG Sound Pack / shade2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/dragnar_tide_appear.ogg | 80 CC0 creature SFX / roar_02.ogg; 80 CC0 creature SFX / monster_07.ogg; 100 CC0 SFX / splash_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/dragnar_tide_attack.ogg | 80 CC0 creature SFX / monster_01.ogg; RPG Sound Pack / bubble2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/klykar_fire_appear.ogg | 80 CC0 creature SFX / howl.ogg; 80 CC0 creature SFX / grunt_02.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/klykar_fire_attack.ogg | 80 CC0 creature SFX / barking_02.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/klykar_gale_appear.ogg | RPG Sound Pack / wolfman.wav; 80 CC0 creature SFX / howl.ogg; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/klykar_gale_attack.ogg | 80 CC0 creature SFX / barking_01.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/klykar_light_appear.ogg | 80 CC0 creature SFX / barking_01.ogg; 80 CC0 creature SFX / grunt_02.ogg; Magic SFX Sample / Healing Full.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/klykar_light_attack.ogg | RPG Sound Pack / wolfman.wav; Magic SFX Sample / Misc 02.wav | artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/klykar_stone_appear.ogg | 80 CC0 creature SFX / howl.ogg; 80 CC0 creature SFX / grunt_02.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/klykar_stone_attack.ogg | 80 CC0 creature SFX / barking_02.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/klykar_shadow_appear.ogg | RPG Sound Pack / wolfman.wav; 80 CC0 creature SFX / howl.ogg; RPG Sound Pack / shade7.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/klykar_shadow_attack.ogg | 80 CC0 creature SFX / barking_01.ogg; RPG Sound Pack / shade2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/klykar_tide_appear.ogg | 80 CC0 creature SFX / barking_01.ogg; 80 CC0 creature SFX / grunt_02.ogg; 100 CC0 SFX / splash_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/klykar_tide_attack.ogg | RPG Sound Pack / wolfman.wav; RPG Sound Pack / bubble2.wav | artisticdude | CC0 | да |
| assets/audio/creatures/grifalon_fire_appear.ogg | 80 CC0 creature SFX / scream_01.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/grifalon_fire_attack.ogg | 80 CC0 creature SFX / alien_03.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/grifalon_gale_appear.ogg | 80 CC0 creature SFX / scream_02.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/grifalon_gale_attack.ogg | 80 CC0 creature SFX / scream_02.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/grifalon_light_appear.ogg | 80 CC0 creature SFX / alien_04.ogg; 80 CC0 creature SFX / scream_01.ogg; Magic SFX Sample / Healing Full.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/grifalon_light_attack.ogg | 80 CC0 creature SFX / alien_02.ogg; Magic SFX Sample / Misc 02.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/grifalon_stone_appear.ogg | 80 CC0 creature SFX / scream_01.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/grifalon_stone_attack.ogg | 80 CC0 creature SFX / alien_03.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/grifalon_shadow_appear.ogg | 80 CC0 creature SFX / scream_02.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg; RPG Sound Pack / shade7.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/grifalon_shadow_attack.ogg | 80 CC0 creature SFX / scream_02.ogg; RPG Sound Pack / shade2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/grifalon_tide_appear.ogg | 80 CC0 creature SFX / alien_04.ogg; 80 CC0 creature SFX / scream_01.ogg; 100 CC0 SFX / splash_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/grifalon_tide_attack.ogg | 80 CC0 creature SFX / alien_02.ogg; RPG Sound Pack / bubble2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/kolossar_fire_appear.ogg | RPG Sound Pack / giant2.wav; RPG Sound Pack / giant5.wav; Magic SFX Sample / Fire impact 1.wav | artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/kolossar_fire_attack.ogg | RPG Sound Pack / giant1.wav; Magic SFX Sample / Fire impact 1.wav | artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/kolossar_gale_appear.ogg | RPG Sound Pack / giant5.wav; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/kolossar_gale_attack.ogg | RPG Sound Pack / giant4.wav; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/kolossar_light_appear.ogg | 80 CC0 creature SFX / troll_01.ogg; RPG Sound Pack / giant2.wav; Magic SFX Sample / Healing Full.wav | rubberduck, artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/kolossar_light_attack.ogg | RPG Sound Pack / ogre3.wav; Magic SFX Sample / Misc 02.wav | artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/kolossar_stone_appear.ogg | RPG Sound Pack / giant2.wav; RPG Sound Pack / giant5.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/kolossar_stone_attack.ogg | RPG Sound Pack / giant1.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/kolossar_shadow_appear.ogg | RPG Sound Pack / giant5.wav; RPG Sound Pack / shade7.wav | artisticdude | CC0 | да |
| assets/audio/creatures/kolossar_shadow_attack.ogg | RPG Sound Pack / giant4.wav; RPG Sound Pack / shade2.wav | artisticdude | CC0 | да |
| assets/audio/creatures/kolossar_tide_appear.ogg | 80 CC0 creature SFX / troll_01.ogg; RPG Sound Pack / giant2.wav; 100 CC0 SFX / splash_02.ogg | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/kolossar_tide_attack.ogg | RPG Sound Pack / ogre3.wav; RPG Sound Pack / bubble2.wav | artisticdude | CC0 | да |
| assets/audio/creatures/rogozhuk_fire_appear.ogg | 80 CC0 creature SFX / bug_04.ogg; RPG Sound Pack / bite-small3.wav; Magic SFX Sample / Fire impact 1.wav | rubberduck, artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/rogozhuk_fire_attack.ogg | RPG Sound Pack / bite-small.wav; 80 CC0 creature SFX / bug_03.ogg; Magic SFX Sample / Fire impact 1.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/rogozhuk_gale_appear.ogg | 80 CC0 creature SFX / bug_02.ogg; 80 CC0 creature SFX / bug_03.ogg; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/rogozhuk_gale_attack.ogg | RPG Sound Pack / bite-small3.wav; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/rogozhuk_light_appear.ogg | 80 CC0 creature SFX / alien_05.ogg; RPG Sound Pack / bite-small.wav; Magic SFX Sample / Healing Full.wav | rubberduck, artisticdude, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/rogozhuk_light_attack.ogg | 80 CC0 creature SFX / bug_03.ogg; Magic SFX Sample / Misc 02.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/rogozhuk_stone_appear.ogg | 80 CC0 creature SFX / bug_04.ogg; RPG Sound Pack / bite-small3.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/rogozhuk_stone_attack.ogg | RPG Sound Pack / bite-small.wav; 80 CC0 creature SFX / bug_03.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/rogozhuk_shadow_appear.ogg | 80 CC0 creature SFX / bug_02.ogg; 80 CC0 creature SFX / bug_03.ogg; RPG Sound Pack / shade7.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/rogozhuk_shadow_attack.ogg | RPG Sound Pack / bite-small3.wav; RPG Sound Pack / shade2.wav | artisticdude | CC0 | да |
| assets/audio/creatures/rogozhuk_tide_appear.ogg | 80 CC0 creature SFX / alien_05.ogg; RPG Sound Pack / bite-small.wav; 100 CC0 SFX / splash_02.ogg | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/rogozhuk_tide_attack.ogg | 80 CC0 creature SFX / bug_03.ogg; RPG Sound Pack / bubble2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/levian_fire_appear.ogg | 80 CC0 creature SFX / spit_02.ogg; 80 CC0 creature SFX / burble_01.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/levian_fire_attack.ogg | 80 CC0 creature SFX / spit_01.ogg; Magic SFX Sample / Fire impact 1.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/levian_gale_appear.ogg | 80 CC0 creature SFX / burble_01.ogg; 80 CC0 creature SFX / spit_02.ogg; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/levian_gale_attack.ogg | 80 CC0 creature SFX / spit_03.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/levian_light_appear.ogg | 80 CC0 creature SFX / weird_05.ogg; 80 CC0 creature SFX / spit_01.ogg; Magic SFX Sample / Healing Full.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/levian_light_attack.ogg | 80 CC0 creature SFX / spit_02.ogg; Magic SFX Sample / Misc 02.wav | rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/levian_stone_appear.ogg | 80 CC0 creature SFX / spit_02.ogg; 80 CC0 creature SFX / burble_01.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/levian_stone_attack.ogg | 80 CC0 creature SFX / spit_01.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/levian_shadow_appear.ogg | 80 CC0 creature SFX / burble_01.ogg; 80 CC0 creature SFX / spit_02.ogg; RPG Sound Pack / shade7.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/levian_shadow_attack.ogg | 80 CC0 creature SFX / spit_03.ogg; RPG Sound Pack / shade2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/levian_tide_appear.ogg | 80 CC0 creature SFX / weird_05.ogg; 80 CC0 creature SFX / spit_01.ogg; 100 CC0 SFX / splash_02.ogg | rubberduck | CC0 | да |
| assets/audio/creatures/levian_tide_attack.ogg | 80 CC0 creature SFX / spit_02.ogg; RPG Sound Pack / bubble2.wav | rubberduck, artisticdude | CC0 | да |
| assets/audio/creatures/ratnik_fire_appear.ogg | RPG Sound Pack / sword-unsheathe.wav; 80 CC0 creature SFX / grunt_04.ogg; RPG Sound Pack / chainmail1.wav; Magic SFX Sample / Fire impact 1.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/ratnik_fire_attack.ogg | RPG Sound Pack / swing.wav; RPG Sound Pack / metal-small1.wav; 80 CC0 creature SFX / grunt_05.ogg; Magic SFX Sample / Fire impact 1.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/ratnik_gale_appear.ogg | RPG Sound Pack / sword-unsheathe2.wav; 80 CC0 creature SFX / grunt_05.ogg; RPG Sound Pack / armor-light.wav; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_gale_attack.ogg | RPG Sound Pack / swing2.wav; RPG Sound Pack / metal-ringing.wav; 80 CC0 creature SFX / grunt_04.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_light_appear.ogg | RPG Sound Pack / sword-unsheathe5.wav; 80 CC0 creature SFX / grunt_01.ogg; RPG Sound Pack / chainmail2.wav; Magic SFX Sample / Healing Full.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/ratnik_light_attack.ogg | RPG Sound Pack / swing3.wav; RPG Sound Pack / metal-small3.wav; 80 CC0 creature SFX / grunt_01.ogg; Magic SFX Sample / Misc 02.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/ratnik_stone_appear.ogg | RPG Sound Pack / sword-unsheathe.wav; 80 CC0 creature SFX / grunt_04.ogg; RPG Sound Pack / chainmail1.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_stone_attack.ogg | RPG Sound Pack / swing.wav; RPG Sound Pack / metal-small1.wav; 80 CC0 creature SFX / grunt_05.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_shadow_appear.ogg | RPG Sound Pack / sword-unsheathe2.wav; 80 CC0 creature SFX / grunt_05.ogg; RPG Sound Pack / armor-light.wav; RPG Sound Pack / shade7.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_shadow_attack.ogg | RPG Sound Pack / swing2.wav; RPG Sound Pack / metal-ringing.wav; 80 CC0 creature SFX / grunt_04.ogg; RPG Sound Pack / shade2.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_tide_appear.ogg | RPG Sound Pack / sword-unsheathe5.wav; 80 CC0 creature SFX / grunt_01.ogg; RPG Sound Pack / chainmail2.wav; 100 CC0 SFX / splash_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/ratnik_tide_attack.ogg | RPG Sound Pack / swing3.wav; RPG Sound Pack / metal-small3.wav; 80 CC0 creature SFX / grunt_01.ogg; RPG Sound Pack / bubble2.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_fire_appear.ogg | RPG Sound Pack / shade8.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_01.ogg; Magic SFX Sample / Fire impact 1.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/gorgul_fire_attack.ogg | RPG Sound Pack / shade14.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_hit_01.ogg; Magic SFX Sample / Fire impact 1.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/gorgul_gale_appear.ogg | RPG Sound Pack / shade9.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_05.ogg; 100 CC0 SFX #2 / sfx100v2_air_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_gale_attack.ogg | RPG Sound Pack / shade5.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_hit_01.ogg; 100 CC0 SFX #2 / sfx100v2_air_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_light_appear.ogg | RPG Sound Pack / shade12.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_09.ogg; Magic SFX Sample / Healing Full.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/gorgul_light_attack.ogg | RPG Sound Pack / shade15.wav; 100 CC0 SFX #2 / sfx100v2_stones_02.ogg; Magic SFX Sample / Misc 02.wav | artisticdude, rubberduck, ViRiX | CC0, CC-BY 3.0 | да |
| assets/audio/creatures/gorgul_stone_appear.ogg | RPG Sound Pack / shade8.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_01.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_breaking_01.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_stone_attack.ogg | RPG Sound Pack / shade14.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_hit_01.ogg; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_03.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_shadow_appear.ogg | RPG Sound Pack / shade9.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_05.ogg; RPG Sound Pack / shade7.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_shadow_attack.ogg | RPG Sound Pack / shade5.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_hit_01.ogg; RPG Sound Pack / shade2.wav | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_tide_appear.ogg | RPG Sound Pack / shade12.wav; 75 CC0 breaking / falling / hit sfx / bfh1_rock_falling_09.ogg; 100 CC0 SFX / splash_02.ogg | artisticdude, rubberduck | CC0 | да |
| assets/audio/creatures/gorgul_tide_attack.ogg | RPG Sound Pack / shade15.wav; 100 CC0 SFX #2 / sfx100v2_stones_02.ogg; RPG Sound Pack / bubble2.wav | artisticdude, rubberduck | CC0 | да |

## Шрифты интерфейса
Fira Sans (Regular, SemiBold), SIL Open Font License 1.1. Текст лицензии: assets/fonts/OFL.txt.

## Физика ткани
GPU Cloth Sim 3.0.0 — alien-life, MIT: https://github.com/alien-life/gpu-cloth-sim.
Локальные изменения для интеграции перечислены в addons/godot_gpu_cloth/LOCAL_CHANGES.md.
Полный текст лицензии: addons/godot_gpu_cloth/LICENSE; в Windows-архиве — GPU_CLOTH_LICENSE.txt.

## Дополнение: обратная связь арены — 2026-10-31

`tools/audio/build_feedback.py` создаёт `ui_denied.wav`, `turn_yours.wav` и
`turn_opponent.wav` локальным синтезом синусоид, без новых сторонних записей.
`card_select_v2/v3`, `card_place_v2/v3`, `ball_throw_v2/v3`, `clash_v2/v3` и
`card_swoosh` — обработанные варианты уже атрибутированных в этом файле эффектов
проекта (изменение тембра/высоты, фильтрация). Исходные атрибуции и лицензии
сохраняются; новые сторонние музыкальные или звуковые материалы не добавлялись.


## Полёт и расширение ворот — 2026-10-31

`gate_flight_wind.wav` и `gate_expand_wave.wav` — собственный локальный синтез
фильтрованного шума и плавного низкого тона (`tools/audio/build_gate_wind.py`),
без записи или извлечения звука из аниме. Амплитуда ограничена, при воспроизведении
дополнительно используются −7/−8 dB. Декор новых арен создан примитивами Godot;
новые сторонние текстуры и модели не использовались.


## Аниме-персонаж игрока — актуальный состав (31 октября 2026)

В assets/avatars/fighter_mpfb.glb от MakeHuman Community сохранены только
кисти с пальцами и humanoid rig default_no_toes: CC0-1.0.
Источник: https://github.com/makehumancommunity/mpfb2/tree/v2.0.18 .
Лицензия: assets/avatars/LICENSE-MAKEHUMAN-CC0.md; SHA исходного архива —
tools/avatars/sources.json, SHA готового ресурса — fighter_mpfb.manifest.json.
MPFB 2.0.18 (код GPLv3) используется только в инструменте подготовки;
исходники аддона не входят в поставку игры.

Голова/лицо/уши, три причёски, торс/руки, куртка с воротником, майка, наручи,
пояс, брюки, накладки и кроссовки — оригинальная геометрия проекта:
tools/avatars/anime_head.py, anime_hair.py, anime_body.py.
Материалы с контуром, рисованной радужкой и бликами — код проекта.
Внешних текстур нет. Условия CC0 на исходные кисти/риг не означают отдельного
CC0-посвящения новой авторской геометрии.

Присланные пользователем изображения используются как художественные ориентиры.
Модели из показанной игры не скачивались и не извлекались.

Исторические варианты в build/avatar-source/ использовали MakeHuman CC0:
тело/кожу young_asian_male, глаза high-poly, eyebrow001/eyelashes01,
male_casualsuit01/shoes01, ponytail01/short02 и волосы Cortu Johnstone
cortu_short_messy_hair. В актуальный ресурс эти элементы, кроме кистей/рига,
не входят. Источники прежних пакетов:
https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html
и https://static.makehumancommunity.org/assets/assetpacks/hair01.html .


## Готовые VRM-образцы и MToon (31 октября 2026)

- godot-vrm (V-Sekai и участники), MIT; addons/vrm/LICENSE.
- Godot-MToon-Shader, MIT; addons/Godot-MToon-Shader/LICENSE.
  Исходник обоих: https://github.com/V-Sekai/godot-vrm,
  закреплённый commit e15199f980064028bfa4fbee5e70dddb82dd55c3.
- Sakurada Fumiriya и Vita / β Ver AvatarSample_3, pixiv Inc., CC0-1.0.
  Официальные модельные условия:
  https://vroid.pixiv.help/hc/en-us/articles/360014788554-Sakurada-Fumiriya
  https://vroid.pixiv.help/hc/en-us/articles/360014900113
  Зеркало: https://github.com/madjin/vrm-samples/tree/e16eb187100149a315ad92c3c9968f1d5baa6c7d/vroid/beta

Исходные VRM не изменены; поза/предпросмотр реализованы кодом игры. Подробные
URL/SHA и встроенные сведения лицензий — assets/avatars/vrm/*.source.json.
Лицензия этих конкретных старых образцов не распространяется автоматически
на современные пресеты/модели VRoid Studio. Они используются для оценки основы.


## Дополнительные детали аниме-редактора (31 октября 2026)

HairSample_Male, HairSample_Female и Vivi / β Ver AvatarSample_2 — pixiv Inc.,
CC0-1.0. Официальные условия:
https://vroid.pixiv.help/hc/en-us/articles/4402614652569
https://vroid.pixiv.help/hc/en-us/articles/360014900273
Точные исходники, SHA и embedded metadata находятся в assets/avatars/vrm/*.source.json.
Детали из 5 CC0-образцов подогнаны/подготовлены инструментом проекта
prepare_vrm_parts.gd; manifest в assets/avatars/vrm/parts/.

Производные варианты MToon для палитр сохраняют MIT LICENSE в
scenes/avatar/mtoon_palette/. Исходники V-Sekai аддона не менялись;
генератор адаптации — tools/avatars/build_palette_shaders.py.

## Анимации бойцов — Quaternius

Universal Animation Library 1 и 2, Standard, CC0-1.0:
https://quaternius.itch.io/universal-animation-library
https://quaternius.itch.io/universal-animation-library-2
Оригинальная лицензия: assets/avatars/motions/LICENSE.txt.
Закреплённые источники/SHA: assets/avatars/motions/sources.json.
Анимации перенесены на наши VRM-основы; исходные библиотеки автора сохранены.


Kevin Iglesias — Human Throwing Animations FREE / Human Spellcasting Animations FREE.
https://kevdev.itch.io/human-throwing-animations-free
https://kevdev.itch.io/human-spellcasting-animations-free
Локальные лицензированные клипы внутри игры; это не CC0. Исходные/производные
файлы не распространяются отдельной библиотекой. Условия/подготовка/границы:
assets/avatars/motions/KEVIN.md; pinned SHA: tools/avatars/kevin_sources.json.

Новые волосы hair_*_5/6 и одежда body_0_2/3,body_1_3/4 — производные тех же
пяти закреплённых CC0 VRM-образцов; исходные VRM не менялись. Подготовка:
tools/avatars/build_wardrobe_variants.gd, источники/SHA —
assets/avatars/vrm/parts/wardrobe_manifest.json. Общая фактура складок сохранена
из HairSample_Male, воротник/застёжка построены инструментом проекта.


## Дополнительные детали персонажа с itch.io — 2026-11-01

- **Kai — Fox Jump**: https://fox-jump.itch.io/kai-vroid-model . Включённая VRM
  указывает `licenseName=CC_BY`, author=Fox Jump, commercial/violent usage=Allow.
  Использованы производные худи/брюк/обуви и причёски, подогнаны к обеим основам.
  Страница автора отдельно указывает создателей худи **ハルノキ屋**
  (https://harunokiya.booth.pm/) и обуви **兎野りえ** (https://rielymart.booth.pm/).
  Авторство сохранено; это не CC0 и не наша оригинальная модель.
- **stylized female character parts and presets — hiamBoz**:
  https://hiamboz.itch.io/stylized-female-base-mesh-blend . CC0 по странице автора.
  В редакторе использованы производное каре; добавлена внутренняя
  шапочка для наших голов. Остальная исходная библиотека сохранена локально.
- **Denim Jeans (Multiple options) — ScaerieTale**:
  https://scaerietale.itch.io/vroid-denim-jeans . Автор разрешает личные и
  коммерческие игры, запрещает перепродажу как самостоятельных assets.
  14 производных текстур: подавлен исходный цветной шум, приведена палитра,
  сохранены рисунок карманов/швов и пояс. Исходный архив закреплён SHA.

Официальные файлы/SHA: tools/avatars/itch_character_sources.json;
подготовленные ресурсы: assets/avatars/itch/manifest.json.
Mari **не включена**: фактическая бесплатная загрузка больше недоступна,
checkout требует покупки. Никаких платных файлов не получали.


## Первый уличный образ (2026-11-01)

Бомбер и основа высокого хвоста производны от ранее закреплённых CC0-образцов
pixiv (Sakurada Fumiriya, Vita, HairSample_Male). Собственные процедурные
дополнения: пряди хвоста, подложка головы, отделка бомбера и футляр сфер.
Новых сторонних ресурсов не загружалось. Источники/условия исходных образцов —
assets/avatars/vrm/README.md; генератор и SHA — assets/avatars/street/README.md,
tools/avatars/build_street_set.gd, assets/avatars/street/manifest.json.


## Звук волны карты (2026-11-01)

assets/audio/sfx/gate_expand_wave.wav — собственный синтезированный эффект,
выбранный автором после подбора (08_field_clean). Сторонних сэмплов нет.
Воспроизводимый генератор: tools/audio/build_gate_activation.py (Python/NumPy).


### Спортивный комплект и зачёс — 1 ноября 2026

Четыре новых ресурса `assets/avatars/sport/` — собственные производные уже
имеющихся CC0-образцов pixiv (Sakurada Fumiriya, Vita, HairSample_Male).
Сохранены исходные основы и веса; добавлены фасон спортивной куртки/брюк,
контрастная отделка и короткая причёска с зачёсом. Новых загрузок нет.
Происхождение, генератор и перечень входов: `assets/avatars/sport/README.md`.
Миниатюры — рендеры этих же игровых ресурсов, `assets/avatars/editor/`.
