import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/json
import std/algorithm
import std/strutils
import core/trusted/legacy_cert_classifier
import core/trusted/append_store
import core/crypto/hash_kernel

type MigrationRecord* = object
  migrationId*: string
  oldCertificateIds*: seq[string]
  newClaimIds*: seq[string]
  policyVersion*: string
  reason*: string
  oldMetricSnapshot*: string
  newMetricSnapshot*: string
  migrationInputHash*: string

func migrationInputHashFor*(certIds: seq[string]; policyVersion: string): string =
  let sortedIds = sorted(certIds)
  let joined = sortedIds.join("")
  sha256Hex(joined & policyVersion)

func makeMigrationRecord*(certIds: seq[string]; policyVersion: string; oldMetric, newMetric: string): MigrationRecord =
  let inputHash = migrationInputHashFor(certIds, policyVersion)
  let migrationId = sha256Hex(inputHash & oldMetric & newMetric)
  MigrationRecord(
    migrationId: migrationId,
    oldCertificateIds: sorted(certIds),
    newClaimIds: @[],
    policyVersion: policyVersion,
    reason: "SCHEMA_RECLASSIFICATION",
    oldMetricSnapshot: oldMetric,
    newMetricSnapshot: newMetric,
    migrationInputHash: inputHash
  )

func countLegacy*(nodes: seq[JsonNode]): int =
  for node in nodes:
    if classifyLegacyCert(node):
      result += 1

proc appendMigrationRecord*(storePath: string; rec: MigrationRecord): bool =
  let obj = newJObject()
  obj.add("migrationId", %rec.migrationId)
  obj.add("oldCertificateIds", %rec.oldCertificateIds)
  obj.add("newClaimIds", %rec.newClaimIds)
  obj.add("policyVersion", %rec.policyVersion)
  obj.add("reason", %rec.reason)
  obj.add("oldMetricSnapshot", %rec.oldMetricSnapshot)
  obj.add("newMetricSnapshot", %rec.newMetricSnapshot)
  obj.add("migrationInputHash", %rec.migrationInputHash)
  appendRecord(storePath, $obj)

{.pop.}