#!/usr/bin/env bash
set -euo pipefail

echo "=== 驗證 GitHub Variables ==="
for v in PROJECT_URL UPDATE_SERVER_URL PACKAGE_NAME SIGNING_CERT_SHA256; do
  val=$(gh variable get "$v" 2>/dev/null || echo "❌ 缺失")
  echo "  $v: $val"
done

echo -e "\n=== 驗證 GitHub Secrets ==="
gh secret list --json name --jq '.[].name' | grep -q "SIGNING_KEYSTORE_BASE64" && echo "  SIGNING_KEYSTORE_BASE64: ✅" || echo "  SIGNING_KEYSTORE_BASE64: ❌"
gh secret list --json name --jq '.[].name' | grep -q "SIGNING_KEYSTORE_PASSWORD" && echo "  SIGNING_KEYSTORE_PASSWORD: ✅" || echo "  SIGNING_KEYSTORE_PASSWORD: ❌"
gh secret list --json name --jq '.[].name' | grep -q "SIGNING_KEY_ALIAS" && echo "  SIGNING_KEY_ALIAS: ✅" || echo "  SIGNING_KEY_ALIAS: ❌"
gh secret list --json name --jq '.[].name' | grep -q "SIGNING_KEY_PASSWORD" && echo "  SIGNING_KEY_PASSWORD: ✅" || echo "  SIGNING_KEY_PASSWORD: ❌"

echo -e "\n=== 驗證 Worker ==="
curl -sf "$UPDATE_SERVER_URL/v1/latest" >/dev/null && echo "  /v1/latest: ✅" || echo "  /v1/latest: ❌"
curl -sf -X POST "$UPDATE_SERVER_URL/v1/ping" -H "Content-Type: application/json" -d '{"day":"2026-11-19","id":"test"}' >/dev/null && echo "  /v1/ping: ✅" || echo "  /v1/ping: ❌"

echo -e "\n=== 驗證 Keystore 指紋 ==="
CERT=$(gh variable get SIGNING_CERT_SHA256)
echo "  GitHub 變數: $CERT"
# 本地驗證（需 release.jks 存在）
if [ -f release.jks ]; then
  LOCAL=$(keytool -list -v -keystore release.jks -alias upload -storepass "$SIGNING_KEYSTORE_PASSWORD" 2>/dev/null | grep "SHA256:" | sed 's/.*SHA256: //' | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  echo "  本地 keystore: $LOCAL"
  [ "$CERT" = "$LOCAL" ] && echo "  ✅ 指紋一致" || echo "  ❌ 指紋不一致"
fi
