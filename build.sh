#!/bin/sh
# 危险Shell拦截 DSI - 构建脚本
# 将模块目录打包为 Magisk / KernelSU 风格的 ZIP。
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/dist"
ZIP="$OUT/危险Shell拦截DSI.zip"

# 确保脚本具有可执行权限
chmod 0755 "$HERE/dsi/bin/dsi" 2>/dev/null || true
chmod 0755 "$HERE"/*.sh 2>/dev/null || true

mkdir -p "$OUT"
rm -f "$ZIP"

cd "$HERE"
python3 - "$HERE" "$ZIP" <<'PY'
import os, sys, zipfile

root, zip_path = sys.argv[1], sys.argv[2]
exclude_dirs = {".git", "dist", "docs", "__pycache__"}
exclude_files = {"build.sh", "README.md", "LICENSE", ".DS_Store"}

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirnames, filenames in os.walk(root):
        # 过滤排除目录
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for fn in filenames:
            if fn in exclude_files:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            if rel.startswith("."):
                continue
            z.write(full, rel)
print("已生成:", zip_path)
PY

echo "模块 ZIP 已生成: $ZIP"
ls -lh "$ZIP"
