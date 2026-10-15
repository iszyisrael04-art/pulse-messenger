from pathlib import Path
import shutil
import subprocess


def run_logged(command, destination, cwd):
    with destination.open("w", encoding="utf-8") as log:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )

    print(
        destination.read_text(encoding="utf-8", errors="replace"),
        flush=True,
    )
    return result.returncode


def build(root):
    flutter = shutil.which("flutter")
    if flutter is None:
        print("Flutter was not found on PATH.")
        return 127

    logs = root / "build-logs"
    logs.mkdir(exist_ok=True)

    code = run_logged(
        [
            flutter,
            "build",
            "windows",
            "--release",
            "--dart-define-from-file=config.example.json",
            "--verbose",
        ],
        logs / "windows-build.log",
        root,
    )

    if code != 0:
        cmake = shutil.which("cmake")
        output = root / "build/windows/x64"

        if cmake and (output / "cmake_install.cmake").exists():
            run_logged(
                [
                    cmake,
                    "--install",
                    str(output),
                    "--config",
                    "Release",
                    "--verbose",
                ],
                logs / "windows-install.log",
                root,
            )

    return code


if __name__ == "__main__":
    raise SystemExit(build(Path(__file__).resolve().parents[1]))
