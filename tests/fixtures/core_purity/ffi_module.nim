## ffi_module — one FFI bypass without effects, one properly declared binding,
## and one string that merely spells the token. Expect exactly one violation.
import core/trusted/layer_declaration
axiomLayer "domain"

type
  Stat {.importc: "struct stat", header: "<sys/stat.h>".} = object

proc accessPure*(path: cstring): cint {.importc: "access", noSideEffect.}

const TokenName = "importc"