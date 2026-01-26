#!/usr/bin/env bash
set -euo pipefail

SITE="${SITE:-https://sc691583.github.io/gatekeeperops-site}"
BUNDLE="${1:-bundle_readiness_go_nogo}"

ROOT="${ROOT:-_gk_proof}"
mkdir -p "$ROOT"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ts_fn="${ts//:/-}"

WORK="$ROOT/tmp_${BUNDLE}_${ts_fn}"
mkdir -p "$WORK/$BUNDLE"

receipt="$ROOT/proof_run_${BUNDLE}_${ts_fn}.txt"

u_ver="$SITE/bundles/verify.py"
u_base="$SITE/bundles/$BUNDLE"
u_manifest="$u_base/manifest.json"
u_events="$u_base/events.jsonl"
u_receipt="$u_base/decision_receipt.json"
u_chain="$u_base/audit_chain.jsonl"
u_replay="$u_base/replay_manifest.json"

echo "[1/3] Download verifier..."
curl -sSL -o "$WORK/verify.py" "$u_ver"

echo "[2/3] Download bundle files..."
curl -sSL -o "$WORK/$BUNDLE/manifest.json" "$u_manifest"
curl -sSL -o "$WORK/$BUNDLE/events.jsonl" "$u_events"
curl -sSL -o "$WORK/$BUNDLE/decision_receipt.json" "$u_receipt"
curl -sSL -o "$WORK/$BUNDLE/audit_chain.jsonl" "$u_chain"
curl -sSL -o "$WORK/$BUNDLE/replay_manifest.json" "$u_replay"

vsha="$(python3 - <<PY
import hashlib
print(hashlib.sha256(open("$WORK/verify.py","rb").read()).hexdigest())
PY
)"
msha="$(python3 - <<PY
import hashlib
print(hashlib.sha256(open("$WORK/$BUNDLE/manifest.json","rb").read()).hexdigest())
PY
)"

echo "[3/3] Verify..."
set +e
out="$(python3 "$WORK/verify.py" --bundle "$WORK/$BUNDLE" 2>&1)"
rc=$?
set -e

status="FAIL"
if [ $rc -eq 0 ] && echo "$out" | grep -q "^PASS"; then
  status="PASS"
fi

{
  echo "Gatekeeper/SEMAF — Proof Run Receipt"
  echo "timestamp_utc: $ts"
  echo "site: $SITE"
  echo "bundle: $BUNDLE"
  echo "workspace: $WORK"
  echo "verifier_url: $u_ver"
  echo "manifest_url: $u_manifest"
  echo "events_url: $u_events"
  echo "decision_receipt_url: $u_receipt"
  echo "audit_chain_url: $u_chain"
  echo "replay_manifest_url: $u_replay"
  echo "verifier_sha256: $vsha"
  echo "manifest_sha256: $msha"
  echo "status: $status"
  echo
  echo "--- verifier output ---"
  echo "$out"
} > "$receipt"

echo "$out"
echo "receipt: $receipt"

exit $rc
