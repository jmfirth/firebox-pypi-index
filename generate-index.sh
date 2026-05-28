#!/usr/bin/env bash
set -euo pipefail

# Generate the PEP 503 simple repository index from wheels in packages/.
#
# Mirrors the shape of wasix-org/python-index's generate-index.sh:
#   1. Collect all .whl and .tar.gz files from packages/
#   2. Compute sha256 digests for each
#   3. Build a JSON-lines package list for dumb-pypi
#   4. Run dumb-pypi to generate the static HTML index under dist/
#   5. Copy packages into dist/packages/ so relative URLs resolve
#
# When packages/ is empty (MVP state), this produces an empty index
# with just the root landing page and /simple/ directory listing.

cd "$(dirname "$0")"

PACKAGES_DIR="packages"
OUTPUT_DIR="dist"

# Step 1: Collect wheel and sdist files
shopt -s nullglob
wheel_files=()
for f in "${PACKAGES_DIR}"/*.whl "${PACKAGES_DIR}"/*.tar.gz; do
    wheel_files+=("$f")
done
shopt -u nullglob

package_list=$(mktemp)
trap 'rm -f "$package_list"' EXIT

if [ ${#wheel_files[@]} -eq 0 ]; then
    echo "No packages found in ${PACKAGES_DIR}/ — generating empty index."
    # Create an empty package list so dumb-pypi still produces the root index
    touch "$package_list"
else
    for filepath in "${wheel_files[@]}"; do
        filename=$(basename "$filepath")
        sha256=$(sha256sum "$filepath" | awk '{print $1}')

        # dumb-pypi expects: filename<tab>sha256=<hash>
        printf '%s\tsha256=%s\n' "$filename" "$sha256" >> "$package_list"
    done
fi

# Step 3: Generate static HTML via dumb-pypi
uv run dumb-pypi \
    --package-list "$package_list" \
    --output-dir "$OUTPUT_DIR" \
    --packages-url "../../packages/" \
    --title "firebox-pypi-index"

# Step 4: Copy landing page and any supplementary files
cp index.html "$OUTPUT_DIR/index.html"

# Step 5: Copy packages into dist/packages/ so relative URLs resolve
if [ ${#wheel_files[@]} -gt 0 ]; then
    mkdir -p "$OUTPUT_DIR/packages"
    for filepath in "${wheel_files[@]}"; do
        cp "$filepath" "$OUTPUT_DIR/packages/$(basename "$filepath")"
    done
fi

echo "Index generated in $OUTPUT_DIR/"
echo "  Packages: ${#wheel_files[@]}"
echo "  URL: https://pythonindex.firebox.run/simple/"