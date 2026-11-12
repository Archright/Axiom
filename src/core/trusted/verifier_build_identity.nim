import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/algorithm
import std/strutils
import core/crypto/hash_kernel

## verifier_build_identity.nim — content-based verifier build identity (Phase 1B).
##
## `engineBuild` in a certificate `toolchainIdentity` must identify the VERIFIER
## BUILD INPUTS, not the repository state: the repo commit (BuildEnvGitHash)
## churns on docs-only and topic-vs-merge commits that change nothing the
## verifier compiled. The identity is therefore a canonical digest over the
## measured build-input manifest:
##
##   - every verifier source file (src/**/*.nim, excluding src/generated/ —
##     generated code is an OUTPUT of the build, not an input),
##   - the compiler flags (config.nims),
##   - the dependency pins (axiom.nimble, axiom.lock).
##
## Docs, tests, journal/baseline data and git metadata are NOT build inputs and
## are excluded — a docs-only commit keeps the identity, a verifier source change
## moves it. The manifest collector lives in tools/hermetic_build.nim (the
## generator owns the filesystem walk and freezes the result into
## src/generated/build_env.nim as `VerifierBuildId`); this module owns the pure
## composition so the generator and the tests share ONE formula.

const VerifierBuildIdScheme* = "axiom-verifier-build-v1"

func computeVerifierBuildId*(
    records: openArray[tuple[relPath, contentSha256: string]]): string {.raises: [].} =
  ## Canonical verifier build identity over a (repo-relative path, sha256 of
  ## file bytes) manifest. Deterministic regardless of caller order: records
  ## are sorted by path, then folded as "path\x1fdigest" lines into
  ## "<scheme>\n" + join("\n") → SHA-256. Empty input → "" (fail-closed: an
  ## empty manifest never yields a plausible identity).
  if records.len == 0:
    return ""
  var sorted = @records
  sorted.sort(proc(a, b: tuple[relPath, contentSha256: string]): int =
    cmp(a.relPath, b.relPath))
  var lines: seq[string]
  for r in sorted:
    lines.add(r.relPath & "\x1f" & r.contentSha256)
  sha256Hex(VerifierBuildIdScheme & "\n" & lines.join("\n"))

{.pop.}
