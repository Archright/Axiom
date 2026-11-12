# nim-check: skip
# Standalone subject probe: imports serialization/object_serialization from the
# OUT-OF-TREE pinned nimble pkgs2 package (Zero-Footprint — the subject and its
# deps are never vendored into this repo), compiled and run with an explicit
# --path to the pinned package; it cannot resolve that import in repo context by
# design. Integrity is verified by executing it against the pinned package (see
# field_probe_output.txt and build_command.txt).
# Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim.
## field_probe.nim — B1 input-integrity probe (alpha/beta/gamma variant)
## Pins: which serialization/object_serialization.nim the compiler consumes,
## totalSerializedFields value, and enumAllSerializedFields declaration order.
## Compile+run OUTSIDE the subject repo; see build_command.txt for the exact
## invocation (cwd must NOT be under Axiom3, or nimble.lock kills discovery —
## explicit --path flags make this build cwd-independent).
import serialization/object_serialization

type Probe = object
  alpha: string
  beta: string
  gamma: string

const n = Probe.totalSerializedFields
static: doAssert n == 3, "totalSerializedFields drift: " & $n
static: echo "totalSerializedFields = ", n
enumAllSerializedFields(Probe):
  static: echo "field: ", fieldName

echo "field_probe: OK (all assertions passed)"
