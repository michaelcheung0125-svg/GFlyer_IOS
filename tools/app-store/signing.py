#!/usr/bin/env python3
"""公開版上傳 App Store Connect 用的簽署工具（docs/app-store-signing.md）。

在自己的電腦上跑（Windows 用 Git Bash，要 openssl；secrets 還要登入了的 gh）：
  python -I tools/app-store/signing.py request
      產生私密金鑰和憑證簽署要求（CSR），放在這個 repo 以外的資料夾（預設 ~/GFlyer-signing）
  python -I tools/app-store/signing.py certificate ~/Downloads/distribution.cer
      把 Apple 發的 Apple Distribution 憑證和私密金鑰合成 .p12，密碼隨機產生
  python -I tools/app-store/signing.py secrets --profile A.mobileprovision --profile B.mobileprovision \\
      --api-key AuthKey_XXXXXXXXXX.p8 --issuer ISSUER-ID [--dry-run]
      核對憑證、兩個描述檔和 API 金鑰，再放進這個 repo 的 app-store environment

.github/workflows/app-store.yml 在 macOS runner 上跑：
  install          從 secrets 建臨時 keychain、裝描述檔和 API 金鑰，結果寫進 $GITHUB_ENV
  export-options   印出 xcodebuild -exportArchive 用的選項（--destination export 或 upload）
  check-ipa IPA    核對匯出的 IPA 的簽署、entitlements 和描述檔
  cleanup          刪掉 install 放下的 keychain、描述檔和 API 金鑰
  self-test        用自己產生的假憑證和假描述檔試一遍上面每一步，不用 Apple 帳戶
                   （Windows 上試到 secrets --dry-run，macOS 上連 install 和 check-ipa）
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import io
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = Path.home() / "GFlyer-signing"
ENVIRONMENT = "app-store"
APP_ID = "com.jetpiggy.gflyer"
TUNNEL_ID = "com.jetpiggy.gflyer.tunnel"
NETWORK_EXTENSION = "com.apple.developer.networking.networkextension"
PACKET_TUNNEL = "packet-tunnel-provider"

KEY_FILE = "distribution.key"
CSR_FILE = "distribution.certSigningRequest"
CER_FILE = "distribution.cer"
P12_FILE = "distribution.p12"
PASSWORD_FILE = "distribution-p12-password.txt"

# app-store environment 的 secrets；docs/app-store-signing.md 的表要和這裏相同
SECRETS = {
    "DISTRIBUTION_CERTIFICATE_P12": "Apple Distribution 憑證和私密金鑰（.p12，base64）",
    "DISTRIBUTION_CERTIFICATE_PASSWORD": ".p12 的密碼",
    "APP_STORE_PROFILE_APP": f"{APP_ID} 的 App Store Connect 描述檔（base64）",
    "APP_STORE_PROFILE_TUNNEL": f"{TUNNEL_ID} 的 App Store Connect 描述檔（base64）",
    "APP_STORE_CONNECT_KEY": "App Store Connect API 金鑰（.p8，base64）",
    "APP_STORE_CONNECT_KEY_ID": "API 金鑰的 Key ID",
    "APP_STORE_CONNECT_ISSUER_ID": "API 金鑰的 Issuer ID",
}
PROFILE_SECRETS = {APP_ID: "APP_STORE_PROFILE_APP", TUNNEL_ID: "APP_STORE_PROFILE_TUNNEL"}

DISTRIBUTION_NAME = re.compile(r"Apple Distribution: .+ \(([A-Z0-9]{10})\)")
KEY_FILE_NAME = re.compile(r"AuthKey_([A-Z0-9]{10})\.p8")
ISSUER_ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


class SigningError(Exception):
    pass


# ── 共用 ────────────────────────────────────────────────────────

def run(command: list, *, input: bytes | None = None) -> subprocess.CompletedProcess:
    command = [str(part) for part in command]
    result = subprocess.run(command, input=input, capture_output=True)
    if result.returncode != 0:
        message = (result.stderr or result.stdout).decode("utf-8", "replace").strip()
        raise SigningError(f"{Path(command[0]).name} {command[1]} 失敗：{message}")
    return result


def openssl(*args, input: bytes | None = None) -> bytes:
    executable = os.environ.get("GFLYER_OPENSSL") or shutil.which("openssl")
    if not executable:
        raise SigningError("找不到 openssl。Windows 請在 Git Bash 裏跑這個指令。")
    return run([executable, *args], input=input).stdout


def now() -> dt.datetime:
    # plistlib 讀出來的日期是沒有時區的 UTC
    return dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)


def restrict(path: Path) -> None:
    try:
        path.chmod(0o600)
    except OSError:
        pass


def signing_dir(path: str | None) -> Path:
    directory = Path(path).expanduser().resolve() if path else DEFAULT_DIR
    if directory == ROOT or ROOT in directory.parents:
        raise SigningError(f"簽署檔不可以放在這個 repo 裏（{directory}）：私密金鑰不可以 commit。")
    return directory


def certificate_info(der: bytes) -> dict:
    text = openssl("x509", "-inform", "DER", "-noout", "-subject", "-enddate",
                   "-nameopt", "sep_multiline,sname,utf8,-esc_msb", input=der).decode("utf-8", "replace")
    fields = {}
    for line in text.splitlines():
        if line.startswith("    ") and "=" in line:
            key, value = line.strip().split("=", 1)
            fields[key] = value
    name = fields.get("CN", "")
    match = DISTRIBUTION_NAME.fullmatch(name)
    if not match:
        raise SigningError(f"這不是 Apple Distribution 憑證（名稱是「{name}」）：在 Apple 的網站建憑證時要選 Apple Distribution。")
    end = re.search(r"notAfter=(.+)", text)
    expires = dt.datetime.strptime(end.group(1).strip(), "%b %d %H:%M:%S %Y %Z")
    return {"name": name, "team": match.group(1), "expires": expires,
            "sha1": hashlib.sha1(der).hexdigest().upper()}


def decode_profile(data: bytes) -> dict:
    content = None
    if sys.platform == "darwin":
        with tempfile.NamedTemporaryFile(suffix=".mobileprovision", delete=False) as file:
            file.write(data)
        try:
            content = run(["security", "cms", "-D", "-i", file.name]).stdout
        except SigningError:
            if not os.environ.get("GFLYER_OPENSSL"):
                raise
        finally:
            os.unlink(file.name)
    if content is None:
        content = openssl("cms", "-verify", "-noverify", "-inform", "DER", input=data)
    try:
        profile = plistlib.loads(content)
    except Exception as error:
        raise SigningError(f"讀不到描述檔的內容：{error}") from error
    if not isinstance(profile, dict) or "UUID" not in profile:
        raise SigningError("這不是描述檔（.mobileprovision）。")
    return profile


def check_profiles(profiles: list[tuple[str, dict, bytes]], team: str, certificate_sha1: str) -> dict:
    """profiles 是 [(來源, 內容, 原檔)]。核對兩個描述檔都是給這個團隊、這張憑證的 App Store Connect 描述檔，
    一個是 App、一個是本機通道，回傳 {bundle id: {name, uuid, expires, source, data}}。"""
    found = {}
    for source, profile, data in profiles:
        name = profile.get("Name", "?")
        where = f"描述檔「{name}」（{source}）"
        entitlements = profile.get("Entitlements", {})
        prefix, _, bundle_id = entitlements.get("application-identifier", "").partition(".")
        if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
            raise SigningError(f"{where}不是 App Store Connect 描述檔：建描述檔時在 Distribution 下選 App Store Connect。")
        if entitlements.get("get-task-allow"):
            raise SigningError(f"{where}是開發用的描述檔：建描述檔時在 Distribution 下選 App Store Connect。")
        teams = profile.get("TeamIdentifier", [])
        if team not in teams or prefix != team:
            raise SigningError(f"{where}屬於團隊 {'、'.join(teams) or prefix}，憑證屬於團隊 {team}。")
        if bundle_id not in (APP_ID, TUNNEL_ID):
            raise SigningError(f"{where}的 App ID 是 {bundle_id}，要是 {APP_ID} 或 {TUNNEL_ID}。")
        if bundle_id in found:
            other = TUNNEL_ID if bundle_id == APP_ID else APP_ID
            raise SigningError(f"兩個描述檔都是 {bundle_id} 的：另一個要是 {other} 的。")
        if PACKET_TUNNEL not in entitlements.get(NETWORK_EXTENSION, []):
            raise SigningError(f"{where}沒有 Network Extensions 的 Packet Tunnel：App ID {bundle_id} 要開 "
                               "Network Extensions，再重新產生描述檔。")
        certificates = {hashlib.sha1(item).hexdigest().upper() for item in profile.get("DeveloperCertificates", [])}
        if certificate_sha1 not in certificates:
            raise SigningError(f"{where}裏沒有這張 Apple Distribution 憑證：重新產生描述檔，選同一張憑證。")
        expires = profile.get("ExpirationDate")
        if not isinstance(expires, dt.datetime) or expires <= now():
            raise SigningError(f"{where}已經過期（{expires}）：重新產生一個。")
        found[bundle_id] = {"name": name, "uuid": profile["UUID"], "expires": expires,
                            "source": source, "data": data}
    missing = [bundle_id for bundle_id in (APP_ID, TUNNEL_ID) if bundle_id not in found]
    if missing:
        raise SigningError("缺少 " + "、".join(missing) + " 的描述檔。")
    return found


def check_api_key(name: str, content: bytes) -> str:
    match = KEY_FILE_NAME.fullmatch(name)
    if not match:
        raise SigningError(f"API 金鑰的檔名是 {name}：要用從 App Store Connect 下載、沒有改過名的 AuthKey_<Key ID>.p8。")
    if b"-----BEGIN PRIVATE KEY-----" not in content:
        raise SigningError(f"{name} 不是 App Store Connect 的 API 金鑰（.p8）。")
    return match.group(1)


def check_issuer(issuer: str) -> str:
    issuer = issuer.strip().lower()
    if not ISSUER_ID.fullmatch(issuer):
        raise SigningError(f"Issuer ID「{issuer}」的格式不對：它在 App Store Connect 的 API 金鑰頁，"
                           "像 57246542-96fe-1a63-e053-0824d011072a。")
    return issuer


def encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def decode(environ, name: str) -> bytes:
    try:
        return base64.b64decode(environ[name], validate=True)
    except ValueError as error:
        raise SigningError(f"secret {name} 不是 base64：用 signing.py secrets 重新放一次。") from error


def show_date(value: dt.datetime) -> str:
    return value.strftime("%Y-%m-%d")


# ── 在自己的電腦上 ───────────────────────────────────────────────

def request(args) -> None:
    directory = signing_dir(args.dir)
    key = directory / KEY_FILE
    if key.exists():
        raise SigningError(f"{key} 已經存在。要重新開始，先把 {directory} 整個移走。")
    directory.mkdir(parents=True, exist_ok=True)
    openssl("genrsa", "-out", key, "2048")
    restrict(key)
    csr = directory / CSR_FILE
    openssl("req", "-new", "-key", key, "-out", csr,
            "-subj", f"/emailAddress={args.email}/CN=GFlyer Distribution/C=HK")
    print(f"私密金鑰：{key}（不要給任何人，也不要放進任何 repo）")
    print(f"憑證簽署要求：{csr}")
    print("下一步：在 Apple 的網站用這個 CSR 建 Apple Distribution 憑證，下載 .cer 之後跑")
    print("  python -I tools/app-store/signing.py certificate <下載的 .cer>")


def certificate(args) -> None:
    directory = signing_dir(args.dir)
    key = directory / KEY_FILE
    if not key.exists():
        raise SigningError(f"{directory} 裏沒有 {KEY_FILE}：先跑 signing.py request。")
    raw = Path(args.cer).expanduser().read_bytes()
    der = openssl("x509", "-outform", "DER", input=raw) if raw.startswith(b"-----BEGIN") else raw
    info = certificate_info(der)
    # 憑證要是用這把私密金鑰的 CSR 申請的
    if openssl("x509", "-inform", "DER", "-noout", "-pubkey", input=der).strip() != \
            openssl("pkey", "-in", key, "-pubout").strip():
        raise SigningError(f"這張憑證不是用 {directory / CSR_FILE} 申請的：在 Apple 的網站建憑證時要上傳這個檔。")
    if info["expires"] <= now():
        raise SigningError(f"這張憑證已經過期（{show_date(info['expires'])}）。")
    (directory / CER_FILE).write_bytes(der)
    password_file = directory / PASSWORD_FILE
    password_file.write_text(secrets.token_urlsafe(24), encoding="ascii")
    restrict(password_file)
    pem = directory / "distribution.pem"
    pem.write_bytes(openssl("x509", "-inform", "DER", input=der))
    p12 = directory / P12_FILE
    try:
        # macOS 的 security import 讀 PBE-SHA1-3DES 和 SHA-1 MAC 的 .p12；OpenSSL 3 預設的 AES 格式讀不到
        openssl("pkcs12", "-export", "-inkey", key, "-in", pem, "-out", p12,
                "-passout", f"file:{password_file}", "-name", info["name"],
                "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1")
    finally:
        pem.unlink()
    restrict(p12)
    print(f"憑證：{info['name']}，{show_date(info['expires'])} 到期")
    print(f".p12：{p12}（密碼在 {password_file}）")
    print("下一步：在 Apple 的網站用這張憑證建兩個 App Store Connect 描述檔，再建 API 金鑰，之後跑 signing.py secrets。")


def gh(*args, input: bytes | None = None) -> bytes:
    if not shutil.which("gh"):
        raise SigningError("找不到 GitHub CLI（gh）：先安裝，再跑 gh auth login。")
    return run(["gh", *args], input=input).stdout


def ensure_environment(repo: str) -> None:
    # 只准 main 用 app-store environment 的 secrets
    policy = {"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
    gh("api", "--method", "PUT", f"repos/{repo}/environments/{ENVIRONMENT}", "--input", "-",
       input=json.dumps(policy).encode())
    listed = json.loads(gh("api", f"repos/{repo}/environments/{ENVIRONMENT}/deployment-branch-policies"))
    if not any(item.get("name") == "main" and item.get("type", "branch") == "branch"
               for item in listed.get("branch_policies", [])):
        gh("api", "--method", "POST", f"repos/{repo}/environments/{ENVIRONMENT}/deployment-branch-policies",
           "-f", "name=main", "-f", "type=branch")


def secrets_command(args) -> None:
    directory = signing_dir(args.dir)
    for name in (CER_FILE, P12_FILE, PASSWORD_FILE):
        if not (directory / name).exists():
            raise SigningError(f"{directory} 裏沒有 {name}：先跑 signing.py request 和 certificate。")
    info = certificate_info((directory / CER_FILE).read_bytes())
    if info["expires"] <= now():
        raise SigningError(f"憑證已經過期（{show_date(info['expires'])}）：重新跑 request 和 certificate。")
    profiles = []
    for path in args.profile:
        data = Path(path).expanduser().read_bytes()
        profiles.append((Path(path).name, decode_profile(data), data))
    found = check_profiles(profiles, info["team"], info["sha1"])
    api_key = Path(args.api_key).expanduser()
    key_content = api_key.read_bytes()
    key_id = check_api_key(api_key.name, key_content)
    issuer = check_issuer(args.issuer)
    values = {
        "DISTRIBUTION_CERTIFICATE_P12": encode((directory / P12_FILE).read_bytes()),
        "DISTRIBUTION_CERTIFICATE_PASSWORD": (directory / PASSWORD_FILE).read_text(encoding="ascii").strip(),
        "APP_STORE_PROFILE_APP": encode(found[APP_ID]["data"]),
        "APP_STORE_PROFILE_TUNNEL": encode(found[TUNNEL_ID]["data"]),
        "APP_STORE_CONNECT_KEY": encode(key_content),
        "APP_STORE_CONNECT_KEY_ID": key_id,
        "APP_STORE_CONNECT_ISSUER_ID": issuer,
    }
    assert set(values) == set(SECRETS)
    print(f"團隊：{info['team']}")
    print(f"憑證：{info['name']}，{show_date(info['expires'])} 到期")
    for bundle_id in (APP_ID, TUNNEL_ID):
        item = found[bundle_id]
        print(f"描述檔：{bundle_id} 用「{item['name']}」（{item['source']}），{show_date(item['expires'])} 到期")
    print(f"API 金鑰：Key ID {key_id}")
    if args.dry_run:
        print(f"--dry-run：全部核對通過，沒有改 GitHub。會放進 {ENVIRONMENT} environment 的 secrets："
              + "、".join(values))
        return
    repo = args.repo or gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").decode().strip()
    ensure_environment(repo)
    for name, value in values.items():
        gh("secret", "set", name, "--env", ENVIRONMENT, "--repo", repo, input=value.encode())
    print(f"已經放進 {repo} 的 {ENVIRONMENT} environment（只准 main 用）：" + "、".join(values))


# ── 在 CI（macOS）上 ─────────────────────────────────────────────

def find_identities(keychain: Path, valid_only: bool) -> list[tuple[str, str, str]]:
    output = run(["security", "find-identity", *(["-v"] if valid_only else []), "-p", "codesigning",
                  keychain]).stdout.decode("utf-8", "replace")
    return re.findall(r'^\s*\d+\) ([0-9A-F]{40}) "(Apple Distribution: .+ \(([A-Z0-9]{10})\))"', output, re.M)


def fetch_intermediates(keychain: Path, work: Path) -> bool:
    """憑證的上一層（Apple 的 WWDR 中繼憑證）不在 runner 上時，照憑證裏寫的網址下載。
    下載的只放進臨時 keychain；憑證有效與否照舊由 macOS 用系統內建的 Apple 根憑證判斷。"""
    pem = run(["security", "find-certificate", "-a", "-p", keychain]).stdout.decode("ascii", "replace")
    urls = set()
    for block in re.findall(r"-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----", pem, re.S):
        der = base64.b64decode("".join(block.split()))
        urls.update(url.decode() for url in re.findall(rb"https?://certs\.apple\.com/[A-Za-z0-9._/-]+\.der", der))
    for number, url in enumerate(sorted(urls)):
        path = work / f"intermediate-{number}.der"
        with urllib.request.urlopen(url, timeout=30) as response:
            path.write_bytes(response.read())
        subprocess.run(["security", "import", str(path), "-k", str(keychain)], capture_output=True)
        print(f"加了中繼憑證：{url}")
    return bool(urls)


def keychain_search_list() -> list[str]:
    output = run(["security", "list-keychains", "-d", "user"]).stdout.decode()
    return [line.strip().strip('"') for line in output.splitlines() if line.strip()]


def install(args, environ=os.environ) -> dict:
    missing = [name for name in SECRETS if not environ.get(name, "").strip()]
    if missing:
        raise SigningError(f"{ENVIRONMENT} environment 缺少這些 secrets：" + "、".join(missing)
                           + "。照 docs/app-store-signing.md 用 signing.py secrets 放進去。")
    if sys.platform != "darwin":
        raise SigningError("install 只在 macOS 上跑。")
    work = Path(args.work or environ.get("RUNNER_TEMP") or tempfile.mkdtemp()) / "signing"
    work.mkdir(parents=True, exist_ok=True)

    # 1. 憑證放進只給這次建置用的 keychain
    p12 = work / P12_FILE
    p12.write_bytes(decode(environ, "DISTRIBUTION_CERTIFICATE_P12"))
    restrict(p12)
    keychain = work / "app-store.keychain-db"
    password = secrets.token_urlsafe(24)
    if keychain.exists():
        subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)
    run(["security", "create-keychain", "-p", password, keychain])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain])
    run(["security", "unlock-keychain", "-p", password, keychain])
    try:
        run(["security", "import", p12, "-k", keychain, "-P", environ["DISTRIBUTION_CERTIFICATE_PASSWORD"],
             "-A", "-t", "cert", "-f", "pkcs12"])
    except SigningError as error:
        raise SigningError(f"DISTRIBUTION_CERTIFICATE_P12 放不進 keychain（密碼不對，或者不是 signing.py certificate "
                           f"產生的 .p12）：{error}") from error
    finally:
        p12.unlink()
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain])
    run(["security", "list-keychains", "-d", "user", "-s", keychain,
         *[item for item in keychain_search_list() if item != str(keychain)]])

    identities = find_identities(keychain, valid_only=not args.self_test)
    if not identities and not args.self_test and fetch_intermediates(keychain, work):
        identities = find_identities(keychain, valid_only=True)
    if not identities:
        listed = find_identities(keychain, valid_only=False)
        if listed:
            raise SigningError(f"keychain 裏有「{listed[0][1]}」，但 macOS 認為它無效（過期、被撤銷，或者找不到 Apple 的中繼憑證）。")
        raise SigningError("DISTRIBUTION_CERTIFICATE_P12 裏沒有 Apple Distribution 憑證和私密金鑰。")
    if len(identities) > 1:
        raise SigningError("DISTRIBUTION_CERTIFICATE_P12 裏有多於一張 Apple Distribution 憑證。")
    sha1, identity, team = identities[0]

    # 2. 描述檔
    profiles = [(secret, decode_profile(decode(environ, secret)), decode(environ, secret))
                for secret in PROFILE_SECRETS.values()]
    found = check_profiles(profiles, team, sha1)
    for bundle_id, secret in PROFILE_SECRETS.items():
        if found[bundle_id]["source"] != secret:
            raise SigningError(f"{secret} 放的不是 {bundle_id} 的描述檔：APP_STORE_PROFILE_APP 和 "
                               "APP_STORE_PROFILE_TUNNEL 放反了。")
    # Xcode 16 起讀 UserData 那個資料夾，之前的版本讀 MobileDevice 那個
    profile_dirs = [Path(args.profiles_dir)] if args.profiles_dir else [
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ]
    for directory in profile_dirs:
        directory.mkdir(parents=True, exist_ok=True)
        for item in found.values():
            (directory / f"{item['uuid']}.mobileprovision").write_bytes(item["data"])

    # 3. App Store Connect API 金鑰
    key_id = environ["APP_STORE_CONNECT_KEY_ID"].strip()
    key_content = decode(environ, "APP_STORE_CONNECT_KEY")
    if check_api_key(f"AuthKey_{key_id}.p8", key_content) != key_id:
        raise SigningError("APP_STORE_CONNECT_KEY_ID 的格式不對。")
    key_path = work / "private_keys" / f"AuthKey_{key_id}.p8"
    key_path.parent.mkdir(exist_ok=True)
    key_path.write_bytes(key_content)
    restrict(key_path)
    issuer = check_issuer(environ["APP_STORE_CONNECT_ISSUER_ID"])

    outputs = {
        "GFLYER_TEAM_ID": team,
        "GFLYER_SIGNING_KEYCHAIN": str(keychain),
        "GFLYER_APP_PROFILE": found[APP_ID]["name"],
        "GFLYER_APP_PROFILE_UUID": found[APP_ID]["uuid"],
        "GFLYER_TUNNEL_PROFILE": found[TUNNEL_ID]["name"],
        "GFLYER_TUNNEL_PROFILE_UUID": found[TUNNEL_ID]["uuid"],
        "GFLYER_PROFILE_DIRS": os.pathsep.join(str(directory) for directory in profile_dirs),
        "GFLYER_ASC_KEY_PATH": str(key_path),
        "GFLYER_ASC_KEY_ID": key_id,
        "GFLYER_ASC_ISSUER_ID": issuer,
    }
    env_file = args.env_file or environ.get("GITHUB_ENV")
    if env_file:
        with open(env_file, "a", encoding="utf-8") as file:
            for name, value in outputs.items():
                file.write(f"{name}={value}\n")
    print(f"簽署身分：{identity}")
    for bundle_id in (APP_ID, TUNNEL_ID):
        item = found[bundle_id]
        print(f"描述檔：{bundle_id} 用「{item['name']}」，{show_date(item['expires'])} 到期")
    return outputs


def export_options(args, environ=os.environ) -> None:
    options = {
        "method": "app-store-connect",
        "signingStyle": "manual",
        "teamID": environ["GFLYER_TEAM_ID"],
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {
            APP_ID: environ["GFLYER_APP_PROFILE_UUID"],
            TUNNEL_ID: environ["GFLYER_TUNNEL_PROFILE_UUID"],
        },
        "destination": args.destination,
        # 版本號只在 project.yml 改（docs/RELEASE_PROCESS.md 第 1 步），上傳時不要讓 Xcode 改
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }
    sys.stdout.buffer.write(plistlib.dumps(options))


def check_ipa(args, environ=os.environ) -> None:
    team = environ.get("GFLYER_TEAM_ID", "")
    expected = {APP_ID: environ.get("GFLYER_APP_PROFILE_UUID"), TUNNEL_ID: environ.get("GFLYER_TUNNEL_PROFILE_UUID")}
    with tempfile.TemporaryDirectory() as work:
        run(["ditto", "-x", "-k", args.ipa, work])
        app = Path(work) / "Payload" / "GFlyerPublic.app"
        bundles = {APP_ID: app, TUNNEL_ID: app / "PlugIns" / "GFlyerPublicTunnel.appex"}
        if not app.is_dir():
            raise SigningError(f"{args.ipa} 裏沒有 Payload/GFlyerPublic.app。")
        run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
        for bundle_id, bundle in bundles.items():
            details = run(["codesign", "-d", "--verbose=2", bundle]).stderr.decode("utf-8", "replace")
            if not args.adhoc:
                authority = re.search(r"^Authority=(.*)$", details, re.M)
                if not authority or not authority.group(1).startswith("Apple Distribution:"):
                    raise SigningError(f"{bundle.name} 不是用 Apple Distribution 憑證簽的。")
                if f"TeamIdentifier={team}" not in details:
                    raise SigningError(f"{bundle.name} 的團隊不是 {team}。")
            entitlements = plistlib.loads(run(["codesign", "-d", "--entitlements", "-", "--xml", bundle]).stdout)
            if entitlements.get("application-identifier") != f"{team}.{bundle_id}":
                raise SigningError(f"{bundle.name} 的 application-identifier 是 "
                                   f"{entitlements.get('application-identifier')}，要是 {team}.{bundle_id}。")
            if entitlements.get("get-task-allow"):
                raise SigningError(f"{bundle.name} 有 get-task-allow：是開發用的簽署，App Store Connect 不收。")
            if PACKET_TUNNEL not in entitlements.get(NETWORK_EXTENSION, []):
                raise SigningError(f"{bundle.name} 沒有 Network Extensions 的 Packet Tunnel entitlement，本機通道開不到。")
            # App Store Connect 描述檔簽的才有，TestFlight 要它
            if not args.adhoc and entitlements.get("beta-reports-active") is not True:
                raise SigningError(f"{bundle.name} 沒有 beta-reports-active：不是用 App Store Connect 描述檔簽的。")
            profile = decode_profile((bundle / "embedded.mobileprovision").read_bytes())
            if expected[bundle_id] and profile["UUID"] != expected[bundle_id]:
                raise SigningError(f"{bundle.name} 裏的描述檔不是 install 裝的那個（{expected[bundle_id]}）。")
    print(f"簽署核對通過：App 和本機通道都由團隊 {team} 簽，有 Packet Tunnel entitlement 和 App Store Connect 描述檔。")


def cleanup(args, environ=os.environ) -> None:
    keychain = environ.get("GFLYER_SIGNING_KEYCHAIN")
    if keychain:
        subprocess.run(["security", "delete-keychain", keychain], capture_output=True)
    for name in ("GFLYER_APP_PROFILE_UUID", "GFLYER_TUNNEL_PROFILE_UUID"):
        profile_uuid = environ.get(name)
        for directory in filter(None, environ.get("GFLYER_PROFILE_DIRS", "").split(os.pathsep)):
            if profile_uuid:
                Path(directory, f"{profile_uuid}.mobileprovision").unlink(missing_ok=True)
    key_path = environ.get("GFLYER_ASC_KEY_PATH")
    if key_path:
        Path(key_path).unlink(missing_ok=True)
    print("刪掉了 keychain、描述檔和 API 金鑰。")


# ── self-test ───────────────────────────────────────────────────

REJECTED = []


def expect_failure(action, phrase: str) -> None:
    try:
        action()
    except SigningError as error:
        if phrase not in str(error):
            raise AssertionError(f"錯誤訊息裏沒有「{phrase}」：{error}") from error
        REJECTED.append(phrase)
        return
    raise AssertionError(f"應該因為「{phrase}」失敗，卻通過了")


def self_test(args) -> None:
    team = "ABCDE12345"
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        directory = temp / "signing"
        options = argparse.Namespace

        # 簽署檔不可以放在 repo 裏；request 不蓋掉已有的私密金鑰
        expect_failure(lambda: signing_dir(str(ROOT / "signing")), "不可以放在這個 repo 裏")
        request(options(dir=str(directory), email="gflyer@jetpiggy.com"))
        openssl("req", "-verify", "-noout", "-in", directory / CSR_FILE)
        expect_failure(lambda: request(options(dir=str(directory), email="gflyer@jetpiggy.com")), "已經存在")

        # 假的「Apple」：自己的 CA 用使用者的 CSR 發憑證，名稱照 Apple Distribution 憑證的格式
        ca_key, ca_cert = temp / "ca.key", temp / "ca.pem"
        openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", ca_key, "-out", ca_cert,
                "-days", "2", "-subj", "/CN=GFlyer Signing Self Test CA")
        extensions = temp / "leaf.ext"
        extensions.write_text("basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\n"
                              "extendedKeyUsage=codeSigning\n", encoding="ascii")

        def issue(path: Path, subject: str, csr: Path = directory / CSR_FILE) -> Path:
            openssl("x509", "-req", "-in", csr, "-CA", ca_cert, "-CAkey", ca_key, "-set_serial", "1",
                    "-days", "2", "-extfile", extensions, "-subj", subject, "-outform", "DER", "-out", path)
            return path

        cer = issue(temp / "distribution.cer",
                    f"/UID={team}/CN=Apple Distribution: Self Test, Ltd. ({team})/OU={team}/O=Self Test, Ltd./C=HK")
        development = issue(temp / "development.cer", f"/CN=Apple Development: Self Test ({team})/OU={team}")
        expect_failure(lambda: certificate(options(cer=str(development), dir=str(directory))), "不是 Apple Distribution")
        other_key = temp / "other.key"
        openssl("genrsa", "-out", other_key, "2048")
        openssl("req", "-new", "-key", other_key, "-out", temp / "other.csr", "-subj", "/CN=Other")
        stranger = issue(temp / "stranger.cer", f"/CN=Apple Distribution: Stranger ({team})/OU={team}",
                         csr=temp / "other.csr")
        expect_failure(lambda: certificate(options(cer=str(stranger), dir=str(directory))), "不是用")
        certificate(options(cer=str(cer), dir=str(directory)))
        openssl("pkcs12", "-in", directory / P12_FILE, "-noout",
                "-passin", f"file:{directory / PASSWORD_FILE}")
        cer_der = cer.read_bytes()

        def profile(bundle_id: str, name: str, **changes) -> Path:
            entitlements = {
                "application-identifier": f"{team}.{bundle_id}",
                "com.apple.developer.team-identifier": team,
                "get-task-allow": False,
                "beta-reports-active": True,
                NETWORK_EXTENSION: [PACKET_TUNNEL, "app-proxy-provider"],
            }
            entitlements.update(changes.pop("entitlements", {}))
            content = {
                "Name": name,
                "UUID": str(uuid.uuid4()).upper(),
                "TeamIdentifier": [team],
                "ExpirationDate": now() + dt.timedelta(days=300),
                "DeveloperCertificates": [cer_der],
                "Entitlements": {key: value for key, value in entitlements.items() if value is not None},
            }
            content.update(changes)
            source = temp / f"{name}.plist"
            source.write_bytes(plistlib.dumps(content))
            path = temp / f"{name}.mobileprovision"
            openssl("cms", "-sign", "-nodetach", "-binary", "-outform", "DER", "-in", source,
                    "-signer", ca_cert, "-inkey", ca_key, "-out", path)
            return path

        app_profile = profile(APP_ID, "GFlyer App Store")
        tunnel_profile = profile(TUNNEL_ID, "GFlyer Tunnel App Store")
        api_key = temp / "AuthKey_SELFTEST01.p8"
        api_key.write_bytes(b"-----BEGIN PRIVATE KEY-----\nU0VMRlRFU1Q=\n-----END PRIVATE KEY-----\n")
        issuer = "57246542-96fe-1a63-e053-0824d011072a"

        def secrets_with(*profiles: Path, key: Path = api_key, issuer_id: str = issuer) -> None:
            secrets_command(options(dir=str(directory), profile=[str(item) for item in profiles],
                                    api_key=str(key), issuer=issuer_id, repo=None, dry_run=True))

        secrets_with(app_profile, tunnel_profile)
        bad_profiles = {
            "不是 App Store Connect": profile(APP_ID, "ad-hoc", ProvisionedDevices=["00008110-0000000000000000"]),
            "開發用": profile(APP_ID, "development", entitlements={"get-task-allow": True}),
            "屬於團隊": profile(APP_ID, "other-team", TeamIdentifier=["ZZZZZ99999"]),
            "App ID 是": profile("com.example.other", "other-app"),
            "Packet Tunnel": profile(APP_ID, "no-tunnel", entitlements={NETWORK_EXTENSION: None}),
            "沒有這張": profile(APP_ID, "other-certificate", DeveloperCertificates=[b"not this one"]),
            "過期": profile(APP_ID, "expired", ExpirationDate=now() - dt.timedelta(days=1)),
        }
        for phrase, bad in bad_profiles.items():
            expect_failure(lambda: secrets_with(bad, tunnel_profile), phrase)
        expect_failure(lambda: secrets_with(app_profile, app_profile), "兩個描述檔都是")
        expect_failure(lambda: secrets_with(app_profile), "缺少")
        renamed = temp / "key.p8"
        renamed.write_bytes(api_key.read_bytes())
        expect_failure(lambda: secrets_with(app_profile, tunnel_profile, key=renamed), "檔名")
        expect_failure(lambda: secrets_with(app_profile, tunnel_profile, issuer_id="not-an-id"), "格式不對")
        expect_failure(lambda: install(options(self_test=True, work=str(temp), profiles_dir=None, env_file=None),
                                       environ={}), "DISTRIBUTION_CERTIFICATE_P12")
        tested = "request、certificate、secrets --dry-run"

        if sys.platform == "darwin":
            environ = {
                "DISTRIBUTION_CERTIFICATE_P12": encode((directory / P12_FILE).read_bytes()),
                "DISTRIBUTION_CERTIFICATE_PASSWORD": (directory / PASSWORD_FILE).read_text(encoding="ascii"),
                "APP_STORE_PROFILE_APP": encode(app_profile.read_bytes()),
                "APP_STORE_PROFILE_TUNNEL": encode(tunnel_profile.read_bytes()),
                "APP_STORE_CONNECT_KEY": encode(api_key.read_bytes()),
                "APP_STORE_CONNECT_KEY_ID": "SELFTEST01",
                "APP_STORE_CONNECT_ISSUER_ID": issuer,
            }
            search_list = keychain_search_list()
            env_file = temp / "github_env"
            install_options = options(self_test=True, work=str(temp / "ci"), profiles_dir=str(temp / "profiles"),
                                      env_file=str(env_file))
            try:
                swapped = dict(environ, APP_STORE_PROFILE_APP=environ["APP_STORE_PROFILE_TUNNEL"],
                               APP_STORE_PROFILE_TUNNEL=environ["APP_STORE_PROFILE_APP"])
                expect_failure(lambda: install(install_options, environ=swapped), "放反了")
                expect_failure(lambda: install(install_options, environ=dict(environ, DISTRIBUTION_CERTIFICATE_PASSWORD="wrong")),
                               "放不進 keychain")
                env_file.unlink(missing_ok=True)
                outputs = install(install_options, environ=environ)
                written = env_file.read_text(encoding="utf-8")
                assert f"GFLYER_TEAM_ID={team}\n" in written, written
                assert "GFLYER_APP_PROFILE=GFlyer App Store\n" in written, written
                for profile_uuid in (outputs["GFLYER_APP_PROFILE_UUID"], outputs["GFLYER_TUNNEL_PROFILE_UUID"]):
                    assert (temp / "profiles" / f"{profile_uuid}.mobileprovision").exists()
                assert Path(outputs["GFLYER_ASC_KEY_PATH"]).name == "AuthKey_SELFTEST01.p8"
                written_options = plistlib.loads(
                    capture(lambda: export_options(options(destination="upload"), environ=outputs)))
                assert written_options["destination"] == "upload"
                assert written_options["provisioningProfiles"][TUNNEL_ID] == outputs["GFLYER_TUNNEL_PROFILE_UUID"]
                assert written_options["manageAppVersionAndBuildNumber"] is False

                ipa = fake_ipa(temp, team, app_profile, tunnel_profile, with_tunnel_entitlement=True)
                check_ipa(options(ipa=str(ipa), adhoc=True), environ=outputs)
                broken = fake_ipa(temp, team, app_profile, tunnel_profile, with_tunnel_entitlement=False)
                expect_failure(lambda: check_ipa(options(ipa=str(broken), adhoc=True), environ=outputs), "Packet Tunnel")
                cleanup(options(), environ=outputs)
                assert not Path(outputs["GFLYER_ASC_KEY_PATH"]).exists()
                tested += "、install、export-options、check-ipa、cleanup"
            finally:
                subprocess.run(["security", "list-keychains", "-d", "user", "-s", *search_list], capture_output=True)
                subprocess.run(["security", "delete-keychain", str(temp / "ci" / "signing" / "app-store.keychain-db")],
                               capture_output=True)
    print(f"self-test 通過：{tested}，擋下 {len(REJECTED)} 個應該擋下的例子")


def capture(action) -> bytes:
    """執行 action，回傳它寫到 sys.stdout.buffer 的內容。"""
    saved = sys.stdout
    buffer = io.BytesIO()
    sys.stdout = io.TextIOWrapper(buffer, encoding="utf-8")
    try:
        action()
        sys.stdout.flush()
        return buffer.getvalue()
    finally:
        sys.stdout = saved


def fake_ipa(temp: Path, team: str, app_profile: Path, tunnel_profile: Path, with_tunnel_entitlement: bool) -> Path:
    """用 ad-hoc 簽署做一個和公開版同樣結構的 IPA，給 check-ipa 的 self-test 用。"""
    name = "good" if with_tunnel_entitlement else "broken"
    payload = temp / f"ipa-{name}" / "Payload"
    app = payload / "GFlyerPublic.app"
    appex = app / "PlugIns" / "GFlyerPublicTunnel.appex"
    appex.mkdir(parents=True)
    for bundle, bundle_id, executable, package, source in (
            (appex, TUNNEL_ID, "GFlyerPublicTunnel", "XPC!", tunnel_profile),
            (app, APP_ID, "GFlyerPublic", "APPL", app_profile)):
        shutil.copy("/usr/bin/true", bundle / executable)
        (bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id, "CFBundleExecutable": executable,
            "CFBundlePackageType": package, "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
        }))
        shutil.copy(source, bundle / "embedded.mobileprovision")
        entitlements = {"application-identifier": f"{team}.{bundle_id}",
                        "com.apple.developer.team-identifier": team}
        if with_tunnel_entitlement or bundle_id == APP_ID:
            entitlements[NETWORK_EXTENSION] = [PACKET_TUNNEL]
        entitlements_file = temp / f"{name}-{executable}.entitlements"
        entitlements_file.write_bytes(plistlib.dumps(entitlements))
        run(["codesign", "--force", "--sign", "-", "--entitlements", entitlements_file, bundle])
    ipa = temp / f"{name}.ipa"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", payload, ipa])
    return ipa


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    command = commands.add_parser("request", help="產生私密金鑰和憑證簽署要求")
    command.add_argument("--dir", help=f"放簽署檔的資料夾，預設 {DEFAULT_DIR}")
    command.add_argument("--email", default="gflyer@jetpiggy.com")
    command.set_defaults(action=request)

    command = commands.add_parser("certificate", help="把 Apple Distribution 憑證和私密金鑰合成 .p12")
    command.add_argument("cer")
    command.add_argument("--dir")
    command.set_defaults(action=certificate)

    command = commands.add_parser("secrets", help="核對全部檔案，再放進 GitHub 的 app-store environment")
    command.add_argument("--dir")
    command.add_argument("--profile", action="append", required=True, help="兩個 App Store Connect 描述檔，各寫一次")
    command.add_argument("--api-key", required=True, help="AuthKey_<Key ID>.p8")
    command.add_argument("--issuer", required=True, help="API 金鑰的 Issuer ID")
    command.add_argument("--repo", help="預設是這個資料夾的 GitHub repo")
    command.add_argument("--dry-run", action="store_true", help="只核對，不改 GitHub")
    command.set_defaults(action=secrets_command)

    command = commands.add_parser("install", help="（CI）從 secrets 建臨時 keychain、裝描述檔和 API 金鑰")
    command.add_argument("--work")
    command.add_argument("--profiles-dir")
    command.add_argument("--env-file")
    command.set_defaults(action=install, self_test=False)

    command = commands.add_parser("export-options", help="（CI）印出 xcodebuild -exportArchive 的選項")
    command.add_argument("--destination", choices=("export", "upload"), required=True)
    command.set_defaults(action=export_options)

    command = commands.add_parser("check-ipa", help="（CI）核對匯出的 IPA 的簽署")
    command.add_argument("ipa")
    command.set_defaults(action=check_ipa, adhoc=False)

    command = commands.add_parser("cleanup", help="（CI）刪掉 install 放下的檔案")
    command.set_defaults(action=cleanup)

    command = commands.add_parser("self-test", help="用假的憑證和描述檔試一遍")
    command.set_defaults(action=self_test)

    # Windows 的 Git Bash 和輸出到檔案時，Python 預設用系統的編碼（香港是 Big5），中文會變亂碼
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    args = parser.parse_args(argv)
    try:
        args.action(args)
    except SigningError as error:
        print(f"錯誤：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
