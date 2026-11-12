# Debt Ledger v1.1.0 Schema

**SSOT**: `data/debt_ledger.json` — budget metrics ledger only.  
**Effective**: This commit retires all legacy proc→func schemas (v1.0.0 `{"records":[{"file","line","function"...}]}` and `"debts"` shape). Any version ≠ 1.1.0 is fail-closed rejected by all consumers. No schema-dispatch.

## Top-level fields

| Field | Type | Required | Constraint | Description |
|-------|------|----------|------------|-------------|
| `version` | string | Yes | `"1.1.0"` (const) | Fixed to 1.1.0. Reject any other value. |
| `generated` | string | Yes | ISO 8601 datetime (`YYYY-MM-DDTHH:mm:ssZ`) | Generation timestamp. |
| `description` | string | Yes | minLength 1 | Human-readable purpose. |
| `totalRecords` | integer | Yes | ≥ 0 | Count of entries in `records`. |
| `records` | array | Yes | items = BudgetRecord | The metric records. |

## BudgetRecord fields

| Field | Type | Required | Constraint | Description |
|-------|------|----------|------------|-------------|
| `id` | string | Yes | `^BUDGET#\d{3}$` | Aggregate metric identifier (e.g. `BUDGET#001`). **NOT** a registry debt identity — cross-reference `debt_registry.json` for DEBT# IDs. |
| `category` | string | Yes | `"BudgetCategory"` (const) | Fixed discriminator. |
| `description` | string | Yes | minLength 1 | Metric description. |
| `budgetCategory` | enum | Yes | `bcImportLint \| bcLayerViolation \| bcEffectViolation \| bcNimtryViolation \| bcDebtRegistryOpen \| bcDebtRegistryClosed` | Specific budget category. |
| `metric` | string | Yes | minLength 1 | Metric name. |
| `baseline` | integer | Yes | ≥ 0 | Baseline value. |
| `target` | integer | Yes | ≥ 0 | Target value. |
| `current` | integer | Yes | ≥ 0 | Current measured value. |
| `severity` | enum | Yes | `low \| medium \| high` | Severity of the budget gap. |
| `source` | string | Yes | minLength 1 | Origin (e.g. `debt_budgets.json`). |
| `status` | enum | Yes | `open \| closed` | Lifecycle status. |
| `resolution` | enum | Yes | `WONT_FIX \| FIXED` | Resolution status. |
| `lastVerifiedAt` | string | Yes | ISO 8601 datetime | Last verification timestamp. |

## ID policy

`BUDGET#NNN` ids are aggregate metric identifiers, NOT registry debt identities. To find the corresponding tracked debt(s), cross-reference `data/debt_registry.json` which uses `DEBT#NNN` format.

## Consumers

Three consumers decode strictly: `tools/debt_engine.nim`, `tools/check_debt_sync.nim`, `tools/debt_registry_sync.nim`. All reject non-1.1.0 versions.
