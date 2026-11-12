# SCR Domain Metadata Specification

> SSOT for Semantic Conflict Resolver (SCR) metadata extensions to `domain_layout.json`.
> Version: 4.1.0+ (extends existing v4.0 domain layout registry)

---

## 1. Purpose

This document defines the metadata fields required for the Semantic Conflict Resolver (SCR) to perform **deterministic, evidence-based merge conflict resolution** based on architecture rules rather than line-by-line text comparison.

SCR reads `src/core/domain_layout.json` (SSOT) and resolves conflicts by asking:
> "Which change belongs to a domain with higher `priority_score`?"

---

## 2. Schema Extensions

### 2.1 Top-Level Fields

```json
{
  "version": "4.1.0",
  "metadata": {
    "schema_owner": "axiom-architecture-team",
    "last_updated": "2026-06-10",
    "description": "Domain layout registry with SCR metadata"
  },
  "layer_rules": {
    "layers": ["Domain", "Infrastructure", "Presentation", "Gate"],
    "allowed_dependencies": {
      "Domain": ["Domain"],
      "Infrastructure": ["Domain", "Infrastructure"],
      "Presentation": ["Domain", "Infrastructure", "Presentation"],
      "Gate": ["Domain", "Infrastructure", "Presentation", "Gate"]
    }
  },
  "domains": { ... }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `metadata` | Object | Yes | Registry metadata (owner, description, timestamp) |
| `layer_rules` | Object | Yes | Layer dependency constraints for boundary validation |
| `layer_rules.layers` | Array[String] | Yes | Ordered list of layers (top to bottom) |
| `layer_rules.allowed_dependencies` | Object | Yes | Map of layer → allowed downstream layers |

### 2.2 Per-Domain SCR Fields

Each domain in `domains` MAY include the following fields:

```json
{
  "gate": {
    "prefix": ["architecture_policy_", "gate_evaluators"],
    "import_path": "core/gate",
    "layer": "core",
    "owner": "gate-infrastructure-team",
    "priority_score": 95,
    "dependency_mask": ["core/*", "gate/*"],
    "description": "Gate infrastructure and policy enforcement"
  }
}
```

| Field | Type | Required for SCR | Description |
|-------|------|------------------|-------------|
| `owner` | String | Yes | Team or agent responsible for this domain |
| `priority_score` | Integer (0-100) | Yes | Conflict resolution priority (higher = more fundamental) |
| `dependency_mask` | Array[String] | Optional | Glob patterns of allowed import paths |

#### priority_score Guidelines

| Score Range | Interpretation | Example Domains |
|-------------|----------------|-----------------|
| 90-100 | System-critical, structural | `gate`, `domain_types`, `layer_guard` |
| 70-89 | Core business logic | `bmc`, `proof`, `verification` |
| 50-69 | Supporting infrastructure | `json`, `encoding`, `parsers` |
| 30-49 | Utilities and helpers | `utils`, `sync`, `trusted` |
| 0-29 | Experimental or deprecated | — |

**Rule**: When two changes conflict, the change in the domain with the higher `priority_score` wins. If scores are equal, fall back to manual resolution.

---

## 3. Validation

Use `bin/architecture-guard` to validate SSOT completeness:

```bash
# Legacy mode (warn only for unregistered domains)
bin/architecture-guard --impact-report

# Strict mode (fail on missing SCR metadata)
bin/architecture-guard --strict
```

---

## 4. References

- `layered_decoupling_spec.md` — Base-Macro Layered Decoupling pattern
- AGENTS.md §1.2 — Layer architecture (Domain → Infrastructure → Presentation → Gate)
- ~~`bin/refactor-domain`~~ — [DEPRECATED] (deleted 2026-07-07 per Language Ban; was Domain refactoring engine reading this registry)
