#!/usr/bin/env python3
"""Refresh the README supported-platform table with the latest release links."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
from urllib.parse import quote


START_MARKER = "<!-- SUPPORT_MATRIX:START -->"
END_MARKER = "<!-- SUPPORT_MATRIX:END -->"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="GitHub repo in owner/name form.")
    parser.add_argument("--tag", required=True, help="Release tag used for download links.")
    parser.add_argument(
        "--release-json",
        required=True,
        help="Path to gh release JSON output with an assets array.",
    )
    parser.add_argument(
        "--readme",
        default="README.md",
        help="README path to update.",
    )
    return parser.parse_args()


def build_asset_map(release: dict[str, Any], repo: str, tag: str) -> dict[str, str]:
    base_url = f"https://github.com/{repo}/releases/download/{quote(tag)}"
    assets: dict[str, str] = {}
    for asset in release.get("assets", []):
        name = asset.get("name")
        if not name:
            continue
        assets[name] = f"{base_url}/{quote(name)}"
    return assets


def find_first(assets: dict[str, str], predicate) -> str | None:
    for name in sorted(assets):
        if predicate(name):
            return name
    return None


def format_links(assets: dict[str, str], names: list[tuple[str, str | None]]) -> str:
    parts: list[str] = []
    for label, asset_name in names:
        if not asset_name:
            continue
        parts.append(f"[{label}]({assets[asset_name]})")
    return " / ".join(parts) if parts else "—"


def build_table(repo: str, tag: str, assets: dict[str, str]) -> str:
    macos_dmg = find_first(assets, lambda name: name.endswith(".dmg"))
    linux_zip = find_first(assets, lambda name: name == "xstream-linux.zip")
    linux_appimage = find_first(assets, lambda name: name.endswith(".AppImage"))
    linux_deb = find_first(assets, lambda name: name.endswith(".deb"))
    linux_rpm = find_first(assets, lambda name: name.endswith(".rpm"))
    windows_zip = find_first(assets, lambda name: name == "xstream-windows.zip")
    windows_msi = find_first(assets, lambda name: name.endswith(".msi"))
    android_apk = find_first(assets, lambda name: name == "app-release.apk")
    ios_ipa = find_first(assets, lambda name: name.endswith(".ipa"))

    rows = [
        "| 平台 | 架构 | 测试状态 | 下载 |",
        "|------|------|----------|------|",
        f"| macOS | arm64 | ✅ 已测试 | {format_links(assets, [('DMG', macos_dmg)])} |",
        "| macOS | x64 | ⚠️ 未测试 | — |",
        f"| Linux | x64 | ⚠️ 未测试 | {format_links(assets, [('ZIP', linux_zip), ('AppImage', linux_appimage), ('DEB', linux_deb), ('RPM', linux_rpm)])} |",
        "| Linux | arm64 | ⚠️ 未测试 | — |",
        f"| Windows | x64 | ✅ 已测试 | {format_links(assets, [('ZIP', windows_zip), ('MSI', windows_msi)])} |",
        f"| Android | arm64 | ⚠️ 未测试 | {format_links(assets, [('APK', android_apk)])} |",
        f"| iOS | arm64 | ✅ 已测试 | {format_links(assets, [('IPA', ios_ipa)])} |",
        "",
        f"> 自动更新：当前下载链接指向 GitHub Release [`{tag}`](https://github.com/{repo}/releases/tag/{quote(tag)}).",
    ]
    return "\n".join(rows)


def replace_block(content: str, replacement: str) -> str:
    start = content.find(START_MARKER)
    end = content.find(END_MARKER)
    if start == -1 or end == -1 or end < start:
        raise ValueError("README is missing support-matrix markers.")

    start += len(START_MARKER)
    return f"{content[:start]}\n{replacement}\n{content[end:]}"


def main() -> None:
    args = parse_args()
    release = json.loads(Path(args.release_json).read_text(encoding="utf-8"))
    assets = build_asset_map(release, args.repo, args.tag)
    readme_path = Path(args.readme)
    readme = readme_path.read_text(encoding="utf-8")
    updated = replace_block(readme, build_table(args.repo, args.tag, assets))
    readme_path.write_text(updated, encoding="utf-8")


if __name__ == "__main__":
    main()
