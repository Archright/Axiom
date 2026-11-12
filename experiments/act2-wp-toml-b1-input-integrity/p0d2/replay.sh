#!/usr/bin/env bash
# replay.sh - P0-D2 3-way contrast replay (nim-toml-serialization D2 in
# consumer nimbus-eth1 @ 0c0230857dd8, vendor pin 73529768).
#
# Re-runs the full experiment: materializes the pinned dependency tree into
# /tmp/p0d2_env (git-archive export of the subject pin + curl of the sibling
# vendor pins), verifies per-file identity via probes/deps.SHA256SUMS,
# recompiles the probe from probes/p0d2_probe.nim, runs the three cases, and
# writes raw/{baseline,defect,contrast}.{out,err,exit} + raw/build.log.
#
# Determinism contract: running this script twice produces byte-identical
# per-case outputs (the probe prints no timestamps, no env-dependent data).
# Verified: 2026-10-11 (see experiment.md).
set -euo pipefail

EXP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${ENV_DIR:-/tmp/p0d2_env}"
SUBJECT_CLONE="${SUBJECT_CLONE:-<workspace>/nim-toml-serialization}"
NIM="${NIM:-$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim}"

# Pinned identities (nimbus-eth1 vendor/ submodules at commit 0c0230857dd8)
TOML_PIN="73529768ced17720f78fb5b57191e863f8d8a9c1"
CONFUTILS_PIN="671145b7e68fb9dcac08b62b890d44eb15c72859"
STEW_PIN="83eb1157963b7f49351dbdd858355fa990bbe23c"
SERIALIZATION_PIN="4092500cea76154576539371709ae801afbd2a9d"
FASTSTREAMS_PIN="50889cd16ec8771106cdd0eeea460039e8571e06"
UNITTEST2_PIN="92e1c13dcfb6d7e4ea6fb624fe9cc31e3dc76813"   # fetched, not imported
RESULTS_PIN="df8113dda4c2d74d460a8fa98252b0b771bf1f27"

fetch_dep() { # <repo> <sha> <name> [owner=status-im]
  local repo="$1" sha="$2" name="$3" owner="${4:-status-im}" tmp
  if [ -d "$ENV_DIR/deps/$name" ] && [ -n "$(ls -A "$ENV_DIR/deps/$name" 2>/dev/null)" ]; then
    return 0
  fi
  mkdir -p "$ENV_DIR/deps/$name"
  tmp="$(mktemp -d)"
  curl -sfL "https://codeload.github.com/$owner/$repo/tar.gz/$sha" -o "$tmp/$repo.tgz"
  tar xzf "$tmp/$repo.tgz" -C "$tmp"
  mv "$tmp/${repo}-${sha}"/* "$ENV_DIR/deps/$name/"
  rm -rf "$tmp"
  echo "fetched $owner/$repo @ ${sha:0:12} -> deps/$name"
}

mkdir -p "$ENV_DIR/deps" "$ENV_DIR/bin" "$ENV_DIR/build" "$ENV_DIR/inputs"

# 1. Subject pin: read-only git-archive export (subject clone stays untouched)
if [ ! -f "$ENV_DIR/deps/toml_serialization/toml_serialization/lexer.nim" ]; then
  mkdir -p "$ENV_DIR/deps/toml_serialization"
  git -C "$SUBJECT_CLONE" archive "$TOML_PIN" | tar -x -C "$ENV_DIR/deps/toml_serialization"
  echo "exported toml_serialization @ ${TOML_PIN:0:12} from $SUBJECT_CLONE"
fi

# 2. Sibling vendor pins (as pinned by nimbus-eth1 @ 0c0230857dd8)
fetch_dep nim-confutils    "$CONFUTILS_PIN"    nim-confutils
fetch_dep nim-stew         "$STEW_PIN"         stew
fetch_dep nim-serialization "$SERIALIZATION_PIN" serialization
fetch_dep nim-faststreams  "$FASTSTREAMS_PIN"  faststreams
fetch_dep nim-unittest2    "$UNITTEST2_PIN"    unittest2
fetch_dep nim-results      "$RESULTS_PIN"      results arnetheduck

# 3. Identity check of load-bearing dependency files
( cd "$ENV_DIR" && sha256sum -c "$EXP_DIR/probes/deps.SHA256SUMS" --quiet )

# 4. Input staging + input identity check
cp "$EXP_DIR"/inputs/baseline.toml "$EXP_DIR"/inputs/defect.toml "$EXP_DIR"/inputs/contrast.toml "$ENV_DIR/inputs/"
( cd "$EXP_DIR/inputs" && sha256sum -c sha256sums.txt --quiet )

# 5. Fresh rebuild of the probe from the archived source (neutral cwd: /tmp;
#    compiling inside a tree whose ancestor has nimble.lock would disable
#    nimble path resolution - JUDGMENT.md 1.6 risk #1)
cd "$ENV_DIR"
cp "$EXP_DIR/probes/p0d2_probe.nim" "$ENV_DIR/probe.nim"
rm -rf "$ENV_DIR/build/nimcache_p0d2" "$ENV_DIR/bin/p0d2_probe"
OUT_DIR="$EXP_DIR/raw"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
{
  echo "nim: $("$NIM" --version | head -1)"
  echo "ulimit -s: $(ulimit -s)"
} > "$EXP_DIR/raw/build.log"
"$NIM" c --warnings:off --hints:off --mm:orc \
  --skipUserCfg --skipParentCfg --skipProjCfg \
  --nimcache:"$ENV_DIR/build/nimcache_p0d2" \
  --path:"$ENV_DIR/deps/nim-confutils" \
  --path:"$ENV_DIR/deps/toml_serialization" \
  --path:"$ENV_DIR/deps/stew" \
  --path:"$ENV_DIR/deps/serialization" \
  --path:"$ENV_DIR/deps/faststreams" \
  --path:"$ENV_DIR/deps/unittest2" \
  --path:"$ENV_DIR/deps/results" \
  --out:"$ENV_DIR/bin/p0d2_probe" \
  "$ENV_DIR/probe.nim" >> "$EXP_DIR/raw/build.log" 2>&1

# 6. The three cases
for c in baseline defect contrast; do
  set +e
  ( cd "$ENV_DIR" && "$ENV_DIR/bin/p0d2_probe" "$c" "inputs/$c.toml" ) \
    > "$OUT_DIR/$c.out" 2> "$OUT_DIR/$c.err"
  echo "$?" > "$OUT_DIR/$c.exit"
  set -e
done

echo "replay complete: $OUT_DIR/{baseline,defect,contrast}.{out,err,exit}"
