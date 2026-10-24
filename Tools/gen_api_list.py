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

# 提取所有 API：按函数块扫描，抓函数体内第一个 return invoke(...)
# 兼容两种形态：
#   openURL: function (o) { return invoke('openURL', 'open', o); }            // 单行直返
#   authorize: function (o) {                                                 // 多行（前置逻辑再 invoke）
#     var p = wx._normPerm(o && o.permission);
#     return invoke('permission', 'request', { permission: p });
#   },
apis = []

func_start = re.compile(r"^    (\w+):\s*function\s*\(o\)\s*\{")
invoke_call = re.compile(r"return\s+invoke\('(\w+)',\s*'(\w+)'")


def extract_top_level():
    """逐行扫描顶层函数块（4 空格缩进为字段行，函数体为 6+ 空格缩进）。"""
    lines = src.split('\n')
    current_name = None
    block = []

    def flush():
        nonlocal current_name, block
        if current_name is not None and block:
            m = invoke_call.search('\n'.join(block))
            if m:
                apis.append((current_name, m.group(1), m.group(2), ''))
        current_name = None
        block = []

    for ln in lines:
        m = func_start.match(ln)
        if m:
            flush()
            current_name = m.group(1)
            block = [ln]
            continue
        # 4 空格缩进的非函数定义行 = 下一个顶层字段，结束当前函数块
        if current_name is not None and re.match(r"^    \S", ln):
            flush()
            continue
        if current_name is not None:
            block.append(ln)
    flush()


extract_top_level()

# globalData 子对象（6 空格缩进）
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
