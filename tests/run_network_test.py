"""Run a real ENet host and two separate clients; requires Godot 4.6.3."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parents[1]
subprocess.run(
    ["godot", "--headless", "--xr-mode", "off", "--path", str(project),
     "--editor", "--import", "--quit"], check=True,
)
with tempfile.TemporaryDirectory(prefix="canopy-network-") as scratch:
    scratch = Path(scratch)
    processes = {}
    logs = {}

    def start(role):
        log_path = scratch / f"{role}.log"
        logs[role] = log_path
        log = log_path.open("w")
        env = os.environ.copy()
        env["XDG_DATA_HOME"] = str(scratch / role / "data")
        env["XDG_CACHE_HOME"] = str(scratch / role / "cache")
        process = subprocess.Popen(
            ["godot", "--headless", "--xr-mode", "off", "--audio-driver", "Dummy",
             "--path", str(project), "--", f"--net-test={role}"],
            env=env, stdout=log, stderr=subprocess.STDOUT,
        )
        log.close()
        processes[role] = process

    try:
        start("host")
        time.sleep(0.6)
        start("client1")
        deadline = time.monotonic() + 30
        while "WAIT_LATE_JOIN" not in logs["host"].read_text():
            if processes["host"].poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("Host did not reach late-join stage")
            time.sleep(0.1)
        start("client2")
        for role, process in processes.items():
            result = process.wait(timeout=35)
            if result:
                raise RuntimeError(f"{role} exited {result}")
        for role, path in logs.items():
            content = path.read_text()
            print(f"--- {role} ---\n{content}")
            if "ERROR:" in content or "SCRIPT ERROR" in content:
                raise RuntimeError(f"Errors reported by {role}")
        print("THREE-PROCESS NETWORK TEST PASSED")
    except Exception:
        for role, path in logs.items():
            print(f"--- {role} ---\n{path.read_text()}")
        raise
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
