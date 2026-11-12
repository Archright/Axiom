import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
{.checks: off.}

import verification/ast_extractor
import verification/fingerprint_engine
import core/utils/file_utils
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

proc fingerprintFunction*(sourcePath, name: string): tuple[fingerprint: string; body: string] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"], sideEffect.} =
  var body = ""
  try:
    let source = readFileSafe(sourcePath)
    let extractedRes = extractFunctionBody(source, name)
    if extractedRes.ok:
      let extracted = extractedRes.value
      if extracted.found and extracted.body.len > 0:
        body = extracted.body
    if body.len == 0:
      body = if source.len > 2000: source[0..<2000] else: source
  except CatchableError: # axiom:best-effort(graceful AST parse degradation)
    discard
  let fingerprint = computeFingerprint(body, @[])
  result = (fingerprint: fingerprint, body: body)
{.pop.}
