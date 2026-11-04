#!/usr/bin/env python3
"""Build an allowlisted, art-free source server bundle. Does not deploy or download anything."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tarfile
import time

CORE = ("attr battle_context battle_participant battle_result card_db card_def card_effects "
        "creature_def creature_state deck_def match_controller match_rules match_state player_state power_calc slot_state").split()
NETWORK = "online_server online_protocol state_codec online_physics server_main".split()
PROJECT = '''config_version=5
[application]
config/name="Orbstrike Online Server"
config/version="0.4.0"
config/features=PackedStringArray("4.7")
[rendering]
renderer/rendering_method="gl_compatibility"
'''


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked(command: list[str], log: Path, env: dict[str, str], timeout: int = 90) -> None:
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    log.write_text(result.stdout)
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
        raise RuntimeError(f"command failed ({result.returncode}); inspect {log}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--skip-network-probe", action="store_true", help="Build only; do not claim runtime validation")
    args = parser.parse_args()
    args.godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    project = Path(__file__).resolve().parents[1]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    output = project / "build/online-server" / stamp
    bundle = output / "orbstrike-online"
    bundle.mkdir(parents=True)
    env = dict(os.environ)
    for variable, directory in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        folder = output / "builder-state" / directory
        folder.mkdir(parents=True)
        env[variable] = str(folder)
    version = subprocess.check_output([args.godot, "--version"], env=env, text=True).strip()
    if not version.startswith("4.7.2."):
        raise RuntimeError("Bundle needs Godot4.7.2; received " + version)
    sources = [f"core/{name}.gd" for name in CORE] + [f"network/{name}.gd" for name in NETWORK]
    sources += ["data/game_data.gd", "scenes/shot_physics.gd", "docs/ONLINE_SERVER.md"]
    for name in sources:
        target = bundle / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / name, target)
    for name in ["start_server.sh", "orbstrike-online.service", "Caddyfile.example", "healthcheck.gd"]:
        target = bundle / "deploy" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / "tools/deploy/online" / name, target)
    (bundle / "deploy/start_server.sh").chmod(0o755)
    (bundle / "project.godot").write_text(PROJECT)
    # No existing .godot, user profile or editor configuration is ever copied.
    checked([args.godot, "--headless", "--path", str(bundle), "--log-file", str(output / "import-engine.log"),
             "--editor", "--import", "--quit"], output / "import.log", env)
    cache = bundle / ".godot/global_script_class_cache.cfg"
    if not cache.exists(): raise RuntimeError("fresh global class cache was not generated")
    for path in sorted((bundle / ".godot").rglob("*"), reverse=True):
        if path.is_file() and path.name not in ["global_script_class_cache.cfg", "uid_cache.bin", ".gdignore"]:
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()): path.rmdir()
    checked([args.godot, "--headless", "--path", str(bundle), "--log-file", str(output / "parse-engine.log"),
             "--check-only", "-s", "res://network/server_main.gd"], output / "parse.log", env)
    (bundle / "README.txt").write_text("Orbstrike 0.4.0 source-server bundle; engine is installed separately.\n"
        "Use official Godot4.7.2 Linux x86_64; see the included docs/ONLINE_SERVER.md.\n"
        "No art, client UI, private configuration, account information or engine binary included.\n"
        "Runtime requires pre-generated .godot class cache shipped here; do not delete it.\n")
    validation = {"fresh_import": True, "parse": True, "network_two_client_two_physical_throws": False}
    if not args.skip_network_probe:
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        # Make the entire project tree read-only during the actual service run.
        for path in bundle.rglob("*"):
            path.chmod(0o555 if path.is_dir() or path.name == "start_server.sh" else 0o444)
        bundle.chmod(0o555)
        runtime_env = dict(env, ORBSTRIKE_SERVER_ROOT=str(bundle), GODOT=str(Path(args.godot).resolve()),
                           ORBSTRIKE_STATE_DIR=str(output / "server-state"), ORBSTRIKE_PORT=str(port))
        server_log = open(output / "runtime.log", "w")
        server = subprocess.Popen([str(bundle / "deploy/start_server.sh")], env=runtime_env,
                                  stdout=server_log, stderr=subprocess.STDOUT)
        try:
            until = time.monotonic() + 8
            while time.monotonic() < until:
                if server.poll() is not None: raise RuntimeError("bundle server exited; inspect runtime.log")
                if "ONLINE SERVER listening" in (output / "runtime.log").read_text(): break
                time.sleep(0.05)
            else: raise RuntimeError("bundle server did not listen")
            checked([args.godot, "--headless", "--path", str(project), "--log-file", str(output / "probe-engine.log"),
                     "-s", "res://tests/online_client_probe.gd", "--", f"--url=ws://127.0.0.1:{port}"], output / "probe.log", env)
            checked([args.godot, "--headless", "--path", str(bundle), "--log-file", str(output / "health-engine.log"),
                     "-s", "res://deploy/healthcheck.gd", "--", f"--url=ws://127.0.0.1:{port}"], output / "health.log", env)
            validation["network_two_client_two_physical_throws"] = True
            validation["protocol_healthcheck"] = True
            validation["readonly_project"] = True
        finally:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
            server_log.close()
        text = (output / "runtime.log").read_text()
        if "ERROR:" in text or "SCRIPT ERROR:" in text: raise RuntimeError("bundle server runtime error")
    files = {str(path.relative_to(bundle)): sha(path) for path in sorted(bundle.rglob("*")) if path.is_file()}
    manifest = {"format": 1, "engine_required": "official Godot4.7.2 stable Linux x86_64 (installed separately)",
                "builder_engine": version, "created": stamp, "files_sha256": files, "validation": validation}
    bundle.chmod(0o755)
    (bundle / "MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    (bundle / "MANIFEST.json").chmod(0o444)
    bundle.chmod(0o555)
    archive = output / f"orbstrike-online-{stamp}.tar.gz"
    def public_metadata(entry: tarfile.TarInfo) -> tarfile.TarInfo:
        entry.uid = entry.gid = 0
        entry.uname = entry.gname = ""
        return entry
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(bundle, arcname="orbstrike-online", filter=public_metadata)
    digest = sha(archive)
    (output / (archive.name + ".sha256")).write_text(f"{digest}  {archive.name}\n")
    report = {"archive": str(archive), "bytes": archive.stat().st_size, "sha256": digest,
              "file_count": len(files), "validation": validation, "engine_bundled": False}
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
