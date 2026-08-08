#!/usr/bin/env bash
# Milestone acceptance criteria that can only be proven at the process level —
# a boot that must fail, a validator that must reject a file. Everything else
# lives in tests/ and runs via tools/run_tests.gd.
#
#   GODOT=/path/to/godot tools/acceptance.sh [milestone ...]
#
# With no arguments every milestone check runs. Exits non-zero on any failure.

set -uo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SELECTED=("$@")

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }

wanted() {
  [ ${#SELECTED[@]} -eq 0 ] && return 0
  local milestone
  for milestone in "${SELECTED[@]}"; do [ "$milestone" = "$1" ] && return 0; done
  return 1
}

# Run the game headlessly for one frame. Prints combined output; returns its exit code.
boot() { timeout 120 "$GODOT" --headless --quit 2>&1; }

validate_assets() { timeout 300 "$GODOT" --headless -s tools/validate_assets.gd 2>&1; }

# --------------------------------------------------------------------------- M0

m0() {
  echo "M0 — Project Bootstrap"

  # AC: a clean repo boots.
  local output
  output="$(boot)"
  if [ $? -eq 0 ] && grep -q "Scribblestein booted" <<<"$output"; then
    pass "clean repo boots to an empty scene"
  else
    fail "clean repo boots to an empty scene"
    echo "$output" | tail -20
  fi

  # AC: corrupting a value in parts_db.json crashes the boot, naming file, path and reason.
  cp data/parts_db.json data/parts_db.json.bak
  trap 'mv -f data/parts_db.json.bak data/parts_db.json 2>/dev/null || true' RETURN
  python3 - <<'PY'
import json
with open("data/parts_db.json") as handle:
    db = json.load(handle)
db["parts"]["torso_ribby"]["weight"] = "heavy"
with open("data/parts_db.json", "w") as handle:
    json.dump(db, handle, indent=2)
PY
  output="$(boot)"
  local code=$?
  mv -f data/parts_db.json.bak data/parts_db.json

  if [ $code -ne 0 ]; then
    pass "corrupt parts_db.json fails the boot (exit $code)"
  else
    fail "corrupt parts_db.json fails the boot — exited 0"
  fi
  for fragment in "data/parts_db.json" "/parts/torso_ribby/weight" "expected type number"; do
    if grep -qF "$fragment" <<<"$output"; then
      pass "boot failure names '$fragment'"
    else
      fail "boot failure names '$fragment'"
      echo "$output" | tail -20
    fi
  done

  # AC: a test PNG with a single gray pixel fails the asset validator.
  python3 - <<'PY'
import struct, zlib
w = h = 8
rows = b"".join(b"\x00" + b"".join(
    (b"\x80\x80\x80\xff" if (x, y) == (3, 5) else b"\x00\x00\x00\x00")
    for x in range(w)) for y in range(h))
def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows))
       + chunk(b"IEND", b""))
open("assets/fx/fx_gray_probe.png", "wb").write(png)
PY
  timeout 300 "$GODOT" --headless --import >/dev/null 2>&1
  output="$(validate_assets)"
  code=$?
  rm -f assets/fx/fx_gray_probe.png assets/fx/fx_gray_probe.png.import
  timeout 300 "$GODOT" --headless --import >/dev/null 2>&1

  if [ $code -ne 0 ] && grep -q "fx_gray_probe.png: first offending pixel at (3, 5)" <<<"$output"; then
    pass "one gray pixel fails validate_assets.gd, with coordinates"
  else
    fail "one gray pixel fails validate_assets.gd, with coordinates"
    echo "$output" | tail -20
  fi

  # AC: the clean asset set passes.
  output="$(validate_assets)"
  if [ $? -eq 0 ]; then
    pass "the committed asset set passes the validator"
  else
    fail "the committed asset set passes the validator"
    echo "$output" | tail -20
  fi
}

# --------------------------------------------------------------------------- M2

m2() {
  echo "M2 — Locomotion & Camera"
  local output suite
  for suite in movement camera; do
    output="$(timeout 900 "$GODOT" --headless -s tools/run_tests.gd -- "$suite" 2>&1)"
    if [ $? -eq 0 ]; then
      pass "$suite: measurements match the formulas in game_config.json"
    else
      fail "$suite: measurements match the formulas in game_config.json"
      echo "$output" | tail -30
    fi
  done
}

# --------------------------------------------------------------------------- M3

m3() {
  echo "M3 — The Lab & Scratchpad"
  local output suite
  for suite in lab; do
    output="$(timeout 900 "$GODOT" --headless -s tools/run_tests.gd -- "$suite" 2>&1)"
    if [ $? -eq 0 ]; then
      pass "lab: readouts, drag-drop refusal, unlock cost and the Scratchpad round trip"
    else
      fail "lab: readouts, drag-drop refusal, unlock cost and the Scratchpad round trip"
      echo "$output" | tail -30
    fi
  done
}

# --------------------------------------------------------------------------- M4

m4() {
  echo "M4 — Combat"
  local output suite
  for suite in combat ai; do
    output="$(timeout 900 "$GODOT" --headless -s tools/run_tests.gd -- "$suite" 2>&1)"
    if [ $? -eq 0 ]; then
      pass "$suite: damage formula, attack window, i-frames and the enemy FSM"
    else
      fail "$suite: damage formula, attack window, i-frames and the enemy FSM"
      echo "$output" | tail -30
    fi
  done
}

# --------------------------------------------------------------------------- M5

m5() {
  echo "M5 — Economy, Death & Save"
  local output
  output="$(timeout 900 "$GODOT" --headless -s tools/run_tests.gd -- economy 2>&1)"
  if [ $? -eq 0 ]; then
    pass "economy: corpse run, pity timer, duplicate conversion, Correction Fluid"
  else
    fail "economy: corpse run, pity timer, duplicate conversion, Correction Fluid"
    echo "$output" | tail -30
  fi
  output="$(timeout 900 "$GODOT" --headless -s tools/run_tests.gd -- save 2>&1)"
  if [ $? -eq 0 ]; then
    pass "save: atomic writes, migration and round trips"
  else
    fail "save: atomic writes, migration and round trips"
    echo "$output" | tail -30
  fi
}

# --------------------------------------------------------------------------- run
# Add each milestone's function name here as it lands.
MILESTONES=(m0 m2 m3 m4 m5)

for milestone in "${MILESTONES[@]}"; do
  if wanted "${milestone^^}" || [ ${#SELECTED[@]} -eq 0 ]; then
    $milestone
  fi
done

echo
echo "----------------------------------------------------------------------"
if [ $FAIL -eq 0 ]; then
  echo "ACCEPTANCE PASSED — $PASS check(s)."
  exit 0
fi
echo "ACCEPTANCE FAILED — $FAIL of $((PASS + FAIL)) check(s) failed."
exit 1
