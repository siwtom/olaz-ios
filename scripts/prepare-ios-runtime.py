#!/usr/bin/env python3
"""
Download, verify, strip macOS native modules/unpacked binaries from Zalo's app.asar,
and package a flat self-contained iOS runtime folder at:
  build/ZaloRuntime/runtime-info.plist
  build/ZaloRuntime/app.asar

Avoids nested Contents/Info.plist so iOS codesign never treats ZaloRuntime as an
unsigned sub-bundle. Matches AsarArchive.swift and ZaloRuntimeInstaller.swift.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import plistlib
import platform
import shutil
import struct
import subprocess
import tempfile
import urllib.request

PINNED_VERSION = "26.10.20"
PINNED_URL = "https://res-download-pc.zadn.vn/mac/ZaloSetup-universal-26.10.20.dmg"
PINNED_SHA256 = "a45d30b7f7b060f76b87722ef419b8f41d23a2913cdef084dcb0955dde8d85a0"
VNG_TEAM_ID = "CVB6BX97VM"

STRIPPED_SUFFIXES = (".node", ".dylib", ".so")


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest().lower()


def download_pinned_dmg(download_dir: pathlib.Path) -> pathlib.Path:
    download_dir.mkdir(parents=True, exist_ok=True)
    dmg_path = download_dir / f"ZaloSetup-universal-{PINNED_VERSION}.dmg"
    if dmg_path.exists():
        digest = sha256_file(dmg_path)
        if digest == PINNED_SHA256:
            print(f"Using verified cached DMG: {dmg_path}")
            return dmg_path
        print(f"Cached DMG SHA-256 mismatch ({digest}), re-downloading...")
        dmg_path.unlink()

    print(f"Downloading VNG Zalo {PINNED_VERSION} from {PINNED_URL} ...")
    tmp = dmg_path.with_suffix(".dmg.tmp")
    req = urllib.request.Request(PINNED_URL, headers={"User-Agent": "OlazIOSBuilder/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp, tmp.open("wb") as out:
        shutil.copyfileobj(resp, out)
    tmp.replace(dmg_path)

    digest = sha256_file(dmg_path)
    if digest != PINNED_SHA256:
        dmg_path.unlink(missing_ok=True)
        raise RuntimeError(f"DMG SHA-256 mismatch: expected {PINNED_SHA256}, got {digest}")
    print(f"Verified DMG SHA-256: {digest}")
    return dmg_path


def verify_codesign(app_path: pathlib.Path) -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("codesign verification is only supported on macOS.")
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(app_path)],
        check=True,
    )
    info = subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(app_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    combined = (info.stdout or "") + "\n" + (info.stderr or "")
    if f"TeamIdentifier={VNG_TEAM_ID}" not in combined:
        raise RuntimeError(f"Unexpected VNG code signature; missing TeamIdentifier={VNG_TEAM_ID}")
    print(f"Verified VNG TeamIdentifier={VNG_TEAM_ID}")


def read_asar(asar_path: pathlib.Path) -> tuple[dict, bytes, int]:
    raw = asar_path.read_bytes()
    if len(raw) < 16:
        raise ValueError(f"Invalid ASAR header (too short): {asar_path}")
    first_tag = struct.unpack_from("<I", raw, 0)[0]
    header_pickle_size = struct.unpack_from("<I", raw, 4)[0]
    json_len = struct.unpack_from("<I", raw, 12)[0]
    if first_tag != 4 or 16 + json_len > len(raw):
        raise ValueError(f"Invalid ASAR pickle header in {asar_path}")
    header_json = json.loads(raw[16 : 16 + json_len].decode("utf-8"))
    base = 8 + header_pickle_size
    if base > len(raw):
        raise ValueError(f"Invalid ASAR payload base {base} > {len(raw)}")
    return header_json, raw, base


def write_asar_header_and_payload(header_obj: dict, payload_chunks: list[bytes]) -> bytes:
    json_bytes = json.dumps(header_obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    pad_len = (4 - (len(json_bytes) % 4)) % 4
    padded_json = json_bytes + (b"\x00" * pad_len)
    payload_size = 4 + len(padded_json)
    pickle_size = 4 + payload_size
    prefix = struct.pack("<IIII", 4, pickle_size, payload_size, len(json_bytes))
    return b"".join([prefix, padded_json, *payload_chunks])


def strip_asar(src_asar: pathlib.Path, dst_asar: pathlib.Path) -> tuple[int, int]:
    header, raw, base = read_asar(src_asar)
    kept_chunks: list[bytes] = []
    offset_cursor = 0
    kept_count = 0
    stripped_count = 0

    def walk(node: dict, prefix: str) -> dict | None:
        nonlocal offset_cursor, kept_count, stripped_count
        files = node.get("files")
        if not isinstance(files, dict):
            return None
        new_files: dict[str, dict] = {}
        for name in sorted(files.keys()):
            child = files[name]
            if not isinstance(child, dict):
                continue
            rel = f"{prefix}/{name}" if prefix else name
            if "files" in child:
                sub = walk(child, rel)
                if sub and sub.get("files"):
                    new_files[name] = sub
                continue
            if child.get("unpacked") is True or rel.lower().endswith(STRIPPED_SUFFIXES):
                stripped_count += 1
                continue
            size = int(child.get("size", 0))
            in_offset = int(child.get("offset", "0"))
            start = base + in_offset
            end = start + size
            if end > len(raw):
                raise ValueError(f"Corrupt entry {rel}: {end} > {len(raw)}")
            kept_chunks.append(raw[start:end])
            new_files[name] = {"size": size, "offset": str(offset_cursor)}
            offset_cursor += size
            kept_count += 1
        return {"files": new_files}

    stripped_header = walk(header, "") or {"files": {}}
    dst_asar.parent.mkdir(parents=True, exist_ok=True)
    dst_asar.write_bytes(write_asar_header_and_payload(stripped_header, kept_chunks))
    return kept_count, stripped_count


def package_from_app(app_path: pathlib.Path, out_dir: pathlib.Path, check_signature: bool) -> None:
    if check_signature:
        verify_codesign(app_path)

    app_info_path = app_path / "Contents" / "Info.plist"
    src_asar = app_path / "Contents" / "Resources" / "app.asar"
    if not src_asar.exists():
        raise FileNotFoundError(f"Missing {src_asar}")

    version = PINNED_VERSION
    bundle_version = PINNED_VERSION
    if app_info_path.exists():
        with app_info_path.open("rb") as f:
            plist_data = plistlib.load(f)
        version = str(plist_data.get("CFBundleShortVersionString") or PINNED_VERSION)
        bundle_version = str(plist_data.get("CFBundleVersion") or version)

    tmp_out = out_dir.with_name(out_dir.name + ".staging")
    if tmp_out.exists():
        shutil.rmtree(tmp_out)
    tmp_out.mkdir(parents=True, exist_ok=True)

    kept, stripped = strip_asar(src_asar, tmp_out / "app.asar")
    runtime_plist = {
        "CFBundleShortVersionString": version,
        "CFBundleVersion": bundle_version,
    }
    with (tmp_out / "runtime-info.plist").open("wb") as f:
        plistlib.dump(runtime_plist, f, sort_keys=True)

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    tmp_out.rename(out_dir)
    size_mb = (out_dir / "app.asar").stat().st_size / (1024 * 1024)
    print(f"Prepared {out_dir} (Zalo {version}, kept {kept} entries, stripped {stripped}, app.asar {size_mb:.2f} MiB)")


def package_from_dmg(dmg_path: pathlib.Path, out_dir: pathlib.Path, check_signature: bool) -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("Mounting .dmg requires macOS hdiutil.")
    attach = subprocess.run(
        ["hdiutil", "attach", "-nobrowse", "-readonly", "-plist", str(dmg_path)],
        check=True,
        capture_output=True,
    )
    plist = plistlib.loads(attach.stdout)
    mount_point: str | None = None
    for entity in plist.get("system-entities", []):
        mp = entity.get("mount-point")
        if mp:
            mount_point = mp
            break
    if not mount_point:
        raise RuntimeError("Failed to determine DMG mount point.")

    try:
        mp_path = pathlib.Path(mount_point)
        apps = list(mp_path.glob("*.app")) + list(mp_path.rglob("Zalo.app"))
        if not apps:
            raise FileNotFoundError(f"Could not locate Zalo.app inside mounted DMG {mp_path}")
        zalo_app = next((a for a in apps if a.name == "Zalo.app"), apps[0])
        package_from_app(zalo_app, out_dir, check_signature=check_signature)
    finally:
        subprocess.run(["hdiutil", "detach", mount_point, "-quiet"], check=False)


def run_self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="olaz-asar-test-") as td:
        root = pathlib.Path(td)
        fake_app = root / "FakeZalo.app"
        res_dir = fake_app / "Contents" / "Resources"
        res_dir.mkdir(parents=True)

        with (fake_app / "Contents" / "Info.plist").open("wb") as f:
            plistlib.dump({"CFBundleShortVersionString": PINNED_VERSION, "CFBundleVersion": "261020"}, f)

        fixtures = {
            "pc-dist/index.html": b"<!doctype html><html><body>Olaz</body></html>",
            "pc-dist/login.html": b"<!doctype html><html><body>QR</body></html>",
            "pc-dist/emoji/heart.png": b"\x89PNG\r\n\x1a\nHEART",
            "native/addon.node": b"MACOS_NODE_BINARY",
            "lib/helper.dylib": b"MACOS_DYLIB",
            "lib/extra.so": b"LINUX_SO",
            "unpacked-bin/tool": b"UNPACKED_TOOL",
        }
        header: dict = {"files": {}}
        payload_chunks: list[bytes] = []
        offset = 0
        for rel, content in fixtures.items():
            parts = rel.split("/")
            cursor = header["files"]
            for part in parts[:-1]:
                cursor = cursor.setdefault(part, {"files": {}})["files"]
            entry: dict = {"size": len(content), "offset": str(offset)}
            if rel.startswith("unpacked-bin/"):
                entry["unpacked"] = True
            cursor[parts[-1]] = entry
            payload_chunks.append(content)
            offset += len(content)

        (res_dir / "app.asar").write_bytes(write_asar_header_and_payload(header, payload_chunks))
        out_runtime = root / "ZaloRuntime"
        package_from_app(fake_app, out_runtime, check_signature=False)

        out_asar = out_runtime / "app.asar"
        assert not (out_runtime / "Contents").exists(), "Nested Contents/ must not exist on iOS"
        parsed_header, out_raw, base = read_asar(out_asar)

        # Verify exact Swift AsarArchive math: base == 8 + u32(at: 4), json at 16..<16+u32(at: 12)
        assert struct.unpack_from("<I", out_raw, 4)[0] + 8 == base
        json_len = struct.unpack_from("<I", out_raw, 12)[0]
        assert json.loads(out_raw[16 : 16 + json_len].decode("utf-8")) == parsed_header

        def flatten(node: dict, prefix: str = "") -> dict[str, dict]:
            out: dict[str, dict] = {}
            for k, v in node.get("files", {}).items():
                p = f"{prefix}/{k}" if prefix else k
                if "files" in v:
                    out.update(flatten(v, p))
                else:
                    out[p] = v
            return out

        flat = flatten(parsed_header)
        assert "native/addon.node" not in flat
        assert "lib/helper.dylib" not in flat
        assert "lib/extra.so" not in flat
        assert "unpacked-bin/tool" not in flat
        assert "native" not in parsed_header.get("files", {})
        assert "lib" not in parsed_header.get("files", {})
        assert "unpacked-bin" not in parsed_header.get("files", {})

        for keep in ("pc-dist/index.html", "pc-dist/login.html", "pc-dist/emoji/heart.png"):
            meta = flat[keep]
            start = base + int(meta["offset"])
            end = start + int(meta["size"])
            assert out_raw[start:end] == fixtures[keep], f"Mismatch for {keep}"

        with (out_runtime / "runtime-info.plist").open("rb") as f:
            rt_plist = plistlib.load(f)
        assert rt_plist["CFBundleShortVersionString"] == PINNED_VERSION

    print("SELF-TEST OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare stripped ZaloRuntime bundle for Olaz iOS.")
    parser.add_argument("--dmg", type=pathlib.Path, help="Path to local ZaloSetup-universal-26.10.20.dmg")
    parser.add_argument("--app", type=pathlib.Path, help="Path to extracted Zalo.app")
    parser.add_argument("--download-dir", type=pathlib.Path, default=pathlib.Path("build/downloads"))
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("build/ZaloRuntime"))
    parser.add_argument("--skip-codesign", action="store_true", help="Skip macOS VNG TeamID codesign verification")
    parser.add_argument("--self-test", action="store_true", help="Run synthetic ASAR strip & round-trip check")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    check_sig = not args.skip_codesign
    if args.app:
        package_from_app(args.app, args.out, check_signature=check_sig)
        return 0

    if args.dmg:
        if not args.dmg.exists():
            raise FileNotFoundError(f"DMG not found: {args.dmg}")
        dmg_path = args.dmg
    else:
        dmg_path = download_pinned_dmg(args.download_dir)

    package_from_dmg(dmg_path, args.out, check_signature=check_sig)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
