import std/unittest
import std/strutils
import core/spec/spec_generator_types
import core/spec/spec_generator_helpers
import core/spec/spec_generator_main

suite "mapNimTypeToLean contract":
  test "maps int to Int":
    check mapNimTypeToLean("int") == "Int"

  test "maps bool to Bool":
    check mapNimTypeToLean("bool") == "Bool"

  test "maps string to String":
    check mapNimTypeToLean("string") == "String"

  test "maps Natural to Nat":
    check mapNimTypeToLean("Natural") == "Nat"

  test "passes through unrecognized type":
    check mapNimTypeToLean("SomeType") == "SomeType"

suite "mapNimTypeToLean contract":
  test "maps Result[T, E] to Result T E":
    check mapNimTypeToLean("Result[int, string]") == "Result Int String"
    check mapNimTypeToLean("Result[bool, float]") == "Result Bool Float"

suite "renderTypeMappingProofObligation contract":
  test "renders theorem for int type with auto-proof fallback":
    let cert = TypeMappingCertificate(
      nimType: "int",
      leanType: "Int",
      smtSort: "Int",
      mappingProofObligation: "int_identity",
      verified: true,
      sourceHash: "abc123"
    )
    let rendered = renderTypeMappingProofObligation(cert)
    check rendered.len > 0
    check rendered.contains("theorem")
    check rendered.contains("Int")
    check rendered.contains("first | intros; rfl")
