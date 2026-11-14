import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Shared build-provenance self-check (SourceCoherence) — PURE kernel.
##
## Each ci-compile binary (ax, gate_hook, precompile_gates, install_ax_cas)
## embeds the deterministic src-tree hash (BuildSourceHash,
## src/generated/build_env.nim — generated at build time by bin/hermetic_build)
## and can re-derive the live tree hash on demand. The B-layer cache restore
## probe executes every restored ci-compile binary with --check-provenance
## against a trusted tree materialized OUTSIDE the payload (git archive of the
## b-identity tree): a payload binary that was not built from the key's tree
## FATALs (exit 1) and the whole B payload is discarded (fail-closed).
##
## This module carries the pure judgment only: the canonical fingerprint
## algorithm and the probe-request shape. The boundary effects — tree walk,
## file reads, FATAL reporting — live in src/infrastructure/provenance_probe.nim
## and must stay there: src/core purity is ratcheted by the core_purity gate
## (R1/R2 admit no in-source exemption), so any I/O primitive here is a
## regression, not a boundary.
##
## SSOT: sourceTreeDigest below is the single runtime composition of the source
## fingerprint. tools/hermetic_build.nim computeDeterministicSourceHash and the
## NimScript mirror in config.nims are the build-time twins — all three must
## stay in lock-step (byte-for-byte identical ordering + separators + digest).
##
## Formula v1 (compositional, path-bound):
##
##   fileDigest(p) = $hash(bytes(p))
##   treeDigest    = "vs1-tree-hash/1:" & $hash(
##                     "vs1-tree-hash/1\n" &
##                     Σ_{p sorted by relPath} relPath(p) & "\0" & fileDigest(p) & "\n")
##
## Why: the pre-vs1 formula `$hash(concat(contents))` was not decomposable (a
## cache could not reuse a per-file digest without re-reading everything) and
## did not bind paths (file-boundary ambiguity: "ab"+"c" ≡ "a"+"bc"). Paths now
## enter the digest; the formula id is both folded into the stream and prefixed
## onto the value, so old (decimal) and new values are distinguishable in every
## persisted copy (build_env, run manifests, logs, B-probe output).
##
## The digest primitive is std/hashes on purpose: config.nims runs in the
## NimScript VM where std/sha1|sha2 do not compile (config.nims:392-393), and
## the VM and compiled `$hash` agree byte-for-byte (measured 2026-11-12).

import std/[algorithm, hashes, strutils]

const ProvenanceSelfCheckFlag* = "--check-provenance"

const BuildSourceHashFormula* = "vs1-tree-hash/1"
  ## Formula identifier. Folded into the digest stream and prefixed onto the
  ## value; must match the build-time twins literally.

func isProvenanceSelfCheckRequest*(args: seq[string]): bool {.raises: [].} =
  ## True when argv asks ONLY for the provenance self-check (probe contract —
  ## never triggered by any other invocation shape).
  args.len == 1 and args[0] == ProvenanceSelfCheckFlag

func byRelPathDigest(a, b: tuple[relPath: string, fileDigest: string]): int {.raises: [].} =
  cmp(a.relPath, b.relPath)

func fileContentDigest*(content: string): string {.raises: [].} =
  ## Per-file content digest. std/hashes is the only digest primitive that
  ## also compiles in the NimScript VM (config.nims twin).
  $hash(content)

func sourceTreeDigest*(
    relFiles: seq[tuple[relPath: string, fileDigest: string]]): string {.raises: [].} =
  ## Compositional, path-bound fingerprint over per-file digests. Sorts by
  ## relative path, folds "relPath\0fileDigest\n" lines under the formula id,
  ## and digests the stream. The outer digest is always recomposed from the
  ## caller's live path set — a cache may only supply per-file digests.
  var stream = BuildSourceHashFormula & "\n"
  for f in relFiles.sorted(byRelPathDigest):
    stream.add(f.relPath)
    stream.add('\0')
    stream.add(f.fileDigest)
    stream.add('\n')
  BuildSourceHashFormula & ":" & $hash(stream)

func extractBuildEnvField*(content, field: string): string {.raises: [].} =
  ## Read one `  <field>* = "<value>"` line out of a build_env.nim body.
  ## Returns "" when the field is absent — callers treat empty as "no
  ## observation", never as a matching identity.
  let prefix = field & "* = \""
  for line in content.splitLines():
    let trimmed = line.strip()
    if not trimmed.startsWith(prefix): continue
    let parts = trimmed.split('"')
    if parts.len >= 3: return parts[1]
    return ""
  result = ""

func hashSourceContents*(
    relFiles: seq[tuple[relPath: string, content: string]]): string {.raises: [].} =
  ## Convenience wrapper for callers that already hold file contents (build
  ## twin, tests): per-file digest, then the compositional tree digest.
  var entries: seq[tuple[relPath: string, fileDigest: string]] = @[]
  for f in relFiles:
    entries.add((f.relPath, fileContentDigest(f.content)))
  sourceTreeDigest(entries)
