## Lean LSP Future Utility — extracts value from Future[JsonNode].
## Separate module WITHOUT {raises:[]} pragma.
## Uses type-punning to access Future.result field via memory offset,
## avoiding Nim's implicit 'result' variable shadowing issue.
import core/trusted/layer_declaration
axiomLayer "domain"

import std/json
import std/asyncfutures

## Type-punning struct: same memory layout as Future[JsonNode]'s result field.
## Both RootRef and JsonNode are ref objects (pointers), so sizes match.
type ResultAccessor = object
  payload*: RootRef

## Extract value from a Future[JsonNode].
## Casts the Future pointer to ResultAccessor to read the result field
## at its memory offset without using the reserved 'result' identifier.
proc getFutureValue*(fut: Future[JsonNode]): JsonNode {.raises: [CatchableError].} =
  let accessor = cast[ptr ResultAccessor](fut)
  ## Cast RootRef to pointer, then to ptr JsonNode, then deref.
  let rawPtr = cast[pointer](accessor[].payload)
  let jsonPtr = cast[ptr JsonNode](rawPtr)
  result = jsonPtr[]
