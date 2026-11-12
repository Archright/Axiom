import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/logic/lean_diagnostic
export lean_diagnostic

# Shared types (extracted to leaf module)
import core/lean_lsp_types
export lean_lsp_types

# Split sub-modules (formerly included files)
import verification/lean_lsp_protocol
export lean_lsp_protocol
import verification/lean_lsp_compiler
export lean_lsp_compiler
import verification/lean_lsp_tactic
# axiomIoBoundary
export lean_lsp_tactic

# ---------------------------------------------------------------------------
# Exception boundary for std/asyncdispatch waitFor
# ---------------------------------------------------------------------------

import verification/lean_lsp_client
export lean_lsp_client
import verification/lean_lsp_feedback
export lean_lsp_feedback
import verification/tactic_backtrack
export tactic_backtrack
import verification/lean_lsp_proof_search
export lean_lsp_proof_search
{.pop.}
