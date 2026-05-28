#!/usr/bin/env bash
set -euo pipefail

# Generate the PEP 503 simple repository index from a JSON manifest of
# GitHub Release assets.
#
# Architecture (LOCKED per design-v1.md):
#   Wheels are NOT committed to this repo — they live as GitHub Release
#   assets on jmfirth/firebox-pypi-index. This script reads a manifest
#   file (release-assets.jsonl) that lists each wheel's filename, sha256,
#   and release tag, then produces static HTML under dist/ with links
#   pointing at the Release download URLs.
#
#   release-assets.jsonl format (one JSON object per line):
#     {"filename": "pkg-1.0.0-cp313-cp313-wasix_wasm32.whl",
#      "sha256": "abc...",
#      "tag": "v0.1.0"}
#
#   The generated HTML links to:
#     https://github.com/jmfirth/firebox-pypi-index/releases/download/<tag>/<filename>
#
#   dumb-pypi's --packages-url uses __tag__ as a placeholder; a post-pass
#   substitutes the actual tag per-package from the manifest.
#
# MVP state (this task): release-assets.jsonl is empty. The index is empty.
# Pip cascades to wasix-extras for all packages. The first wheel ships
# when #676 lands (Saturday Opus — cryptography + cffi).
#
# Reference: wasix-org/python-index (generate-index.sh + dumb-pypi pattern).

cd "$(dirname "$0")"

MANIFEST="${1:-release-assets.jsonl}"
OUTPUT_DIR="dist"
RELEASE_BASE="https://github.com/jmfirth/firebox-pypi-index/releases/download"

# Build package list for dumb-pypi
package_list=$(mktemp)
trap 'rm -f "$package_list"' EXIT

if [ ! -s "$MANIFEST" ]; then
    echo "No manifest at ${MANIFEST} — generating empty index."
    touch "$package_list"
else
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filename=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['filename'])")
        sha256=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['sha256'])")
        printf '%s\tsha256=%s\n' "$filename" "$sha256" >> "$package_list"
    done < "$MANIFEST"
fi

# Generate static HTML via dumb-pypi
uv run dumb-pypi \
    --package-list "$package_list" \
    --output-dir "$OUTPUT_DIR" \
    --packages-url "${RELEASE_BASE}/__tag__/" \
    --title "firebox-pypi-index"

# Copy landing page
cp index.html "$OUTPUT_DIR/index.html"

# Substitute __tag__ placeholder with actual release tag per-package
if [ -s "$MANIFEST" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filename=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['filename'])")
        tag=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['tag'])")
        package_dir=$(echo "$filename" | sed -E 's/^([^0-9]*[-_]?[^-]*).*/\L\1/')
        pkg_html="${OUTPUT_DIR}/simple/${package_dir}/index.html"
        [ -f "$pkg_html" ] && sed -i '' "s|__tag__|${tag}|g" "$pkg_html"
    done < "$MANIFEST"
fi

echo "Index generated in $OUTPUT_DIR/"
echo "  Packages: $(wc -l < "$package_list" | tr -d ' ')"
echo "  URL: https://pythonindex.firebox.run/simple/"