import std/[os, strformat]
import ../src/verification/cert_promotion

## P0.3 reclassification runner — derives each canonical certificate's `status`
## from its stored evidence (certificateEvidenceFromJson / tierFromEvidence /
## tierToStatusString) and rewrites overstated statuses (e.g. certGreen →
## certZ3Verified when leanCompilerVerified=false). Run from repo root:
##   nim c -r tools/reclassify_certs.nim

let result = reclassifyCertificates()
echo fmt"reclassified={result.reclassified} skipped={result.skipped} failed={result.failed}"
