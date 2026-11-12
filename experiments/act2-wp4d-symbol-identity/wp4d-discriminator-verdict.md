## axiom-self

- **Total declarations scanned:** 28539
- **Total duplicate (module, name) groups:** 3011
- **Resolved by decl-text discriminator:** 1467
- **Collisions after discriminator:** 1544
  - Hash collisions (different text, same SHA-256): 0
  - Residual collisions (identical normalized text): 1544

### Verdict: FAIL

The declaration-text SHA-256 discriminator does NOT separate every same-(module, name) duplicate group.

- **1,544 residual collisions** — groups where both definitions have identical normalized declaration text (same SHA-256). These are typically `let`/`var` bindings with the same name and same expression in different scopes within the same module.
- **0 hash collisions** — no cases where different text produced the same SHA-256.
- **1,467 resolved** — groups where the discriminator successfully produced different hashes.

### Residual Collision Analysis

The 1,544 residual collisions are almost entirely `let` and `var` local variable bindings
that share the same name and same initialization expression but exist in different scopes
(e.g., different functions or different branches within the same function). Since the
declaration-text discriminator only sees the normalized span (keyword + name + signature),
it cannot distinguish same-named local variables in different scopes.

Notable residual collision categories:
- `let` bindings: 2,579 entries across 1,544 groups
- `var` bindings: 1,020 entries across 1,544 groups
- `proc`/`func`/`template`/`type`/`const`/`iterator`/`macro`: 54 entries across 6 groups

The `proc`/`func`/`template` residual collisions are the most concerning for Axiom's
symbol identity problem — these are cases where same-name overloads have identical
signatures but different bodies, which the decl-text discriminator cannot separate.

### Multi-line signature cases

The span reconstruction follows parameter-list parens to balanced close, or stops at
first `=` for non-paren declarations. This correctly handles multi-line signatures.

### Open Issue candidates

- Same signature, different body: overloaded proc/template with identical signatures
  but different bodies — the body is not part of the declaration span, so these
  cannot be separated by the decl-text discriminator alone.
- Local variable shadowing: `let`/`var` bindings with the same name in different
  scopes produce identical normalized text.

## nim-stew

- **Total duplicate groups found**: 227
- **True duplicates** (same text, same meaning, correctly same SHA): 41
- **Residual collisions** (same SHA but meaningfully different def): 48

### Residual Collisions (same truncated text, meaningfully different def)

- `arrayops.nim::elems`: 2 defs, kinds: let, let
  - Full: `let elems = min(v.len, src.len)` vs `let elems = min(N, src.len)`
  - Truncated: `let elems =`
- `base10.nim::index`: 2 defs, kinds: let, let
  - Full: `let index = uint8((v mod type(value)(100)) shl 1)` vs `let index = uint8(v) shl 1`
  - Truncated: `let index =`
- `base10.nim::v`: 2 defs, kinds: var, var
  - Full: `var v = T(0)` vs `var v = value`
  - Truncated: `var v =`
- `base32.nim::alphabet`: 8 defs, kinds: const
  - Full: `const alphabet = RFCUpperCaseAlphabet` / `RFCLowerCaseAlphabet` / `HEXUpperCaseAlphabet` / `HEXLowerCaseAlphabet` (repeated)
  - Truncated: `const alphabet =`
- `base32.nim::length`: 2 defs, kinds: let, let
  - Full: `let length = btype.encodedLength(len(inbytes))` vs `let length = btype.decodedLength(len(instr))`
  - Truncated: `let length =`
- `base32.nim::limit`: 2 defs, kinds: let, let
  - Full: `let limit = len(inbytes) - reminder` vs `let limit = inlen - reminder`
  - Truncated: `let limit =`
- `base32.nim::reminder`: 4 defs, kinds: let
  - Full: `let reminder = length mod 5` / `length mod 8` / `len(inbytes) mod 5` / `inlen mod 8`
  - Truncated: `let reminder =`
- `base36.nim::alphabet`: 4 defs, kinds: const
  - Full: `const alphabet = B36LcAlphabet` / `B36UcAlphabet` (repeated)
  - Truncated: `const alphabet =`
- `base36.nim::binsz`: 2 defs, kinds: let, let
  - Full: `let binsz = inbytes.len` vs `let binsz = payload.len + 4`
  - Truncated: `let binsz =`
- `base36.nim::buffer`: 2 defs, kinds: var, var
  - Full: `var buffer = newSeq[uint8](size)` vs `var buffer = newSeq[uint32](size)`
  - Truncated: `var buffer =`
- `base36.nim::j`: 2 defs, kinds: var, var
  - Full: `var j = size - 1` vs `var j = 0`
  - Truncated: `var j =`
- `base36.nim::size`: 2 defs each for let and var
  - Full (let): `let size = btype.encodedLength(binsz - zcount)` vs `let size = (binsz + 3) div 4`
  - Full (var): `var size = btype.encodedLength(inbytes.len) + 1` vs `var size = instr.len + 4`
  - Truncated: `let size =` / `var size =`
- `base58.nim::alphabet`: 4 defs, kinds: const
  - Full: `const alphabet = BTCAlphabet` / `FlickrAlphabet` (repeated)
  - Truncated: `const alphabet =`
- `base58.nim::binsz`: 2 defs, kinds: let, let
  - Full: `let binsz = len(inbytes)` vs `let binsz = len(instr) + 4`
  - Truncated: `let binsz =`
- `base58.nim::buffer`: 2 defs, kinds: var, var
  - Full: `var buffer = newSeq[uint8](size)` vs `var buffer = newSeq[uint32](size)`
  - Truncated: `var buffer =`
- `base58.nim::size`: 2 defs each for let and var
  - Full (let): `let size = ((binsz - zcount) * 138) div 100 + 1` vs `let size = (binsz + 3) div 4`
  - Full (var): `var size = (len(inbytes) * 138) div 100 + 1` vs `var size = len(instr) + 4`
  - Truncated: `let size =` / `var size =`
- `base64.nim::alphabet`: 4 defs, kinds: const
  - Full: `const alphabet = B64Alphabet` / `B64UrlAlphabet` (repeated)
  - Truncated: `const alphabet =`
- `base64.nim::length`: 2 defs, kinds: let, let
  - Full: `let length = len(inbytes)` vs `let length = btype.decodedLength(len(instr))`
  - Truncated: `let length =`
- `bitops2.nim::mask`: 2 defs (const) + 6 defs (let)
  - Full (const): `const mask = 8 * sizeof(v) - 1` vs `const mask = bitsof(v) - 1`
  - Full (let): `let mask = T(1) shl bit` / `let mask = mostSignificantBit(x.type) shr bit` (repeated)
  - Truncated: `const mask =` / `let mask =`
- `bitops2.nim::v`: 6 defs, kinds: var, var
  - Full: `var v = x - 1` / `var v = x.uint32` / `var v = x` (repeated)
  - Truncated: `var v =`
- `bitseqs.nim::lhsBits`: 2 defs, kinds: template, template
  - Full: `template lhsBits: auto = (addr(lhsWord))[]` vs `template lhsBits: auto = lhsCurrAddr[]`
  - Truncated: `template lhsBits: auto =`
- `bitseqs.nim::markerPos`: 2 defs, kinds: let, let
  - Full: `let markerPos = log2trunc(lastByte)` vs `let markerPos = log2trunc(lhsWord)`
  - Truncated: `let markerPos =`
- `bitseqs.nim::rhsBits`: 2 defs, kinds: template, template
  - Full: `template rhsBits: auto = (addr(rhsWord))[]` vs `template rhsBits: auto = rhsCurrAddr[]`
  - Truncated: `template rhsBits: auto =`
- `endians2.nim::v`: 2 defs, kinds: let, let
  - Full: `let v = (x shl 16) or (x shr 16)` vs `let v =`
  - Truncated: `let v =`
- `enums.nim::values`: 2 defs, kinds: const, const
  - Full: `const values = enumStrValuesArrayImpl E` vs `const values = @(enumStrValuesArray E)`
  - Truncated: `const values =`
- `interval_set.nim::p`: 3 defs, kinds: let, let, let
  - Full: `let p = rc.value` / `let p = block:` (repeated)
  - Truncated: `let p =`
- `interval_set.nim::rc`: 3 defs (var) + 15 defs (let)
  - Full (var): `var rc = p.ge(low(P))` / `var rc = ds.leftPos.ge(minPt)` / `var rc = ds.leftPos.le(maxPt)`
  - Full (let): various `let rc = ds.leftPos.*` / `let rc = ds.overlap(*)` / `let rc = Segm[P,S].brew(*)` etc.
  - Truncated: `var rc =` / `let rc =`
- `interval_set.nim::s`: 2 defs, kinds: let, let
  - Full: `let s = BlockRef[S](size: p.right - iv.left)` vs `let s = BlockRef[S](size: right - iv.right)`
  - Truncated: `let s =`
- `io2.nim::buffer`: 3 defs, kinds: var, var
  - Full: `var buffer = newSeq[Utf16Char](len(path) * 2 + 1)` / `var buffer = $res` / `var buffer = newWideCString("", int(bufsize))`
  - Truncated: `var buffer =`
- `io2.nim::curpath`: 2 defs, kinds: var, var
  - Full: `var curpath = dpath` vs `var curpath = path`
  - Truncated: `var curpath =`
- `io2.nim::existFlags`: 3 defs, kinds: let, let, let
  - Full: `let existFlags = [EEXIST, ENOSYS]` / `[EEXIST, EROFS]` / `[EEXIST]`
  - Truncated: `let existFlags =`
- `io2.nim::flags`: 2 defs, kinds: let, let
  - Full: `let flags = {OpenFlags.Write, OpenFlags.Truncate, OpenFlags.Create}` vs `let flags = {OpenFlags.Read}`
  - Truncated: `let flags =`
- `io2.nim::gres`: 2 defs, kinds: let, let
  - Full: `let gres = getFileAttributes(...)` vs `let gres = getFileInformationByHandleEx(...)`
  - Truncated: `let gres =`
- `io2.nim::handle`: 2 defs, kinds: let, let
  - Full: `let handle = ? openFile(pathName, flags, createMode, secDescriptor)` vs `let handle = ? openFile(pathName, flags)`
  - Truncated: `let handle =`
- `io2.nim::i`: 2 defs, kinds: var, var
  - Full: `var i = len(path)` vs `var i = pathlen`
  - Truncated: `var i =`
- `io2.nim::ltype`: 2 defs, kinds: let, let
  - Full: `let ltype =` vs `let ltype = cshort(posix.F_UNLCK)`
  - Truncated: `let ltype =`
- `io2.nim::mask`: 2 defs, kinds: let, let
  - Full: `let mask = ? getPermissions(pathName)` vs `let mask = ? getPermissions(handle)`
  - Truncated: `let mask =`
- `io2.nim::path`: 2 defs, kinds: var, var
  - Full: `var path = if isNil(res): "" else: $res` vs `var path = $res`
  - Truncated: `var path =`
- `io2.nim::res`: 50 defs, kinds: let
  - Full: various `let res = ...` with different RHS expressions (getLongPathNameW, getcwd, posix.mkdir, etc.)
  - Truncated: `let res =`
- `io2.nim::sres`: 2 defs, kinds: let, let
  - Full: `let sres = setFileAttributes(...)` vs `let sres = setFileInformationByHandle(...)`
  - Truncated: `let sres =`
- `keyed_queue.nim::key`: 6 defs, kinds: let
  - Full: `let key = rq.kFirst` / `rq.kLast` / `rq.tab[rq.kFirst].kNxt` / `rq.tab[rq.kLast].kPrv` (repeated)
  - Truncated: `let key =`
- `keyed_queue.nim::res`: 5 defs, kinds: let
  - Full: `let res = Opt.some T(key: rq.kFirst, data: move(item[].data))` / `Opt.some(move(item[].data))` / `Opt.some T(key: key, data: move(item[].data))`
  - Truncated: `let res =`
- `shims/macros.nim::p`: 2 defs, kinds: let, let
  - Full: `let p = findPragma(field.pragmas, bindSym(pragmaName))` vs `let p = getPragma(T, field, pragma)`
  - Truncated: `let p =`
- `shims/macros.nim::payload`: 3 defs, kinds: macro, macro, macro
  - Full: `macro payload: untyped =` / `macro payload: untyped = body`
  - Truncated: `macro payload: untyped =`
- `shims/macros.nim::typ`: 3 defs, kinds: var, var, var
  - Full: `var typ = getTypeInst(typeof(arg))[1]` / `var typ = exceptionType`
  - Truncated: `var typ =`
- `shims/strformat.nim::negative`: 2 defs, kinds: let, let
  - Full: `let negative = false` vs `let negative = n < 0`
  - Truncated: `let negative =`
- `shims/strformat.nim::toFill`: 3 defs, kinds: let, let, let
  - Full: `let toFill = spec.minimumWidth - result.len - xx.len - ord(sign)` / `spec.minimumWidth - result.len` / `spec.minimumWidth - f.len - ord(sign)`
  - Truncated: `let toFill =`
- `shims/strformat.nim::v`: 2 defs, kinds: var, var
  - Full: `var v = n.uint64` vs `var v =`
  - Truncated: `var v =`

### Multi-line Signature Cases (27 defs span multiple lines)

- `arraybuf.nim::initCopyFrom` lines 100-102, 107-109
- `base32.nim::encode` lines 135-136, 186-187
- `base36.nim::encode` lines 62-63, 110-111
- `base58.nim::encode` lines 60-61, 114-115
- `base64.nim::encode` lines 71-72, 129-130
- `byteutils.nim::hexToByteArray` lines 64-65
- `interval_set.nim::verify` lines 187-188, 1146-1148
- `io2.nim::lockFile` lines 1529-1530
- `io2.nim::readFile` lines 139-142

### Open Issue Candidates (same truncated text, different signatures)

48 residual collision groups, all caused by the decl-text discriminator truncating
no-paren declarations at `=`, which strips the RHS expression and type annotation
that would otherwise distinguish same-named bindings in different scopes.

### Verdict: FAIL — 48 residual collision(s) found.

The declaration-text SHA-256 discriminator does NOT separate every same-(module, name)
duplicate group into distinct tokens. The 48 residual collisions are caused by the
truncation rule for no-paren declarations (stop at first `=`), which strips the
right-hand-side expression and type annotation from `let`/`var`/`const`/`type`
declarations. This makes same-named local variables and constants in different scopes
indistinguishable. For paren declarations (func/proc/template with parameter lists),
the discriminator works correctly — different parameter types produce different hashes.
