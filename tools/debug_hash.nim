import core/trusted/layer_declaration
axiomLayer "tools"
import std/os
const h = staticExec("ls ../../../proofs/GateInvariants/*.lean | sort | xargs sha256sum | sha256sum")
echo h
