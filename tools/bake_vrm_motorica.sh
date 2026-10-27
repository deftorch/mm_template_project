#!/usr/bin/env bash
# Bake database Motion Matching sebuah library lewat editor Godot (tanpa GPU: Xvfb + Mesa).
# Pemakaian: tools/bake_vrm_motorica.sh [library.tres] [scene.tscn] [NamaNodeMMCharacter]
# Default: animation/vrm_motorica_library.tres pada scenes/main_template.tscn / ThreeVRMGirl
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export BAKE_LIB="${1:-res://animation/vrm_motorica_library.tres}"
export BAKE_SCENE="${2:-res://scenes/main_template.tscn}"
export BAKE_NODE="${3:-ThreeVRMGirl}"
cp project.godot /tmp/project.godot.bak
trap 'cp /tmp/project.godot.bak project.godot' EXIT
python3 - <<'PY'
p='project.godot'; t=open(p).read()
t=t.replace('[autoload]\n','[autoload]\n\nBakeTmp="*res://tools/bake_library_editor.gd"',1)
open(p,'w').write(t)
PY
xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --editor --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 2>&1 | grep -E "\[bake\]|ERROR" || true
