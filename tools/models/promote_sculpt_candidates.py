"""Reversible promotion of A03 exact-geometry material/A04 local crown repairs."""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    'a03': ('kolossar_shadow', '6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c',
            'ca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f'),
    'a04': ('ratnik_light', '454e8442b83fe7fd618d0bc0338dfc8b51b1daabaa49b4a5237dcb669598f727',
            'b209b4bad3ec5e2a4b02104993b7de1adbbdd1b59dba565c7f1e14270fe13df8'),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads((ROOT / path).read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', nargs='+', choices=CASES, required=True)
    args = parser.parse_args()
    evidence = ROOT / 'docs/audits/2026-11-06-model-sculpt-runtime'
    runtime = read('docs/audits/2026-11-06-model-sculpt-runtime/pre-promotion.json')
    assert runtime['failures'] == 0
    posed = read('docs/audits/2026-11-06-model-sculpt-runtime/posed-intersections.json')
    rows = []
    for issue in args.only:
        key, old_sha, new_sha = CASES[issue]
        directory = ROOT / 'build/model_candidates/2026-11-06-sculpt'
        source = directory / 'source' / f'{key}.glb'
        candidate = directory / 'candidate' / f'{key}.glb'
        production = ROOT / 'assets/creatures_hd' / f'{key}.glb'
        assert sha(source) == old_sha and sha(candidate) == new_sha
        assert sha(production) in [old_sha, new_sha], 'Preserve unexpected production changes'
        selected_runtime = read('docs/audits/2026-11-06-model-sculpt-runtime/material-pre-promotion.json') if issue == 'a03' else runtime
        assert selected_runtime['failures'] == 0
        row = next(row for row in selected_runtime['cases'] if row['id'] == key)
        assert row['source_sha256'] == old_sha and row['candidate_sha256'] == new_sha
        assert row['palette_delta'] < 1e-5
        if issue == 'a03':
            contract = read('docs/audits/2026-11-06-model-a03/material/integrity.json')
            assert contract['status'] == 'PASS_EXACT_GEOMETRY_UV_SKIN_MATERIAL_ONLY_PARTIAL'
            assert contract['source_sha256'] == old_sha
            assert contract['candidate_sha256'] == new_sha
            assert contract['every_original_triangle_present_exactly_once']
            assert contract['both_primitives_share_all_original_attribute_accessors']
            assert contract['positions_normals_uv_joints_8weights_nodes_rest_bind_clips_images_exact']
            assert contract['unchanged_original_material_triangles'] == 139551
            assert contract['tinted_effect_material_triangles'] == 10443
            assert row['max_world_delta'] < 2e-5
        else:
            contract = read('build/model_candidates/2026-11-06-a04/crown-integrity.json')
            continuation = read('docs/audits/2026-11-06-model-a04/crown-final/normal-equivalence.json')
            assert contract['status'] == continuation['status'] == 'PASS'
            assert contract['source_sha256'] == old_sha
            assert contract['candidate_sha256'] == continuation['baseline_sha256']
            assert continuation['final_sha256'] == new_sha
            assert continuation['all_positions_indices_joints_weights_UV_CapeGPU_exact']
            poses = next(row for row in posed if row['id'] == 'creature_' + key)['poses']
            assert len(poses) == 43 and all(row['pairs_touching_changed_faces'] == 0 for row in poses)
        rows.append(dict(issue=issue, id=key, source=str(source.relative_to(ROOT)),
                         candidate=str(candidate.relative_to(ROOT)), production=str(production.relative_to(ROOT)),
                         source_sha256=old_sha, installed_sha256=new_sha))
    # Every requested preflight is complete before the first mutation.
    for row in rows:
        production = ROOT / row['production']
        backup = ROOT / row['source']
        sidecar = production.with_suffix('.glb.import')
        backup_sidecar = backup.with_suffix('.glb.import')
        if sidecar.exists() and not backup_sidecar.exists(): backup_sidecar.write_bytes(sidecar.read_bytes())
        if sha(production) != row['installed_sha256']:
            temporary = production.with_suffix('.glb.promoting')
            assert not temporary.exists(), 'Preserve unexpected pending promotion'
            temporary.write_bytes((ROOT / row['candidate']).read_bytes())
            assert sha(temporary) == row['installed_sha256']
            os.replace(temporary, production)
        assert sha(production) == row['installed_sha256']
    result = {'status': 'Source GLB promoted; ordinary imported-resource verification follows',
              'gpu_cloth_review': False, 'release_or_server': False, 'models': rows}
    (evidence / ('promotion-' + '-'.join(args.only) + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__': main()
