import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Verification Scope Schema Version SSOT (L0)
## Canonical schema_version contract for `data/verification_scope.lock`.
## Both the lock writer (`buildScopeLockJson`) and the hermetic reader
## (`hermetic_build.verifyScopeLock`) MUST reference this constant instead of
## hardcoding an integer, so schema drift is structurally impossible.
##
## NOTE: This is the *lock schema* version. It is intentionally DECOUPLED from
## `deterministic_cas_key.VERIFICATION_SCHEMA_VERSION` (the CAS cache-identity
## version). Do NOT unify them — they version different contracts.

const VERIFICATION_SCOPE_SCHEMA_VERSION* = 3

{.pop.}