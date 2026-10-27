#!/bin/sh
# Mengambil model uji VRM 1.0 (pixiv/three-vrm, lisensi VRM 1.0: https://vrm.dev/licenses/1.0/).
# Tidak di-commit ke repo (10 MB). Setelah diunduh, impor: godot --headless --path . --import
set -e
mkdir -p testdata/vrm1
curl -fL -o testdata/vrm1/VRM1_Constraint_Twist_Sample.vrm \
  https://raw.githubusercontent.com/pixiv/three-vrm/dev/packages/three-vrm/examples/models/VRM1_Constraint_Twist_Sample.vrm
echo "OK: testdata/vrm1/VRM1_Constraint_Twist_Sample.vrm"
