#!/usr/bin/env python3
"""Join every original V9 holdout row and its one fixed extension, without filtering.

The originals are read-only. Global roster indexes are remapped only in the new
aggregate; source_case and source_row preserve the original seed formula/index.
"""
import copy
import hashlib
import json
from pathlib import Path
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def merge(original_path, extension_path, output_path):
    paths = [Path(original_path), Path(extension_path)]
    output = Path(output_path)
    if output.resolve() in [p.resolve() for p in paths]:
        raise ValueError("Aggregate must not replace either original raw")
    raws = [json.loads(p.read_text()) for p in paths]
    for raw, expected in zip(raws, [240, 480]):
        assert len(raw["matches"]) == expected
        assert not raw["failures"]
        assert all(not r["mirror"] and r["finished"] for r in raw["matches"])
    assert all(raws[0][key] == raws[1][key] for key in [
        "common_deck_seed", "pair_seeded_streams", "pair_seeded_decks",
        "random_starting_cards", "deck_seed_method", "match_seed_method"])
    catalogs = [p.with_name(p.stem + "-catalog.json") for p in paths]
    assert catalogs[0].read_bytes() == catalogs[1].read_bytes()
    streams = [{r["seed"] for r in raw["matches"]} for raw in raws]
    assert len(streams[0]) == 60 and len(streams[1]) == 120
    assert not streams[0] & streams[1]
    result = copy.deepcopy(raws[0])
    result.update(label="v9-fixed-expanded-holdout-720-including-original240FAIL",
                  rosters=[], seeds=[], gold_roles=[], matches=[], failures=[])
    result["component_sources"] = []
    for component, (path, raw) in enumerate(zip(paths, raws)):
        offset = len(result["rosters"])
        result["component_sources"].append(dict(
            path=str(path), sha256=sha(path), matches=len(raw["matches"]),
            roster_offset=offset,
            original_acceptance="FAIL retained" if component == 0 else "fixed extension"))
        for key in ["rosters", "seeds", "gold_roles"]:
            result[key].extend(raw[key])
        for index, source_row in enumerate(raw["matches"]):
            row = copy.deepcopy(source_row)
            row.update(component=component, source_case=row["roster"], source_row=index)
            row["roster"] += offset
            result["matches"].append(row)
    result["match_seed_method"] += "; use source_case within each component, not aggregate roster index"
    result["stopping"] = "Completed one preregistered 480 extension; all original240 retained; no further growth"
    assert len(result["matches"]) == 720
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    output.with_name(output.stem + "-catalog.json").write_bytes(catalogs[0].read_bytes())
    assert all(sha(path) == source["sha256"] for path, source in zip(paths, result["component_sources"]))
    print(json.dumps(dict(output=str(output), matches=720, streams=180,
                          sha256=sha(output), components=result["component_sources"]), indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: element_balance_merge_validation.py original240.json extension480.json aggregate720.json")
    merge(*sys.argv[1:])
