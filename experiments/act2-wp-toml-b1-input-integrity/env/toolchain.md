# Toolchain & Environment Identity — captured 2026-10-11 (Asia/Seoul local)

All outputs below are **verbatim** from the machine that produced the pinned
build inputs. shell: `/bin/bash`, host: Linux.

## Nim compiler

```
$ nim --version
Nim Compiler Version 2.2.10 [Linux: amd64]
Compiled at 2026-04-24
Copyright (c) 2006-2026 by Andreas Rumpf

git hash: bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef
active boot switches: -d:release
```

Matches the prior finding exactly (2.2.10 / bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef).
Binary identity: `which nim` → `<user-home>/.choosenim/toolchains/nim-2.2.10/bin/nim`
(ELF 64-bit, statically linked, with debug_info; same binary resolves from every cwd;
PATH identical across cwds — verified).

nimble-managed compiler (used by `nimble`): `~/.nimble/pkgs2/nim-2.2.10-17ec440fdb89f8903db29a17898af590087d2b64/bin/nim`.

## nimble

```
$ nimble --version
nimble v0.22.2 compiled at 2026-04-24 03:46:34
git hash: couldn't determine git hash
```

## C compiler

```
$ gcc --version | head -1
gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
```

## Kernel / machine

```
$ uname -a
Linux builder-host 6.17.0-42-generic #42-Ubuntu SMP PREEMPT_DYNAMIC Thu Jul 23 19:56:28 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
```

## Resource limits

```
$ ulimit -s
8192
```

```
$ ulimit -a
real-time non-blocking time  (microseconds, -R) unlimited
core file size              (blocks, -c) 0
data seg size               (kbytes, -d) unlimited
scheduling priority                 (-e) 0
file size                   (blocks, -f) unlimited
pending signals                     (-i) 125414
max locked memory           (kbytes, -l) 4030872
max memory size             (kbytes, -m) unlimited
open files                          (-n) 1048576
pipe size                (512 bytes, -p) 8
POSIX message queues          (bytes, -q) 819200
real-time priority                  (-r) 0
stack size                  (kbytes, -s) 8192
cpu time                   (seconds, -t) unlimited
max user processes              (-u) 125414
virtual memory              (kbytes, -v) unlimited
file locks                          (-x) unlimited
```

## Nim-relevant environment

No `NIM*` environment variables are set (`env | grep -i '^nim'` → none).
`NIMBLE_DIR` is unset. `HOME=<user-home>`. The process environment is
identical regardless of cwd (only `PWD` differs — verified by full `env` diff).

## Configuration files that participate in resolution

* `<user-home>/.choosenim/toolchains/nim-2.2.10/config/nim.cfg` — defines
  `nimblepath="/opt/nimble/pkgs2/"`, `"/opt/nimble/pkgs/"`, `$home/.nimble/pkgs2/`,
  `$home/.nimble/pkgs/` (non-Windows branch). This is the ONLY mechanism through
  which plain `nim c` sees nimble packages on this machine.
* `<user-home>/.choosenim/toolchains/nim-2.2.10/config/config.nims` — minimal
  (cpp defines + nimVersion define); no path effects.
* `./config.nims` — line 337:
  `switch("noNimblePath")` (nimble v2 config block). Loads ONLY for projects
  under Axiom3 (project-path ancestor chain). Any source file placed under
  `Axiom3/**` (incl. this `env/` dir) inherits it unless `--skipParentCfg`.
* `./nimble.lock` — present. Nim
  compiler (`compiler/nim.nim:42,84`) disables the nimblePath when a
  `nimble.lock` exists in the **cwd ancestor chain** — independent of the
  project location. Consequence: compiles launched with cwd inside Axiom3
  resolve zero nimble packages (dump shows `lazyPaths: []`), compiles from
  neutral cwds (e.g. `/tmp`) auto-discover pkgs2 at the newest installed
  version per package.
* `strace` available at `/usr/bin/strace` (used for the open()-level evidence).

## Memory-management (–mm:) feasibility

* `--mm:orc`: PRIMARY. Full main probe + both field probes compile, link and
  run (exit 0).
* `--mm:refc`: FEASIBLE. field_probe compiles, links, runs with identical
  output; main probe `--compileOnly` exit 0. Recorded commands in
  `build_command.txt`.

## Build flavors

No flavor flags in the pinned commands beyond `--mm:`. Note that the subject
repo's own `config.nims` task adds `--styleCheck:usages --styleCheck:error`,
`--outdir:build --nimcache:build/nimcache -f` etc. — **none of these apply** to
the pinned out-of-tree builds (the repo's config.nims is not loaded; nothing is
written into the subject repo).
