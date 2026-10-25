#!/usr/bin/env python3
"""
扫描 apps/ 目录，生成 index.json。

目录结构：
  apps/
    calculator/
      manifest.json      ← 应用元数据（appId, name, category, description）
      icon.png           ← 图标
      1.0.0.zip          ← 版本包
      1.0.1.zip

用法：
  python3 build_index.py [base_url]

base_url 用于生成 iconURL 和 downloadURL 的绝对地址。
默认用 jsDelivr：https://cdn.jsdelivr.net/gh/用户/repo@main
"""

import os
import json
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
APPS_DIR = ROOT / "apps"

# 默认 base URL（改成你自己的 GitHub 用户名/仓库名）
DEFAULT_BASE = "https://cdn.jsdelivr.net/gh/USER/kinter-store@main"
BASE_URL = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BASE


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def parse_version(v):
    """1.0.1 -> (1,0,1)"""
    try:
        return tuple(int(x) for x in v.split('.'))
    except Exception:
        return (0,)


def build_app(app_dir: Path):
    manifest_path = app_dir / 'manifest.json'
    if not manifest_path.exists():
        print(f"  跳过 {app_dir.name}（无 manifest.json）")
        return None

    manifest = json.load(open(manifest_path, encoding='utf-8'))
    app_id = manifest.get('appId')
    name = manifest.get('name', app_dir.name)
    category = manifest.get('category', '未分类')
    description = manifest.get('description', '')
    min_host = manifest.get('minHostVersion', '1.0.0')

    if not app_id:
        print(f"  跳过 {app_dir.name}（manifest 缺少 appId）")
        return None

    # 找所有 zip，按版本排序取最新的
    zips = sorted(app_dir.glob('*.zip'), key=lambda p: parse_version(p.stem))
    if not zips:
        print(f"  跳过 {app_dir.name}（无 zip）")
        return None

    latest = zips[-1]
    version = latest.stem

    icon_path = app_dir / 'icon.png'
    has_icon = icon_path.exists()

    app = {
        'appId': app_id,
        'name': name,
        'version': version,
        'subtitle': manifest.get('subtitle', ''),
        'description': description,
        'category': category,
        'size': latest.stat().st_size,
        'sha256': sha256_of(latest),
        'minHostVersion': min_host,
        'downloadURL': f"{BASE_URL}/apps/{app_dir.name}/{version}.zip",
    }
    if has_icon:
        app['iconURL'] = f"{BASE_URL}/apps/{app_dir.name}/icon.png"

    # 售价（元）：manifest.price > 0 才输出；缺省 = 免费
    price = manifest.get('price')
    if isinstance(price, (int, float)) and price > 0:
        app['price'] = float(price)
        app['currency'] = manifest.get('currency', 'CNY')

    print(f"  ✓ {name} v{version}  ({latest.stat().st_size} bytes, {len(zips)} 个版本)")
    return app


def main():
    if not APPS_DIR.exists():
        print(f"错误：{APPS_DIR} 不存在")
        sys.exit(1)

    print(f"扫描 {APPS_DIR}")
    apps = []
    for d in sorted(APPS_DIR.iterdir()):
        if d.is_dir():
            app = build_app(d)
            if app:
                apps.append(app)

    index = {
        'name': 'Kinter 官方源',
        'identifier': 'com.kinter.source.official',
        'subtitle': f'共 {len(apps)} 个应用',
        'website': BASE_URL,
        'apps': apps,
    }

    out = ROOT / 'index.json'
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    print(f"\n生成 {out}")
    print(f"  共 {len(apps)} 个应用")
    print(f"  总大小 {sum(a['size'] for a in apps) / 1024:.1f} KB")


if __name__ == '__main__':
    main()
