#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp/home
echo "== [0] sandbox state =="
id || true
ls /home 2>&1 || true
ls /root 2>&1 || true
curl_exit=0
curl -s -m 10 https://cache.mathlib.org >/dev/null 2>&1 || curl_exit=$?
echo "curl_exit=$curl_exit"
echo "== [1] workspace copy =="
cp -a --reflink=auto /tmp/b1_gate_a/leanproj /workspace/leanproj
echo "== [2] force fresh root compile =="
rm -rf /workspace/leanproj/.lake/build
echo "== [3] cache unpack =="
cd /workspace/leanproj
lake exe cache unpack
echo "== [4] build =="
lake build
echo "== [5] print axioms =="
lake env lean PrintAxioms.lean
echo "== [6] artifact digests =="
find /workspace/leanproj/.lake/build -name '*.olean' -type f -print0 | sort -z | xargs -0 sha256sum
echo "== [7] ro-mount check =="
touch /toolchain/.write_test 2>&1 || echo "toolchain_readonly=ok"
touch /cache/.write_test 2>&1 || echo "cache_readonly=ok"
touch /tmp/b1_gate_a/leanproj/.write_test 2>&1 || echo "inputs_readonly=ok"
