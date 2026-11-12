# nim-check: skip
# Standalone subject probe: imports serialization/object_serialization from the
# OUT-OF-TREE pinned nimble pkgs2 package (Zero-Footprint — the subject and its
# deps are never vendored into this repo), compiled and run with an explicit
# --path to the pinned package; it cannot resolve that import in repo context by
# design. Integrity is verified by executing it against the pinned package (see
# field_probe_output.txt and build_command.txt).
# Marker + rationale follow the established repo convention:
# experiments/bug-verdict-e2e/cout_probe.nim.
## field_probe_abc.nim — variant matching the test's object shape:
## three string fields named a, b, c.
import serialization/object_serialization

type Probe = object
  a: string
  b: string
  c: string

const n = Probe.totalSerializedFields
static: doAssert n == 3, "totalSerializedFields drift: " & $n
static: echo "totalSerializedFields = ", n
enumAllSerializedFields(Probe):
  static: echo "field: ", fieldName

echo "field_probe_abc: OK (all assertions passed)"
