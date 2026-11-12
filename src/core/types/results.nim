import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import core/trusted/axiom_pragmas_lite
import std/macros
import std/strutils
import std/typetraits
template assertHeapFreeError*(E: typedesc) =
  ## E must be a non-ref type that Nim can safely copy.
  ## supportsCopyMem is too strict — rejects objects with string/seq fields.
  ## Under ARC/ORC, all non-ref types have compiler-generated =copy hooks.
  ## Ref types are explicitly rejected (cyclic reference risk).
  static:
    assert not (E is ref),
      "Result E type '" & $E & "' is not safely copyable. " &
      "Ref types are forbidden (cyclic reference risk). " &
      "Use value types: enum, object, string, seq, or distinct."
type
  Result*[T, E] = object
    case ok*: bool
    of true:
      value*: T
    else:
      err*: E
## I Ok.
## I Err.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="1 = 1" smt="(assert (= 1 1))"
## Get.
## Error.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="1 = 1" smt="(assert (= 1 1))"
## I Ok.
## I Ok.
func isOk*[T, E](r: Result[T, E]): bool {.inline, raises: [].} =
  r.ok

## I Err.
func isErr*[T, E](r: Result[T, E]): bool {.inline, raises: [], axiom: ["(assert (and (>= depth 0) (= 1 1)))", "depth >= 0 ∧ 1 = 1"].} =
  not r.ok

## Get.
func get*[T, E](r: Result[T, E]): T {.inline, raises: [].} =
  doAssert r.ok
  r.value

## Error.
func error*[T, E](r: Result[T, E]): E {.inline, raises: [], axiom: ["(assert (and ast_parse_failed_isolated (= 1 1)))", "ast_parse_failed_isolated ∧ 1 = 1"].} =
  doAssert not r.ok
  r.err

template ok*[T](v: T): untyped =
  ## Delegate return type to caller's result type
  ## T is inferred from argument v's type
  ## E is inferred from caller's Result[T, E]
  block:
    type R = typeof(result)
    R(ok: true, value: v)
template err*[E](e: E): untyped =
  ## Delegate return type to caller's result type
  block:
    assertHeapFreeError(E)
    type R = typeof(result)
    R(ok: false, err: e)

## Compile-time type guard for Result nodes.
## 3-tier: eqIdent → exact string → endsWith (module-prefix tolerant).
func isResultType*(typeNode: NimNode): bool =
  if typeNode.kind == nnkBracketExpr:
    let head = typeNode[0]
    if head.kind == nnkIdent:
      head.eqIdent("Result")                   # 1차: Nim 공식 API
    elif head.kind == nnkSym:
      $head == "Result"                         # 2차: resolved symbol
    else:
      let reprStr = head.repr
      reprStr.endsWith("Result") and            # 3차: module prefix
        (reprStr.len == "Result".len or reprStr[^7] == '.')
  else: false
macro `??`*[T, E](r: Result[T, E]): untyped =
  ## Compile-time safe unwrap-or-early-return.
  ## Guards against non-Result types and module-prefixed type names.
  ## No block: wrapper — err() template needs access to caller's `result`.
  let resType = r.getTypeInst()
  if isResultType(resType):
    result = quote do:
      if `r`.isErr():
        return err(`r`.error)
      `r`.get()
  else:
    error("`??` applied to non-Result type: " & resType.repr, r)

## Map Err.
## Map — transform success value, propagate error
## FlatMap — chain Result-returning operations
## AndThen — apply side-effectful proc on success, propagate error
## GetOrDefault — return value on Ok, caller-supplied default on Err (no panic).
func mapErr*[T, E](r: Result[T, E]; mapper: proc(e: E): E {.raises: [], noSideEffect.}): Result[T, E] =
  if r.isErr():
    Result[T, E](ok: false, err: mapper(r.error))
  else:
    r

## Map — transform success value, propagate error
func map*[T, E, U](r: Result[T, E]; f: proc(x: T): U {.raises: [], noSideEffect.}): Result[U, E] =
  if r.isOk: Result[U, E](ok: true, value: f(r.value))
  else: Result[U, E](ok: false, err: r.err)

## FlatMap — chain Result-returning operations
func flatMap*[T, E, U](r: Result[T, E]; f: proc(x: T): Result[U, E] {.raises: [], noSideEffect.}): Result[U, E] =
  if r.isOk: f(r.value)
  else: Result[U, E](ok: false, err: r.err)

## AndThen — apply side-effectful proc on success, propagate error
func andThen*[T, E](r: Result[T, E]; f: proc(x: T) {.raises: [], noSideEffect.}): Result[T, E] =
  if r.isOk: f(r.value)
  r

## GetOrDefault — return value on Ok, caller-supplied default on Err (no panic).
func getOrDefault*[T, E](r: Result[T, E]; default: T): T {.inline, raises: [].} =
  if r.ok: r.value
  else: default

{.pop.}

