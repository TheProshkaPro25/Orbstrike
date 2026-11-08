# Независимый аудит клиентского пакета0.4.2.6

**PASS / package GO.** Sol high независимо выполнил свежий статический аудит нового
`build/release0426/client/` и `build/Orbstrike_v0.4.2.6_win64.zip`; блокеров пакета нет.
Полный отчёт: `build/release0426-audit/report.json`; закреплённый итог —
[independent-package.json](independent-package.json).

- Все12файлов ZIP: CRC, точный SHA256 staging, безопасные пути, отсутствие дубликатов,
  symlink/encryption, sidecar и release SHA256SUMS — PASS.
- Все1563записи PCK: MD5; privacy signatures и запрещённые пути —0.
- AMD64 PE32+ file/product0.4.2.6, ProductName Orbstrike; ECFG0.4.2.6/Boot — PASS.
- Все155клиентских GDC побайтно равны новому независимому scripts-only reference,
  исходные SHA актуальны. Два прежних server-only GDC побайтно равны immutable0425
  клиентскому PCK с закреплённым SHA; серверные исходники не читались.
- Сохранены49GLB/49импортов,49исходных portraitPNG/импортов,14animation/skin.res,
  68pdat/manifest, runtimeKevin,portrait shader и текущие audio imports.
- Девять канонических документов/лицензий, approvedwave/CC0provenance и исключение
  кандидатов/приватных материалов — PASS.

ZIP:1035655235байт; SHA256
`9cbf7f1c8ad35d8b4df94dfe625933710f440f009d1d044a1df88b9c75e42cde`.
EXE:`5659dc5fe98429cd2bc94b12e214a649cb9d89bf7b8e8bbec65aa7377147b9b3`.
PCK:`4447af8e9b7bfd9ae1ae6e7ed822a9d70a4484cf0d875ad6b8a84a4d1a3ac6b4`.

Границы: этот независимый аудит не запускал игру/GPU/Windows/Wine/сервер,
не прослушивал звук и не проверял публикацию. RuntimeUI/ARTприёмка оформляется
ведущим отдельно. Клиентrules11и публичный серверrules10несовместимы.
Production-файлы не менялись; записи reviewer ограничены build/ и этим отчётом.
