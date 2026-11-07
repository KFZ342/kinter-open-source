#!/usr/bin/env python3
"""给 Kinter 小程序包做开发者签名（签名前先过第三方模型安全审查）。

流程：
  1. 收集包里的代码与清单文本
  2. 调第三方模型（OpenAI 兼容 /chat/completions）判断是否安全
  3. 不通过 → 拒绝签名，打印风险点
  4. 通过 → 用根私钥签发开发者证书（证书里含模型审查结论）
  5. 用开发者私钥给整包摘要签名，把证书一起写进 signature.json

宿主内置根公钥。没有根私钥的人签出来的包只能算「自签名」，
正式模式下会被当成「未受验证的开发者」挡住——所以证书无法伪造。


用法：
    python3 Tools/sign_app.py <应用目录> --developer com.example.dev
    python3 Tools/sign_app.py <应用目录> --developer com.example.dev \
        --api-base https://api.example.com/v1 --api-key sk-xxx --model gpt-4o-mini

不传 --api-base 时会提示输入一次，存到 ~/.kinter/sign_config.json（权限 600）。

密钥（Ed25519）：
    不给 --key 时，会在当前目录生成 dev_ed25519.pem（私钥，自己收好）与
    dev_ed25519.pub（公钥）。私钥不要发给别人。

签名算法必须与宿主 HostApp/Core/Package/PackageInspector.swift 里的
PackageSignature.digest 一致：
    - 遍历应用目录下所有普通文件，跳过 signature.json
    - 相对路径按 UTF-8 字节排序
    - 每个文件：SHA256(内容) → hex
    - 拼 "路径\\0摘要hex\\n"，整体再 SHA256 → 摘要
    - 用 Ed25519 对摘要签名

宿主在「每次打开」时重新算摘要并验签，所以装完之后任何文件被改了，
都会提示「未受验证的开发者，App暂时无法打开」。
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

SIG_FILE = "signature.json"
CONFIG_DIR = os.path.expanduser("~/.kinter")
CONFIG_FILE = os.path.join(CONFIG_DIR, "sign_config.json")

# 交给模型看的文本文件，图片/二进制跳过
REVIEW_EXTS = {".html", ".htm", ".js", ".mjs", ".json", ".css", ".ktml",
               ".md", ".txt", ".xml", ".svg"}
PER_FILE_LIMIT = 60 * 1024
TOTAL_LIMIT = 220 * 1024

REVIEW_SYSTEM_PROMPT = """你是小程序应用商店的安全审核员。你会收到一个 Kinter 小程序的 manifest 和源码。
判断它是否安全、能不能发给普通用户。

重点查这些（发现任一即判 unsafe）：
- 偷偷收集通讯录、相册、剪贴板、定位、健康数据并上传到外部服务器
- 把用户数据编码/加密后外发，或先读隐私再请求网络（组合越权）
- eval / new Function / 动态加载远程代码 / 远程配置里塞脚本
- 伪装系统界面骗取权限，诱导输入账号密码
- 挖矿、刷量、批量注册、绕过安全模式或宿主权限校验
- 读取其他小程序的数据目录、遍历文件系统
- 明显的诈骗、赌博、色情内容

允许：正常使用相机/相册/定位/网络，只要 manifest 声明了并且用途能对上。

只输出 JSON，不要解释、不要 markdown 代码块：
{"verdict":"safe"或"unsafe","risk":"low"/"medium"/"high","summary":"一句话结论","findings":["具体风险点，没有就空数组"]}"""


def digest_of(app_dir: str) -> bytes:
    rels = []
    for root, _dirs, files in os.walk(app_dir):
        for name in files:
            full = os.path.join(root, name)
            if not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, app_dir).replace(os.sep, "/")
            if rel == SIG_FILE:
                continue
            rels.append(rel)
    rels.sort(key=lambda s: s.encode("utf-8"))
    canonical = bytearray()
    for rel in rels:
        with open(os.path.join(app_dir, rel), "rb") as f:
            h = hashlib.sha256(f.read()).hexdigest()
        canonical += rel.encode("utf-8")
        canonical += b"\x00"
        canonical += h.encode("utf-8")
        canonical += b"\n"
    return hashlib.sha256(bytes(canonical)).digest()


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, **kw)


def ensure_key(key_path: str):
    if os.path.exists(key_path):
        return
    print(f"未找到密钥，生成 Ed25519 私钥：{key_path}")
    run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", key_path])
    os.chmod(key_path, 0o600)
    run(["openssl", "pkey", "-in", key_path, "-pubout", "-out", key_path + ".pub"])
    print(f"公钥：{key_path}.pub（可以随应用一起公开）")


def raw_public_key(key_path: str) -> bytes:
    # SPKI DER 里 Ed25519 raw key 固定是最后 32 字节
    der = run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]).stdout
    if len(der) < 32:
        raise SystemExit("公钥解析失败")
    return der[-32:]


def sign_digest(key_path: str, digest: bytes) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(digest)
        digest_path = f.name
    sig_path = digest_path + ".sig"
    try:
        run(["openssl", "pkeyutl", "-sign", "-inkey", key_path,
             "-rawin", "-in", digest_path, "-out", sig_path])
        with open(sig_path, "rb") as f:
            return f.read()
    finally:
        os.unlink(digest_path)
        if os.path.exists(sig_path):
            os.unlink(sig_path)


def verify_self(key_path: str, digest: bytes, sig: bytes):
    pub_path = key_path + ".pub"
    if not os.path.exists(pub_path):
        run(["openssl", "pkey", "-in", key_path, "-pubout", "-out", pub_path])
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(digest)
        d = f.name
    s = d + ".sig"
    with open(s, "wb") as f:
        f.write(sig)
    try:
        run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin",
             "-inkey", pub_path, "-in", d, "-sigfile", s])
    finally:
        os.unlink(d)
        os.unlink(s)


def ca_key_path(args=None):
    if args and args.ca_key:
        return os.path.expanduser(args.ca_key)
    env = os.environ.get("KINTER_CA_KEY")
    if env:
        return os.path.expanduser(env)
    return os.path.expanduser("~/.kinter/ca/root_ed25519.pem")


def init_ca(path):
    if os.path.exists(path):
        raise SystemExit(f"根私钥已存在：{path}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", path])
    os.chmod(path, 0o600)
    with open(path + ".pub", "wb") as f:
        f.write(run(["openssl", "pkey", "-in", path, "-pubout", "-outform", "DER"]).stdout)
    raw = raw_public_key(path)
    print(f"根私钥：{path}（只有这一份，丢了就再也签不出可信证书）")
    print(f"根公钥 base64：{base64.b64encode(raw).decode()}")
    print("把它写进 HostApp/Core/Package/PackageInspector.swift 的")
    print("PackageSignature.Anchor.publicKeyBase64，重新构建 App，这个根才被认。")


def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def save_config(cfg):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.chmod(CONFIG_FILE, 0o600)


def resolve_review_config(args):
    cfg = load_config()
    base = args.api_base or cfg.get("apiBase")
    key = args.api_key or cfg.get("apiKey")
    model = args.model or cfg.get("model")
    if not base:
        print("签名前要用第三方模型审一遍代码，先填一下接口信息（只存本机）。")
        base = input("模型 API 地址（OpenAI 兼容，如 https://api.example.com/v1）：").strip()
    if not key:
        key = input("API Key：").strip()
    if not model:
        model = input("模型名（如 gpt-4o-mini）：").strip() or "gpt-4o-mini"
    if not base or not key:
        raise SystemExit("缺 API 地址或 Key，没法审查，也不会签名。")
    save_config({"apiBase": base.rstrip("/"), "apiKey": key, "model": model})
    return base.rstrip("/"), key, model


def collect_review_source(app_dir: str):
    parts = []
    total = 0
    rels = []
    for root, _dirs, files in os.walk(app_dir):
        for name in files:
            ext = os.path.splitext(name)[1].lower()
            if ext not in REVIEW_EXTS:
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, app_dir).replace(os.sep, "/")
            rels.append((rel, full))
    rels.sort(key=lambda x: x[0].encode("utf-8"))
    for rel, full in rels:
        try:
            with open(full, "r", encoding="utf-8", errors="replace") as f:
                body = f.read()
        except Exception:
            continue
        if len(body) > PER_FILE_LIMIT:
            body = body[:PER_FILE_LIMIT] + "\n…（截断）"
        block = f"### 文件：{rel}\n{body}\n"
        if total + len(block) > TOTAL_LIMIT:
            parts.append("…（还有文件未展示，已截断）")
            break
        parts.append(block)
        total += len(block)
    return "\n".join(parts)


def call_review_model(base, key, model, source):
    url = base + "/chat/completions"
    payload = {
        "model": model,
        "temperature": 0,
        "messages": [
            {"role": "system", "content": REVIEW_SYSTEM_PROMPT},
            {"role": "user", "content": source},
        ],
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:400]
        raise SystemExit(f"审查接口返回 {e.code}：{detail}")
    except Exception as e:
        raise SystemExit(f"审查接口连不上：{e}")
    try:
        data = json.loads(body)
        content = data["choices"][0]["message"]["content"]
    except Exception:
        raise SystemExit(f"审查接口返回格式不对：{body[:300]}")
    return content


def parse_verdict(content):
    text = content.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except Exception:
        start, end = text.find("{"), text.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end + 1])
            except Exception:
                pass
    raise SystemExit(f"模型没有返回可解析的判定：{text[:300]}")


def main():
    ap = argparse.ArgumentParser(description="Kinter 小程序开发者签名")
    ap.add_argument("app_dir", nargs="?", help="小程序目录（含 manifest.json）")
    ap.add_argument("--developer", required=True, help="开发者标识，如 com.example.dev")
    ap.add_argument("--key", default="dev_ed25519.pem", help="Ed25519 私钥路径")
    ap.add_argument("--api-base", help="第三方模型 API 地址（OpenAI 兼容）")
    ap.add_argument("--api-key", help="模型 API Key")
    ap.add_argument("--model", help="模型名")
    ap.add_argument("--ca-key", help="根私钥路径（默认 ~/.kinter/ca/root_ed25519.pem）")
    ap.add_argument("--days", type=int, default=365, help="证书有效期（天）")
    ap.add_argument("--init-ca", action="store_true", help="只生成根密钥，不签名")
    args = ap.parse_args()

    ca_path = ca_key_path(args)
    if args.init_ca:
        init_ca(ca_path)
        return

    if not os.path.exists(ca_path):
        raise SystemExit(f"找不到根私钥：{ca_path}\n先运行：python3 Tools/sign_app.py --init-ca")

    if not args.app_dir:
        raise SystemExit("要签哪个包？把应用目录传进来")
    app_dir = os.path.abspath(args.app_dir)
    if not os.path.isdir(app_dir):
        raise SystemExit(f"目录不存在：{app_dir}")
    if not os.path.exists(os.path.join(app_dir, "manifest.json")):
        raise SystemExit("这个目录里没有 manifest.json，可能指错了")

    ensure_key(args.key)
    digest = digest_of(app_dir)

    # 1) 先把代码交给第三方模型审
    base, api_key, model = resolve_review_config(args)
    source = collect_review_source(app_dir)
    if not source.strip():
        raise SystemExit("包里没有可审查的文本文件，拒绝签名。")
    print(f"正在送审：{len(source)} 字符 → {base}（{model}）")
    content = call_review_model(base, api_key, model, source)
    verdict = parse_verdict(content)
    v = str(verdict.get("verdict", "")).lower()
    risk = str(verdict.get("risk", "")).lower()
    summary = str(verdict.get("summary", "")).strip()
    findings = verdict.get("findings") or []
    if v != "safe" or risk == "high":
        print("\n审查没通过，不签名、不发证书。")
        print(f"结论：{summary or v or '未知'}")
        for f in findings:
            print(f"  - {f}")
        raise SystemExit(2)
    print(f"审查通过：{summary}")

    now = datetime.now(timezone.utc).replace(microsecond=0)
    expires = now + timedelta(days=args.days)

    # 2) 根私钥签发开发者证书：把「谁」「哪把 key」「哪个包」「审查结论」绑在一起
    cert = {
        "kind": "kinter-developer-certificate",
        "version": 1,
        "rootKeyId": "root-1",
        "developerId": args.developer,
        "publicKey": base64.b64encode(raw_public_key(args.key)).decode(),
        "packageDigest": digest.hex(),
        "issuedAt": now.isoformat().replace("+00:00", "Z"),
        "expiresAt": expires.isoformat().replace("+00:00", "Z"),
        "review": {
            "model": model,
            "verdict": "safe",
            "risk": risk or "low",
            "summary": summary,
            "findings": findings,
        },
    }
    cert_text = json.dumps(cert, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    cert_digest = hashlib.sha256(cert_text.encode("utf-8")).digest()
    cert_sig = sign_digest(ca_path, cert_digest)
    verify_self(ca_path, cert_digest, cert_sig)

    # 3) 开发者私钥签整包摘要
    sig = sign_digest(args.key, digest)
    verify_self(args.key, digest, sig)

    signature = {
        "algorithm": "ed25519",
        "developerId": args.developer,
        "publicKey": base64.b64encode(raw_public_key(args.key)).decode(),
        "signature": base64.b64encode(sig).decode(),
        "signedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "certificate": cert_text,
        "certificateSignature": base64.b64encode(cert_sig).decode(),
    }
    out = os.path.join(app_dir, SIG_FILE)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(signature, f, ensure_ascii=False, indent=2)
    print(f"已写入 {out}")
    print(f"开发者：{args.developer}")
    print(f"摘要：{digest.hex()}")
    print(f"审查：{summary}（{model}）")
    print(f"证书：{args.developer}，有效期到 {cert['expiresAt']}（根 {ca_path}）")
    print("重新打包 ZIP 后导入。证书链到宿主内置的根，打开时直接放行，不再问信任。")


if __name__ == "__main__":
    main()
