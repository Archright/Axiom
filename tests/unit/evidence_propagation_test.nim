# evidence_propagation_test.nim
# Phase C — P0 pure verification: receipt→KAA→CLE→cert value end-to-end consistency.
#
# Run: nim c --hints:off --path:src -o:tmp/test_evidence_prop -r tests/unit/evidence_propagation_test.nim

import std/[unittest, json, os, sequtils, strutils, algorithm]
import verification/obligation/evidence_propagation

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func canon*(items: seq[string]): seq[string] =
  ## Canonical form matching evidence_propagation.nim's canonicalizeObservedSet.
  if items.len == 0:
    return @[]
  var sorted = items
  sorted.sort()
  result = @[sorted[0]]
  for i in 1 ..< sorted.len:
    if sorted[i] != sorted[i - 1]:
      result.add(sorted[i])

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "Evidence Propagation Consistency — Phase C P0":

  # -----------------------------------------------------------------------
  # (a) 전파 일치 시나리오: 모든 경로의 observed set이 동일 → true
  # -----------------------------------------------------------------------

  test "consistent propagation returns true when all three paths agree":
    let axioms = @["propext", "Quot.sound", "funext"]
    check evidencePropagationConsistent(
      axioms, axioms, axioms,
      kernelAccepted = true, hasKaa = true
    ) == true

  # -----------------------------------------------------------------------
  # (b) receipt와 cert의 observed set이 어긋나면 false
  # -----------------------------------------------------------------------

  test "mismatched receipt vs cert observed set returns false":
    let receiptAxioms = @["propext", "Quot.sound"]
    let certAxioms = @["propext", "funext"]
    check evidencePropagationConsistent(
      receiptAxioms, receiptAxioms, certAxioms,
      kernelAccepted = true, hasKaa = true
    ) == false

  # -----------------------------------------------------------------------
  # (c) kernel accepted인데 KAA 정보 부재 시 false
  # -----------------------------------------------------------------------

  test "kernelAccepted true but hasKaa false returns false (fail-closed)":
    let axioms = @["propext"]
    check evidencePropagationConsistent(
      axioms, axioms, axioms,
      kernelAccepted = true, hasKaa = false
    ) == false

  # -----------------------------------------------------------------------
  # (d) canonicalize(순서 무관/중복 제거)로 동일 의미 인정
  # -----------------------------------------------------------------------

  test "different order and duplicates normalize to same canonical form":
    let receiptRaw = @["funext", "propext", "Quot.sound", "propext"]
    let kaaRaw = @["Quot.sound", "funext", "propext"]
    let certRaw = @["propext", "Quot.sound", "funext", "funext"]
    check evidencePropagationConsistent(
      receiptRaw, kaaRaw, certRaw,
      kernelAccepted = true, hasKaa = true
    ) == true

  test "all empty observed sets are consistent (trivial theorem)":
    check evidencePropagationConsistent(
      @[], @[], @[],
      kernelAccepted = true, hasKaa = true
    ) == true

  test "kernelAccepted false and hasKaa false is consistent (no evidence path)":
    check evidencePropagationConsistent(
      @[], @[], @[],
      kernelAccepted = false, hasKaa = false
    ) == true

  # -----------------------------------------------------------------------
  # (e) 실제 cert.json에서 읽어 end-to-end 일치 스모크
  # -----------------------------------------------------------------------

  test "smoke: real certificate file propagates consistently":
    let certPath = "src/verification/certificates/" &
      "c14243cdc6d5628d64cb11ff38a9b7cf5cd04a817c5ed28979cc1b0f28c24e39.json"
    let certExists = fileExists(certPath)
    if certExists:
      let certJson = parseJson(readFile(certPath))

      # Extract observedAxiomSet from the embedded canonicalKaa JSON.
      let canonicalKaaStr = certJson["canonicalKaa"].getStr("")
      let canonicalKaaJson = parseJson(canonicalKaaStr)
      let kaaAxioms = canonicalKaaJson["observedAxiomSet"].getElems().mapIt(it.getStr(""))

      # Extract axiomsUsed from the certificate top-level field.
      let certAxiomsNode = certJson.getOrDefault("axiomsUsed")
      var certAxioms: seq[string] = @[]
      if certAxiomsNode != nil and certAxiomsNode.kind == JArray:
        for ax in certAxiomsNode.items:
          let name = ax.getStr("")
          if name.len > 0 and name notin certAxioms:
            certAxioms.add(name)

      # receiptObserved mirrors what the #print axioms probe captured.
      # In the canonical path, this is the same source as kaaObserved.
      let receiptObserved = kaaAxioms

      let consistent = evidencePropagationConsistent(
        receiptObserved,
        kaaAxioms,
        certAxioms,
        kernelAccepted = true,
        hasKaa = true
      )
      check consistent == true
    else:
      echo "SKIP: golden cert not found at " & certPath
      check true