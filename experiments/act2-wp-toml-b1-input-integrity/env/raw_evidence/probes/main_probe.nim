# nim-check: skip
# Standalone subject probe: imports out-of-tree pinned packages (stew /
# serialization / toml_serialization) via explicit --path. Cannot resolve those
# imports in repo context by design (Zero-Footprint: subjects are never vendored
# into this repo). Integrity is verified by executing the probe against the
# pinned packages (see ../consumed_files_strace.txt and ../../dependency_sources.md).
# Marker + rationale follow experiments/bug-verdict-e2e/cout_probe.nim.
import toml_serialization
import serialization/object_serialization

echo "main probe ok"
