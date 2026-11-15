#!/usr/bin/env python3
"""
Inspect an Apple .mobileprovision profile (and optional .p12 certificate),
resolve the target CFBundleIdentifier, generate profile-aligned entitlements
plist for zsign, optionally export GitHub Actions secrets, and verify signed
.ipa archives before distribution.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import pathlib
import plistlib
import sys
import tempfile
import zipfile
from typing import Any

DEFAULT_BUNDLE_ID = "app.olaz.ios"
DEFAULT_DISPLAY_NAME = "Olaz"


def _utc_now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _as_utc(dt: datetime.datetime) -> datetime.datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def parse_mobileprovision_bytes(raw: bytes) -> dict[str, Any]:
    """Extract and parse the XML plist embedded in a CMS .mobileprovision blob."""
    start = raw.find(b"<?xml")
    if start == -1:
        start = raw.find(b"<plist")
    end = raw.find(b"</plist>")
    if start == -1 or end == -1:
        raise ValueError("Invalid .mobileprovision: embedded XML plist not found")
    plist_bytes = raw[start : end + len(b"</plist>")]
    parsed = plistlib.loads(plist_bytes)
    if not isinstance(parsed, dict):
        raise ValueError("Invalid .mobileprovision: root plist is not a dictionary")
    return parsed


def parse_mobileprovision(path: pathlib.Path) -> dict[str, Any]:
    return parse_mobileprovision_bytes(path.read_bytes())


def extract_team_id(profile: dict[str, Any]) -> str:
    team_ids = profile.get("TeamIdentifier")
    if isinstance(team_ids, list) and team_ids and isinstance(team_ids[0], str):
        return team_ids[0].strip()
    ent = profile.get("Entitlements", {})
    if isinstance(ent, dict):
        ent_team = ent.get("com.apple.developer.team-identifier")
        if isinstance(ent_team, str) and ent_team.strip():
            return ent_team.strip()
    raise ValueError("Provisioning profile is missing TeamIdentifier")


def resolve_bundle_id(profile: dict[str, Any], default_bundle_id: str = DEFAULT_BUNDLE_ID) -> str:
    """Resolve explicit or wildcard bundle ID from profile Entitlements."""
    team_id = extract_team_id(profile)
    ent = profile.get("Entitlements", {})
    if not isinstance(ent, dict):
        raise ValueError("Provisioning profile is missing Entitlements dictionary")

    app_id = ent.get("application-identifier")
    if not isinstance(app_id, str) or not app_id.strip():
        raise ValueError("Provisioning profile Entitlements missing application-identifier")

    team_prefix = f"{team_id}."
    suffix = app_id[len(team_prefix) :] if app_id.startswith(team_prefix) else app_id

    if suffix == "*":
        return default_bundle_id
    if suffix.endswith(".*") and len(suffix) > 2:
        return f"{suffix[:-2]}.olaz"
    return suffix


def is_bundle_id_compatible(bundle_id: str, profile: dict[str, Any]) -> bool:
    """Check whether bundle_id matches profile's application-identifier pattern."""
    team_id = extract_team_id(profile)
    ent = profile.get("Entitlements", {})
    app_id = ent.get("application-identifier", "") if isinstance(ent, dict) else ""
    if not isinstance(app_id, str) or not app_id:
        return False
    team_prefix = f"{team_id}."
    pattern = app_id[len(team_prefix) :] if app_id.startswith(team_prefix) else app_id
    if pattern == "*":
        return True
    if pattern.endswith(".*"):
        prefix = pattern[:-1]
        return bundle_id.startswith(prefix)
    return bundle_id == pattern


def build_signed_entitlements(profile: dict[str, Any], bundle_id: str) -> dict[str, Any]:
    """
    Build a clean entitlements plist matching the provisioning profile without
    empty arrays or unconfigured capability keys that can fail installd.
    """
    team_id = extract_team_id(profile)
    ent = profile.get("Entitlements", {})
    if not isinstance(ent, dict):
        raise ValueError("Provisioning profile is missing Entitlements dictionary")

    if not is_bundle_id_compatible(bundle_id, profile):
        raise ValueError(
            f"Bundle ID '{bundle_id}' is not authorized by profile application-identifier "
            f"'{ent.get('application-identifier')}'"
        )

    result: dict[str, Any] = {
        "application-identifier": f"{team_id}.{bundle_id}",
        "com.apple.developer.team-identifier": team_id,
        "get-task-allow": bool(ent.get("get-task-allow", False)),
    }

    kag = ent.get("keychain-access-groups")
    if isinstance(kag, (list, tuple)):
        if f"{team_id}.*" in kag or f"{team_id}.{bundle_id}" in kag:
            result["keychain-access-groups"] = [f"{team_id}.{bundle_id}"]

    for capability_key in (
        "com.apple.developer.kernel.increased-memory-limit",
        "com.apple.developer.kernel.extended-virtual-addressing",
    ):
        if ent.get(capability_key) is True:
            result[capability_key] = True

    return result


def verify_p12_against_profile(
    p12_path: pathlib.Path,
    password: str | None,
    profile: dict[str, Any],
) -> dict[str, str] | None:
    """Verify .p12 password and confirm its leaf cert is listed in DeveloperCertificates."""
    try:
        from cryptography.hazmat.primitives.serialization import Encoding, pkcs12
    except ImportError:
        print(
            "NOTE: python 'cryptography' package not installed; "
            "skipping PKCS#12 verification (zsign will verify .p12 + password directly)."
        )
        return None

    pw_bytes = None if password is None else password.encode("utf-8")
    p12_bytes = p12_path.read_bytes()
    try:
        _key, cert, _additional = pkcs12.load_key_and_certificates(p12_bytes, pw_bytes)
    except ValueError as exc:
        if password == "":
            _key, cert, _additional = pkcs12.load_key_and_certificates(p12_bytes, None)
        else:
            raise ValueError(f"Failed to decrypt PKCS#12 '{p12_path}' with provided password: {exc}") from exc

    if cert is None:
        raise ValueError(f"PKCS#12 '{p12_path}' does not contain a leaf certificate")

    not_after = _as_utc(cert.not_valid_after_utc)
    if not_after <= _utc_now():
        raise ValueError(f"PKCS#12 leaf certificate expired at {not_after.isoformat()}")

    leaf_der = cert.public_bytes(Encoding.DER)
    profile_certs = [bytes(raw_cert) for raw_cert in profile.get("DeveloperCertificates", [])]
    matched_idx = next((idx for idx, der in enumerate(profile_certs) if der == leaf_der), None)
    if matched_idx is None:
        raise ValueError(
            "PKCS#12 leaf certificate does NOT match any DeveloperCertificates entry "
            "in the provisioning profile"
        )

    return {
        "subject": cert.subject.rfc4514_string(),
        "not_valid_after": not_after.isoformat(),
        "sha256": hashlib.sha256(leaf_der).hexdigest(),
        "matched_index": str(matched_idx),
    }


def validate_profile(
    profile: dict[str, Any],
    expect_udid: str | None = None,
) -> None:
    exp = profile.get("ExpirationDate")
    if isinstance(exp, datetime.datetime) and _as_utc(exp) <= _utc_now():
        raise ValueError(f"Provisioning profile expired at {_as_utc(exp).isoformat()}")

    if expect_udid:
        provisions_all = profile.get("ProvisionsAllDevices") is True
        devices = profile.get("ProvisionedDevices", [])
        if not provisions_all and (not isinstance(devices, list) or expect_udid not in devices):
            raise ValueError(
                f"Expected UDID '{expect_udid}' not found in ProvisionedDevices ({len(devices) if isinstance(devices, list) else 0} entries)"
            )


def export_gh_secrets(
    out_dir: pathlib.Path,
    p12_path: pathlib.Path,
    provision_path: pathlib.Path,
    password: str,
) -> dict[str, pathlib.Path]:
    """Export single-line base64 secrets into a gitignored directory and verify round-trip."""
    out_dir.mkdir(parents=True, exist_ok=True)
    p12_raw = p12_path.read_bytes()
    prov_raw = provision_path.read_bytes()

    p12_b64 = base64.b64encode(p12_raw).decode("ascii")
    prov_b64 = base64.b64encode(prov_raw).decode("ascii")

    p12_out = out_dir / "MUACERT_P12_BASE64.txt"
    prov_out = out_dir / "MUACERT_PROVISION_BASE64.txt"
    pass_out = out_dir / "MUACERT_P12_PASSWORD.txt"

    p12_out.write_text(p12_b64, encoding="utf-8", newline="\n")
    prov_out.write_text(prov_b64, encoding="utf-8", newline="\n")
    pass_out.write_text(password, encoding="utf-8", newline="\n")

    decoded_p12 = base64.b64decode(p12_out.read_text(encoding="utf-8").strip(), validate=True)
    decoded_prov = base64.b64decode(prov_out.read_text(encoding="utf-8").strip(), validate=True)
    if decoded_p12 != p12_raw:
        raise ValueError("Round-trip verification failed for MUACERT_P12_BASE64.txt")
    if decoded_prov != prov_raw:
        raise ValueError("Round-trip verification failed for MUACERT_PROVISION_BASE64.txt")

    return {
        "p12_b64": p12_out,
        "provision_b64": prov_out,
        "password": pass_out,
    }


def verify_ipa(
    ipa_path: pathlib.Path,
    expected_bundle_id: str | None = None,
    expect_udid: str | None = None,
    expected_display_name: str = DEFAULT_DISPLAY_NAME,
) -> dict[str, Any]:
    """Inspect a signed .ipa ZIP to ensure bundle ID, profile, signature, and app.asar are valid."""
    if not ipa_path.is_file():
        raise FileNotFoundError(f"IPA file not found: {ipa_path}")

    with zipfile.ZipFile(ipa_path, "r") as zf:
        names = set(zf.namelist())
        info_name = "Payload/Olaz.app/Info.plist"
        prov_name = "Payload/Olaz.app/embedded.mobileprovision"
        codesig_name = "Payload/Olaz.app/_CodeSignature/CodeResources"
        if any(n.startswith("Payload/Olaz.app/Resources/") for n in names):
            raise ValueError(
                "IPA contains Payload/Olaz.app/Resources/, which breaks iOS flat CFBundle structure; use AppResources/"
            )
        asar_candidates = (
            "Payload/Olaz.app/ZaloRuntime/app.asar",
            "Payload/Olaz.app/ZaloRuntime/Contents/Resources/app.asar",
        )
        asar_name = next((c for c in asar_candidates if c in names), None)
        if not asar_name:
            raise ValueError(f"IPA missing required app.asar (checked {asar_candidates})")
        if asar_name == "Payload/Olaz.app/ZaloRuntime/app.asar":
            if "Payload/Olaz.app/AppResources/bridge-table.json" not in names:
                raise ValueError("IPA missing required entry: Payload/Olaz.app/AppResources/bridge-table.json")

        for required in (info_name, prov_name, codesig_name, asar_name):
            if required not in names:
                raise ValueError(f"IPA missing required entry: {required}")
            if zf.getinfo(required).file_size <= 0:
                raise ValueError(f"IPA entry is empty: {required}")

        info = plistlib.loads(zf.read(info_name))
        bundle_id = info.get("CFBundleIdentifier")
        display_name = info.get("CFBundleDisplayName") or info.get("CFBundleName")
        if expected_bundle_id and bundle_id != expected_bundle_id:
            raise ValueError(
                f"CFBundleIdentifier mismatch: expected '{expected_bundle_id}', found '{bundle_id}'"
            )
        if expected_display_name and display_name != expected_display_name:
            raise ValueError(
                f"CFBundleDisplayName mismatch: expected '{expected_display_name}', found '{display_name}'"
            )

        profile = parse_mobileprovision_bytes(zf.read(prov_name))
        validate_profile(profile, expect_udid=expect_udid)
        if not isinstance(bundle_id, str) or not is_bundle_id_compatible(bundle_id, profile):
            raise ValueError(
                f"IPA CFBundleIdentifier '{bundle_id}' is incompatible with embedded.mobileprovision"
            )

        return {
            "bundle_id": bundle_id,
            "display_name": display_name,
            "team_id": extract_team_id(profile),
            "app_asar_bytes": zf.getinfo(asar_name).file_size,
            "codesig_bytes": zf.getinfo(codesig_name).file_size,
        }


def _make_fake_profile(app_id: str, extra_ent: dict[str, Any] | None = None) -> dict[str, Any]:
    ent: dict[str, Any] = {
        "application-identifier": app_id,
        "com.apple.developer.team-identifier": app_id.split(".", 1)[0],
        "get-task-allow": False,
        "keychain-access-groups": [f"{app_id.split('.', 1)[0]}.*", "com.apple.token"],
        "com.apple.developer.in-app-payments": [],
    }
    if extra_ent:
        ent.update(extra_ent)
    return {
        "Name": "SelfTestProfile",
        "UUID": "00000000-1111-2222-3333-444444444444",
        "TeamName": "Self Test",
        "TeamIdentifier": [app_id.split(".", 1)[0]],
        "ExpirationDate": _utc_now() + datetime.timedelta(days=365),
        "ProvisionedDevices": ["00008020-001474A40A81002E"],
        "Entitlements": ent,
    }


def _wrap_profile_bytes(profile: dict[str, Any]) -> bytes:
    xml_bytes = plistlib.dumps(profile, fmt=plistlib.FMT_XML)
    return b"\x30\x82\x01\x00PKCS7" + xml_bytes + b"\x00\x00DER_TRAILER"


def run_self_test() -> None:
    wildcard = _make_fake_profile("TEAM123.*")
    assert resolve_bundle_id(wildcard) == "app.olaz.ios"
    wc_ent = build_signed_entitlements(wildcard, "app.olaz.ios")
    assert wc_ent == {
        "application-identifier": "TEAM123.app.olaz.ios",
        "com.apple.developer.team-identifier": "TEAM123",
        "get-task-allow": False,
        "keychain-access-groups": ["TEAM123.app.olaz.ios"],
    }, wc_ent

    sub_wildcard = _make_fake_profile("TEAM123.com.example.*")
    assert resolve_bundle_id(sub_wildcard) == "com.example.olaz"

    explicit = _make_fake_profile(
        "YHYVTUKWV9.app.lynx1884.lavender1499",
        {
            "com.apple.developer.kernel.increased-memory-limit": True,
            "com.apple.developer.kernel.extended-virtual-addressing": True,
            "aps-environment": "production",
        },
    )
    resolved_explicit = resolve_bundle_id(explicit)
    assert resolved_explicit == "app.lynx1884.lavender1499", resolved_explicit
    exp_ent = build_signed_entitlements(explicit, resolved_explicit)
    assert exp_ent == {
        "application-identifier": "YHYVTUKWV9.app.lynx1884.lavender1499",
        "com.apple.developer.team-identifier": "YHYVTUKWV9",
        "get-task-allow": False,
        "keychain-access-groups": ["YHYVTUKWV9.app.lynx1884.lavender1499"],
        "com.apple.developer.kernel.increased-memory-limit": True,
        "com.apple.developer.kernel.extended-virtual-addressing": True,
    }, exp_ent
    assert "com.apple.developer.in-app-payments" not in exp_ent
    assert "aps-environment" not in exp_ent

    with tempfile.TemporaryDirectory() as tmp:
        ipa_path = pathlib.Path(tmp) / "test.ipa"
        info_bytes = plistlib.dumps(
            {
                "CFBundleIdentifier": "app.lynx1884.lavender1499",
                "CFBundleDisplayName": "Olaz",
                "CFBundleExecutable": "Olaz",
            },
            fmt=plistlib.FMT_XML,
        )
        with zipfile.ZipFile(ipa_path, "w") as zf:
            zf.writestr("Payload/Olaz.app/Info.plist", info_bytes)
            zf.writestr("Payload/Olaz.app/embedded.mobileprovision", _wrap_profile_bytes(explicit))
            zf.writestr("Payload/Olaz.app/_CodeSignature/CodeResources", b"<plist/>")
            zf.writestr("Payload/Olaz.app/ZaloRuntime/app.asar", b"ASAR_TEST")
            zf.writestr("Payload/Olaz.app/AppResources/bridge-table.json", b"{}")

        summary = verify_ipa(
            ipa_path,
            expected_bundle_id="app.lynx1884.lavender1499",
            expect_udid="00008020-001474A40A81002E",
        )
        assert summary["team_id"] == "YHYVTUKWV9"

        bad_failed = False
        try:
            verify_ipa(ipa_path, expected_bundle_id="app.olaz.ios")
        except ValueError:
            bad_failed = True
        assert bad_failed, "verify_ipa must reject mismatched bundle ID"

    print("SELF-TEST OK")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare iOS entitlements & bundle ID from a muacert/Apple .mobileprovision profile"
    )
    parser.add_argument("--self-test", action="store_true", help="Run built-in unit tests and exit")
    parser.add_argument("--provision", type=pathlib.Path, help="Path to .mobileprovision file")
    parser.add_argument("--p12", type=pathlib.Path, help="Optional path to .p12 file to verify")
    parser.add_argument("--password", help="Password for .p12 certificate")
    parser.add_argument("--password-file", type=pathlib.Path, help="Read .p12 password from file")
    parser.add_argument("--default-bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--expect-udid", help="Verify device UDID exists in ProvisionedDevices")
    parser.add_argument("--entitlements-out", type=pathlib.Path, help="Output XML entitlements plist")
    parser.add_argument("--bundle-id-out", type=pathlib.Path, help="Output resolved bundle ID file")
    parser.add_argument(
        "--export-gh-secrets",
        type=pathlib.Path,
        help="Write single-line base64 GitHub Secrets files into gitignored directory",
    )
    parser.add_argument("--verify-ipa", type=pathlib.Path, help="Verify a packaged/signed .ipa file")
    parser.add_argument("--expected-bundle-id", help="Expected CFBundleIdentifier for --verify-ipa")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return 0

    if args.verify_ipa:
        summary = verify_ipa(
            args.verify_ipa,
            expected_bundle_id=args.expected_bundle_id,
            expect_udid=args.expect_udid,
        )
        print(
            f"IPA verified: bundle_id={summary['bundle_id']} display_name={summary['display_name']} "
            f"team={summary['team_id']} app_asar={summary['app_asar_bytes']} bytes"
        )
        return 0

    if not args.provision:
        parser.error("--provision is required unless --self-test or --verify-ipa is used")

    password = args.password
    if password is None and args.password_file:
        password = args.password_file.read_text(encoding="utf-8").strip()

    profile = parse_mobileprovision(args.provision)
    validate_profile(profile, expect_udid=args.expect_udid)

    team_id = extract_team_id(profile)
    bundle_id = resolve_bundle_id(profile, default_bundle_id=args.default_bundle_id)
    entitlements = build_signed_entitlements(profile, bundle_id)

    print(f"Profile: {profile.get('Name', '<unnamed>')} (Team {team_id} / {profile.get('TeamName', '')})")
    print(f"Expiration: {profile.get('ExpirationDate')}")
    print(f"Bundle ID: {bundle_id}")
    if args.expect_udid:
        print(f"UDID verified: {args.expect_udid}")

    if args.p12:
        cert_info = verify_p12_against_profile(args.p12, password, profile)
        if cert_info is not None:
            print(
                f"PKCS#12 verified: OK (matches DeveloperCertificates[{cert_info['matched_index']}], "
                f"subject={cert_info['subject']}, expires={cert_info['not_valid_after']})"
            )

    if args.entitlements_out:
        args.entitlements_out.parent.mkdir(parents=True, exist_ok=True)
        args.entitlements_out.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML))
        print(f"Wrote entitlements: {args.entitlements_out}")

    if args.bundle_id_out:
        args.bundle_id_out.parent.mkdir(parents=True, exist_ok=True)
        args.bundle_id_out.write_text(f"{bundle_id}\n", encoding="utf-8", newline="\n")
        print(f"Wrote bundle ID: {args.bundle_id_out}")

    if args.export_gh_secrets:
        if not args.p12 or password is None:
            parser.error("--export-gh-secrets requires --p12 and --password (or --password-file)")
        exported = export_gh_secrets(args.export_gh_secrets, args.p12, args.provision, password)
        print(
            "Exported GitHub Secrets (round-trip verified): "
            + ", ".join(str(p) for p in exported.values())
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
