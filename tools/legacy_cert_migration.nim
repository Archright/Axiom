## tools/legacy_cert_migration.nim
## Legacy Certificate Migration Tool — Migrates proof_vault certificates
## to use canonical IR hashes.
##
## Scans logs/proof_vault/*.json, computes new canonical irHash from
## serialized IR fields, renames files, updates irHash field, and reports
## statistics.
##
## Safety features:
##   - --dry-run: preview without changes
##   - --backup: create .bak files before modification
##   - Idempotent: safe to run multiple times
##
## Build & Run:
##   export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
##   nim c tools/legacy_cert_migration.nim
##   ./tools/legacy_cert_migration [--dry-run] [--backup]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils, parseopt]
import checksums/sha2

const
  ProofVaultDir = "logs/proof_vault"

type
  CertFields = object
    irHash: string
    sourceHash: string
    functionName: string
    modulePath: string
    verificationTier: string
    status: string
    fingerprint: string
    rawNode: JsonNode
    fileName: string

  MigrationStats = object
    total: int
    migrated: int
    skipped: int
    errors: seq[string]
    legacyMarked: int

proc isCertificateFile(path: string): bool =
  path.endsWith(".json") and not path.contains("backup")

proc computeCanonicalIrHash(cert: JsonNode): string =
  let
    fn_name = cert{"functionName"}.getStr("")
    mod_path = cert{"modulePath"}.getStr("")
    tier = cert{"verificationTier"}.getStr("none")
    status = cert{"status"}.getStr("certUnknown")
    fingerprint = cert{"fingerprint"}.getStr("")
    sourceHash = cert{"sourceHash"}.getStr("")

  let canonicalPayload = fn_name & "|" & mod_path & "|" & tier & "|" & status & "|" & fingerprint & "|" & sourceHash

  var hasher = initSha_256()
  hasher.update(canonicalPayload)
  result = $hasher.digest()

proc scanCertificates(vaultDir: string): seq[CertFields] =
  if not dirExists(vaultDir):
    return @[]
  for kind, path in walkDir(vaultDir):
    if kind != pcFile: continue
    if not isCertificateFile(path): continue
    let content = readFile(path)
    try:
      let node = parseJson(content)
      if node.kind != JObject: continue
      result.add(CertFields(
        irHash: node{"irHash"}.getStr(""),
        sourceHash: node{"sourceHash"}.getStr(""),
        functionName: node{"functionName"}.getStr(""),
        modulePath: node{"modulePath"}.getStr(""),
        verificationTier: node{"verificationTier"}.getStr("none"),
        status: node{"status"}.getStr("certUnknown"),
        fingerprint: node{"fingerprint"}.getStr(""),
        rawNode: node,
        fileName: extractFilename(path)
      ))
    except JsonParsingError:
      stderr.writeLine("[WARN] Invalid JSON: " & path)
    except CatchableError as e:
      stderr.writeLine("[WARN] Error reading " & path & ": " & e.msg)

proc runMigration(dryRun, backup: bool) =
  echo "=== Axiom Legacy Certificate Migration Tool ==="
  echo "Migrating certificates in " & ProofVaultDir & " to canonical IR hashes"
  if dryRun: echo "  [DRY RUN] No changes will be written"
  if backup: echo "  [BACKUP MODE] .bak files will be created"

  let certs = scanCertificates(ProofVaultDir)
  var stats = MigrationStats(total: certs.len)

  echo ""
  echo "Found " & $stats.total & " certificate(s)"
  echo ""

  if stats.total == 0:
    echo "No certificates to migrate. Exiting."
    return

  for idx, cert in certs:
    let progress = $(idx + 1) & "/" & $stats.total
    let newHash = computeCanonicalIrHash(cert.rawNode)
    let oldHash = cert.irHash

    if newHash == oldHash:
      echo "  [" & progress & "] SKIP: " & cert.fileName & " (irHash already canonical)"
      stats.skipped += 1
      continue

    let oldPath = ProofVaultDir / (oldHash & ".json")
    let newPath = ProofVaultDir / (newHash & ".json")

    if not fileExists(oldPath):
      echo "  [" & progress & "] ERROR: " & cert.fileName & " (file not found: " & oldPath & ")"
      stats.errors.add(cert.fileName & ": file not found")
      continue

    if dryRun:
      echo "  [" & progress & "] DRY: " & cert.fileName
      echo "         " & oldHash & " -> " & newHash
      stats.migrated += 1
      continue

    try:
      if backup:
        let bakPath = oldPath & ".bak"
        copyFile(oldPath, bakPath)
        echo "  [" & progress & "] BACKUP: " & bakPath

      var updatedCert = cert.rawNode
      updatedCert["irHash"] = newJString(newHash)
      updatedCert["legacyIrHash"] = newJString(oldHash)
      let prettyJson = updatedCert.pretty()

      if fileExists(newPath):
        stderr.writeLine("  [" & progress & "] WARN: target file exists, overwriting: " & newPath)

      writeFile(newPath, prettyJson & "\n")
      removeFile(oldPath)

      echo "  [" & progress & "] OK: " & cert.fileName
      echo "         " & oldHash & " -> " & newHash
      stats.migrated += 1

    except CatchableError as e:
      echo "  [" & progress & "] ERROR: " & cert.fileName & " — " & e.msg
      stats.errors.add(cert.fileName & ": " & e.msg)

  echo ""
  echo "=== Migration Summary ==="
  echo "  Total:     " & $stats.total
  echo "  Migrated:  " & $stats.migrated
  echo "  Skipped:   " & $stats.skipped
  echo "  Errors:    " & $stats.errors.len

  if stats.errors.len > 0:
    echo ""
    echo "  Errors:"
    for err in stats.errors:
      echo "    " & err

  echo ""
  if dryRun:
    echo "  [DRY RUN] No changes were written."
  elif stats.errors.len == 0:
    echo "  Migration completed successfully."
    if backup:
      echo "  Backup files (*.json.bak) remain in " & ProofVaultDir
  else:
    echo "  Migration completed with errors."

proc main() =
  var dryRun = false
  var backup = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "dry-run", "d": dryRun = true
      of "backup", "b": backup = true
      of "help", "h":
        echo "Usage: legacy_cert_migration [OPTIONS]"
        echo ""
        echo "Migrates proof_vault certificates to canonical IR hashes."
        echo ""
        echo "Options:"
        echo "  --dry-run, -d    Preview changes without writing"
        echo "  --backup, -b     Create .bak files before modification"
        echo "  --help, -h       Show this help"
        echo ""
        echo "Build:"
        echo "  nim c tools/legacy_cert_migration.nim"
        return
    else: discard

  runMigration(dryRun, backup)

when isMainModule:
  main()
