import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Measured content digests — file-content hashing helpers for the
## verification boundary.
##
## Structural repair note (LCOM): these two procs moved out of
## `lean_kernel_boundary.nim` so the trust-boundary module stays about the
## canonical sink + opaque receipt semantics. Both are called only from that
## module's digest compositions — same signatures, same bodies, same
## fail-closed component values; only the module boundary moved.
##
## `lake` is a ~13MB binary and the digest is sha256Hex over its bytes, which
## the pure-Nim SHA-256 implementation runs at a few MB/s — ~4.6s per call on
## the 2-vCPU CI runner. The composition in lean_kernel_boundary is invoked
## once per evidence artifact (per funcDef subject binding + per dual-write),
## so the same binary bytes would be re-hashed dozens of times per run for one
## identical answer.
##
## The memo key is the content identity the digest is a function of —
## (path, size, last write time) — not a run flag, so any change to the bytes
## invalidates the entry and the returned value is always byte-identical to a
## fresh hash. Digests are content, not time: memoizing never weakens the
## binding, it only stops re-proving the same bytes.
##
## threadvar, not a plain global: a GC'ed module global would make callers
## non-gcsafe and infect every gcsafe caller in the kernel chain. A threadvar
## is thread-local, so the memo is per-thread by construction — a sharded
## runner would compute once per shard, still correct.

import std/[os, times]
import core/axiom_pragmas
import core/crypto/hash_kernel

axiomIoBoundary()

proc measuredFileDigest*(path: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Content digest of one measured file; "" when unmeasurable. "" is its
  ## own component value — it can never pass as, or collide with, a real
  ## sha256 measurement.
  if fileExists(path):
    try:
      return sha256Hex(readFile(path))
    except CatchableError: # bestEffort("""unmeasurable file — "" can never collide with a real sha256""")
      discard
  ""

type BinaryDigestMemo = tuple[cwd, path: string, size: BiggestInt,
                              mtime: Time, digest: string]

var binaryDigestMemo {.threadvar.}: seq[BinaryDigestMemo]

proc measuredBinaryDigest*(path: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256Hex of the binary at `path`, memoized on (cwd, path, size, mtime).
  ## "" for an absent or unreadable path — the same fail-closed component
  ## value the unmemoized composition produced.
  ## `cwd` is part of the key so a relative `path` can never alias the same
  ## bytes across two working directories.
  if path.len == 0:
    return ""
  var info: FileInfo
  var cwd = ""
  try:
    cwd = getCurrentDir()
    if not fileExists(path):
      return ""
    info = getFileInfo(path)
  except CatchableError:
    return ""
  for entry in binaryDigestMemo:
    if entry.cwd == cwd and entry.path == path and entry.size == info.size and
        entry.mtime == info.lastWriteTime:
      return entry.digest
  var digest = ""
  try:
    digest = sha256Hex(readFile(path))
  except CatchableError:
    return ""
  if digest.len > 0:
    binaryDigestMemo.add((cwd, path, info.size, info.lastWriteTime, digest))
  digest

{.pop.}
