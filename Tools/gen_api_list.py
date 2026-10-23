#!/usr/bin/env python3
"""从 SDK/wx.js 提取所有 API 名，生成 Swift 常量文件。
每次改 wx.js 后跑一次：
  python3 Tools/gen_api_list.py
"""

import os
import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
WXJS = ROOT / 'SDK' / 'wx.js'
OUT = ROOT / 'HostApp' / 'AI' / 'WXAPIList.swift'

src = WXJS.read_text(encoding='utf-8')

# 提取：apiName: function (o) { return invoke('module', 'method', ...)
# 同时抓 globalData 子对象
apis = []

# 顶层函数
for m in re.finditer(r"^    (\w+):\s*function\s*\(o\)\s*\{\s*return\s+invoke\('(\w+)',\s*'(\w+)'", src, re.M):
    api_name, module, method = m.group(1), m.group(2), m.group(3)
    apis.append((api_name, module, method, ''))

# globalData 子对象
for m in re.finditer(r"      (\w+):\s*function\s*\(o\)\s*\{\s*return\s+invoke\('(\w+)',\s*'(\w+)'", src):
    api_name, module, method = m.group(1), m.group(2), m.group(3)
    apis.append(('globalData.' + api_name, module, method, 'globalData'))

# 去重
seen = set()
unique = []
for a in apis:
    if a[0] in seen:
        continue
    seen.add(a[0])
    unique.append(a)

unique.sort(key=lambda x: x[0])

# 生成 Swift
lines = []
lines.append('import Foundation\n')
lines.append('/// 由 Tools/gen_api_list.py 从 SDK/wx.js 自动生成，勿手改。')
lines.append('/// 改 wx.js 后跑：python3 Tools/gen_api_list.py')
lines.append('enum WXAPIList {')
lines.append('    /// 所有可用的 wx.* API 名')
lines.append('    static let all: [String] = [')
for name, _, _, _ in unique:
    lines.append(f'        "{name}",')
lines.append('    ]')
lines.append('')
lines.append('    /// API 到模块的映射，用于生成清单')
lines.append('    static let moduleMap: [String: String] = [')
for name, module, method, _ in unique:
    lines.append(f'        "{name}": "{module}.{method}",')
lines.append('    ]')
lines.append('}')
lines.append('')

OUT.write_text('\n'.join(lines), encoding='utf-8')
print(f'Generated {OUT}')
print(f'  {len(unique)} APIs')
