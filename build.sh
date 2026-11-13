#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
build_dir="$script_dir/build"
app_dir="$build_dir/图片参数随机生成器.app"
exif_commit=1da714924f67763b6a8a7013dd2aa1983a16f87b

if [[ -e "$app_dir" ]]; then
  printf '输出已存在：%s\n请先移动或删除它，再重新构建。\n' "$app_dir" >&2
  exit 1
fi
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/photo-parameters-build.XXXXXXXX")
trap 'rm -rf "$temp_dir"' EXIT
git -C "$temp_dir" init -q
git -C "$temp_dir" remote add origin https://github.com/exiftool/exiftool.git
git -C "$temp_dir" -c advice.detachedHead=false fetch --depth 1 origin "$exif_commit"
git -C "$temp_dir" -c advice.detachedHead=false checkout --detach FETCH_HEAD
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/exiftool"
cp "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$script_dir/PhotoParameters.swift" "$app_dir/Contents/Resources/PhotoParameters.swift"
cp "$temp_dir/exiftool" "$app_dir/Contents/Resources/exiftool/exiftool"
cp -R "$temp_dir/lib" "$app_dir/Contents/Resources/exiftool/lib"
cp "$temp_dir/LICENSE" "$app_dir/Contents/Resources/exiftool/LICENSE"
swiftc -swift-version 5 "$script_dir/PhotoParameters.swift" -o "$app_dir/Contents/MacOS/PhotoParameters"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '构建完成：%s\n' "$app_dir"
