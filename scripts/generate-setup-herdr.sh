#!/usr/bin/env bash
# Regenerate the embedded Herdr plugin in setup-herdr.sh from the canonical
# Resources/herdr-plugin files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SETUP_SCRIPT="$PROJECT_DIR/Resources/scripts/setup-herdr.sh"
MANIFEST="$PROJECT_DIR/Resources/herdr-plugin/herdr-plugin.toml"
PLUGIN="$PROJECT_DIR/Resources/herdr-plugin/index.js"
RUNNER="$PROJECT_DIR/Resources/herdr-plugin/run.sh"

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
    printf "cat << 'MUH_PLUGIN_MANIFEST' > \"\$PLUGIN_DIR/herdr-plugin.toml\"\n"
    cat "$MANIFEST"
    printf "MUH_PLUGIN_MANIFEST\n"
} > "$tmp_manifest"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED PLUGIN MANIFEST' \
    '# END GENERATED PLUGIN MANIFEST' \
    "$tmp_manifest"
rm -f "$tmp_manifest"

tmp_runner=$(mktemp)
{
    printf "cat << 'MUH_PLUGIN_RUNNER' > \"\$PLUGIN_DIR/run.sh\"\n"
    cat "$RUNNER"
    printf "MUH_PLUGIN_RUNNER\n"
} > "$tmp_runner"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED PLUGIN RUNNER' \
    '# END GENERATED PLUGIN RUNNER' \
    "$tmp_runner"
rm -f "$tmp_runner"

tmp_plugin=$(mktemp)
{
    printf "cat << 'MUH_PLUGIN_INDEX' > \"\$PLUGIN_DIR/index.js\"\n"
    cat "$PLUGIN"
    printf "MUH_PLUGIN_INDEX\n"
} > "$tmp_plugin"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED PLUGIN INDEX' \
    '# END GENERATED PLUGIN INDEX' \
    "$tmp_plugin"
rm -f "$tmp_plugin"

chmod +x "$SETUP_SCRIPT"
echo "Generated embedded Herdr plugin in $SETUP_SCRIPT"
