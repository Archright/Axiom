import std/unittest
import std/strutils

import core/boundary/axiom_registry_loader
import core/boundary/abstract_spec_lowering
import core/boundary/abstract_spec_registry
import core/boundary/axiom_consistency_checker
import core/types/results

const registryPath = "data/axiom_registry.json"

suite "Axiom Registry Loader":
  test "loadAxiomRegistry succeeds for valid file":
    let res = loadAxiomRegistry(registryPath)
    check res.isOk()
    let registry = res.get
    check registry.version == "1.0.0"
    check registry.entries.len >= 2

  test "checksum verification passes for unmodified file":
    let res = loadAxiomRegistry(registryPath)
    check res.isOk()
    let registry = res.get
    check registry.verifyChecksum()

  test "checksum verification fails for tampered content":
    let raw = """{"version":"1.0.0","checksum":"bad","entries":[]}"""
    let computed = computeRegistryChecksum(raw)
    check computed != "bad"

  test "buildAxiomLineIndex finds name fields":
    let raw = """{"entries":[{"name":"axiom_one"},{"name":"axiom_two"}]}"""
    let idx = buildAxiomLineIndex(raw)
    check idx.len == 2
    check idx[0].name == "axiom_one"
    check idx[1].name == "axiom_two"
    check idx[0].line == 1

  test "lookupAxiomLine returns correct line":
    let idx = @[("foo", 5), ("bar", 10), ("baz", 15)]
    check lookupAxiomLine(idx, "bar") == 10
    check lookupAxiomLine(idx, "missing") == -1

  test "readJsonContextLines returns surrounding lines":
    let raw = "line1\nline2\nline3\ntarget\nline5\nline6\nline7"
    let ctx = readJsonContextLines(raw, 4, radius = 2)
    check ctx.len == 5  # lines 2-6
    check ctx[2].contains("target")
    check ctx[2].startsWith(">> ")

  test "readJsonContextLines returns empty for invalid line":
    let ctx = readJsonContextLines("hello", 999)
    check ctx.len == 0

  test "registry entries have correct types":
    let res = loadAxiomRegistry(registryPath)
    check res.isOk()
    let registry = res.get
    var foundJson = false
    var foundString = false
    for entry in registry.entries:
      if entry.typeName == "JsonNode":
        foundJson = true
        check entry.tier == atTier2
        check entry.axioms.len >= 2
      elif entry.typeName == "string":
        foundString = true
        check entry.tier == atTier2
        check entry.axioms.len >= 2
    check foundJson
    check foundString

  test "loadAxiomRegistry fails for nonexistent file":
    let res = loadAxiomRegistry("data/nonexistent_registry.json")
    check res.isErr()

  test "buildLocationReport returns valid report for known axiom":
    let res = loadAxiomRegistry(registryPath)
    check res.isOk()
    let registry = res.get
    let report = buildLocationReport(registry, "jsonnode_isWellFormed")
    check report.name == "jsonnode_isWellFormed"
    check report.location.line > 0
    check report.contextLines.len > 0

suite "Abstract Spec Lowering — Tier 1 ADT":
  test "lowerOptionAdt produces declare-datatypes":
    let lr = lowerOptionAdt("MyOption", "Int")
    check lr.tier == ltTier1
    check lr.typeName == "MyOption"
    check lr.smtDecls.len >= 1
    check lr.smtDecls[0].contains("declare-datatypes")
    check lr.smtDecls[0].contains("some-MyOption")
    check lr.smtDecls[0].contains("none-MyOption")
    check lr.smtAxioms.len >= 2

  test "lowerResultAdt produces declare-datatypes with ok/err":
    let lr = lowerResultAdt("MyResult", "Int", "String")
    check lr.tier == ltTier1
    check lr.smtDecls[0].contains("declare-datatypes")
    check lr.smtDecls[0].contains("MyResult-ok")
    check lr.smtDecls[0].contains("MyResult-err")
    check lr.smtAxioms.len >= 3

  test "classifyNimType routes Option to Tier 1":
    check classifyNimType("Option[int]") == ltTier1
    check classifyNimType("Option[string]") == ltTier1

  test "classifyNimType routes Result to Tier 1":
    check classifyNimType("Result[int, string]") == ltTier1

suite "Abstract Spec Lowering — Tier 2 Abstract":
  test "lowerAbstractSort produces declare-sort + axioms":
    let axioms = @[
      AxiomDef(name: "test_axiom", formula: "(forall ((x T)) true)", lean: "theorem test := by trivial")
    ]
    let lr = lowerAbstractSort("MyType", "(declare-sort MyType 0)", axioms)
    check lr.tier == ltTier2
    check lr.smtDecls.len == 1
    check lr.smtDecls[0].contains("declare-sort MyType 0")
    check lr.smtAxioms.len == 1
    check lr.smtAxioms[0].contains(":named test_axiom")

  test "classifyNimType routes JsonNode to Tier 2":
    check classifyNimType("JsonNode") == ltTier2

  test "classifyNimType routes string to Tier 2":
    check classifyNimType("string") == ltTier2

  test "classifyNimType routes Table to Tier 2":
    check classifyNimType("Table[string, int]") == ltTier2

suite "Abstract Spec Lowering — Tier 3 Uninterpreted":
  test "lowerUninterpreted produces declare-fun":
    let ops = @[("read", @["FilePath"], "String")]
    let lr = lowerUninterpreted("FileHandle", ops)
    check lr.tier == ltTier3
    check lr.smtDecls.len == 1
    check lr.smtDecls[0].contains("declare-fun FileHandle.read")
    check lr.smtAxioms.len == 0

  test "classifyNimType routes unknown types to Tier 3":
    check classifyNimType("CustomObject") == ltTier3
    check classifyNimType("XmlNode") == ltTier3

suite "Abstract Spec Lowering — Composite":
  test "emitSmtLib2 produces valid script":
    let lr1 = lowerOptionAdt("Opt", "Int")
    let lr2 = lowerAbstractSort("Json", "(declare-sort Json 0)", @[])
    let script = emitSmtLib2(@[lr1, lr2])
    check script.contains("(set-logic QF_S)")
    check script.contains("declare-datatypes")
    check script.contains("declare-sort Json 0")
    check script.contains("(check-sat)")

suite "Abstract Spec Registry":
  test "initAbstractSpecRegistry creates empty registry":
    let reg = initAbstractSpecRegistry()
    check registeredTypeCount(reg) == 0

  test "classifyNimType classifies types by heuristic":
    check classifyNimType("JsonNode") == ltTier2
    check classifyNimType("string") == ltTier2
    check classifyNimType("Option[int]") == ltTier1

  test "registerType adds custom type":
    var reg = initAbstractSpecRegistry()
    registerType(reg, "CustomType", ltTier3)
    check registeredTypeCount(reg) == 1
    check isRegistered(reg, "CustomType")
    check classifyNimType("CustomType") == ltTier3

  test "lowerTypeViaRegistry lowers via heuristic fallback":
    let reg = initAbstractSpecRegistry()
    let lr = lowerTypeViaRegistry(reg, "JsonNode")
    check lr.isOk()
    check lr.get.tier == ltTier2
    check lr.get.smtDecls.len >= 1
    check lr.get.smtDecls[0].contains("declare-sort JsonNode")

  test "emitRegistrySmtLib2 produces complete script":
    var reg = initAbstractSpecRegistry()
    registerType(reg, "JsonNode", ltTier2)
    registerType(reg, "string", ltTier2)
    let script = emitRegistrySmtLib2(reg)
    check script.contains("(set-logic QF_S)")
    check script.contains("declare-sort JsonNode 0")
    check script.contains("declare-sort string 0")
    check script.contains("(check-sat)")

suite "Axiom Consistency Checker":
  test "buildConsistencyQuery includes named assertions":
    let entry = AxiomRegistryEntry(
      typeName: "TestType",
      tier: atTier2,
      sortDecl: "(declare-sort TestType 0)",
      axioms: @[
        AxiomDef(name: "ax1", formula: "(forall ((x TestType)) true)", lean: ""),
        AxiomDef(name: "ax2", formula: "(forall ((x TestType)) true)", lean: "")
      ]
    )
    let query = buildConsistencyQuery(entry)
    check query.contains("(declare-sort TestType 0)")
    check query.contains("ax1")
    check query.contains("ax2")
    check query.contains("(check-sat)")

  test "buildUnsatCoreQuery includes produce-unsat-cores":
    let entry = AxiomRegistryEntry(
      typeName: "T",
      tier: atTier2,
      sortDecl: "(declare-sort T 0)",
      axioms: @[AxiomDef(name: "a1", formula: "(forall ((x T)) true)", lean: "")]
    )
    let query = buildUnsatCoreQuery(entry)
    check query.contains(":produce-unsat-cores true")
    check query.contains("(assert false)")
    check query.contains("(get-unsat-core)")

  test "parseZ3Response identifies sat/unsat":
    check parseZ3Response("sat") == acrInconsistent
    check parseZ3Response("unsat") == acrConsistent
    check parseZ3Response("unknown") == acrUnknown
    check parseZ3Response("  sat  ") == acrInconsistent

  test "parseUnsatCore extracts names from parenthesized list":
    let core = "(ax1 ax2 ax3)"
    let names = parseUnsatCore(core)
    check names.len == 3
    check names[0] == "ax1"
    check names[1] == "ax2"
    check names[2] == "ax3"

  test "parseUnsatCore handles empty core":
    let names = parseUnsatCore("()")
    check names.len == 0

  test "checkAxiomConsistency builds report from Z3 response":
    let entry = AxiomRegistryEntry(
      typeName: "T",
      tier: atTier2,
      sortDecl: "",
      axioms: @[AxiomDef(name: "a1", formula: "true", lean: "")]
    )
    let report = checkAxiomConsistency(entry, "unsat")
    check report.typeName == "T"
    check report.verdict == acrConsistent

  test "formatReport produces human-readable output":
    let entry = AxiomRegistryEntry(
      typeName: "T",
      tier: atTier2,
      sortDecl: "",
      axioms: @[]
    )
    let report = checkAxiomConsistency(entry, "sat")
    let formatted = formatReport(report)
    check formatted.contains("Type: T")
    check formatted.contains("INCONSISTENT")

  test "runConsistencyBenchmark processes Tier 2 entries":
    let res = loadAxiomRegistry(registryPath)
    check res.isOk()
    let registry = res.get
    var responses: seq[tuple[typeName: string, mainResponse: string, coreResponse: string]] = @[]
    for entry in registry.entries:
      if entry.tier == atTier2:
        responses.add((typeName: entry.typeName, mainResponse: "unsat", coreResponse: "(ax1)"))
    let benchmark = runConsistencyBenchmark(registry, responses)
    check benchmark.totalTypes >= 2
    check benchmark.consistent >= 2
    check benchmark.inconsistent == 0
    check benchmark.unknown == 0

  test "formatBenchmarkResult produces summary":
    let benchmark = ConsistencyBenchmarkResult(
      totalTypes: 2,
      consistent: 2,
      inconsistent: 0,
      unknown: 0,
      reports: @[]
    )
    let formatted = formatBenchmarkResult(benchmark)
    check formatted.contains("Total Tier 2 types: 2")
    check formatted.contains("Consistent: 2")
    check formatted.contains("=== Axiom Consistency Benchmark ===")
