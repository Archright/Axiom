#!/usr/bin/env python3
"""Repair the Theater DEBT#357+ five-field contract in data/debt_registry.json.

The repair is deliberately a one-shot, auditable program: it reads the current
baseline tree, selects the exact source lines named by each entry, hashes those
bytes, and appends a verification-journal record. It never invents a historical
verification timestamp: existing lastVerifiedAt values are preserved, and only
missing values are stamped with the actual run time.
"""
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
REGISTRY = BASE / "data" / "debt_registry.json"
JOURNAL = BASE / "data" / "debt" / "verification_journal.jsonl"

# path/range/symbol are fixed to the baseline tree. `rev` selects a historical
# blob; `preserve` keeps the already-valid symbol/contentHash (#499/#500).
PLAN = {
    "DEBT#370": dict(path="src/personas/scribe.nim", ranges="52-54", symbol="synthesizeLeanTheorem*"),
    "DEBT#372": dict(path="src/personas/legislator.nim", ranges="244", symbol="queryViaStdioPipe*"),
    "DEBT#373": dict(path="tools/verify_lfs_integrity.nim", ranges="8-34", symbol="verifyLfsIntegrity*"),
    "DEBT#374": dict(path="tools/hooks/semantic_grounding_hook.nim", ranges="118-121", symbol="main", rev="25a7a2f00^"),
    "DEBT#375": dict(path="src/verification/state_manager.nim", ranges="495", symbol="saveProofState*"),
    "DEBT#376": dict(path="src/verification/pipeline_negative_scan_part2.nim", ranges="356-364", symbol="buildAnnotatedHit*"),
    "DEBT#377": dict(path="src/core/session/session_parser_validators.nim", ranges="62-64", symbol="isAnyString*"),
    "DEBT#378": dict(path="src/core/observer/scanner.nim", ranges="70-71", symbol="scanDirectory"),
    "DEBT#379": dict(path="src/core/observer/scanner.nim", ranges="123,151,159", symbol="scanProject"),
    "DEBT#380": dict(path="src/gate/runners/effect_inference_gate.nim", ranges="116-121", symbol="runEffectInferenceScan"),
    "DEBT#381": dict(path="src/gate/runners/documentation_first_gate.nim", ranges="433-436,629-632", symbol="main"),
    "DEBT#484": dict(path="tests/verification/test_attestation.nim", ranges="1176-1229", symbol="P15 TrustedExecutorSet membership suite"),
    "DEBT#485": dict(path="config/policy/merge_admission.json", ranges="4", symbol="merge_admission policy description"),
    "DEBT#486": dict(path="src/gate/runners/debt_scan_gate.nim", ranges="84-102", symbol="loadExemptionText / isExempted"),
    "DEBT#487": dict(path="tools/hotspot_ranker.nim", ranges="18-42", symbol="parseDebtRegistry"),
    "DEBT#488": dict(path="tools/ci/proof_unit_consistency_gate.nim", ranges="1093-1133", symbol="collectLetBindings"),
    "DEBT#489": dict(path="tools/check_imports_ast.nim", ranges="90-98", symbol="cachedViolations"),
    "DEBT#490": dict(path="src/verification/obligation/canonical_verification.nim", ranges="679-700", symbol="baseVerificationResult"),
    "DEBT#499": dict(path="src/gate/runners/debt_integrity_gate.nim", ranges="1-340", symbol=None, preserve=True),
    "DEBT#500": dict(path="src/gate/runners/quality_gate_runner.nim", ranges="1-158", symbol=None, preserve=True),
}


def parse_ranges(spec: str):
    out = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            out.append((int(a), int(b)))
        else:
            n = int(part)
            out.append((n, n))
    return out


def selected_text(path: str, ranges: str, rev: str | None):
    if rev:
        text = subprocess.check_output(
            ["git", "show", f"{rev}:{path}"], cwd=BASE, text=True
        )
    else:
        text = (BASE / path).read_text(encoding="utf-8")
    lines = text.splitlines()
    chunks = []
    for a, b in parse_ranges(ranges):
        if a < 1 or b > len(lines) or a > b:
            raise SystemExit(
                f"range {ranges} out of bounds for {path} ({len(lines)} lines)"
            )
        chunks.append("\n".join(lines[a - 1 : b]))
    return "\n".join(chunks)


def sha256_digest(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def main():
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    entries = {e["id"]: e for e in registry["entries"]}
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    baseline = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=BASE, text=True
    ).strip()
    records = []

    for debt_id, plan in PLAN.items():
        entry = entries[debt_id]
        text = selected_text(plan["path"], plan["ranges"], plan.get("rev"))
        digest = sha256_digest(text)
        line_range = f"{plan['path']}:{plan['ranges']}"
        if plan.get("rev"):
            line_range += f"@{plan['rev']}"

        if plan.get("preserve"):
            entry["lineRange"] = line_range
            verified = ["lineRange"]
            preserved = True
        else:
            entry["symbol"] = plan["symbol"]
            entry["lineRange"] = line_range
            entry["contentHash"] = digest
            verified = ["symbol", "lineRange", "contentHash"]
            preserved = False

        had_last_verified = bool(entry.get("lastVerifiedAt"))
        if not had_last_verified:
            entry["lastVerifiedAt"] = timestamp
            verified.append("lastVerifiedAt")

        records.append(
            {
                "ts": timestamp,
                "id": debt_id,
                "verificationKind": "source-hash-integrity",
                "verifiedFields": verified,
                "debtResolutionVerified": False,
                "lastVerifiedAtPreserved": had_last_verified,
                "baselineSha": baseline,
                "sourceRef": line_range,
                "symbol": entry.get("symbol", ""),
                "contentHash": entry.get("contentHash", ""),
                "evidence": "tools/ci/repair_theater_fields.py",
            }
        )

    REGISTRY.write_text(
        json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    JOURNAL.parent.mkdir(parents=True, exist_ok=True)
    existing = set()
    if JOURNAL.exists():
        for line in JOURNAL.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rec = json.loads(line)
                existing.add((rec["id"], rec.get("contentHash")))
    with JOURNAL.open("a", encoding="utf-8") as fh:
        for rec in records:
            if (rec["id"], rec["contentHash"]) in existing:
                continue
            fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")

    print(f"repaired={len(records)} baseline={baseline} ts={timestamp}")


if __name__ == "__main__":
    main()
