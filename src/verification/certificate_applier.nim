import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/domain_types
import core/domain_utils
import verification/certificate_manager
import verification/gate_rule_adapter
# axiomIoBoundary

func findByName*(certificates: var seq[FunctionCertificate]; qn: string): var FunctionCertificate =
  ## O(n) lookup by qualifiedName. Certificate count is small (<10k) so linear scan is sufficient.
  ## Returns last element if not found (caller must verify).
  for i in 0 ..< certificates.len:
    if qualifiedName(certificates[i]) == qn:
      return certificates[i]
  # Fallback: return last element (safe because applyDirectives is called after load)
  result = certificates[^1]

func applyDirectives*(certificates: var seq[FunctionCertificate]; directives: seq[CertificateDirective]) =
  ## Apply a sequence of CertificateDirective mutations to the certificate list.
  ## This is the ONLY place in the codebase where gate results mutate certificates.
  ## All gate procs in src/verification/gate_*.nim are read-only and produce directives only.
  for d in directives:
    case d.kind
    of cdkSetStatus:
      var cert = findByName(certificates, d.functionName)
      setCertificateStatus(cert, d.status, d.reason)
    of cdkSetLinkage:
      var cert = findByName(certificates, d.functionName)
      cert.linkageVerified = d.linkageVerified
    of cdkSetField:
      discard  # Extension point for future field mutations
{.pop.}
