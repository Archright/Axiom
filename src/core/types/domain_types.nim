import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## domain_types.nim — Forwarding stub for backward compatibility.
## All types have been extracted into focused modules.
## New code SHOULD import the specific module directly.

import core/types/error_types
import core/types/certificate_types
import core/types/solver_types
import core/types/smt_types
import core/types/gate_types
import core/types/verification_types
import core/types/vault_types
import core/types/lean_types
import core/types/refinement_types
import core/types/translation_types
import core/symbolic/symbolic_types_expr

export error_types
export certificate_types
export solver_types
export smt_types
export gate_types
export verification_types
export vault_types
export lean_types
export refinement_types
export translation_types
export symbolic_types_expr

{.pop.}
