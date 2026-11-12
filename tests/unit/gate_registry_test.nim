import std/[options, tables, unittest]

import verification/reporter
import gate/gate_rules
import core/types/certificate_types
import core/gate/gate_evaluators

suite "Gate registry":
  test "registered semantic integrity gate applies semantic hallucination":
    var certificates = @[
      FunctionCertificate(
        functionName: "drift",
        modulePath: FilePath("src/sample.nim"),
        status: certGreen,
        reason: "fingerprint-matched",
        trusted: true
      )
    ]
    var semanticResults = initTable[string, TranslationValidationResult]()
    semanticResults["sample.drift"] = TranslationValidationResult(
      equivalent: false,
      nimSmt2: "(>= i 0)",
      leanSmt2: "(< i 0)",
      message: "synthetic semantic divergence",
      verifiedByZ3: true,
      verifiedByLean: true
    )

    let gate = runSemanticIntegrityGate(certificates, semanticResults, enabled = true)

    check gate.blockingFailures == 1
    check gate.semanticHallucinations == 1
    check gate.violations.len == 1

  test "disabled semantic integrity gate stays empty for non-symbolic runs":
    var certificates = @[
      FunctionCertificate(
        functionName: "stable",
        modulePath: FilePath("src/sample.nim"),
        status: certGreen,
        reason: "fingerprint-matched",
        trusted: true
      )
    ]
    let gate = runSemanticIntegrityGate(
      certificates,
      initTable[string, TranslationValidationResult](),
      enabled = false
    )

    check gate.blockingFailures == 0
    check gate.validatedCount == 0
    check gate.semanticHallucinations == 0
    check gate.violations.len == 0
    check certificates[0].status == certGreen
