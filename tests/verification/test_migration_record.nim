import std/[json, os, strutils]
import core/trusted/migration_record
import core/trusted/legacy_cert_classifier
import core/trusted/append_store

proc main() =
  echo "=== MigrationRecord Tests ==="

  # Test 1: migrationInputHashFor is deterministic and order-insensitive
  let hash1 = migrationInputHashFor(@["cert-a", "cert-b"], "v1")
  let hash2 = migrationInputHashFor(@["cert-b", "cert-a"], "v1")
  doAssert hash1 == hash2, "migrationInputHashFor must be order-insensitive"
  let hash3 = migrationInputHashFor(@["cert-a", "cert-b"], "v1")
  doAssert hash1 == hash3, "migrationInputHashFor must be deterministic"
  echo "  [PASS] migrationInputHashFor is deterministic and order-insensitive"

  # Test 2: countLegacy correctly counts classifyLegacyCert==true
  let legacyNode1 = parseJson("""{"schemaVersion":"1","status":"certGreen"}""")
  let legacyNode2 = parseJson("""{"schemaVersion":"2","claimId":"c1","specificationId":"s1","status":"certZ3Verified"}""")
  let legacyNode3 = parseJson("""{"status":"certPending"}""")
  let nonLegacyNode = parseJson("""{"schemaVersion":"2","claimId":"c2","specificationId":"s2","status":"certGreen"}""")
  let nodes = @[legacyNode1, legacyNode2, legacyNode3, nonLegacyNode]
  let nLegacy = countLegacy(nodes)
  doAssert nLegacy == 2, "countLegacy should return 2, got " & $nLegacy
  echo "  [PASS] countLegacy correctly counts 2 legacy out of 4 nodes"

  # Test 3: makeMigrationRecord sets reason and migrationId reproducibly
  let oldSnapshot = readFile("data/baseline.json")
  let newSnapshot = """{"vkdFixed4":"0.0000","verifiedFunctions":1,"vksTotal":23}"""
  let rec = makeMigrationRecord(@["cert-b", "cert-a"], "v1", oldSnapshot, newSnapshot)
  doAssert rec.reason == "SCHEMA_RECLASSIFICATION", "reason must be SCHEMA_RECLASSIFICATION"
  doAssert rec.oldCertificateIds == @["cert-a", "cert-b"], "oldCertificateIds must be sorted"
  doAssert rec.newClaimIds == @[], "newClaimIds must be empty"
  doAssert rec.policyVersion == "v1", "policyVersion must be v1"
  doAssert rec.migrationInputHash.len > 0, "migrationInputHash must be non-empty"
  doAssert rec.migrationId.len > 0, "migrationId must be non-empty"
  let rec2 = makeMigrationRecord(@["cert-b", "cert-a"], "v1", oldSnapshot, newSnapshot)
  doAssert rec.migrationId == rec2.migrationId, "migrationId must be reproducible"
  echo "  [PASS] makeMigrationRecord sets reason, sorted IDs, reproducible migrationId"

  # Test 4: appendMigrationRecord round-trip
  let tmpPath = "/tmp/axiom_migration_test.jsonl"
  if fileExists(tmpPath):
    removeFile(tmpPath)
  let appended = appendMigrationRecord(tmpPath, rec)
  doAssert appended == true, "appendMigrationRecord must return true"
  let records = readRecords(tmpPath)
  doAssert records.len == 1, "readRecords should return 1 record, got " & $records.len
  let parsed = parseJson(records[0])
  doAssert parsed["migrationId"].getStr() == rec.migrationId, "round-trip must preserve migrationId"
  doAssert parsed["reason"].getStr() == "SCHEMA_RECLASSIFICATION", "round-trip must preserve reason"
  doAssert parsed["migrationInputHash"].getStr() == rec.migrationInputHash, "round-trip must preserve migrationInputHash"
  removeFile(tmpPath)
  echo "  [PASS] appendMigrationRecord round-trip preserves migrationId"

  echo "=== MigrationRecord Tests OK ==="

main()