## IAuditStorage — Concept interface for gate audit persistence
##
## The Domain layer depends ONLY on this concept.
## Actual JSONL file I/O is implemented by the Infrastructure layer
## (src/verification/audit_impl/jsonl_audit_store.nim).
##
## Any type that satisfies the three methods below satisfies the interface.

import core/trusted/layer_declaration
axiomLayer "domain"
import audit_types
{.push raises: [].}

type
  IAuditStorage* = concept s
    s.append(AuditEntry)
    s.recentEntries(int) is seq[AuditEntry]
    s.assessHealth(string) is HealthLevel

{.pop}
