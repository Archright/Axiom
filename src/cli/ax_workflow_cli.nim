import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Re-export hub for backward compatibility.
## All functionality has been split into:
##   wf_state    — proof state & shortcut state management
##   wf_planning — proof planning & request building
##   wf_semantic — semantic proof processing
##   wf_render   — report rendering
##   wf_runners  — CLI runners & command entry points

import cli/wf_state
export wf_state

import cli/wf_planning
export wf_planning

import cli/wf_semantic
export wf_semantic

import cli/wf_render
export wf_render

import cli/wf_runners
export wf_runners
{.pop.}
