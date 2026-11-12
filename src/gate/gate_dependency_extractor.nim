## Gate Dependency Extractor
##
## Legacy module for static dependency inference. All dependency edges
## are now declared in ``gate_manifest.json`` via the ``after`` field (SSOT).
## The functions here are retained for backward compatibility but return
## empty results. New code should read dependencies from the manifest.

import core/trusted/layer_declaration
axiomLayer "gate"



