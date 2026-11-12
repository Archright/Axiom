# SLA & Baseline Update Report

**Date**: 2026-06-21
**Source**: `.axiom/gate_history.jsonl` (573 records, 32 unique gates)

---

## gate_performance_baseline.json

### Before

| Gate | Pass Rate | Max Duration (ms) | Criticality |
|------|-----------|-------------------|-------------|
| import-encapsulation-gate | 0.9 | 3000 | medium |
| manifest-consistency-gate | 0.95 | 2000 | medium |
| language-ban-gate | 0.99 | 1000 | medium |
| nimtry-gate | 0.85 | 10000 | medium |
| gate-self-check | 0.99 | 500 | high |
| sentinel | 0.99 | 500 | high |
| quality-gate-marker | 0.99 | 500 | high |
| unstaged-guard | 0.95 | 1000 | high |
| logging-policy-gate | 0.9 | 2000 | medium |
| procedure-gate | 0.85 | 5000 | medium |
| hermetic-test-gate | 0.9 | 8000 | low |
| architecture-config-gate | 0.95 | 1000 | high |
| integrity-workflow | 0.8 | 15000 | high |

### After (based on p95 telemetry)

| Gate | Pass Rate | Max Duration (ms) | Criticality | p50 (s) | p95 (s) | p99 (s) | Max (s) | Count |
|------|-----------|-------------------|-------------|---------|---------|---------|---------|-------|
| architecture-config-gate | 0.83 | 35000 | high | 25.1 | 34.5 | 41.1 | 42.7 | 18 |
| asset-hygiene-gate | 1.0 | 32000 | medium | 22.7 | 31.8 | 33.3 | 33.7 | 18 |
| binary-artifact-gate | 1.0 | 30000 | medium | 4.4 | 29.1 | 32.8 | 34.6 | 42 |
| context-size-guard | 1.0 | 37000 | medium | 31.4 | 36.9 | 37.4 | 37.5 | 2 |
| context7-evidence-gate | 1.0 | 23000 | medium | 20.9 | 22.3 | 22.4 | 22.5 | 2 |
| debt-blocker | 1.0 | 35000 | medium | 21.1 | 34.2 | 36.9 | 37.6 | 18 |
| debt-reduction-gate | 1.0 | 10000 | medium | 7.4 | 10.0 | 10.3 | 10.4 | 4 |
| delegation-enforcer | 1.0 | 22000 | medium | 10.7 | 21.2 | 23.8 | 24.9 | 42 |
| doc-completeness-gate | 1.0 | 32000 | medium | 9.5 | 31.8 | 32.1 | 32.2 | 18 |
| documentation-first-gate | 1.0 | 32000 | medium | 10.6 | 31.8 | 32.2 | 32.3 | 18 |
| drnim | 1.0 | 48000 | medium | 23.8 | 47.1 | 60.6 | 64.0 | 13 |
| gate-self-check | 1.0 | 2000 | high | 0.0 | 1.8 | 1.8 | 1.8 | 24 |
| hermetic-test-gate | 0.77 | 30000 | low | 20.1 | 29.2 | 29.9 | 30.1 | 13 |
| import-encapsulation-gate | 1.0 | 24000 | medium | 15.9 | 23.9 | 26.4 | 27.1 | 18 |
| integrity-workflow | 0.5 | 39000 | high | 27.8 | 39.0 | 39.1 | 39.2 | 21 |
| intent-gate | 1.0 | 28000 | medium | 3.0 | 27.2 | 28.7 | 29.1 | 21 |
| language-ban-gate | 1.0 | 25000 | medium | 5.4 | 24.7 | 28.1 | 29.4 | 42 |
| logging-policy-gate | 1.0 | 55000 | medium | 34.3 | 54.4 | 55.3 | 55.5 | 18 |
| magic-number-sniffer | 1.0 | 30000 | medium | 4.9 | 29.2 | 31.5 | 32.1 | 21 |
| manifest-consistency-gate | 1.0 | 31000 | medium | 25.4 | 30.0 | 30.4 | 30.5 | 4 |
| memory-policy-gate | 1.0 | 39000 | medium | 35.1 | 38.6 | 38.9 | 38.9 | 2 |
| nimtry | 1.0 | 10000 | medium | 1.1 | 9.9 | 15.7 | 17.1 | 18 |
| nimtry-gate | 1.0 | 30000 | medium | 15.6 | 29.9 | 55.1 | 61.4 | 18 |
| policy-validator | 1.0 | 9000 | medium | 3.8 | 8.6 | 9.9 | 10.2 | 18 |
| procedure-gate | 0.5 | 30000 | medium | 10.0 | 29.6 | 31.5 | 32.0 | 18 |
| quality-gate-marker | 1.0 | 2000 | high | 0.0 | 1.7 | 1.7 | 1.7 | 19 |
| quality-gate-runner | 1.0 | 39000 | medium | 26.9 | 39.0 | 42.4 | 43.3 | 18 |
| sentinel | 1.0 | 2000 | high | 0.0 | 1.7 | 1.7 | 1.7 | 19 |
| spec-binding-gate | 1.0 | 43000 | medium | 27.0 | 42.0 | 44.1 | 44.7 | 8 |
| sync-protocol-gate | 0.5 | 19000 | medium | 2.4 | 18.2 | 18.3 | 18.4 | 21 |
| unstaged-guard | 1.0 | 2000 | high | 0.0 | 1.7 | 1.8 | 1.8 | 19 |

---

## gate_sla.json

### Before

```json
{
  "default_timeout_sec": 120,
  "gates": {
    "proof-universe-lock-gate": {
      "timeout_sec": 240
    },
    "nim-check": {
      "timeout_sec": 300
    },
    "gateway-test": {
      "timeout_sec": 300
    },
    "nimtry": {
      "timeout_sec": 300
    }
  },
  "orchestrator_buffer_sec": 30
}
```

### After

```json
{
  "default_timeout_sec": 120,
  "gates": {
    "architecture-config-gate": {
      "timeout_sec": 120
    },
    "asset-hygiene-gate": {
      "timeout_sec": 120
    },
    "binary-artifact-gate": {
      "timeout_sec": 120
    },
    "context-size-guard": {
      "timeout_sec": 120
    },
    "context7-evidence-gate": {
      "timeout_sec": 120
    },
    "debt-blocker": {
      "timeout_sec": 120
    },
    "debt-reduction-gate": {
      "timeout_sec": 120
    },
    "delegation-enforcer": {
      "timeout_sec": 120
    },
    "doc-completeness-gate": {
      "timeout_sec": 120
    },
    "documentation-first-gate": {
      "timeout_sec": 120
    },
    "drnim": {
      "timeout_sec": 300
    },
    "gate-self-check": {
      "timeout_sec": 60
    },
    "hermetic-test-gate": {
      "timeout_sec": 120
    },
    "import-encapsulation-gate": {
      "timeout_sec": 120
    },
    "integrity-workflow": {
      "timeout_sec": 120
    },
    "intent-gate": {
      "timeout_sec": 120
    },
    "language-ban-gate": {
      "timeout_sec": 120
    },
    "logging-policy-gate": {
      "timeout_sec": 120
    },
    "magic-number-sniffer": {
      "timeout_sec": 120
    },
    "manifest-consistency-gate": {
      "timeout_sec": 120
    },
    "memory-policy-gate": {
      "timeout_sec": 120
    },
    "nimtry": {
      "timeout_sec": 300
    },
    "nimtry-gate": {
      "timeout_sec": 300
    },
    "policy-validator": {
      "timeout_sec": 120
    },
    "procedure-gate": {
      "timeout_sec": 120
    },
    "quality-gate-marker": {
      "timeout_sec": 60
    },
    "quality-gate-runner": {
      "timeout_sec": 120
    },
    "sentinel": {
      "timeout_sec": 60
    },
    "spec-binding-gate": {
      "timeout_sec": 120
    },
    "sync-protocol-gate": {
      "timeout_sec": 120
    },
    "unstaged-guard": {
      "timeout_sec": 60
    }
  },
  "orchestrator_buffer_sec": 30
}
```

### Changes

| Gate | Old Timeout (s) | New Timeout (s) | Reason |
|------|-----------------|-----------------|--------|
| architecture-config-gate | N/A (default) | 120 | New entry from telemetry |
| asset-hygiene-gate | N/A (default) | 120 | New entry from telemetry |
| binary-artifact-gate | N/A (default) | 120 | New entry from telemetry |
| context-size-guard | N/A (default) | 120 | New entry from telemetry |
| context7-evidence-gate | N/A (default) | 120 | New entry from telemetry |
| debt-blocker | N/A (default) | 120 | New entry from telemetry |
| debt-reduction-gate | N/A (default) | 120 | New entry from telemetry |
| delegation-enforcer | N/A (default) | 120 | New entry from telemetry |
| doc-completeness-gate | N/A (default) | 120 | New entry from telemetry |
| documentation-first-gate | N/A (default) | 120 | New entry from telemetry |
| drnim | N/A (default) | 300 | New entry from telemetry |
| gate-self-check | N/A (default) | 60 | New entry from telemetry |
| gateway-test | 300 | 300 | Preserved (no telemetry) |
| hermetic-test-gate | N/A (default) | 120 | New entry from telemetry |
| import-encapsulation-gate | N/A (default) | 120 | New entry from telemetry |
| integrity-workflow | N/A (default) | 120 | New entry from telemetry |
| intent-gate | N/A (default) | 120 | New entry from telemetry |
| language-ban-gate | N/A (default) | 120 | New entry from telemetry |
| logging-policy-gate | N/A (default) | 120 | New entry from telemetry |
| magic-number-sniffer | N/A (default) | 120 | New entry from telemetry |
| manifest-consistency-gate | N/A (default) | 120 | New entry from telemetry |
| memory-policy-gate | N/A (default) | 120 | New entry from telemetry |
| nim-check | 300 | 300 | Preserved (no telemetry) |
| nimtry | 300 | 300 | Unchanged |
| nimtry-gate | N/A (default) | 300 | New entry from telemetry |
| policy-validator | N/A (default) | 120 | New entry from telemetry |
| procedure-gate | N/A (default) | 120 | New entry from telemetry |
| proof-universe-lock-gate | 240 | 240 | Preserved (no telemetry) |
| quality-gate-marker | N/A (default) | 60 | New entry from telemetry |
| quality-gate-runner | N/A (default) | 120 | New entry from telemetry |
| sentinel | N/A (default) | 60 | New entry from telemetry |
| spec-binding-gate | N/A (default) | 120 | New entry from telemetry |
| sync-protocol-gate | N/A (default) | 120 | New entry from telemetry |
| unstaged-guard | N/A (default) | 60 | New entry from telemetry |

---

## Full Telemetry Statistics

| Gate | Count | p50 (s) | p95 (s) | p99 (s) | Max (s) | Failures | Failure Rate |
|------|-------|---------|---------|---------|---------|----------|--------------|
| architecture-config-gate | 18 | 25.083 | 34.517 | 41.051 | 42.685 | 3 | 16.7% |
| asset-hygiene-gate | 18 | 22.671 | 31.752 | 33.291 | 33.675 | 0 | 0.0% |
| binary-artifact-gate | 42 | 4.417 | 29.088 | 32.755 | 34.568 | 0 | 0.0% |
| context-size-guard | 2 | 31.436 | 36.881 | 37.365 | 37.486 | 0 | 0.0% |
| context7-evidence-gate | 2 | 20.877 | 22.320 | 22.448 | 22.480 | 0 | 0.0% |
| debt-blocker | 18 | 21.071 | 34.211 | 36.947 | 37.631 | 0 | 0.0% |
| debt-reduction-gate | 4 | 7.443 | 9.958 | 10.306 | 10.393 | 0 | 0.0% |
| delegation-enforcer | 42 | 10.698 | 21.230 | 23.773 | 24.929 | 0 | 0.0% |
| doc-completeness-gate | 18 | 9.527 | 31.795 | 32.094 | 32.169 | 0 | 0.0% |
| documentation-first-gate | 18 | 10.636 | 31.834 | 32.181 | 32.268 | 0 | 0.0% |
| drnim | 13 | 23.775 | 47.141 | 60.590 | 63.952 | 0 | 0.0% |
| gate-self-check | 24 | 0.005 | 1.800 | 1.810 | 1.813 | 0 | 0.0% |
| hermetic-test-gate | 13 | 20.065 | 29.192 | 29.947 | 30.136 | 3 | 23.1% |
| import-encapsulation-gate | 18 | 15.879 | 23.949 | 26.432 | 27.053 | 0 | 0.0% |
| integrity-workflow | 21 | 27.839 | 38.983 | 39.141 | 39.181 | 15 | 71.4% |
| intent-gate | 21 | 3.018 | 27.237 | 28.733 | 29.107 | 0 | 0.0% |
| language-ban-gate | 42 | 5.381 | 24.740 | 28.121 | 29.369 | 0 | 0.0% |
| logging-policy-gate | 18 | 34.295 | 54.424 | 55.272 | 55.483 | 0 | 0.0% |
| magic-number-sniffer | 21 | 4.857 | 29.220 | 31.505 | 32.076 | 0 | 0.0% |
| manifest-consistency-gate | 4 | 25.434 | 30.003 | 30.409 | 30.511 | 0 | 0.0% |
| memory-policy-gate | 2 | 35.145 | 38.564 | 38.868 | 38.944 | 0 | 0.0% |
| nimtry | 18 | 1.079 | 9.946 | 15.707 | 17.147 | 0 | 0.0% |
| nimtry-gate | 18 | 15.606 | 29.925 | 55.105 | 61.400 | 0 | 0.0% |
| policy-validator | 18 | 3.767 | 8.562 | 9.864 | 10.189 | 0 | 0.0% |
| procedure-gate | 18 | 9.975 | 29.570 | 31.492 | 31.973 | 10 | 55.6% |
| quality-gate-marker | 19 | 0.013 | 1.677 | 1.709 | 1.717 | 0 | 0.0% |
| quality-gate-runner | 18 | 26.860 | 38.982 | 42.417 | 43.276 | 0 | 0.0% |
| sentinel | 19 | 0.013 | 1.736 | 1.744 | 1.746 | 0 | 0.0% |
| spec-binding-gate | 8 | 27.021 | 42.012 | 44.144 | 44.677 | 0 | 0.0% |
| sync-protocol-gate | 21 | 2.431 | 18.171 | 18.347 | 18.391 | 15 | 71.4% |
| unstaged-guard | 19 | 0.014 | 1.687 | 1.770 | 1.791 | 0 | 0.0% |

---

## Notes

- **Duration source**: Only non-cached runs with `durationNs > 0` are used for timing stats.
- **Baseline `maxDurationMs`**: p95 duration rounded up to nearest 1000ms.
- **SLA formula**: `max(120, p95_sec * 1.5)` unless p95 < 5s (→ 60s) or compilation-heavy (→ 300s).
- **Compilation-heavy gates**: `drnim`, `nimtry-gate`, `nimtry` hardcoded to 300s.
- **Preserved**: `default_timeout_sec: 120`, `orchestrator_buffer_sec: 30`.
