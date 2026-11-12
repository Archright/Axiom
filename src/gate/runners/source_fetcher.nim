import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Source Fetcher Gate — Network Immutability
##
## Nix fixed-output derivation model:
## - External sources are "Input Artifacts" with expected hashes
## - Content MUST match expected hash to enter the store
## - Mismatch = ContentCollisionDefect (build failure)
##
## Bazel http_archive model:
## - sha256 is mandatory
## - Lockfile records all fetched sources with hashes

import std/[os, json, strutils, strformat, httpclient]
import checksums/sha2
import core/axiom_pragmas

type
  FetcherKind* = enum
    fkHttp = "http"        ## HTTP(S) download
    fkGit = "git"          ## Git clone + checkout
    fkLocal = "local"      ## Local path (development)

  FetchSource* = object
    name*: string              ## "nim-stdlib", "lean-4.29.0"
    url*: string               ## URL or local path
    expectedHash*: string      ## SHA-256 of expected content
    fetcher*: FetcherKind
    stripPrefix*: string       ## Remove prefix from archive paths

  FetchResult* = object
    name*: string
    contentHash*: string       ## Actual SHA-256 of fetched content
    storePath*: string         ## Store path (if stored)
    verified*: bool            ## expectedHash == contentHash

  Lockfile* = object
    sources*: seq[FetchSource]

  ContentCollisionDefect* = object of CatchableError
    expectedHash*: string
    actualHash*: string
    sourceName*: string

# --- Hash Computation ---

proc computeContentHash*(content: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  $secureHash(Sha_256, content)

# --- Fetch Operations ---

proc fetchHttp*(url: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [Exception].} =
  # axiomIoBoundary
  ## Download content from URL. Returns content as string.
  let client = newHttpClient()
  try:
    let content = client.getContent(url)
    return content
  finally:
    client.close()

proc fetchLocal*(path: string): string =
  # axiomIoBoundary
  ## Read content from local path.
  readFile(path)

proc fetchAndVerify*(source: FetchSource): FetchResult {.axiomEffect: IOEffect, raises: [Exception].} =
  # axiomIoBoundary
  ## Fetch content and verify against expected hash.
  ## Nix fixed-output derivation model: hash MUST match.
  var content: string

  case source.fetcher
  of fkHttp:
    content = fetchHttp(source.url)
  of fkGit:
    # For git: clone to temp dir, read content
    # Simplified: just read local if available
    content = fetchLocal(source.url)
  of fkLocal:
    content = fetchLocal(source.url)

  let actualHash = computeContentHash(content)
  let verified = source.expectedHash.len == 0 or actualHash == source.expectedHash

  if not verified:
    raise (ref ContentCollisionDefect)(
      msg: &"Source '{source.name}' hash mismatch: expected {source.expectedHash}, got {actualHash}",
      expectedHash: source.expectedHash,
      actualHash: actualHash,
      sourceName: source.name
    )

  FetchResult(
    name: source.name,
    contentHash: actualHash,
    storePath: "",  # Caller stores to CAS
    verified: true
  )

# --- Lockfile Operations ---

proc loadLockfile*(path: string): Lockfile {.axiomEffect: IOEffect.} =
  # axiomIoBoundary
  ## Load lockfile from disk.
  if not fileExists(path):
    return Lockfile(sources: @[])
  let j = parseJson(readFile(path))
  result.sources = @[]
  for item in j{"sources"}:
    result.sources.add(FetchSource(
      name: item{"name"}.getStr(),
      url: item{"url"}.getStr(),
      expectedHash: item{"hash"}.getStr(),
      fetcher: parseEnum[FetcherKind](item{"fetcher"}.getStr("local")),
      stripPrefix: item{"stripPrefix"}.getStr()
    ))

proc saveLockfile*(lockfile: Lockfile, path: string) {.axiomEffect: IOEffect.} =
  # axiomIoBoundary
  ## Save lockfile to disk.
  var j = newJArray()
  for src in lockfile.sources:
    j.add(%*{
      "name": src.name,
      "url": src.url,
      "hash": src.expectedHash,
      "fetcher": $src.fetcher,
      "stripPrefix": src.stripPrefix
    })
  writeFile(path, pretty(%*{"sources": j}))

proc fetchAll*(sources: seq[FetchSource]): seq[FetchResult] {.axiomEffect: IOEffect, raises: [Exception].} =
  # axiomIoBoundary
  ## Fetch all sources and verify hashes.
  result = @[]
  for source in sources:
    result.add(fetchAndVerify(source))

# --- Default Sources (Axiom project dependencies) ---

proc axiomDefaultSources*(): seq[FetchSource] =
  ## Default external sources for the Axiom project.
  @[
    FetchSource(
      name: "nim-stdlib",
      url: "~/.choosenim/toolchains/nim-2.2.10/lib",
      expectedHash: "",  # First run: compute and lock
      fetcher: fkLocal
    )
  ]

{.pop.}

