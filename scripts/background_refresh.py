#!/usr/bin/env python3
"""Install or remove a per-user launch agent for headless usage refreshes."""

import argparse
import os
import plistlib
import shlex
import subprocess
from pathlib import Path


LABEL = "com.gteijeiro.MiConsumoMovil.backgroundRefresh"
LEGACY_LABEL = "com.gteijeiro.MiConsumoMovil.ensureRunning"
APP_NAME = "PersonalDataWidget.app"
SCRIPT_NAME = "refresh-if-needed.sh"


def paths(label: str = LABEL, script_name: str = SCRIPT_NAME) -> tuple[Path, Path]:
    home = Path.home()
    return (
        home / "Library" / "LaunchAgents" / f"{label}.plist",
        home / "Library" / "Application Support" / "Mi Consumo Movil" / script_name,
    )


def launchctl(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["/bin/launchctl", *args], check=check, text=True, capture_output=True)


def remove(label: str, script_name: str) -> None:
    plist_path, script_path = paths(label, script_name)
    launchctl("bootout", f"gui/{os.getuid()}", str(plist_path), check=False)
    plist_path.unlink(missing_ok=True)
    script_path.unlink(missing_ok=True)


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

    remove(LEGACY_LABEL, "ensure-running.sh")
    plist_path, script_path = paths()
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.parent.mkdir(parents=True, exist_ok=True)
    script = (
        "#!/bin/sh\n"
        f"exec {shlex.quote(str(binary))} --background-refresh\n"
    )
    script_path.write_text(script, encoding="utf-8")
    script_path.chmod(0o700)
    definition = {
        "Label": LABEL,
        "ProgramArguments": [str(script_path)],
        "RunAtLoad": True,
        "StartCalendarInterval": [{"Minute": minute} for minute in range(0, 60, 5)],
        "ProcessType": "Background",
    }
    domain = f"gui/{os.getuid()}"
    launchctl("bootout", domain, str(plist_path), check=False)
    with plist_path.open("wb") as handle:
        plistlib.dump(definition, handle)
    launchctl("bootstrap", domain, str(plist_path))
    print("Actualización sin ventana activada. macOS comprobará la lectura cada 5 minutos.")


def uninstall() -> None:
    remove(LABEL, SCRIPT_NAME)
    remove(LEGACY_LABEL, "ensure-running.sh")
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
