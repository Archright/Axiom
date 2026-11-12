## Test: serialize/deserialize round-trip for IRFuncDef
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_ir
proc testRoundTrip() =
  # Build a simple IR function: func add(x: BV64, y: BV64): BV64 = x + y
  let t = irTypeBitVec64()
  let x = irVar("x", t)
  let y = irVar("y", t)
  let body = irAdd(x, y)
  let f = irFuncDef("add", @[("x", t), ("y", t)], t, body)

  # Serialize
  let serialized = serializeIRFuncDef(f)
  echo "Serialized: ", serialized

  # Deserialize
  let deserialized = deserializeIRFuncDef(serialized)
  echo "Deserialized name: ", deserialized.name

  # Round-trip check
  let reserialized = serializeIRFuncDef(deserialized)
  echo "Re-serialized: ", reserialized

  assert deserialized.name == "add", "Name mismatch"
  assert deserialized.params.len == 2, "Param count mismatch"
  assert deserialized.retType.kind == irtBitVec64, "Return type mismatch"
  assert reserialized == serialized, "Round-trip FAILED: " & reserialized & " != " & serialized
  echo "✅ Round-trip PASSED"

  # Test sentinel on invalid input
  let invalid = deserializeIRFuncDef("GARBAGE")
  assert invalid.name.len == 0, "Sentinel failed for invalid input"
  echo "✅ Sentinel PASSED"

  # Test sentinel on empty string
  let empty = deserializeIRFuncDef("")
  assert empty.name.len == 0, "Sentinel failed for empty input"
  echo "✅ Empty sentinel PASSED"

  # Test with literal body
  let litFunc = irFuncDef("const42", @[], t, irLit(42))
  let litSer = serializeIRFuncDef(litFunc)
  let litDeser = deserializeIRFuncDef(litSer)
  assert serializeIRFuncDef(litDeser) == litSer, "Literal round-trip FAILED"
  echo "✅ Literal round-trip PASSED"

  # Test with if expression
  let boolT = irTypeBool()
  let cond = irVar("c", boolT)
  let ifBody = irIf(cond, irLit(1), irLit(0))
  let ifFunc = irFuncDef("choose", @[("c", boolT)], t, ifBody)
  let ifSer = serializeIRFuncDef(ifFunc)
  let ifDeser = deserializeIRFuncDef(ifSer)
  assert serializeIRFuncDef(ifDeser) == ifSer, "If round-trip FAILED"
  echo "✅ If round-trip PASSED"

  echo "All tests passed!"

testRoundTrip()
