# WSL2 Development Environment (Windows 11)

This guide records how to build and run Axiom on a clean Windows 11 machine
without a native port, without a custom installer, and without a second
computer. Every command and number below was executed and observed.

Administrator privileges depend on the machine state, and this is not a
general claim:

- Clean Windows with the WSL optional features still disabled: `wsl --install`
  requires an **administrator** PowerShell. Microsoft documents this because
  the command enables the WSL and Virtual Machine Platform optional components.
- Windows where the WSL features are already enabled: installing a distribution
  with `wsl --install -d ...` works in a non-elevated session. The measurements
  in section 11 are this case.

So "it works without administrator rights" is an observation about one machine,
not a reproducible guarantee.

## 0. Principles

- Windows is the host; the development and execution environment is WSL2 Ubuntu.
- Keep the repository and the toolchain on **ext4 `/home`**. Do not run Linux
  toolchains over `/mnt/c`.
- Delegate to external authorities (apt, upstream tarballs, elan). Do not write
  a local installer.
- The version declarations in the repository (`lean-toolchain`, `nimble.lock`,
  `data/toolchain_lock.json`) are the authority for installation.
- **Binary paths and hashes are pinned by `data/toolchain_lock.json`.** An
  install at an arbitrary location is rejected at commit time (section 8).

## 1. WSL2 and Ubuntu 24.04

```powershell
wsl --status          # expect "Default Version: 2"
wsl --list --online   # confirm Ubuntu-24.04 is offered
wsl --install -d Ubuntu-24.04 --no-launch
```

If `wsl --status` fails, the WSL feature itself is off. Only in that case run
`wsl --install` from an **administrator** PowerShell and reboot.

`--no-launch` skips the interactive first-run user setup. Enter as root and
create the user afterwards:

```bash
wsl -d Ubuntu-24.04 -u root
useradd -m -s /bin/bash <user>
printf '[user]\ndefault=<user>\n' > /etc/wsl.conf
```

No reboot is needed on a machine where the features are already enabled.
`sparseVhd` is currently disabled by default by Microsoft because of a data
corruption risk and does not apply without `--allow-unsafe`. Not setting it is
the default.

## 2. Repository

```bash
mkdir -p ~/develop && cd ~/develop
git clone https://github.com/Archright/Axiom.git
cd Axiom
git rev-parse HEAD              # must match the expected SHA
git rev-parse --show-toplevel   # must be /home/<user>/...
```

If `--show-toplevel` prints `/mnt/c/...`, the location is wrong.

## 3. System packages

```bash
sudo apt-get update
sudo apt-get install -y build-essential cargo curl xz-utils unzip zstd jq \
  ca-certificates libpcre3
```

`libpcre3` is undocumented but **required**. Without it `make build` exits 0 and
only `bin/ax` fails, at load time:

```
could not load: libpcre.so(.3|.1|)
```

## 4. Nim 2.2.10

Ubuntu 24.04 ships nim 1.6.14, which is too old. Use the upstream tarball.

```bash
NIMV=2.2.10
curl -fsSLO "https://nim-lang.org/download/nim-$NIMV-linux_x64.tar.xz"
curl -fsSLO "https://nim-lang.org/download/nim-$NIMV-linux_x64.tar.xz.sha256"
sha256sum -c "nim-$NIMV-linux_x64.tar.xz.sha256"     # upstream checksum
sudo tar -xJf "nim-$NIMV-linux_x64.tar.xz" -C /opt
ln -sf /opt/nim-$NIMV/bin/nim    /usr/local/bin/nim
ln -sf /opt/nim-$NIMV/bin/nimble /usr/local/bin/nimble
```

### The choosenim layout is required

`config.nims:387` resolves the `compiler/` sources only through
`$HOME/.choosenim/toolchains/nim-<version>`. Without that path the build fails
with `cannot open file: compiler/ast`. Either unpack the tarball there or
symlink it:

```bash
mkdir -p ~/.choosenim/toolchains
ln -sfn /opt/nim-$NIMV ~/.choosenim/toolchains/nim-$NIMV
test -f ~/.choosenim/toolchains/nim-$NIMV/compiler/ast.nim && echo OK
```

This path is required by **both** `config.nims` and `data/toolchain_lock.json`.
Installing under `/opt` and creating the symlink above satisfies both at once.

## 5. Z3 4.13.3

Ubuntu 24.04 ships z3 4.8.12, which is too old.

```bash
Z3=z3-4.13.3-x64-glibc-2.35.zip
curl -fsSLO "https://github.com/Z3Prover/z3/releases/download/z3-4.13.3/$Z3"
stat -c%s "$Z3"     # must be 49681288
sha256sum "$Z3"     # upstream publishes no checksum; record the received digest
unzip -q "$Z3" -d /tmp/z3
sudo mv /tmp/z3/z3-4.13.3-x64-glibc-2.35 /opt/z3-4.13.3
ln -sf /opt/z3-4.13.3/bin/z3 /usr/local/bin/z3
mkdir -p ~/.local/bin
ln -sfn /opt/z3-4.13.3/bin/z3 ~/.local/bin/z3   # path required by the lock
```

Z3 4.13.3 is the only component whose upstream publishes no checksum. Only the
HTTPS transport and the size comparison are verified, which is a weaker
guarantee than the other components get.

Omitting `~/.local/bin/z3` still builds and still runs, but **aborts the
commit**:

```
TOOLCHAIN MISMATCH: binary not found: /home/<user>/.local/bin/z3
[ERROR] gateway: [gateway] Toolchain verification failed - commit aborted
```

`/usr/local/bin/z3` alone is not enough. The lock looks at `~/.local/bin`.

## 6. Lean 4.33.0

`lean-toolchain` is the authority for the version. elan does not verify download
checksums, so verify the tarball yourself and then register it.

```bash
LEANT=lean-4.33.0-linux.tar.zst
curl -fsSL -o "$LEANT" \
  "https://github.com/leanprover/lean4/releases/download/v4.33.0/$LEANT"
EXPECTED=$(curl -fsSL \
  "https://api.github.com/repos/leanprover/lean4/releases/tags/v4.33.0" \
  | jq -r --arg n "$LEANT" '.assets[]|select(.name==$n)|.digest' | cut -d: -f2)
echo "$EXPECTED  $LEANT" | sha256sum -c -
tar --zstd -xf "$LEANT" -C /tmp
sudo mv /tmp/lean-4.33.0-linux /opt/lean-4.33.0
```

Install elan and register the toolchain:

```bash
ELT=elan-x86_64-unknown-linux-gnu.tar.gz
curl -fsSL -o "$ELT" \
  "https://github.com/leanprover/elan/releases/download/v4.4.0/$ELT"
# verify against the release API digest before continuing
tar -xzf "$ELT" && ./elan-init -y --default-toolchain none
elan toolchain link leanprover/lean4:v4.33.0 /opt/lean-4.33.0
```

`lean` and `lake` are resolved from `lean-toolchain` when the working directory
is inside the repository. Using `elan toolchain install` without verification
makes elan download again and verify nothing.

There is deliberately no `elan default`. Resolution through the repository pin
is the intended mechanism.

## 7. Nimble dependencies

```bash
nimble install --depsOnly -y
ls ~/.nimble/pkgs2    # checksums, fusion, malebolgia, nimcrypto, ed25519
```

`ci/checker.mk` immediately checks for the `checksums` and `fusion` directories
and stops the build when they are absent (DEBT#509).

## 8. Build and run

```bash
make build
bin/ax --version
bin/ax --check-provenance
```

### Toolchain lock verification before commit

`data/toolchain_lock.json` pins the **path and SHA-256** of four binaries.
`axiom-gate commit` verifies this lock and aborts when any entry disagrees.

| Tool | Path required by the lock | Expected SHA-256 |
|---|---|---|
| nim | `~/.choosenim/toolchains/nim-2.2.10/bin/nim` | `d955005687bea4d3ca6c5813792789987405343a1e8b8c0a8b3a22b9c23936cf` |
| z3 | `~/.local/bin/z3` | `4c13bd5b2526453ba7f88ffd852bbaec80a8132638cbe60ed3463dbc98952711` |
| lean | `~/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean` | `e8baaa71855a616dc351028f3ad2200051b0671f423a1696a100e809302d5550` |
| lake | `~/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lake` | `60330ab6f07dce20f3fa9ebb08e8b984ea9549eac172afeb15d9d2227060e2b3` |

Installing under `/opt` and creating the symlinks listed above is fine: the
hash follows the symlink and reads the real binary. When the upstream artifact
is the same, the hash matches the lock byte for byte (measured in section 11).

Do not bypass the lock. Matching the path is the fix.

### Windows PATH leaks into WSL

WSL inherits the Windows `PATH`. On the machine measured here it contained
Windows executable directories such as `/mnt/c/Nim/nim-2.2.8/bin` and
`/mnt/c/.../z3-4.16.0/.../bin`.

`/usr/local/bin` comes first, so the Linux binaries were actually selected, but
without the symlinks the interop layer can resolve the Windows `nim` or `z3`
instead. The symptom is `cannot open file: compiler/ast` or an unexplained
version mismatch. Check before building:

```bash
command -v nim z3 lean lake
readlink -f "$(command -v nim)"    # a /mnt/c/... result is wrong
```

## 9. Observing reproducibility

`--limit` may pick a **different subject on every run**. The first run stores a
certificate that the second run hydrates from the vault, which skips the
already-verified node (`verified_frontier.nim:70`). `logs/ax_proof_state.json`
is a fixed path and is overwritten.

To observe reproducibility, pin the subject and snapshot immediately after the
run:

```bash
TARGET=src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers

AXIOM_CI=1 bin/ax prove --target "$TARGET" --fresh
cp logs/ax_proof_state.json logs/run1.state.json
bin/ax report --canonical-digest --state-file logs/run1.state.json \
  | grep -E '^[0-9a-f]{64}$'
bin/ax report --json --state-file logs/run1.state.json
```

The projection digest is a single 64-hex line on **stdout**. It is not a JSON
field and it is not written to a log file. `report_cli.nim:352` sets
`emitJson:false`.

### Identical twice is not a successful proof

An identical digest means the projection is deterministic. It does not mean the
proof succeeded. Check `runOutcome.verdict`, `runOutcome.gateVerdict` and
`summary.verified` as well. A target with no postcondition stays
`NOT_VERIFIABLE` and `gateVerdict` stays `FAIL`.

## 10. Known traps

- **Do not run `make readiness-collect` locally.** Its default `--out` is
  `data/readiness/evidence`. Run against an empty `logs/`, it overwrites the
  tracked R1-R8 evidence with red results and still exits 0. The committed
  evidence is a frozen snapshot taken at decision time, not a freshness
  guarantee.
- **`verify-contract-release-e2e-full` does not pass locally.** It requires the
  `data/trusted/certificates` vault, which is not in the repository. It only
  holds under the CI assumption that the vault is restored.
- Exit code 0 is not a successful verification. Read the report verdict.
- `ax prove` writes progress to stderr and has no `--json`. Decide from the
  report.

## 11. Environment observed while writing this

| Item | Value |
|---|---|
| Windows | 11 Home, build 26200 |
| WSL | 2.6.3.0, kernel 6.6.87.2-1 |
| Ubuntu | 24.04.5 LTS |
| CPU / RAM | 16 logical / 15.3 GiB (WSL default, 50 percent) |
| Golden path | ext4 `/home/<user>/develop/Axiom` |
| HEAD | `d6ee3ead` |
| Toolchain lock | nim, lean and lake match the lock hash. z3 aborted the first commit because `~/.local/bin/z3` was absent; after creating the path: `Toolchain lock verified OK` |
| Gates | `validate-root-layout`, `check-repository-surface`, `check-debt`, `check-git-access`, `check-layer-enforcement` all exit 0 |
| Build | `make build` exit 0, `bin/ax --version` prints `v0.6.6`, `--check-provenance` prints OK |

### Why this document is in English

`compliance/policy/script-scan-policy.yml` forbids a landing diff from adding
any code point outside the ASCII, Latin, Greek, Common and Inherited scripts,
apart from exact-path product i18n exemptions. Hangul is outside that set, so a
Korean-language guide cannot land. The document is written in English to comply
with the enforced policy rather than to amend it.