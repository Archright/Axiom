## Negative fixture — RL-14.4 falsification: forbidden prefix "ui/".
## nim-check: skip
##
## RL-14.4 (docs/agents/core_rules.md): src/core/ importing src/ui/ is an
## immediate revert offense. This file MUST FAIL
## src/gate/runners/layer_enforcement_gate.nim once LayerRules gains the
## "ui/" forbidden prefix for src/core/.
##
## KNOWN GAP (2026-10-11): LayerRules.forbiddenImports for src/core/ lacks
## "ui/" (src/core/trusted/layer_rules.nim), so the gate currently exits 0
## for this import — fail-open for exactly this prefix. The
## check-layer-negative assertion pins the CURRENT rc=0 + PASS verdict with a
## KNOWN-GAP marker and MUST be flipped to rc=1 + the violation verdict when
## the rule lands (the flip is the loud ratchet; a silent pass-over would be
## the fail-open regression the suite exists to catch). Tracked in
## data/debt_registry.json.
import ui/notion_semantic_mapper
