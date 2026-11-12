{.push raises: [].}

import std/options
import std/unittest
import core/telemetry/metrics
import core/types/domain_types
import core/types/asi_types

suite "ValidatedAsi type-level enforcement":
  test "exportAsiFixed4 returns ValidatedAsi not string":
    let asi = exportAsiFixed4(initAsiRatio(0.1234).get(defaultAsiRatio()))
    check asi is ValidatedAsi

  test "asString extracts raw value":
    let asi = exportAsiFixed4(initAsiRatio(0.1234).get(defaultAsiRatio()))
    check asString(asi) == "0.1234"

  test "rejection boundary — out-of-range values rejected by initAsiRatio (fallback to default)":
    check asString(exportAsiFixed4(initAsiRatio(-0.5).get(defaultAsiRatio()))) == "0.0000"
    check asString(exportAsiFixed4(initAsiRatio(1.5).get(defaultAsiRatio()))) == "0.0000"

  test "4 decimal places":
    check asString(exportAsiFixed4(initAsiRatio(0.12345678).get(defaultAsiRatio()))) == "0.1235"

  test "validateUniverse passes for full-source universe":
    check validateUniverse(2414, usTotalSource) == true

  test "validateUniverse fails for certificate-only count (usTotalSource)":
    check validateUniverse(299, usTotalSource) == false

  test "validateUniverse passes for realistic kernel domain":
    check validateUniverse(46, usKernelDomain) == true

  test "validateUniverse fails for sparse kernel domain":
    check validateUniverse(5, usKernelDomain) == false

  test "computeInformationGainWeightedAsi with full coverage":
    let certs = @[
      FunctionCertificate(
        functionName: "test1",
        status: certVerifiedAxiom,
        informationGain: initAsiRatio(0.0).get(defaultAsiRatio())
      ),
      FunctionCertificate(
        functionName: "test2",
        status: certVerifiedAxiom,
        informationGain: initAsiRatio(0.0).get(defaultAsiRatio())
      )
    ]
    let universe = AsiUniverse(totalFunctions: 2)
    let score = computeInformationGainWeightedAsi(certs, universe, 0.0)
    check score.toFloat == 1.0

  test "computeInformationGainWeightedAsi with partial coverage":
    let certs = @[
      FunctionCertificate(
        functionName: "test1",
        status: certVerifiedAxiom,
        informationGain: initAsiRatio(0.0).get(defaultAsiRatio())
      )
    ]
    let universe = AsiUniverse(totalFunctions: 4)
    let score = computeInformationGainWeightedAsi(certs, universe, 0.0)
    check score.toFloat == 0.25

  test "computeInformationGainWeightedAsi with missing functions":
    let certs = @[
      FunctionCertificate(
        functionName: "test1",
        status: certVerifiedAxiom,
        informationGain: initAsiRatio(0.0).get(defaultAsiRatio())
      )
    ]
    let universe = AsiUniverse(totalFunctions: 2414)
    let score = computeInformationGainWeightedAsi(certs, universe, 0.0)
    check score.toFloat > 0.0
    check score.toFloat < 0.01

  # DEBT#202: Former deprecated compat test — now uses the canonical SSOT function.
  test "computeInformationGainWeightedAsi with 50% coverage":
    var certs = newSeq[FunctionCertificate]()
    for i in 0..<50:
      certs.add(FunctionCertificate(
        functionName: "f" & $i,
        status: certVerifiedAxiom,
        informationGain: initAsiRatio(0.0).get(defaultAsiRatio())
      ))
    let universe = AsiUniverse(totalFunctions: 100)
    let score = computeInformationGainWeightedAsi(certs, universe, 0.0)
    check score.toFloat == 0.5

{.pop.}
