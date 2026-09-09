#!/usr/bin/env python3
"""Read-only D135 guard for active Xcode inputs and an optional built iPhone app.

Historical source outside target membership is intentionally inert. No build,
signing, Simulator, network, or readiness mutation is performed by this checker.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

WATCH = re.compile(r"WatchConnectivity|WCSession|GameTimeWatch|PhoneWatchConnectivity|watchkit|watchos|watchsimulator|WKCompanionApp|WKWatchKitApp", re.I)
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".c", ".cpp", ".modulemap"}
MACHO_MAGIC = {bytes.fromhex(x) for x in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_project(root):
    root = root.resolve()
    project_dir = root / "ios/GameTime"
    project = project_dir / "GameTime.xcodeproj"
    objects = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(project / "project.pbxproj")
    ]))["objects"]
    # Inspect the entire project, including standalone targets, proxy dependencies,
    # copy phases, linker flags and shell phases, not just Release reachability.
    require(not WATCH.search(json.dumps(objects)), "Watch reference in active project")
    for obj in objects.values():
        if obj.get("isa") == "PBXCopyFilesBuildPhase":
            copy_path = str(obj.get("dstPath", ""))
            require(not re.search(r"(?:^|/)Watch(?:/|$)", copy_path, re.I),
                    "Watch embedding copy phase in active project")
        settings = obj.get("buildSettings", {})
        family = str(settings.get("TARGETED_DEVICE_FAMILY", ""))
        require(not re.search(r"\b4\b", family), "Watch device family in active project")

    parents = {}
    for key, obj in objects.items():
        for child in obj.get("children", []):
            require(child not in parents, "Ambiguous project group parent")
            parents[child] = key

    def resolve(key, seen=None):
        seen = set() if seen is None else seen
        require(key not in seen, "Cyclic project group")
        seen.add(key)
        obj = objects[key]
        tree = obj.get("sourceTree", "<group>")
        require(tree in {"<group>", "SOURCE_ROOT", "<absolute>"}, "Unsupported source tree: " + tree)
        base = resolve(parents[key], seen) if tree == "<group>" and key in parents else project_dir
        path = (base / obj.get("path", "")).resolve()
        require(path.is_relative_to(root), "Source path escapes repository: " + str(path))
        return path

    targets = {key: obj for key, obj in objects.items() if obj.get("isa") == "PBXNativeTarget"}
    require(any(x.get("name") == "GameTime" for x in targets.values()), "GameTime target missing")
    app_target = next(x for x in targets.values() if x.get("name") == "GameTime")
    configs = objects[app_target["buildConfigurationList"]]["buildConfigurations"]
    require(configs, "App build configurations missing")
    for config_id in configs:
        config = objects[config_id]
        entitlement_path = config.get("buildSettings", {}).get("CODE_SIGN_ENTITLEMENTS")
        require(entitlement_path, "HealthKit entitlement input missing: " + config["name"])
        entitlement_file = (project_dir / entitlement_path).resolve()
        require(entitlement_file.is_relative_to(root), "Entitlements escape repository")
        with entitlement_file.open('rb') as f:
            entitlements = plistlib.load(f)
        require(entitlements.get("com.apple.developer.healthkit") is True,
                "HealthKit capability missing: " + config["name"])
    sources = set()
    for key, target in targets.items():
        for group_id in target.get("fileSystemSynchronizedGroups", []):
            group = objects[group_id]
            require(group.get("isa") == "PBXFileSystemSynchronizedRootGroup", "Unsupported synchronized group")
            # Fail closed if membership gains exceptions; inspect these deliberately
            # before teaching the guard another way to exclude product sources.
            require(not group.get("exceptions"), "Source membership exceptions require review")
            folder = resolve(group_id)
            require(folder.is_dir(), "Missing target source directory: " + str(folder))
            sources.update(p.resolve() for p in folder.rglob('*') if p.suffix in SOURCE_SUFFIXES)
        for phase_id in target.get("buildPhases", []):
            phase = objects[phase_id]
            if phase.get("isa") != "PBXSourcesBuildPhase":
                continue
            for build_id in phase.get("files", []):
                sources.add(resolve(objects[build_id]["fileRef"]))
    require(sources, "No active target sources found")
    # Local package dependencies are source inputs too; do not scan build caches.
    for obj in objects.values():
        if obj.get("isa") == "XCLocalSwiftPackageReference":
            package = (project_dir / obj["relativePath"]).resolve()
            require(package.is_relative_to(root), "Local package escapes repository")
            sources.add(package / "Package.swift")
            sources.update(p for p in (package / "Sources").rglob('*') if p.suffix in SOURCE_SUFFIXES)
    for path in sorted(sources):
        require(path.is_relative_to(root), "Source symlink escapes repository")
        require(not WATCH.search(path.read_text()), "Watch runtime source in target: " + str(path.relative_to(root)))
    for path in (project_dir / "Configuration").rglob("*.xcconfig"):
        require(not WATCH.search(path.read_text()), "Watch reference in active configuration: " + path.name)
    schemes = list((project / "xcshareddata/xcschemes").glob("*.xcscheme"))
    require(schemes, "No shared candidate schemes found")
    for path in schemes:
        require(not WATCH.search(path.read_text()), "Watch build/launch in shared scheme: " + path.name)
        for ref in ET.parse(path).iter("BuildableReference"):
            require(ref.get("BlueprintIdentifier") in targets, "Unknown scheme buildable: " + path.name)
    return {"targets": sorted(x['name'] for x in targets.values()), "schemes": sorted(p.name for p in schemes), "source_files": len(sources)}


def check_app(app):
    require(app.is_dir() and app.suffix == ".app", "Expected a built .app directory")
    binaries = []
    healthkit = False
    with (app / "Info.plist").open('rb') as f:
        info = plistlib.load(f)
    require(info.get("CFBundleSupportedPlatforms") in [["iPhoneSimulator"], ["iPhoneOS"]], "Product is not an iPhone app")
    require(info.get("NSHealthShareUsageDescription"), "iPhone Health read usage description missing")
    for path in sorted(app.rglob('*')):
        require(path.name.lower() != "watch" and not WATCH.search(path.name), "Watch payload in app: " + str(path.relative_to(app)))
        if not path.is_file():
            continue
        if path.name == "Info.plist":
            with path.open('rb') as f:
                nested = plistlib.load(f)
            require(not WATCH.search(json.dumps(nested)), "Watch metadata in app: " + str(path.relative_to(app)))
        with path.open('rb') as f:
            magic = f.read(4)
        if magic not in MACHO_MAGIC:
            continue
        links = subprocess.check_output(["xcrun", "otool", "-L", str(path)], text=True)
        require(not WATCH.search(links), "WatchConnectivity linked by " + str(path.relative_to(app)))
        # Includes dynamic-load literals and WCSession symbols, in the main
        # executable, Debug dylib and every embedded Mach-O framework/extension.
        data = path.read_bytes()
        require(not any(token in data for token in [b"WatchConnectivity", b"WCSession", b"PhoneWatchConnectivityCoordinator", b"GameTimeWatchContext"]), "Watch runtime symbols in " + str(path.relative_to(app)))
        healthkit |= "HealthKit.framework/HealthKit" in links
        binaries.append(str(path.relative_to(app)))
    require(binaries, "No Mach-O product binaries found")
    require(healthkit, "iPhone product no longer links HealthKit")
    return {"app": str(app), "mach_o_files": binaries, "healthkit_linked": healthkit, "watch_payloads_or_links": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--app", type=Path, help="Also inspect an existing built product (never builds it)")
    args = parser.parse_args()
    try:
        result = {"project": check_project(args.root.resolve())}
        if args.app:
            result["product"] = check_app(args.app.resolve())
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError, KeyError, ET.ParseError, subprocess.CalledProcessError) as error:
        print("BLOCKER iphone-product: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
