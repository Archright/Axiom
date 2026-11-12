#!/usr/bin/env bash
# Capability-delta contrast experiment for nph config parsing.
# Compares: defect-input configs vs valid-TOML equivalents vs baseline.
set -u
NPH=/tmp/capdelta/nph/nph
ROOT=/tmp/capdelta/exp
WORK=$ROOT/work
rm -rf "$WORK"; mkdir -p "$WORK"

mklm() { # make misformatted nim files in $1
  local d=$1
  mkdir -p "$d/sub"
  printf 'echo  "a"\n' > "$d/a.nim"       # double space -> needs reformat
  printf 'echo\t"b"\n' > "$d/b.nims"      # tab -> needs reformat
  printf 'echo   "c"\n' > "$d/sub/b.nim"  # triple space -> needs reformat
  printf 'not nim\n' > "$d/c.txt"
  printf 'echo "ok"\n' > "$d/ok.nim"      # already formatted
}

run() { # name, cmd...
  local name=$1; shift
  echo "================ $name ================"
  ( "$@" 2>"$WORK/.stderr" | cat -v )
  local rc=$?
  echo "--- exit: $rc"
  echo "--- stderr: $(cat "$WORK/.stderr")"
}

cd "$WORK"

### T0: baseline - no config
mklm "$WORK/t0"; cd "$WORK/t0"
run "T0 baseline (no config) --check ." "$NPH" --check .
run "T0b baseline --diff . (first 5 lines)" bash -c "$NPH --diff . | head -5"

### T1: VALID config excluding everything (probe: are filters live at all?)
mklm "$WORK/t1"; cd "$WORK/t1"
printf 'exclude = [".*"]\n' > .nph.toml
run "T1 VALID exclude=[\".*\"] --check ." "$NPH" --check .

### T2: duplicate-key defect (i): last-wins  vs valid equivalent
mklm "$WORK/t2d"; cd "$WORK/t2d"
printf 'exclude = ["xxxx_never"]\nexclude = [".*"]\n' > .nph.toml
run "T2-DEFECT duplicate exclude, 2nd=.* --check ." "$NPH" --check .
mklm "$WORK/t2v"; cd "$WORK/t2v"
printf 'exclude = [".*"]\n' > .nph.toml
run "T2-VALID  single exclude=.*     --check ." "$NPH" --check .

### T3: duplicate color (i): true then false vs valid false (observable via --diff ANSI)
mkcfg_color() { printf 'color = %s\ncolor = %s\n' "$1" "$2" > "$3"; }
mklm "$WORK/t3d"; cd "$WORK/t3d"
mkcfg_color true false .nph.toml
run "T3-DEFECT color=true,color=false --diff ." bash -c "$NPH --diff . | head -4"
mklm "$WORK/t3v"; cd "$WORK/t3v"
printf 'color = false\n' > .nph.toml
run "T3-VALID  color=false            --diff ." bash -c "$NPH --diff . | head -4"
mklm "$WORK/t3d2"; cd "$WORK/t3d2"
mkcfg_color false true .nph.toml
run "T3-DEFECT2 color=false,color=true --diff ." bash -c "$NPH --diff . | head -4"
mklm "$WORK/t3v2"; cd "$WORK/t3v2"
printf 'color = true\n' > .nph.toml
run "T3-VALID2  color=true             --diff ." bash -c "$NPH --diff . | head -4"

### T4: trailing-skip defect (ii): 4 fields + unknown key + garbage table
mklm "$WORK/t4d"; cd "$WORK/t4d"
cat > .nph.toml <<'EOF'
exclude = []
extend-exclude = ["sub"]
include = ["\\.nim$"]
color = true
unknown_key = "attacker controlled"
[[attacker_table]]
some = "garbage"
EOF
run "T4-DEFECT 4 fields + trailing garbage --diff ." bash -c "$NPH --diff . | head -4"
mklm "$WORK/t4v"; cd "$WORK/t4v"
cat > .nph.toml <<'EOF'
exclude = []
extend-exclude = ["sub"]
include = ["\\.nim$"]
color = true
EOF
run "T4-VALID  same 4 fields, no garbage  --diff ." bash -c "$NPH --diff . | head -4"
# unknown key WITHOUT defect coverage: alone, must warn+defaults
mklm "$WORK/t4u"; cd "$WORK/t4u"
printf 'unknown_key = "x"\n' > .nph.toml
run "T4-UNKNOWN unknown key only --check ." "$NPH" --check .

### T5: outright broken TOML -> warn + defaults
mklm "$WORK/t5"; cd "$WORK/t5"
printf 'this is [[ not toml\n' > .nph.toml
run "T5-BROKEN invalid TOML --check ." "$NPH" --check .

### T6: trailing junk on SAME LINE as last value (checkEol path)
mklm "$WORK/t6"; cd "$WORK/t6"
printf 'color = true junk\n' > .nph.toml
run "T6 same-line junk after last value --diff ." bash -c "$NPH --diff . | head -4"

### T7: config discovery - is .nph.toml picked up from a SUBDIRECTORY run?
mklm "$WORK/t7"; cd "$WORK/t7"
printf 'color = true\n' > .nph.toml
cd "$WORK/t7/sub"
run "T7 run from sub/ (config in parent) --check ." bash -c "cd $WORK/t7/sub && $NPH --check . ; echo exit=\$?"

echo "ALL DONE"
