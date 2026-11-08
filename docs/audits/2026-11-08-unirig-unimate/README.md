# Грифалон Света: UniRig → UniMate — 8 ноября 2026

Локальный эксперимент по прямому поручению автора. Получены реальные отдельные
GLB, включая буквальную цепочку нового UniRig-рига и новой UniMate-анимации.
**Итог: исходный Грифалон лучше; ни один кандидат не установлен в игру.**
Независимый Sol high лично осмотрел движение: буквальная UniRig34→UniMate
получила ART FAIL — в33–80%фазы крылья/перья вытягиваются в длинные полосы,
хвостовой веер выходит перед лапами; силуэт ломается. Это наблюдаемая проблема
комбинации рига/весов/движения, а не ошибка canonical camera alignment.
Точная запись — `comparison/independent-sol-review.json`.

Корень артефактов: `build/experiments/unirig-unimate-2026-11-08/`.
[Эталон runtime / native](../../../build/experiments/unirig-unimate-2026-11-08/baseline/baseline-runtime-native.png) ·
[UniRig: исходные21 / новые34кости](../../../build/experiments/unirig-unimate-2026-11-08/comparison/unirig-rig-overlay.png) ·
[UniMate на исходном риге — GIF](../../../build/experiments/unirig-unimate-2026-11-08/comparison/unimate-aligned-old-new.gif) ·
[UniRig34→UniMate: исходник / новый клип — GIF](../../../build/experiments/unirig-unimate-2026-11-08/comparison/combined-old-new.gif) ·
[Фазы комбинированного результата](../../../build/experiments/unirig-unimate-2026-11-08/comparison/combined-motion-phases.png).

## Источник и отдельные ветки

Эталон `assets/creatures_hd/grifalon_light.glb`:149996tri,21кость,
idle/stance/roar/attack/hit; SHA256
`0437c2014c5c0e87801a0acc7b25a4f957acf3a8028dbb699b5e6672d9574481`.
Точная копия — `input/grifalon_light.glb`. Production GLB не записывался.
Существующие незакоммиченные изменения проекта сохранены.

1. **UniMate на исходном риге:** `unimate/artifacts/grifalon_light-animated.glb`,
   NPZ рядом;20 retained костей (неподвижный source `root` удалён preprocessing),
   60 кадров/30FPS,1rep,batch1,seed20261108. SHA `a786163e54cda74f747614acf12d9d4a33b25f73d08ccbdf5568c47733d14189`.
   Независимый Sol: крылья движутся, но тело/голова/лапы почти не участвуют,
   выпад не читается; как атака **не лучше исходника**. Возврат не является
   ограничением генератора и не совпадает точно с начальной позой.
2. **UniRig skeleton+skin+merge:** `candidates/unirig/grifalon_light-rigged.glb`,
   34кости,149996tri,Mesh_0,3изображения,без клипов. SHA
   `ceecfd971be1f5c722dab0f777a3ce36674a788eee0c3607814e6b21af8702bb`.
   Независимый Sol осмотрел GPU rest+оверлей: различимы обе ветви крыльев,
   лапы, шея/голова и хвост. Это **проверка размещения костей в rest**, не
   приёмка skinning под движением и не доказанное улучшение.
3. **Буквальная UniRig34 → UniMate:**
   `unirig_to_unimate/grifalon_light-unirig-unimate.glb` + `.npz`;
   34кости,149996tri,60кадров,клип `Reconstructed_Action`.
   SHA `4b3c1219983f7925cba5092acbd3c35a8c9272e273af3b1f04cefc1d165c2339`.
   Offline rule+ручная Sol-разметка костей, exact facing, один тот же промпт:
   `An object flaps its wings, lunges forward, then returns to its starting pose.`
   Inference/экспорт/order+frame validation PASS. Независимый Sol high **ART FAIL**:
   деформация крыльев/перьев в полосы и хвост перед лапами в33–80%фазы.
   Новый риг и анимацию не переносить в production.

## Исправленная ошибка входа UniRig

`bpy4.2` при импорте GLB создаёт `Icosphere` (42вершины/80tri) в
`glTF_not_exported` для отображения21кости. Official `process_mesh` собирал все
MESH, включая display helper:149996+80tri, ложные bounds примерно[-1,1].
Первый запуск с4костями был **невалидным входом**, не оценкой качества UniRig.
Он сохранён в `unirig/invalid-input-icosphere/`.

Только external clone исправлен фильтром `custom_shape` в extract/merge;
`unirig/exclude-bone-display-helpers.patch` и `input-fixture-correction.json`
фиксируют изменения. Повтор с **тем же seed20261108**, без перебора seed,
использовал только Mesh_0;50ktri inference-копия, корректные source bounds.
Получен34-костный результат, после merge восстановлена исходная149996tri сетка.

## Сравнение и границы

Renderer `tools/unirig_unimate_review.gd` использует штатный `test_window.gd`:
minimized/unfocusable/offscreen/60FPS, actual RTX4070/Vulkan/Forward+.
Узкие реальные прогоны: baseline85/0(27PNG), source attack58/0(18PNG),
UniMate aligned57/0(18PNG), UniRig rest10/0(2PNG), combined aligned57/0(18PNG).
Это технические утверждения renderer, не итог художественного качества.
Runtime CreatureBall+support и native GLB разделены. Кандидаты сравниваются
с native source; runtime-пластику нельзя приписывать нейросетям.

У UniMate иной canonical frame. Точное обратное преобразование восстановлено
по всем retained rest joints, без визуального подбора:20костей max2.464e-7,
34кости max2.752e-7. Матрицы — `unimate/frame-mapping.json` и
`unirig_to_unimate/frame-mapping.json`. Для20костей независимое сравнение тех же
вершин подтвердило fit max6.59e-7. Renderer возвращает кадр к исходным единицам,
фиксирует source normalization и использует одинаковые свет/камеру.
Ранние unaligned GIF/PNG оставлены как диагностика, не честное art-сравнение.

GIF сопоставляет нормированную фазу клипа, не одинаковое wall-clock время:
source attack1.1667с,generated1.9667с. Непрерывные контакты/BVH, игровые
CreatureAnim/support/pool/Boot, весь матч, Windows и звук не проверены.

Upstream preprocessing ограничивает веса четырьмя влияниями. В исходнике
63855/107278вершин действительно имеют больше4влияний; это реальное отличие,
а не пустые слоты. Новый риг/клип не является drop-in заменой принятого21bone
runtime: имена/rest/bind и перенос движений на6стихий потребовали бы отдельной задачи.

В логах сохранены: optional missing Draco compression (несжатые GLB реально
экспортированы/прочитаны), warning нескольких texture nodes, bpy unfreed-memory
при завершении, предупреждения PyTorch/FlashAttention. Это не zero-warning run.

## Окружения, лицензии, повтор

- GPU прочитан `nvidia-smi`:RTX4070Laptop,8188MiB. Inference выполнялся
  последовательно, без остановки пользовательских приложений; OOM не получен.
  Snapshot GPU не выдаётся за измерение peak. После установки `df` показывал31GB
  свободного места; `/tmp` (tmpfs) не использовался для весов/окружений.
- UniRig commit `6793c6640ff01c8fb389f3993434124bb43d2933`, отдельные
  Python3.11.17/torch2.5.1+cu124/bpy4.2.0/spconv2.3.8/flash-attn2.7.4.post1.
  Код и официальная HF карточка весов — MIT. Skeleton1.44GB+skin4.38GB,
  exact SHA/URL в `unirig/weights-manifest.json`; training datasets не скачивались.
- UniMate commit `b78c7807df7cf4231d4e67f8d0ece29c5e11025b`, отдельные
  Python3.10.22/torch2.5.1+cu124/bpy4.0.0; готовый `unimate_uniml3d_f60_v3`
  и FLAN-T5-base. Code MIT, **weights CC BY-NC4.0: только эксперимент, не shipping**.
  HF revisions/SHA, dependency freeze, команды и logs сохранены в `unimate/`.
- Общие окружения Hunyuan/ComfyUI и live Blender не использовались для установки.
  Tripo/API-ключи/покупки не использованы. BlenderMCP отдельно проверялся read-only:
  connected Blender5.2.3, Tripo provider off/Premium only; этот пилот через него
  не запускал генерацию.

Повтор только нужной стадии, из корня проекта:

```sh
python3 build/experiments/unirig-unimate-2026-11-08/unirig/run_pilot.py extract
python3 build/experiments/unirig-unimate-2026-11-08/unirig/run_pilot.py skeleton
python3 build/experiments/unirig-unimate-2026-11-08/unirig/run_pilot.py extract-skeleton
python3 build/experiments/unirig-unimate-2026-11-08/unirig/run_pilot.py skin
python3 build/experiments/unirig-unimate-2026-11-08/unirig/run_pilot.py merge
```

Первый запуск установки/скачивания — логи `logs/unirig-*-install.log`,
`unirig/download_weights.py`, `unirig/requirements-pilot.txt` и freeze.
Команды UniMate/chain — `unimate/commands.md`, `unirig_to_unimate/commands.md`.
Повторять успешные стадии автоматически не нужно. Для renderer см. `RENDERER.md`
и `comparison/REVIEW.md` в experiment root.

## Отдельный образец Astra

По отдельному прямому поручению автора Astra сделала новый процедурный GLB/BLEND
через live BlenderMCP. Независимый Sol high: **ART FAIL как замена существующего
Грифалона** — проще голова/броня и повторяющиеся перья. Это самостоятельный новый
asset, а не результат UniRig/UniMate; он также не установлен в игру.
[Reference/source/Astra](../../../build/experiments/astra-grifalon-2026-11-08/comparison_concept_source_astra.jpg) ·
[Отчёт/BLEND/GLB/границы](../../../build/experiments/astra-grifalon-2026-11-08/README.md).

## Первоисточники

[UniRig](https://github.com/VAST-AI-Research/UniRig) ·
[UniRig weights](https://huggingface.co/VAST-AI/UniRig) ·
[UniMate](https://github.com/Friedrich-M/UniMate) ·
[UniMate weights/лицензия](https://huggingface.co/Linzhan/UniMate).
Сервер/.codex, сборки, коммиты и публикация не затронуты.
