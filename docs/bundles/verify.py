#!/usr/bin/env python3
import argparse, json, hashlib, sys
from pathlib import Path

def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load_json(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))

def load_jsonl(p: Path):
    rows=[]
    with p.open("r", encoding="utf-8") as f:
        for line in f:
            line=line.strip()
            if not line: 
                continue
            rows.append(json.loads(line))
    return rows

def calc_chain_head(chain_rows):
    # our generator format: each row has {"i","prev","head","payload": {...}}
    # but we re-calc deterministically from payload: prev + json(payload)
    prev = "0"*64
    for row in chain_rows:
        payload = json.dumps(row["payload"], sort_keys=True)
        head = hashlib.sha256((prev + payload).encode()).hexdigest()
        if row.get("prev") != prev:
            return None, f"chain prev mismatch at i={row.get('i')}: expected {prev}, got {row.get('prev')}"
        if row.get("head") != head:
            return None, f"chain head mismatch at i={row.get('i')}: expected {head}, got {row.get('head')}"
        prev = head
    return prev, None

def main():
    ap = argparse.ArgumentParser(description="Verify Gatekeeper/SEMAF defense assurance sample bundle (offline).")
    ap.add_argument("--bundle", required=True, help="Path to bundle directory (contains manifest.json)")
    args = ap.parse_args()

    bdir = Path(args.bundle).resolve()
    manifest_path = bdir / "manifest.json"
    if not manifest_path.exists():
        print(f"FAIL: missing {manifest_path}")
        return 2

    m = load_json(manifest_path)
    files = m.get("files", {})
    expected_head = m.get("chain_head")

    # 1) file hashes
    for rel, exp in files.items():
        p = bdir / rel
        if not p.exists():
            print(f"FAIL: missing file {rel}")
            return 2
        got = sha256_file(p)
        if got != exp:
            print(f"FAIL: sha256 mismatch {rel}\n expected: {exp}\n got: {got}")
            return 2

    # 2) chain head verify
    chain_path = bdir / "audit_chain.jsonl"
    if chain_path.exists():
        chain_rows = load_jsonl(chain_path)
        head, err = calc_chain_head(chain_rows)
        if err:
            print("FAIL:", err)
            return 2
        if expected_head and head != expected_head:
            print("FAIL: chain_head mismatch\n expected:", expected_head, "\n got: ", head)
            return 2
    else:
        print("WARN: audit_chain.jsonl not found; skipping chain verification")

    print("PASS")
    print("bundle:", m.get("bundle"))
    print("manifest_sha256:", sha256_file(manifest_path))
    if expected_head:
        print("chain_head:", expected_head)
    return 0

if __name__ == "__main__":
    sys.exit(main())
