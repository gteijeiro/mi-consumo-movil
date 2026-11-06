#!/usr/bin/env python3
"""Set the signing identifiers for a fork without editing Xcode files by hand."""

import argparse
import plistlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PersonalDataWidget.xcodeproj" / "project.pbxproj"
SHARED = ROOT / "Shared" / "UsageSnapshot.swift"
ENTITLEMENTS = (
    ROOT / "Configuration" / "App.entitlements",
    ROOT / "Configuration" / "Widget.entitlements",
)


def configure(team_id: str, bundle_id: str) -> None:
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("El Team ID debe tener 10 letras mayúsculas o números.")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*){2,}", bundle_id):
        raise ValueError("Usá un Bundle ID propio, por ejemplo com.tunombre.MiConsumoMovil.")
    if bundle_id.endswith(".Widget"):
        raise ValueError("El Bundle ID de la app no debe terminar en .Widget.")

    group_id = f"{team_id}.PersonalDataWidget"
    project = PROJECT.read_text(encoding="utf-8")
    team_pattern = r"DEVELOPMENT_TEAM = [A-Z0-9]{10};"
    project, team_count = re.subn(team_pattern, f"DEVELOPMENT_TEAM = {team_id};", project)
    if team_count != 4:
        raise ValueError("No se encontraron los cuatro Team IDs esperados en el proyecto.")

    bundle_pattern = r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);"
    bundle_matches = re.findall(bundle_pattern, project)
    if len(bundle_matches) != 4 or sum(value.strip('"').endswith(".Widget") for value in bundle_matches) != 2:
        raise ValueError("No se encontraron los cuatro Bundle IDs esperados en el proyecto.")

    def replace_bundle(match: re.Match[str]) -> str:
        is_widget = match.group(1).strip('"').endswith(".Widget")
        return f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}{'.Widget' if is_widget else ''};"

    project = re.sub(bundle_pattern, replace_bundle, project)
    shared = SHARED.read_text(encoding="utf-8")
    shared, group_count = re.subn(
        r'static let appGroup = "[^"]+"',
        f'static let appGroup = "{group_id}"',
        shared,
    )
    if group_count != 1:
        raise ValueError("No se encontró el App Group del código compartido.")

    plist_updates = []
    for path in ENTITLEMENTS:
        settings = plistlib.loads(path.read_bytes())
        if not isinstance(settings.get("com.apple.security.application-groups"), list):
            raise ValueError(f"Falta App Groups en {path.name}.")
        settings["com.apple.security.application-groups"] = [group_id]
        plist_updates.append((path, plistlib.dumps(settings, sort_keys=False)))

    PROJECT.write_text(project, encoding="utf-8")
    SHARED.write_text(shared, encoding="utf-8")
    for path, data in plist_updates:
        path.write_bytes(data)

    print(f"Team: {team_id}")
    print(f"App: {bundle_id}")
    print(f"Widget: {bundle_id}.Widget")
    print(f"App Group: {group_id}")
    print("Abrí Xcode y verificá Signing & Capabilities en ambos targets.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team-id", required=True, help="ID de 10 caracteres de tu equipo de Apple")
    parser.add_argument("--bundle-id", required=True, help="Bundle ID propio, por ejemplo com.tunombre.MiConsumoMovil")
    args = parser.parse_args()
    try:
        configure(args.team_id, args.bundle_id)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
