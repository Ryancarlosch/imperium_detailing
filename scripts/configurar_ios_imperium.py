#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERRO: {message}")
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail(
        "Informe o Bundle Identifier. "
        "Exemplo: python3 scripts/configurar_ios_imperium.py "
        "br.com.suaempresa.imperiummanager"
    )

bundle_id = sys.argv[1].strip()

if not re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id):
    fail("Bundle Identifier invalido. Use apenas letras, numeros, ponto e hifen.")

if "." not in bundle_id:
    fail("Bundle Identifier deve possuir formato reverso, por exemplo br.com.empresa.app.")

root = Path(__file__).resolve().parents[1]
plist_path = root / "ios" / "Runner" / "Info.plist"
pbxproj_path = root / "ios" / "Runner.xcodeproj" / "project.pbxproj"

if not plist_path.exists():
    fail("ios/Runner/Info.plist nao encontrado. Gere a plataforma iOS primeiro.")

if not pbxproj_path.exists():
    fail("ios/Runner.xcodeproj/project.pbxproj nao encontrado.")

with plist_path.open("rb") as handle:
    plist = plistlib.load(handle)

plist["CFBundleDisplayName"] = "Imperium Manager"
plist["CFBundleName"] = "Imperium Manager"
plist["NSCameraUsageDescription"] = (
    "O Imperium usa a câmera para registrar veículos, serviços, "
    "checklist e documentos."
)
plist["NSPhotoLibraryUsageDescription"] = (
    "O Imperium acessa suas fotos para anexar imagens de veículos, "
    "serviços e documentos."
)
plist["NSPhotoLibraryAddUsageDescription"] = (
    "O Imperium pode salvar imagens e documentos gerados pelo aplicativo."
)

url_types = plist.get("CFBundleURLTypes")
if not isinstance(url_types, list):
    url_types = []

scheme = "imperiumdetailing"
found = False

for item in url_types:
    if not isinstance(item, dict):
        continue
    schemes = item.get("CFBundleURLSchemes")
    if isinstance(schemes, list) and scheme in schemes:
        item["CFBundleURLName"] = bundle_id
        found = True

if not found:
    url_types.append(
        {
            "CFBundleURLName": bundle_id,
            "CFBundleURLSchemes": [scheme],
        }
    )

plist["CFBundleURLTypes"] = url_types

with plist_path.open("wb") as handle:
    plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)

pbxproj = pbxproj_path.read_text(encoding="utf-8")

pattern = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);")


def bundle_replacement(match: re.Match[str]) -> str:
    current = match.group(1).strip()
    if current.endswith(".RunnerTests") or "RunnerTests" in current:
        value = f"{bundle_id}.RunnerTests"
    else:
        value = bundle_id
    return f"PRODUCT_BUNDLE_IDENTIFIER = {value};"


updated, count = pattern.subn(bundle_replacement, pbxproj)

if count == 0:
    fail("Nenhum PRODUCT_BUNDLE_IDENTIFIER foi encontrado no projeto Xcode.")

pbxproj_path.write_text(updated, encoding="utf-8")

print("CONFIGURACAO IOS IMPERIUM APLICADA.")
print(f"Bundle Identifier: {bundle_id}")
print("URL scheme: imperiumdetailing")
print("Display name: Imperium Manager")
