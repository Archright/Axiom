import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/diagnostics/diagnostics_engine_helpers
export diagnostics_engine_helpers
import core/diagnostics/diagnostics_engine_main
export diagnostics_engine_main

{.pop.}
