"""Structural audit regression tests use synthetic, non-executable metadata."""
import io
import struct
import tarfile
import unittest

import audit_package as gate


def command_string(cmd, name):
    raw = name.encode() + b"\0"
    size = (24 + len(raw) + 7) // 8 * 8
    return struct.pack("<6I", cmd, size, 24, 1, 0, 0) + raw.ljust(size - 24, b"\0")


def sample(cpu_sub=2, blur=False, substrate=True):
    deps = ["/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib",
            "/System/Library/Frameworks/UIKit.framework/UIKit",
            "/System/Library/Frameworks/Foundation.framework/Foundation"]
    if substrate:
        deps.append("@loader_path/.jbroot/usr/lib/libsubstrate.dylib")
    cmds = [command_string(0xD, "@loader_path/.jbroot/" + gate.BASE + gate.NAME + ".dylib")]
    cmds += [command_string(0xC, name) for name in deps]
    cmds += [struct.pack("<6I", 0x32, 24, 2, 0xF0000, 0x100500, 0)]
    size = sum(len(cmd) for cmd in cmds) + 32
    dataoff = 32 + size
    cmds += [struct.pack("<4I", 0x80000034, 16, dataoff, 8),
             struct.pack("<4I", 0x1D, 16, dataoff + 8, 8)]
    header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, cpu_sub, 6,
                         len(cmds), size, 0x81, 0)
    tail = b"\0" * 16 + b"_MSHookMessageEx\0"
    if blur:
        tail += b"UIVisualEffectView\0"
    return header + b"".join(cmds) + tail


def archive(name, link=False):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w") as tar:
        info = tarfile.TarInfo(name)
        if link:
            info.type = tarfile.SYMTYPE
            info.linkname = "elsewhere"
            tar.addfile(info)
        else:
            info.size = 1
            tar.addfile(info, io.BytesIO(b"x"))
    return out.getvalue()


class AuditTests(unittest.TestCase):
    def test_minimal_metadata(self):
        self.assertEqual(gate.macho(sample())["architecture"], "arm64e")

    def test_reject_arm64(self):
        with self.assertRaisesRegex(ValueError, "ARM64E"):
            gate.macho(sample(cpu_sub=0))

    def test_reject_glass(self):
        with self.assertRaisesRegex(ValueError, "blur/glass"):
            gate.macho(sample(blur=True))

    def test_reject_missing_substrate(self):
        with self.assertRaisesRegex(ValueError, "Substrate"):
            gate.macho(sample(substrate=False))

    def test_reject_truncation(self):
        with self.assertRaises(ValueError):
            gate.macho(sample()[:40])

    def test_archive(self):
        self.assertEqual(gate.archive_files(archive("./control")), {"control": b"x"})

    def test_reject_parent_path(self):
        with self.assertRaisesRegex(ValueError, "unsafe"):
            gate.archive_files(archive("../out"))

    def test_reject_absolute_path(self):
        with self.assertRaisesRegex(ValueError, "unsafe"):
            gate.archive_files(archive("/out"))

    def test_reject_symlink(self):
        with self.assertRaisesRegex(ValueError, "symlinks"):
            gate.archive_files(archive("control", link=True))


if __name__ == "__main__":
    unittest.main()
