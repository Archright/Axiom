import core/trusted/layer_declaration
axiomLayer "domain"
import ../../core/trusted/axiom_pragmas
import core/vault/vault_manager_spec
## Compute stable source fingerprint for content-addressed proof hydration.
## Deterministic: identical source code always produces identical fingerprint.
##
## .. deprecated::
##   For cache key generation, prefer ``core/ast_hash.computeAstHash`` which
##   provides structural fidelity (AST-level tokens) that FNV-1a cannot
##   guarantee.  This function remains valid for non-cache use cases
##   (transitive dependency fingerprinting, certificate hydration, etc.).
## DEBT#446 self-site marker — this source-only fingerprint is the mechanism
## behind stale-cert-gate's "sourceHash-only" limitation (consumer:
## tools/stale_cert_gate, which sits outside the src/ marker-scan scope).
func computeStableSourceFingerprint*(sourceCode: string): string {.raises: [], axiomDebt: "DEBT#446", axiom: ["(assert (and (>= (str.len sourceCode) 0)))", "sourceCode.length ≥ 0"].} =
  computeSourceFingerprint(sourceCode)

## Sink-variant for move semantics where the caller has no further use of the source.
func computeStableSourceFingerprintSink*(sourceCode: sink string): string {.raises: [], axiom: ["(assert (and (>= (str.len sourceCode) 0)))", "sourceCode.length ≥ 0"].} =
  computeSourceFingerprint(sourceCode)


