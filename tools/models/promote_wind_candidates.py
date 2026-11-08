"""Promote only reviewed A01/A02 GLBs after the narrow CPU/import contract.

Immutable source snapshots are verified before each reversible atomic replace.
This does not build or publish a client/server and does not claim GPU acceptance.
"""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = [
    ('a01', 'klykar_gale',
     'f16e61d615e7897ed513d3abb73aa941cb335827d7f43c07961fd8e277ab4c28',
     '1c2855cee29711dc61eaedd108a0368158ca5d488f03e15796257eaf63dff0cc'),
    ('a02', 'levian_gale',
     'fe5c04377285353b7a95bdb723612464824aaaed05f9b499acb732e858db2ddc',
     'c4359efccb27e465c6bd2be8bec3badf567dff0f8991e700a2ddfbf4539fbfb9'),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    evidence = ROOT / 'docs/audits/2026-11-06-model-wind-runtime'
    checks = json.loads((evidence / 'pre-promotion.json').read_text())
    assert checks['failures'] == 0 and checks['display_server'] == 'headless'
    assert len(checks['cases']) == 2
    rows = []
    # Complete all preflight checks before the first asset mutation.
    for issue, key, source_sha, candidate_sha in CASES:
        directory = ROOT / f'build/model_candidates/2026-11-06-{issue}'
        source = directory / 'source' / f'{key}.glb'
        candidate = directory / f'{key}.glb'
        production = ROOT / 'assets/creatures_hd' / f'{key}.glb'
        row = next(row for row in checks['cases'] if row['id'] == key)
        assert row['max_pose_palette_delta'] < 1e-5
        assert row['max_world_delta'] < 2e-5 and row['ordinary_world_delta'] < 1e-4
        assert sha(source) == source_sha and sha(candidate) == candidate_sha
        assert sha(production) in [source_sha, candidate_sha], 'Unexpected production changes; preserve them'
        contract = json.loads((ROOT / f'docs/audits/2026-11-06-model-{issue}/integrity.json').read_text())
        assert contract.get('failures') == 0
        assert contract['candidate_sha256'] == candidate_sha
        rows.append(dict(id=key, issue=issue, source=str(source.relative_to(ROOT)),
                         candidate=str(candidate.relative_to(ROOT)), production=str(production.relative_to(ROOT)),
                         source_sha256=source_sha, installed_sha256=candidate_sha))
    for row in rows:
        production = ROOT / row['production']
        source = ROOT / row['source']
        sidecar = production.with_suffix('.glb.import')
        backup_sidecar = source.with_suffix('.glb.import')
        if sidecar.exists() and not backup_sidecar.exists():
            backup_sidecar.write_bytes(sidecar.read_bytes())
        if sha(production) != row['installed_sha256']:
            temporary = production.with_suffix('.glb.promoting')
            assert not temporary.exists(), 'Preserve unexpected pending promotion file'
            temporary.write_bytes((ROOT / row['candidate']).read_bytes())
            assert sha(temporary) == row['installed_sha256']
            os.replace(temporary, production)
        assert sha(production) == row['installed_sha256']
    result = {'status': 'Source GLBs promoted; ordinary Godot reimport verification follows',
              'gpu_review': False, 'release_or_server': False, 'models': rows}
    (evidence / 'promotion.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
