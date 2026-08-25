#!/usr/bin/env bash
# Regenerate the embedded Luvus module in setup-luvus.sh from the canonical
# Resources/luvus-plugin files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SETUP_SCRIPT="$PROJECT_DIR/Resources/scripts/setup-luvus.sh"
MANIFEST="$PROJECT_DIR/Resources/luvus-plugin/luvus-module.toml"
PLUGIN="$PROJECT_DIR/Resources/luvus-plugin/index.js"
RUNNER="$PROJECT_DIR/Resources/luvus-plugin/run.sh"

replace_block() {
    local file="$1" start="$2" end="$3" content="$4" tmp
    tmp=$(mktemp "${file}.XXXXXX")
    awk -v start="$start" -v end="$end" -v content="$content" '
        $0 == start {
            print start
            while ((getline line < content) > 0) print line
            close(content)
            skip = 1
            next
        }
        skip && $0 == end { print end; skip = 0; next }
        !skip { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

tmp_manifest=$(mktemp)
{
    printf "cat << 'MUH_MODULE_MANIFEST' > \"\$MODULE_DIR/luvus-module.toml\"\n"
    cat "$MANIFEST"
    printf "MUH_MODULE_MANIFEST\n"
} > "$tmp_manifest"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED MODULE MANIFEST' \
    '# END GENERATED MODULE MANIFEST' \
    "$tmp_manifest"
rm -f "$tmp_manifest"

tmp_runner=$(mktemp)
{
    printf "cat << 'MUH_MODULE_RUNNER' > \"\$MODULE_DIR/run.sh\"\n"
    cat "$RUNNER"
    printf "MUH_MODULE_RUNNER\n"
} > "$tmp_runner"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED MODULE RUNNER' \
    '# END GENERATED MODULE RUNNER' \
    "$tmp_runner"
rm -f "$tmp_runner"

tmp_plugin=$(mktemp)
{
    printf "cat << 'MUH_MODULE_INDEX' > \"\$MODULE_DIR/index.js\"\n"
    cat "$PLUGIN"
    printf "MUH_MODULE_INDEX\n"
} > "$tmp_plugin"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED MODULE INDEX' \
    '# END GENERATED MODULE INDEX' \
    "$tmp_plugin"
rm -f "$tmp_plugin"

chmod +x "$SETUP_SCRIPT"
echo "Generated embedded Luvus module in $SETUP_SCRIPT"
