import std/[options, strutils, unittest]

import core/types/pipeline_core_types
import core/logic/pipeline_trace_artifacts

suite "Universal pipeline trace artifacts":
  test "dedicated module builds traces":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(
        kind: vkGhostUpdate,
        guInfo: GhostUpdateInfo(shadowStateVariable: "version")
      ),
      sat: true,
      violatedProperty: "version monotonicity violated",
      counterExampleInput: """{"bindings":{"version":2,"payload":200,"stale_version":1,"stale_payload":100,"delta":1},"trace":{"branchPoints":["stale"],"pathSignature":"stale write"}}""",
      remediation: "assert next.version >= state.version"
    )

    let directTrace = pipeline_trace_artifacts.buildTraceReport(some(hit))
    let poc = pipeline_trace_artifacts.buildPocSnippet("nim", "commitRecord", hit)

    check directTrace.pathSignature == "stale write"
    check "reproduceGhostUpdate" in poc
