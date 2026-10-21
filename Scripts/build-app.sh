#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
scratch_dir="${CHAPTERLOOM_BUILD_DIR:-/private/tmp/chapterloom-build}"
cache_dir="${CHAPTERLOOM_CACHE_DIR:-/private/tmp/chapterloom-spm-cache}"
module_cache="${CHAPTERLOOM_MODULE_CACHE:-/private/tmp/chapterloom-swift-cache}"
clang_cache="${CHAPTERLOOM_CLANG_CACHE:-/private/tmp/chapterloom-clang-cache}"
output_dir="${CHAPTERLOOM_OUTPUT_DIR:-${project_dir}/dist}"

mkdir -p "$scratch_dir" "$cache_dir" "$module_cache" "$clang_cache" "$output_dir"
cd "$project_dir"
CLANG_MODULE_CACHE_PATH="$clang_cache" SWIFT_MODULE_CACHE_PATH="$module_cache" \
  swift build --disable-sandbox --configuration release \
  --cache-path "$cache_dir" --scratch-path "$scratch_dir" \
  -Xswiftc -module-cache-path -Xswiftc "$module_cache" \
  -Xcc -fmodules-cache-path="$clang_cache"

app="$output_dir/Chapterloom.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$scratch_dir/release/Chapterloom" "$app/Contents/MacOS/Chapterloom"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign - "$app"
echo "$app"
