#!/usr/bin/env python3
"""Negative + positive fixture for the Theater DEBT#357+ five-field contract
and the binding-type contract (data/debt_schema.json `binding`/`bindingRationale`)."""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

BASE = Path(__file__).resolve().parents[2]


def validator():
    schema = json.loads((BASE / "data" / "debt_schema.json").read_text(encoding="utf-8"))
    wrapper = {
        "$schema": schema["$schema"],
        "definitions": schema["definitions"],
        "$ref": "#/definitions/DebtRegistryFile",
    }
    Draft202012Validator.check_schema(wrapper)
    return Draft202012Validator(wrapper)


def base_entry(**overrides):
    entry = {
        "category": "Theater/Always-Pass",
        "description": "fixture",
        "files": ["src/gate/runners/release_version_gate.nim"],
        "id": "DEBT#999",
        "severity": "high",
        "source": "fixture",
        "status": "closed",
        "resolution": "FIXED",
        "symbol": "fixture*",
        "lineRange": "src/gate/runners/release_version_gate.nim:1-1",
        "contentHash": "sha256:" + "0" * 64,
        "lastVerifiedAt": "2026-10-19T00:00:00Z",
    }
    entry.update(overrides)
    return entry


def registry(entry):
    return {
        "version": 3,
        "generatedAt": None,
        "scanner": "fixture",
        "entries": [entry],
    }


def run_fixtures():
    v = validator()
    failures = []

    valid = registry(base_entry())
    if list(v.iter_errors(valid)):
        failures.append("valid Theater fixture was rejected")

    for field in ("symbol", "contentHash", "lineRange", "resolution", "lastVerifiedAt"):
        broken = registry(base_entry(**{field: ""}))
        if not list(v.iter_errors(broken)):
            failures.append(f"Theater fixture missing {field} was accepted")
        broken = registry(base_entry())
        del broken["entries"][0][field]
        if not list(v.iter_errors(broken)):
            failures.append(f"Theater fixture without {field} was accepted")

    non_theater = registry(base_entry(category="CI/Pipeline Health"))
    del non_theater["entries"][0]["contentHash"]
    if list(v.iter_errors(non_theater)):
        failures.append("non-Theater fixture was rejected by the Theater rule")

    old = registry(base_entry(id="DEBT#356"))
    del old["entries"][0]["contentHash"]
    if list(v.iter_errors(old)):
        failures.append("DEBT#356 fixture was rejected by the DEBT#357+ rule")

    # ── Binding-type contract (docs/spec/debt_registry_schema.md §10) ──

    # Negative 1: registry_disposition without bindingRationale → invalid
    broken = registry(base_entry(binding="registry_disposition"))
    if not list(v.iter_errors(broken)):
        failures.append("binding=registry_disposition without bindingRationale was accepted")

    # Negative 2: reserved value comment_marker → invalid (enum rejection)
    broken = registry(
        base_entry(
            binding="comment_marker",
            bindingRationale="trace: reserved value must fail",
        )
    )
    if not list(v.iter_errors(broken)):
        failures.append("reserved binding=comment_marker was accepted")

    # Negative 3: whitespace-only bindingRationale → invalid
    broken = registry(
        base_entry(binding="registry_disposition", bindingRationale="   \t\n  ")
    )
    if not list(v.iter_errors(broken)):
        failures.append("whitespace-only bindingRationale was accepted")

    # Positive 1: registry_disposition + non-empty rationale → valid
    ok = registry(
        base_entry(
            binding="registry_disposition",
            bindingRationale="Non-Nim medium; trace: resolution/source in this entry.",
        )
    )
    if list(v.iter_errors(ok)):
        failures.append("binding=registry_disposition with rationale was rejected")

    # Positive 2 (legacy): binding absent → valid, no extra requirement
    ok = registry(base_entry())
    if list(v.iter_errors(ok)):
        failures.append("legacy fixture without binding was rejected")

    real = json.loads((BASE / "data" / "debt_registry.json").read_text(encoding="utf-8"))
    real_errors = list(v.iter_errors(real))
    if real_errors:
        failures.append(f"real registry has {len(real_errors)} schema error(s)")

    return failures


def main():
    failures = run_fixtures()
    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print("PASS: Theater five-field + binding-type fixtures all green (3 negative, 2 positive); real registry is clean")
    return 0


def test_theater_and_binding_rules():
    failures = run_fixtures()
    assert failures == [], failures


if __name__ == "__main__":
    sys.exit(main())
