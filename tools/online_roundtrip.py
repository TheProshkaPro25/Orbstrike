#!/usr/bin/env python3
"""One dedicated Godot server + two independent bot processes over real loopback sockets."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import socket
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--timeout", type=float, default=260)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project / "build/checks/online-roundtrip" / time.strftime("%Y%m%d-%H%M%S")
    output.mkdir(parents=True)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    common = [args.godot, "--headless", "--path", str(project)]
    processes: dict[str, subprocess.Popen] = {}
    handles = []
    peak_rss: dict[str, int] = {}
    start = time.monotonic()
    failures = []

    def spawn(name: str, script: str, options: list[str]):
        log = open(output / f"{name}.log", "w")
        handles.append(log)
        proc = subprocess.Popen(common + ["--log-file", str(output / f"{name}-engine.log"), "-s", script, "--"] + options,
                                cwd=project, stdout=log, stderr=subprocess.STDOUT)
        processes[name] = proc
        return proc

    try:
        server = spawn("server", "res://network/server_main.gd", [f"--port={port}", "--bind=127.0.0.1"])
        # Read the server's concrete ready output rather than consuming a peer slot by probing TCP.
        while time.monotonic() - start < 8:
            if server.poll() is not None:
                raise RuntimeError("dedicated server exited before listening")
            if "ONLINE SERVER listening" in (output / "server.log").read_text():
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("server did not become ready")
        for side in (0, 1):
            spawn(f"bot{side}", "res://tests/online_bot_client.gd", [f"--side={side}", f"--url=ws://127.0.0.1:{port}", f"--shared={output}"])
        while time.monotonic() - start < args.timeout:
            for name, process in processes.items():
                try:
                    status = Path(f"/proc/{process.pid}/status").read_text()
                    rss = int(next(row.split()[1] for row in status.splitlines() if row.startswith("VmRSS:")))
                    peak_rss[name] = max(peak_rss.get(name, 0), rss)
                except (OSError, StopIteration):
                    pass
            if all(processes[name].poll() is not None for name in ("bot0", "bot1")):
                break
            if server.poll() is not None:
                raise RuntimeError("dedicated server exited during match")
            time.sleep(0.1)
        else:
            raise RuntimeError("separate-process match timed out")
        for name in ("bot0", "bot1"):
            if processes[name].returncode != 0:
                failures.append(f"{name} exit {processes[name].returncode}")
        bots = [json.loads((output / f"bot{side}.json").read_text()) for side in (0, 1)]
        for row in bots:
            if row["failures"] or row["finished_matches"] != 1 or row["matches"] != 2 or not row["rematch_confirmed"]:
                failures.append(f"bot{row['side']} incomplete match/rematch")
            if row["physical_flights"] < 3:
                failures.append(f"bot{row['side']} insufficient captured physical flights")
        if bots[0]["results"] != bots[1]["results"]:
            failures.append("players received different final result")
        if bots[0]["ended_reason"] != "disconnected" or bots[1]["ended_reason"] != "intentional_disconnect":
            failures.append("rematch disconnect not observed by peer")
    except Exception as error:
        failures.append(str(error))
        bots = []
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for handle in handles:
            handle.close()
    for name in processes:
        text = (output / f"{name}.log").read_text()
        if any(marker in text for marker in ("SCRIPT ERROR:", "ERROR:", "FAIL:")):
            failures.append(f"{name} engine/log error")
    summary = {"kind": "dedicated_server_two_separate_clients_full_physical_match_rematch_disconnect",
               "seconds": round(time.monotonic() - start, 3), "processes": len(processes),
               "peak_sampled_rss_kib": peak_rss, "bots": bots, "failures": failures,
               "scope": "Linux headless actual WebSockets and RigidBody3D; no public host, TLS or Windows run"}
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"Report: {output}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
