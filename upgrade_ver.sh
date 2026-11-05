#!/bin/bash
# Local version preparation only. Publishing is a separate, explicit operation.
set -euo pipefail
cd "$(dirname "$0")"
if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：./upgrade_ver.sh 2.0.0（仅修改本地 podspec 并运行验证）" >&2
  exit 1
fi
python3 - "$1" <<'PY'
from pathlib import Path
import re, sys
path = Path('StoreKitFlow.podspec')
path.write_text(re.sub(r'spec.version = "[0-9.]+"', 'spec.version = "' + sys.argv[1] + '"', path.read_text()))
PY
swift test
if command -v pod >/dev/null 2>&1; then
  pod lib lint StoreKitFlow.podspec --quick
fi
echo "本地版本准备完成。请核对 CHANGELOG、真实沙盒验收和发布说明。"
echo "此脚本不会提交、打标签、推送或发布 CocoaPods。"
