## Реальный пользовательский GPU-запуск — 6 ноября 2026

Завершён **70004/0**, exit0,30.88с: Vulkan1.4.351 / Forward+ /
NVIDIA GeForce RTX4070 Laptop GPU / X11. Окно штатно minimized/unfocusable,
offscreen/60FPS. Текущие4 GLB/SCN/sidecar и37PNG совпали по хэшам. Engine log
без ERROR/WARNING/shader failures/leaks. Sol лично принял A03 idle/attack,
A04 голову и captured GPUcloth/rim/reuse, A01/A02 и settled/reduced HUD.
[Отчёт](hardware-report.json), [лог](hardware-engine.log),
[визуальный вывод и точный охват](hardware-visual-review.json).

Один normal-motion G-delta PNG показывает числа без остального HUD: причина
не установлена, этот кадр не принят. Полный UI PASS не заявляется. Повторного
запуска не было. Ниже сохранена история прежнего sandbox BLOCKED.

# Узкая GPU-приёмка — 6 ноября2026

**Фактический результат: BLOCKED до сцены. Аппаратная GPU/визуальная приёмка OPEN.**
Изображений Godot/аппаратных cloth buffers этим этапом не получено.

## Свежая граница среды

`python3 tools/check.py --profile models --checks review-state --visual` завершился
за0.05с с exit1: X11 недоступен, fallback Wayland тоже не создал DisplayServer.
Лог: [display-probe.log](display-probe.log), [summary](display-probe-summary.json).
Сцена и `tools/test_window.gd` не начали работу; окно игры не показывалось.
Шесть ObjectDB startup leaks в этом логе относятся к неудачному созданию DisplayServer,
не к выполненному CreatureBall/cloth сценарию.

Отдельная свежая read-only проверка: `/tmp/.X11-unix/X0` и `X1` существуют, но
Unix socket connect обоих возвращает **EPERM/errno1**. Wayland socket существует
в `/run/user/1000/wayland-1`, однако Godot не может подключиться к нему.
`DISPLAY=:0`/`WAYLAND_DISPLAY=wayland-1` сами по себе не подтверждают доступ.
Видимых `/dev/dri`, `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm` нет;
`nvidia-smi` exit9, не может связаться с драйвером.
Локальные executable: Godot4.7.2, Blender5.2.3 LTS.
[Точные наблюдения и доступные интерфейсы](environment-probe.json).
[Исходные SHA на момент разведки](initial-sources.json) сохранены отдельно от будущего acceptance.

Purpose-built Godot connector документирует `run_project(projectPath, scene?)`,
но не CLI flags/execute-code/screenshot/readback. Единственный read-only запрос
`mcp__godot__get_godot_version({})` не вернул metadata и был прерван после326.4с.
**Проект через connector не запускался; повторных host-запросов не было.**
Поэтому доступный host/GPU маршрут не подтверждён. Многоминутный BlenderMCP
из предыдущего этапа не повторяли. Запрещённые socket/network границы не обходили
другим API/host shell, видимый обычный проект не запускали.

## Исправленный R01 material contract

У `CreatureBall.RIM_SHADER` прежде не было vertex-деформации, хотя основной
материал CapeGPU читает simulated positions/normals/welded textures. `next_pass`
делает отдельный draw и потому получал native skinned поверхность плаща.
Это подтверждённое несоответствие кода; видимый двойной контур здесь не наблюдался.

`CreatureCloth.rim_for_surface()` теперь создаёт только для `gpu_driven` материала
плаща собственный pass с **тем же exact GPU_VERTEX** и восьмью параметрами
positions/normals/weld map, widths, transform, offset, enabled. Shader общий;
uniforms/cache metadata принадлежат исходному материалу этого actor. Смена
владельца меняет его col/strength; native body/fallback используют прежний rim.
Reparent не очищает binding. `ModelLifetime.release()` отключает старый pass,
снимает texture references/metadata/next_pass и удерживает снятый **Material**
до того же frame boundary, что исходный материал. При обычном удалении solver
инвалидирует shared Texture2DRD wrappers; глобального actor/pass cache нет.
Vendor solver, resident reparent/cache hashes и GLB этим исправлением не менялись.

Свежий узкий `cloth-rim-contract --logic-only`: **29/0, exit0**, без ERROR/leaks.
Проверены actual `_set_rim`, per-actor uniforms, owner switch, fallback/reenable,
reparent и release. WeakRef без внешнего strong pass проверяет, что снятый pass
жив сразу послеrelease и освобождён послеframe. При независимом review найден
и исправлен первоначальный риск раннего освобождения снятого pass; финальный
[independent-rim-review.json](independent-rim-review.json) принимает29/0.
[Лог](rim-contract.log), [машинный отчёт](rim-contract.json).
**Это assignment/lifetime, не GPU shader compilation, симуляция или художественная приёмка.**

## Готовый ограниченный запуск на разрешённой аппаратной среде

После нового promotion и фактического обычного import **один раз** зафиксировать
принятые входы (скрипт отклоняет stale source_md5):

```bash
python3 tools/gpu_acceptance_sources.py
python3 tools/check.py --profile models --checks gpu-acceptance --visual
```

Первый скрипт записывает [accepted-sources.json](accepted-sources.json): четыре
sourceGLB SHA256, `.glb.import` SHA256, remappedSCN SHA256 и живой `.md5` путь/содержимое.
Это freezeвходов, не приёмка. A03 соответствует установленному geometry69b159…; freeze обновлён после ordinary
import с новым sourceMD5. Это не аппаратная приёмка.
A04 дополнительно жёстко проверяет `d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70`.

`tools/test_gpu_acceptance.gd` доступен только как opt-in modelscheck. Wrapper
штатного `check.py` создаёт окно с `--windowed --position -20000,-20000`, до
инициализации теста вызывает `tools/test_window.gd`: minimized, unfocusable,
приглушённый Master,60FPS, force_draw(false,delta). Все кадры читаются из собственного
SubViewport1280×720; оконный буфер не показывается. Обычное меню/Boot не запускаются.
Пользовательские настройки FPS не меняются; DeviceSettings используют отдельный fixture.

Аппаратный gate требует windowed RenderingDevice и integrated/discrete device type;
llvmpipe/lavapipe/SwiftShader/software/dummy/virtual/unknown отклоняются exit2.
Затем он проверяет frozen hashes/remap, сравнивает ориентированные triangle-position
fingerprints directGLTF→обычныйSCN→реальныйCreatureBall и пишет актуальные counts/digests.
Только четыре CreatureBall получают локальную подготовку; весь49каталог моделей не готовится.

Ограниченные сценарии стенда:

- A01/A02/A03: front/gamequarter/back idle и quarter attack/hit, обычный ресурсный путь.
- A04: head closeup; side/back при светлом/тёмном фоне и обоих owner rim;
  attack/hit, настоящий GPU buffer readback, finite/pinned/bounded/floor checks,
  resident reparent/hide/reset с тем же solverUID и последующим readback.
- HUD: шесть реальных72px портретов (нимб/рога/длинная форма/fullbody), шесть карт,
  normal/reduced criticalshow/Gdelta, обе стороны соперника, один4:3logicallayout.
  Повторного49GPUпортретного каталога или полного физического матча нет.

Выход: `build/checks/models/gpu-acceptance/report.json`, PNG и GPU buffer BIN;
логи/summary — `build/checks/models/selected-gpu-acceptance/`. `MACHINE_PASS_VISUAL_OPEN`
означает только завершённый machine contract. Sol должен открыть свежие PNG и отдельно
принять head/cloth/rim/HUD. Этот аппаратный путь **ещё не исполнялся**.

Новый `--logic-only` запуск проверил парсинг/gate: exit2,
`BLOCKED_NO_HARDWARE_GPU`, checks0/failures0/models0/captures0.
[Отчёт](hardware-gate-headless.json), [лог](hardware-gate-headless.log).
Общий check правильно отмечен **FAIL**, не зелёныйGPU PASS. Этот результат
не является заменой первой графической попытки или приёмкой скрытой GPU ветки.

Windows, прослушивание, FPS/Boot performance, сервер, сборка и публикация этим этапом не проверялись.
