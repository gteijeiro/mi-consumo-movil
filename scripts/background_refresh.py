#!/usr/bin/env python3
"""Install or remove a per-user launch agent that keeps the app available."""

import argparse
import os
import plistlib
import re
import shlex
import subprocess
from pathlib import Path


LABEL = "com.gteijeiro.MiConsumoMovil.ensureRunning"
APP_NAME = "PersonalDataWidget.app"
SCRIPT_NAME = "ensure-running.sh"


def paths() -> tuple[Path, Path]:
    home = Path.home()
    return (
        home / "Library" / "LaunchAgents" / f"{LABEL}.plist",
        home / "Library" / "Application Support" / "Mi Consumo Movil" / SCRIPT_NAME,
    )


def launchctl(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["/bin/launchctl", *args], check=check, text=True, capture_output=True)


def install(app: Path) -> None:
    app = app.expanduser().resolve()
    info = app / "Contents" / "Info.plist"
    binary = app / "Contents" / "MacOS" / "PersonalDataWidget"
    if not binary.is_file() or not info.is_file():
        raise SystemExit(f"No se encontró una app instalada en {app}")
    with info.open("rb") as handle:
        app_info = plistlib.load(handle)
    if app_info.get("CFBundleExecutable") != "PersonalDataWidget":
        raise SystemExit(f"El ejecutable de {app} no corresponde a Mi Consumo Móvil")

    plist_path, script_path = paths()
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.parent.mkdir(parents=True, exist_ok=True)
    script = (
        "#!/bin/sh\n"
        f"if /usr/bin/pgrep -f {shlex.quote('^' + re.escape(str(binary)) + '($| )')} >/dev/null; then exit 0; fi\n"
        f"/usr/bin/open -g {shlex.quote(str(app))}\n"
    )
    script_path.write_text(script, encoding="utf-8")
    script_path.chmod(0o700)
    definition = {
        "Label": LABEL,
        "ProgramArguments": [str(script_path)],
        "RunAtLoad": True,
        "StartInterval": 300,
        "ProcessType": "Background",
    }
    domain = f"gui/{os.getuid()}"
    launchctl("bootout", domain, str(plist_path), check=False)
    with plist_path.open("wb") as handle:
        plistlib.dump(definition, handle)
    launchctl("bootstrap", domain, str(plist_path))
    print("Actualización en segundo plano activada. macOS comprobará la app cada 5 minutos.")


def uninstall() -> None:
    plist_path, script_path = paths()
    launchctl("bootout", f"gui/{os.getuid()}", str(plist_path), check=False)
    plist_path.unlink(missing_ok=True)
    script_path.unlink(missing_ok=True)
    print("Tarea de segundo plano eliminada.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--install", action="store_true")
    group.add_argument("--uninstall", action="store_true")
    parser.add_argument("--app", type=Path, default=Path("/Applications") / APP_NAME)
    args = parser.parse_args()
    if args.install:
        install(args.app)
    else:
        uninstall()


if __name__ == "__main__":
    main()
