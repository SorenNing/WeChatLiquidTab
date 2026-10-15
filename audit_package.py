#!/usr/bin/env python3
"""Read-only structural gate. Never installs a package or runs its scripts.
A PASS is not proof of private WeChat ABI compatibility or device stability.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import subprocess
import tarfile

NAME = "WeChatGroupExtractor"
BASE = "Library/MobileSubstrate/DynamicLibraries/"
EXPECTED = {BASE + NAME + ".dylib", BASE + NAME + ".plist"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE, timeout=60)


def archive_files(raw):
    result = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            require(not path.is_absolute() and ".." not in path.parts,
                    "unsafe archive path")
            if member.isdir():
                continue
            require(member.isfile(), "symlinks/special files are not allowed")
            name = path.as_posix()
            require(name not in result, "duplicate archive member")
            require(0 <= member.size <= 10 * 1024 * 1024, "oversized member")
            result[name] = archive.extractfile(member).read()
    return result


def macho(data):
    require(len(data) >= 32, "Mach-O header missing")
    magic, cpu, sub, kind, count, size, flags, _ = struct.unpack_from("<8I", data)
    require(magic == 0xFEEDFACF, "expected thin little-endian Mach-O 64")
    require(cpu == 0x0100000C and sub & 0xFFFFFF == 2, "expected ARM64E slice")
    require(kind == 6, "expected MH_DYLIB")
    require(flags & 1 and flags & 0x80, "expected NOUNDEFS and TWOLEVEL linking")
    require(32 + size <= len(data) and count < 1000, "invalid load commands")
    dependencies, rpaths, platforms, commands = [], [], [], []
    identifier = None
    position = 32
    for _ in range(count):
        require(position + 8 <= 32 + size, "truncated load command")
        cmd, length = struct.unpack_from("<II", data, position)
        require(length >= 8 and length % 8 == 0 and position + length <= 32 + size,
                "invalid load command size")
        commands.append(cmd)
        if cmd in (0xC, 0xD, 0x80000018, 0x8000001F, 0x20, 0x80000023, 0x8000001C):
            offset = struct.unpack_from("<I", data, position + 8)[0]
            require(12 <= offset < length, "invalid command string offset")
            value = data[position + offset:position + length].split(b"\0", 1)[0].decode()
            if cmd == 0xD:
                identifier = value
            elif cmd == 0x8000001C:
                rpaths.append(value)
            else:
                dependencies.append(value)
        if cmd == 0x32:
            require(length >= 24, "invalid build version")
            platform, minimum, sdk = struct.unpack_from("<III", data, position + 8)
            platforms.append({"platform": platform, "minos": minimum, "sdk": sdk})
        if cmd == 0x2C:
            require(length >= 24, "invalid encryption command")
            require(struct.unpack_from("<I", data, position + 16)[0] == 0,
                    "encrypted binary is not accepted")
        if cmd in (0x1D, 0x80000034):
            require(length >= 16, "invalid linkedit command")
            offset, amount = struct.unpack_from("<II", data, position + 8)
            require(amount > 0 and offset + amount <= len(data), "invalid linkedit range")
        position += length
    require(position == 32 + size, "load command size mismatch")
    require(identifier == "@loader_path/.jbroot/" + BASE + NAME + ".dylib",
            "missing roothide install name")
    require("@loader_path/.jbroot/usr/lib/libsubstrate.dylib" in dependencies,
            "missing roothide Substrate dependency")
    require("/usr/lib/libSystem.B.dylib" in dependencies, "missing real libSystem")
    require("/usr/lib/libobjc.A.dylib" in dependencies, "missing libobjc")
    for framework in ("UIKit", "Foundation"):
        require("/System/Library/Frameworks/" + framework + ".framework/" + framework
                in dependencies, "missing " + framework)
    allowed = {"/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib",
               "@loader_path/.jbroot/usr/lib/libsubstrate.dylib"}
    for dependency in dependencies:
        require(dependency in allowed or dependency.startswith("/System/Library/Frameworks/"),
                "unexpected dependency: " + dependency)
    require(all(p.startswith("@loader_path/.jbroot/") or p.startswith("/System/Library/")
                for p in rpaths), "unexpected runtime search path")
    require(platforms and all(p["platform"] == 2 for p in platforms), "expected iOS platform")
    require(0x80000034 in commands, "missing chained fixups")
    require(0x1D in commands, "missing code signature command")
    require(b"MSHookMessageEx" in data, "missing ObjC hook import")
    require(b"UIVisualEffectView" not in data and b"UIBlurEffect" not in data,
            "unexpected blur/glass class in pure group build")
    return {"architecture": "arm64e", "install_name": identifier,
            "dependencies": dependencies, "rpaths": rpaths, "build_versions": platforms,
            "chained_fixups": True, "code_signature_present_not_verified": True}


def audit(path):
    control = command("dpkg-deb", "-f", str(path)).decode()
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
    require(fields.get("Package") == "com.soren.wechatgroupextractor", "wrong package ID")
    require(fields.get("Architecture") == "iphoneos-arm64e", "wrong package architecture")
    require("mobilesubstrate" in fields.get("Depends", ""), "missing hook dependency")
    require("com.soren.wechatliquidtab" in fields.get("Conflicts", ""),
            "old standalone plugin must not load simultaneously")
    controls = archive_files(command("dpkg-deb", "--ctrl-tarfile", str(path)))
    require(set(controls) <= {"control", "md5sums"}, "unexpected maintainer script/control file")
    files = archive_files(command("dpkg-deb", "--fsys-tarfile", str(path)))
    require(set(files) == EXPECTED, "package must contain exactly the dylib and filter plist")
    config = plistlib.loads(files[BASE + NAME + ".plist"])
    require(config == {"Filter": {"Bundles": ["com.tencent.xin"]}},
            "injection filter is not limited to WeChat")
    binary = files[BASE + NAME + ".dylib"]
    details = macho(binary)
    return {"static_audit": "PASS", "device_tested": False,
            "scope": "Package structure/link metadata only, not runtime correctness",
            "package": fields, "deb_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "dylib_sha256": hashlib.sha256(binary).hexdigest(),
            "files": sorted(files), "macho": details}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deb", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = audit(args.deb)
    except Exception as error:
        report = {"static_audit": "FAIL", "reason": str(error), "device_tested": False}
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    print(text, end="")
    return 0 if report["static_audit"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
