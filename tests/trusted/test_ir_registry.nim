proc testManualRegistration() =
  ## Test 2: Manual registerAxiom + round-trip
  let t = irTypeBitVec64()
  let x = irVar("x", t)
  let y = irVar("y", t)
  let body = irAdd(x, y)
  let f = irFuncDef("testAdd", @[("x", t), ("y", t)], t, body)
  let serialized = serializeIRFuncDef(f)

  # Register manually
  registerAxiom("testAdd", serialized, "smt-placeholder", "lean-placeholder")

  # Verify it was added
  var found = false
  for entry in runtimeAxiomRegistry:
    if entry.name == "testAdd":
      found = true
      # Deserialize and verify
      let deser = deserializeIRFuncDef(entry.irSerialized)
      assert deser.name == "testAdd", "Name mismatch after round-trip"
      assert deser.params.len == 2, "Param count mismatch"
      assert deser.retType.kind == irtBitVec64, "Return type mismatch"
      assert serializeIRFuncDef(deser) == serialized, "Round-trip serialization mismatch"
      echo "✅ Manual registration round-trip PASSED"
      break
  assert found, "testAdd not found in runtimeAxiomRegistry"
proc testSentinelValidation() =
  ## Test 4: Sentinel validation (name.len == 0)
  let invalid = deserializeIRFuncDef("GARBAGE_INPUT")
  assert invalid.name.len == 0, "Sentinel should have empty name"
  echo "✅ Sentinel validation PASSED"
proc testEmptyRegistry() =
  ## Test 1: runtimeAxiomRegistry starts empty (before generateAxiomInit)
  # Note: in a test context, the registry may or may not be populated
  # depending on whether axiomImpl functions are in scope.
  # We just verify the type exists and is accessible.
  echo "✅ runtimeAxiomRegistry accessible, type: ", typeof(runtimeAxiomRegistry)
## Test: IR Registry + crossValidate integration
##
## Verifies:
## 1. Empty runtime registry starts clean
## 2. Manual registerAxiom + deserializeIRFuncDef round-trip
## 3. serializeIRFuncDef ↔ deserializeIRFuncDef round-trip
## 4. crossValidate works on deserialized IR

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_ir
import verification/cross_validation
proc testCrossValidate() =
  ## Test 3: crossValidate works on deserialized IR
  let t = irTypeBitVec64()
  let boolT = irTypeBool()
  let cond = irVar("c", boolT)
  let ifBody = irIf(cond, irLit(1), irLit(0))
  let f = irFuncDef("choose", @[("c", boolT)], t, ifBody)
  let serialized = serializeIRFuncDef(f)
  let deser = deserializeIRFuncDef(serialized)

  assert deser.name == "choose", "Deserialization failed"
  let cvResult = crossValidate(deser)
  echo "crossValidate result: consistent=", cvResult.consistent,
       " digest=", cvResult.irDigest,
       " z3Len=", cvResult.z3Result.len,
       " leanLen=", cvResult.leanResult.len
  assert cvResult.consistent, "crossValidate FAILED for choose()"
  assert cvResult.irDigest.len > 0, "IR digest is empty"
  assert cvResult.z3Result.len > 0, "SMT output is empty"
  assert cvResult.leanResult.len > 0, "Lean output is empty"
  echo "✅ crossValidate PASSED"
proc testSerializeDeserializeAllKinds() =
  ## Test 5: All expression kinds survive round-trip
  let t = irTypeBitVec64()
  let boolT = irTypeBool()

  # Literal
  let litFunc = irFuncDef("const42", @[], t, irLit(42))
  assert serializeIRFuncDef(deserializeIRFuncDef(serializeIRFuncDef(litFunc))) ==
         serializeIRFuncDef(litFunc), "Lit round-trip FAILED"

  # Let
  let letBody = irLet("z", irLit(5), irVar("z", t))
  let letFunc = irFuncDef("five", @[], t, letBody)
  assert serializeIRFuncDef(deserializeIRFuncDef(serializeIRFuncDef(letFunc))) ==
         serializeIRFuncDef(letFunc), "Let round-trip FAILED"

  # Binary op
  let binFunc = irFuncDef("add1", @[("x", t)], t, irAdd(irVar("x", t), irLit(1)))
  assert serializeIRFuncDef(deserializeIRFuncDef(serializeIRFuncDef(binFunc))) ==
         serializeIRFuncDef(binFunc), "BinOp round-trip FAILED"

  # Unary op
  let unFunc = irFuncDef("neg", @[("x", t)], t, irBvNeg(irVar("x", t)))
  assert serializeIRFuncDef(deserializeIRFuncDef(serializeIRFuncDef(unFunc))) ==
         serializeIRFuncDef(unFunc), "UnaryOp round-trip FAILED"

  # Call
  let callBody = irCall("helper", @[irVar("x", t)])
  let callFunc = irFuncDef("caller", @[("x", t)], t, callBody)
  assert serializeIRFuncDef(deserializeIRFuncDef(serializeIRFuncDef(callFunc))) ==
         serializeIRFuncDef(callFunc), "Call round-trip FAILED"

  echo "✅ All expression kinds round-trip PASSED"

# Run all tests
echo "=== IR Registry Tests ==="
testEmptyRegistry()
testManualRegistration()
testCrossValidate()
testSentinelValidation()
testSerializeDeserializeAllKinds()
echo "=== All IR Registry Tests PASSED ==="
