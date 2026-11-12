# nim-check: skip
# Standalone subject probe: imports NOTHING from the subject. It demonstrates a
# Nim 2.2.10 language-level OBSERVATION that enables the Task 5 collision
# matrix: an object type CAN declare two fields whose names differ only by
# letter case (`foo` and `Foo`) — Nim's style-insensitive identifier matching
# does not reject this declaration, and the constructed value keeps both
# fields byte-distinct. OBSERVED OUTCOME: compiles successfully and prints
# the constructed value at runtime.
type Bad = object
  foo: int
  Foo: int

let v = Bad(foo: 1)
echo v
