## Positive control — RL-14.4 falsification suite: allowed import.
## nim-check: skip
##
## A src/core/ module importing core/... is legal: LayerRules allowedImports
## for src/core/ is ["core/"] (src/core/trusted/layer_rules.nim). This file
## MUST PASS src/gate/runners/layer_enforcement_gate.nim (rc=0, no
## violation) — it guards the RL-14.4 rule set against over-blocking legal
## core-internal dependencies once the "verification/" and "ui/" prefixes
## land.
##
## This file is never compiled: the "nim-check: skip" marker makes
## .githooks/pre-commit exclude it from the staged-file compiler gate; the
## layer gate scans it as text only.
## Run: make check-layer-negative
## Asserted verdict: PASS — no layer violations in 1 files
import core/trusted/layer_rules
