"""Collect AOT measurements separately from deterministic correctness gates."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / ".dart_tool/ci-performance"
SOURCES = {
    "open": "packages/pdfrx_engine/tool/pdf_open_benchmark.dart",
    "pixels": "packages/pdfrx_engine/tool/pdf_pixel_conversion_benchmark.dart",
    "hebrew": "packages/pdfrx_engine/tool/pdf_hebrew_text_normalizer_benchmark.dart",
    "selection": "packages/pdfrx/tool/text_selection_index_benchmark.dart",
}
FIXTURES = {
    "hello": "packages/pdfrx/example/viewer/assets/hello.pdf",
    "multipage": "packages/pdfrx/test/assets/multipage40.pdf",
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture(command, **kwargs):
    return subprocess.check_output(command, text=True, cwd=ROOT, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=5)
    args = parser.parse_args()
    if not 3 <= args.samples <= 20:
        parser.error("--samples must be between 3 and 20")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    dart = os.environ.get("DART_EXECUTABLE", "dart")
    metadata = {
        "revision": capture(["git", "rev-parse", "HEAD"]),
        "workingTreeChanges": capture(["git", "status", "--short"]),
        "platform": platform.platform(),
        "architecture": platform.machine(),
        "cpuCount": os.cpu_count(),
        "cpu": Path("/proc/cpuinfo").read_text() if Path("/proc/cpuinfo").exists() else platform.processor(),
        "dart": capture([dart, "--version"], stderr=subprocess.STDOUT),
        "mode": "AOT executable; one fresh process per sample",
        "samplesPerBenchmark": args.samples,
        "filesystemCache": "not flushed; benchmark order rotates between repetitions",
        "timingThresholds": None,
        "sourceSha256": {name: digest(ROOT / source) for name, source in SOURCES.items()},
        "fixtures": {
            name: {"path": path, "sha256": digest(ROOT / path), "bytes": (ROOT / path).stat().st_size}
            for name, path in FIXTURES.items()
        },
    }
    (OUTPUT / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for name, source in SOURCES.items():
        with (OUTPUT / f"compile-{name}.log").open("w") as log:
            subprocess.run(
                [dart, "compile", "exe", source, "-o", str(OUTPUT / name)],
                cwd=ROOT,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
            )
    # The build hook has verified this archive's pinned digest. Use its stable
    # cache path, not a test runner manifest referring to deleted temporary files.
    libraries = list((ROOT / ".dart_tool/hooks_runner/shared/pdfium_dart/build").glob("*/linux-x64/libpdfium.so"))
    if len(libraries) != 1:
        raise RuntimeError(f"Expected one PDFium build-hook library in a clean checkout; found {libraries}")
    library = libraries[0]
    metadata["pdfium"] = {"path": str(library.relative_to(ROOT)), "sha256": digest(library)}
    metadata["executableSha256"] = {name: digest(OUTPUT / name) for name in SOURCES}
    (OUTPUT / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    environment = {**os.environ, "PDFIUM_PATH": str(library)}
    commands = {
        "open": [str(ROOT / FIXTURES["multipage"]), "20"],
        "pixels": [str(ROOT / FIXTURES["hello"]), "7"],
        "hebrew": ["20"],
        "selection": [],
    }
    names = list(commands)
    with (OUTPUT / "samples.jsonl").open("w") as samples:
        for repetition in range(args.samples):
            offset = repetition % len(names)
            for name in names[offset:] + names[:offset]:
                command = [str(OUTPUT / name), *commands[name]]
                started = time.perf_counter_ns()
                result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True)
                measurement = {
                    "benchmark": name,
                    "sample": repetition,
                    "command": command,
                    "processElapsedMicros": (time.perf_counter_ns() - started) // 1000,
                    "exitCode": result.returncode,
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                }
                samples.write(json.dumps(measurement) + "\n")
                samples.flush()
                result.check_returncode()
                print(f"Recorded {name} sample {repetition + 1}/{args.samples}", flush=True)


if __name__ == "__main__":
    main()
