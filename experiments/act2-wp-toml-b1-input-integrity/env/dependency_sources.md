# Dependency Sources — nim-toml-serialization bug-hunt (B1 input integrity)

Subject repo: `<workspace>/nim-toml-serialization`
@ commit `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (toml_serialization 0.2.18,
declares `nim >= 2.0.0`, `faststreams >= 0.5.0`, `serialization >= 0.5.3`, `stew`).

All evidence below is **empirical** (compiler-side observation), not inferred from
`nimblemeta.json`. Methods used:

1. `strace -f -e trace=%file` around the real compile — the literal set of `.nim`
   files the compiler front-end **opened successfully** (raw log:
   `raw_evidence/strace_G.log`, ENOENT probes filtered out; see
   `consumed_files_strace.txt`).
2. `nim --dump.format:json dump` — the compiler's own resolved `lazyPaths`
   (pkgs2 auto-discovery result).
3. Four-point compile-probe matrix for the `stew` version question.
4. Compile attempts of the actual subject repo against every candidate
   dependency version set (fresh vs degraded).

## 1. Resolution verdict (which sources the compiler actually consumes)

**Primary (pinned) build profile** — explicit `--path` flags, `--mm:orc`:

| Package | Version | vcsRevision (nimblemeta.json) | Absolute path |
|---|---|---|---|
| serialization | **0.5.4** | `b5473564e80a4908cf6c5a038e4c4a6ca7de2223` | `<user-home>/.nimble/pkgs2/serialization-0.5.4-6a75be38ab6c8a5d49108a54b494ff70d68ea011` |
| faststreams | **0.5.2** | `059bc2f52546ac14b583639c33372c14b1d46fa3` | `<user-home>/.nimble/pkgs2/faststreams-0.5.2-589a9cf07e1d978f460f3da7f8de9b37ac3141af` |
| stew | **0.5.0** | `4382b18f04b3c43c8409bfcd6b62063773b2bbaa` | `<user-home>/.nimble/pkgs2/stew-0.5.0-db22942939773ab7d5a0f2b2668c237240c67dd6` |
| results | 0.5.1 (installed, NOT in compiled closure) | `df8113dda4c2d74d460a8fa98252b0b771bf1f27` | `<user-home>/.nimble/pkgs2/results-0.5.1-a9c011f74bc9ed5c91103917b9f382b12e82a9e7` |
| unittest2 | 0.2.5 / 0.2.4 (installed, NOT in compiled closure) | `26f2ef3ae0ec72a2a75bfe557e02e88f6a31c189` / `8b51e99b4a57fcfb31689230e75595f024543024` | `<user-home>/.nimble/pkgs2/unittest2-0.2.5-02bb3751ba9ddc3c17bfd89f2e41cb6bfb8fc0c9` etc. |

`results` and `unittest2` are **not opened at all** in the compiled closure of
`import toml_serialization` (strace-proven). They are transitive *nimble*
requirements (serialization/faststreams nimble files) but no library module
imports them.

## 2. Consumed source files (strace-proven closure) + SHA256

### 2a. Subject repo (11 files)

| File (relative to repo) | sha256 |
|---|---|
| `toml_serialization.nim` | `648fe2c8028f0ce07a49d87e70c08326ac700268388544e53c3e32b64abaef2d` |
| `toml_serialization/decoder.nim` | `b39162bf23ecd83e1ebfb9d2d14f7b39c478bc78ce0b4253900167603f71d5bb` |
| `toml_serialization/desc.nim` | `84f2dc42cc9833c374877e215c166cbd253811c563f0839066ad7a557d38c479` |
| `toml_serialization/format.nim` | `98656e3e3c6527ac8ff144ed328c69bcc651736cc7a8e40add93bc343f415b03` |
| `toml_serialization/lexer.nim` | `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` |
| `toml_serialization/private/array_reader.nim` | `b27dd13f36347cba756e0bf78dd581b99d49bd67bb1317344034c8b0ccdb8c2e` |
| `toml_serialization/private/utf8_validate.nim` | `7b33a854c6198be99ab85858bd8690d00988b2c1e9bb90fdea2d6325952d6f73` |
| `toml_serialization/private/utils.nim` | `452da999ac783ed28d369f202616d8f2db26b17ce26f952db0f3e0f04d60896e` |
| `toml_serialization/reader.nim` | `9e860006d4a26533beddcd762e21390fb7bafb5cf45ab1547ad96efacff569b5` |
| `toml_serialization/types.nim` | `33814f06086b0dedc8177eea5e7ee0f0b0677b262ae48662c5d0a884ffa07295` |
| `toml_serialization/writer.nim` | `50248ca7ad9c6d0ad58265b0c056ef6777aae95c4333a531b38f39ca2cf4624d` |

### 2b. serialization 0.5.4 (6 files)

| File | sha256 |
|---|---|
| `serialization.nim` | `ee248aaa265209da63545a2a5a1479708b008b4d3894eebbe09badcdab72881d` |
| `serialization/errors.nim` | `5a8e19f65cca5d1ed8ebef49784271636846878f75ed663c3769826f6c4d98a6` |
| `serialization/flavor_auto_serialization.nim` | `c2e944fa088d14cb526bed770f014696466d00bdb4c2816679f1e3d816f09e8b` |
| `serialization/formats.nim` | `922b5e60fe3b10d8b79bb83ce023afb85b3af1e3190a501c6f8dd1a997ab89b6` |
| `serialization/macros.nim` | `c7cea515ae6bebf9ecf063afc24041ff28717b6a6b687715edeb67d1d193f382` |
| **`serialization/object_serialization.nim`** (the field-matching logic) | `049d26ae3e2050e63b788bb0356ac0cf33df70401581c7a00d95a861ced7cd1b` |

### 2c. faststreams 0.5.2 (6 files)

| File | sha256 |
|---|---|
| `faststreams/async_backend.nim` | `ae722c2889a94559cff23d01f00784351725075030f2464ae62db50813b7e91a` |
| `faststreams/buffers.nim` | `05910b295c4edf163546ad47a24997bd3fc3872f63a6fac44f7315acc24c5925` |
| `faststreams/inputs.nim` | `8f7d583ba774e8ab434b48aee1268db6d21c81924d2b2f11acb20a35b5056267` |
| `faststreams/multisync.nim` | `4b52f357a28252ee2b4652a552afa229bb5dbd8b23194cb4ceec76c14cdf8e64` |
| `faststreams/outputs.nim` | `2a69ce50193ccc95ba9bcc7fc160a4f481b0fbfbd609bb8c0fd06eb84f4e1fc9` |
| `faststreams/textio.nim` | `dbedbeaaed783a6b70cdb0902289f123d4efbc4099d2696e22323e119ce60a92` |

### 2d. stew 0.5.0 (7 files)

Note: `stew` has no top-level `stew.nim`; the package is consumed purely via
submodule imports.

| File | sha256 |
|---|---|
| `stew/assign2.nim` | `0dc1ac4d1d97e0b6b16c80cff9b653762dc0adf15bee087d3524da76ba3b47ec` |
| `stew/enums.nim` | `3eb9505f6de74a8ced54c695207de2b105886048f6b7081cf8c78db6dad4638e` |
| `stew/objects.nim` | `92be9634a5bd5b34ada258dbe209bf0bdc34a7c860b4ef80da53ae41dc882359` |
| `stew/ptrops.nim` | `18709f9b2e475ca71e00a9b45f69190f36a4905977d2e3221e8733cb8076eb38` |
| `stew/shims/macros.nim` | `d2207be677046886173326b47e7aa6689b20b52db72c1e2dc0bbb6532e654ee6` |
| `stew/shims/sequninit.nim` | `729efddb07520513db99a7a2289514e0a6ef09fbd26733d9623fcbcf2a324b6b` |
| `stew/strings.nim` | `492d22f0fc3dc08c85e9ffd48cb56d5488e87e78df76a8172f93d39b8a0f4ac3` |

### 2e. Not consumed (drift-relevant alternates, for the record)

| Package:file | sha256 | Note |
|---|---|---|
| serialization 0.2.6:`serialization/object_serialization.nim` | `f93815d92deb7bcfb45a8be2a1bd45424caee853a3b53701bfd763c4bd47cf47` | **cannot compile this repo commit** (see §4) |
| serialization 0.2.6:`serialization.nim` | `115878bc40703a7c1f16c6f6a05cf6d58045e40080dd9cfceadb79e349a2ae9c` | vcsRevision `2086c99608b4bf472e1ef5fe063710f280243396` |
| serialization 0.2.6:`serialization/errors.nim` | `3ed5fa7dd0d8ae3a5d9618d020f60c494813c1469b3b3578977bdf731078d11d` | |
| serialization 0.2.6:`serialization/formats.nim` | `de181c3483d5bd15ee44f73bfb511dc7ada4d8e40974f2b62cecc06cc3156d22` | |
| faststreams 0.3.0:`faststreams/inputs.nim` | `f8113e67595ea03a78b0a2d8ccea26e87a77951851aa506a722972193d419ddd` | vcsRevision `2b08c774afaafd600cf4c6f994cf78b8aa090c0c` |
| faststreams 0.3.0:`faststreams/outputs.nim` | `3b3266835db0ef2ff4e7786a67629b6896df90137b282781ba9bdd6cf674a293` | |
| stew 0.2.0:`stew/objects.nim` | `d50026b8c640390bc6530d2a1ebec4a9e44073168dfd497f8a987a31d69540ac` | differs from 0.5.0 |
| stew 0.2.0:`stew/enums.nim` | `5b078a83cc84e0399a99dd99515c7389ed0e192c8bf977d0ed00a62727fb9c56` | differs from 0.5.0 |
| stew 0.2.0:`stew/ptrops.nim` | `c8c4356754e292dc67003713252edb2788b5d86d260a885146648ea405e248f6` | differs from 0.5.0 |
| stew 0.2.0:`stew/strings.nim` | `d23f33e75b0d01089c41d8470ded9b470e596bef0bc874fc2d24a887282672a5` | differs from 0.5.0 |
| stew 0.2.0:`stew/assign2.nim` | `9d22d576ae0b7291c81b10ef4fae67ede6064b39b4a5b2ce105b79ba628ee1d7` | differs from 0.5.0 |
| stew 0.2.0:`stew/shims/macros.nim` | `d2207be677046886173326b47e7aa6689b20b52db72c1e2dc0bbb6532e654ee6` | **byte-identical** to 0.5.0 |
| stew 0.2.0:`stew/shims/sequninit.nim` | (does not exist in 0.2.0) | module absent; see §5 note |
| results 0.5.1:`results.nim` | `b2bbc400629ac9a09945b66b166336734b9013959459c32dd15c9b6b1f8c18f2` | not in closure |
| unittest2 0.2.5:`unittest2.nim` | `b53709b9a193a9d67f04ee256bb3d78a4994ad7c53ca51554da41afd0879ae97` | not in closure |
| unittest2 0.2.4:`unittest2.nim` | `3348afd7c812d7e8233087261e84edea1d6eab67664b7bda9aa3a35749774d3b` | not in closure |

## 3. Stew disambiguation — empirical result

Installed: `stew-0.2.0-26d477c7…` and `stew-0.5.0-db229429…`.

1. **Auto-discovery picks stew 0.5.0 — strace-proven.** With `--nimblePath`
   scanning active (i.e. cwd NOT under Axiom3, see §6), a bare
   `import stew/lentutils` (module exists only in 0.5.0) opens
   `<user-home>/.nimble/pkgs2/stew-0.5.0-db229429…/stew/lentutils.nim`
   (raw_evidence/strace_M2.log). `import stew/result` (exists only in 0.2.0)
   **fails to compile** under auto-discovery — because 0.5.0 was chosen and it
   has no `stew/result`. Mechanism (`compiler/nimblecmd.nim`, `addPackage`):
   the scanner keeps the **highest version** per package name.
2. Discriminator matrix under explicit single-version `--path`:

   | probe | `--path: stew-0.2.0/` | `--path: stew-0.5.0/` |
   |---|---|---|
   | `import stew/lentutils` | FAILS (no such file) | COMPILES |
   | `import stew/result` | COMPILES | FAILS (no such file) |

   (The task's suggested discriminators hold exactly under single-version
   paths. One anomalous early run of "lentutils + 0.2.0 path" appeared to
   succeed from a different cwd; the verified rerun with the same flags fails
   — the matrix above is the reproducible verdict.)
3. **stew 0.2.0 also compiles the full subject-repo probe when explicitly
   forced via `--path`** (attempt D, exit 0). So the compiler does not force a
   stew version when paths are manual — the version is determined by the build
   command. The pinned profile uses **stew 0.5.0**, which is also what
   auto-discovery and a fresh nimble resolve pick.

## 4. Declared vs actual — the drift is real and decisive

* `serialization >= 0.5.3` declared; **serialization 0.2.6 is installed but
  CANNOT be the used version**: compiling the subject repo @4aa8e22 against
  `serialization-0.2.6-26deca68…` fails at
  `toml_serialization/desc.nim(16, 1)`:
  `serializationFormat Toml, mimeType = "application/toml", version = 1` →
  `unknown named parameter: version` (0.2.6's template is
  `serializationFormat(Name; mimeType: static string = "")` — no `version`).
  Raw error: `raw_evidence/attempt_A_full.log` (same failure with stew 0.2.0 or
  0.5.0). Any prior claim that 0.2.6 was "used" is refuted for this commit.
* `faststreams >= 0.5.0` declared; **0.3.0 installed but not consumed**; the
  fresh profile consumes 0.5.2. (The 0.2.6+0.3.0 "degraded" set dies at the
  same desc.nim error before faststreams semantics can matter.)
* Fresh nimble verification (`nimble build` log on a /tmp copy):
  `serialization@>= 0.5.3`, `faststreams@>= 0.5.0`, `stew@>= 0.5.0`,
  `unittest2@>= 0.2.5` all "already satisfied" from pkgs2 — consistent with
  the fresh-resolve set (0.5.4 / 0.5.2 / 0.5.0) being the one true build.

## 5. The decisive file for the defect: object_serialization.nim

Consumed: `serialization-0.5.4-6a75be38…/serialization/object_serialization.nim`
sha256 `049d26ae3e2050e63b788bb0356ac0cf33df70401581c7a00d95a861ced7cd1b`,
vcsRevision `b5473564e80a4908cf6c5a038e4c4a6ca7de2223`. It contains
`totalSerializedFields`, `enumAllSerializedFields(Impl)`, `FieldReader`,
`FieldReadersTable`, `findFieldReader`, `makeFieldReadersTable` — the typed
field-matching logic under study. The 0.2.6 counterpart (sha256
`f93815d92deb7bcf…`) is a *different program* and cannot even compile the repo.

Note: `stew/shims/sequninit.nim` is consumed from stew 0.5.0 but does not exist
in stew 0.2.0; the forced stew-0.2.0 build (attempt D) still compiled, so the
import is conditionally guarded — a fragility footnote, not a blocker.

## 6. How Nim resolves the dependencies here (reproducibility-critical)

* Plain `nim c` resolves packages **only** via the `nimblePath` lazy scanner
  (`compiler/nimblecmd.nim`): it walks each `nimblePath` dir, picks the
  **highest version** per package name, inserts `<pkg>-<ver>-<hash>` into
  `lazyPaths`, and modules are opened from there. Confirmed by
  `nim --dump.format:json dump` (lazyPaths listing) and strace.
* **`compiler/nim.nim:84` — "disable nimble path if nimble.lock is present."**
  The compiler looks for `nimble.lock` in the cwd's ancestor dirs. Because the
  session's default cwd is inside Axiom3 (which has `nimble.lock` and
  `config.nims` line 337 `switch("noNimblePath")`), any compile launched with
  cwd inside Axiom3 resolves **zero** nimble packages (strace: 0 pkgs2
  accesses; dump: lazyPaths empty — `raw_evidence/dump_axiom3.json` vs
  `dump_tmp.json`).
* **A file located under `env/` inherits `Axiom3/config.nims` via the
  project-path ancestor chain** (it runs the whole hermetic/integrity
  bootstrap and fails). Compiling anything under `env/` requires
  `--skipParentCfg`.
* Therefore the pinned build commands in `build_command.txt` use explicit
  `--path` flags + `--skipParentCfg` and are **cwd-independent**; the
  auto-discovery variant (cwd=/tmp, no `--path`) yields the identical
  consumption and is recorded as corroboration.

## 7. Raw evidence index (`raw_evidence/`)

| File | What it proves |
|---|---|
| `strace_G.log` | Full strace of pinned-profile compile: every file opened, incl. all 30 consumed `.nim` files |
| `strace_M1.log` | Auto-discovery build (only `--path:REPO`): opens serialization-0.5.4 + faststreams-0.5.2 + stew-0.5.0, exit 0 |
| `strace_M2.log` | Auto-discovery `import stew/lentutils` → opens stew-0.5.0's lentutils.nim |
| `attempt_A_full.log` | Degraded set (ser 0.2.6 + fs 0.3.0 + stew 0.5.0) FAILS: desc.nim(16) `version` param |
| `attempt_B_full.log` | Degraded set + stew 0.2.0: same failure |
| `attempt_C_full.log` | Fresh set (0.5.4/0.5.2/0.5.0): SuccessX, exit 0 |
| `attempt_D_full.log` | Fresh set but stew 0.2.0: also compiles (exit 0) — stew not compiler-forced under manual paths |
| `dump_axiom3.json` / `dump_tmp.json` | lazyPaths empty vs populated (nimble.lock effect) |
| `nimble_build_copy.log` | Fresh nimble resolve of the /tmp repo copy (no bin → "Nothing to build", dep verification lines) |
