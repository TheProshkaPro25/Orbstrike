# Колоссар: ручной полный комплект

Astra medium: master V3 Stone, пять клипов `idle/stance/roar/attack/hit`, шесть animation-only AnimationLibrary. Attack1.2с, контакт.4с; root motion внутри rootbone, без object/Ball tracks. Один master и timing для всех стихий. Source rest/bind/UV/геометрия сохранены.

`light-heel-skin.res` — отдельный sparse3012-row overlay только thigh.R→foot.R; потребитель создаёт immutable ArrayMesh clone, исходные данные не меняет. Constant sole adapter уже baked в roottracks, повторно не добавлять. CreatureModels сохраняет исходную нормализацию; sole-only support не добавляет шаг/приседание.

[Runtime/доказательства/ограничения](../../../docs/audits/2026-11-08-kolossar-fullset-runtime/README.md). Это ручные ресурсы Astra, не UniMate/UniRig output. Без публикации/Windows/full-match проверки.
