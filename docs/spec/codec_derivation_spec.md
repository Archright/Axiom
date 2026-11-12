# Compile-Time Type-Driven JSON Codec Derivation Spec

## Overview

`deriveJsonCodec(T)` is a compile-time macro that auto-generates `toJson` and `fromJson` procs for any Nim type. It eliminates manual JSON serialization boilerplate and ensures strict validation by default.

**Location**: `src/core/codec/` (3-module architecture)

| Module | Role |
|--------|------|
| `codec_typesense.nim` | Type introspection engine (pure compile-time) |
| `codec_codegen.nim` | AST→code generation engine |
| `axiom_codec.nim` | Macro entry point (`deriveJsonCodec(T)`) |

**Hub stub**: `src/core/codec/axiom_codec.nim` → re-exports `deriveJsonCodec`

## Supported Types

| Type Kind | toJson | fromJson |
|-----------|--------|----------|
| `string`, `int`, `float`, `bool` | `newJString`/`newJInt`/etc. | `getStr`/`getInt`/etc. |
| `enum` | `newJString($x)` | `case node.getStr()` matching all variants |
| `object` | Field-by-field serialization | `hasKey` + `kind` validation per field |
| `ref object` | Same as object (unwrapped) | Same as object |
| `variant object` (case) | Discriminator + case branch | Discriminator validation + case dispatch |
| `distinct T` | Cast to base type, serialize | Deserialize base, cast back |
| `seq[T]` | `newJArray` + per-element | `JArray` guard + per-element |
| `Option[T]` | `toJson(get())` or `newJNull` | Skip if missing/JNull, else deserialize |
| `Table[string, T]` | `newJObject` + per-value | `JObject` guard + per-value |
| `JsonNode` | Pass through | Pass through |

## Design Decisions

### 1. Enum Dispatch Ordering (Concern #1)

`getTypeImpl` on a `typedesc[T]` returns `nnkBracketExpr(typedesc, T)` for all types, including enums. The typedesc wrapper MUST be unwrapped BEFORE checking `nnkEnumTy`, otherwise the enum path is never taken and the macro falls through to the object path (which fails on `nnkRecList` traversal).

**Fix**: Unwrap `nnkBracketExpr(typedesc, ...)` first, then dispatch on `impl.kind`.

### 2. Strict Validation (Concern #2)

All required fields MUST be present with correct types. No silent defaults.

- Missing field → `err("Missing required field 'X'")`
- Wrong JSON kind → `err("Wrong type for field 'X'")`
- Non-array for seq → `err("Expected JSON array for field 'X'")`
- Unknown enum value → `err("Unknown X value: Y")`

Only `Option[T]` fields allow missing/JNull.

### 3. nnkRecList Extraction (quirk)

`nnkObjectTy` structure is `[pragmas, inheritance, nnkRecList]`. The `extractObjectFields` function expects `nnkRecList` directly, NOT the full `nnkObjectTy`. `classifyFull` must pass `node[2]` to `extractObjectFields`.

### 4. Enum nnkSym Children (quirk)

Enum types from imported modules have `nnkSym` children in `nnkEnumTy`, NOT `nnkIdent`. `extractEnumValues` must handle both `nnkIdent` and `nnkSym`.

### 5. Primitive seq Element Serialization (quirk)

`toJson(elem)` / `fromJson(elem, T)` has NO overloads for primitive types (`string`, `int`, `bool`, `float`). For `seq[string]`, the generated code MUST use inline `newJString(elem)` / `elem.getStr()` instead of `toJson`/`fromJson`. Complex element types (object, enum) use `toJson`/`fromJson`.

### 6. typedesc Wrapping in fromJson Calls (quirk)

`fromJson(node, T)` expects the second argument to be `typedesc[T]`, not bare `T`. All generated `fromJson` calls must wrap the type in `nnkBracketExpr(ident("typedesc"), typeNode)`.

### 7. Quote Do Field Access (quirk)

In Nim's `quote do:` syntax, `\`field.typeNode\`` where `field` is a `FieldInfo` object does NOT correctly interpolate the `typeNode` NimNode — it may serialize the entire `FieldInfo` object into the AST. All field properties must be pre-extracted into local `let` variables before `quote do:` blocks.

### 8. node["key"] KeyError Suppression (quirk)

`node["key"]` on `JsonNode` has `{.raises: [KeyError].}`. Even after `hasKey` validation, the compiler flags this. Solution: wrap `fromJson` body in `{.cast(raises: []).}:`.

### 9. Custom Result Type

Axiom uses a custom `Result[T, E]` in `core/types/results` (NOT `std/results`):
- `.ok` (bool) — case discriminator
- `.value` (T) — when ok == true
- `.err` (E) — when ok == false

No `.isOk`, `.isErr`, `.get()`, `.error` methods.

### 10. genSym for Loop Variables in Nested quote do

When building loop bodies in a separate `quote do:` and interpolating into an outer `quote do:`, identifiers like `arrNode` get different gensyms. Use `genSym(nskLet, "arrNode")` in the outer scope and pass the same NimNode to both inner and outer `quote do:` blocks.

## Generated Code Convention

- All procs: `{.noSideEffect, raises: [].}`
- JSON mutation: `{.cast(noSideEffect).}` block
- fromJson body: `{.cast(raises: []).}` block
- Field access: `node{"key"}` or `node["key"]` (with cast)
- No `%` or `%*{}` (avoids `{.raises: [Exception].}`)
- Error messages: descriptive, includes type/field name

## Quirks Registry

| Quirk | Module | Description |
|-------|--------|-------------|
| typedesc unwrap ordering | axiom_codec.nim | `nnkBracketExpr(typedesc, T)` must be unwrapped before kind check |
| nnkRecList extraction | codec_typesense.nim | `extractObjectFields` expects `node[2]`, not full `nnkObjectTy` |
| nnkSym enum children | codec_typesense.nim | Imported enums have `nnkSym`, not `nnkIdent` |
| quote do field access | codec_codegen.nim | Pre-extract `field.*` into local vars before `quote do:` |
| typedesc wrapping | codec_codegen.nim | `fromJson` calls need `typedesc[T]`, not bare `T` |
| Primitive seq elements | codec_codegen.nim | Use `newJString(elem)` not `toJson(elem)` for primitives |
| KeyError suppression | codec_codegen.nim | `{.cast(raises: []).}` for `node["key"]` access |
| gensym loop variables | codec_codegen.nim | Use `genSym` for shared identifiers across nested `quote do:` |
| Custom Result API | codec_codegen.nim | `.ok`/`.value`/`.err`, NOT `.isOk`/`.get()`/`.error` |

## Future Migration Path

1. Add `deriveJsonCodec(T)` in each type file (e.g., `domain_types.nim`, `workflow_state.nim`)
2. Remove manual `toJson`/`fromJson`/`%` overloads
3. Remove `import core/json/std_redirect` from consumers
4. Extend to `distinct` base types beyond string/int
