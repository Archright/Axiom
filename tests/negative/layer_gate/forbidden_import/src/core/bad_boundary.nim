## Negative fixture — RL-14.4 falsification: forbidden prefix "mcp/".
## nim-check: skip
##
## RL-14.4 (docs/agents/core_rules.md): src/core/ importing src/mcp/ is an
## immediate revert offense. This file MUST FAIL
## src/gate/runners/layer_enforcement_gate.nim — LayerRules
## (src/core/trusted/layer_rules.nim) forbids the "mcp/" prefix for src/core/.
##
## This file is never compiled: the "nim-check: skip" marker makes
## .githooks/pre-commit exclude it from the staged-file compiler gate; the
## layer gate scans it as text only.
## Run: make check-layer-negative
## Asserted verdict: imports 'mcp/tools' (tools from domain)
import mcp/tools
