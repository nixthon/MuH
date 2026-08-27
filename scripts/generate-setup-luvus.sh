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
PI_MANIFEST="$PROJECT_DIR/Resources/luvus-plugin/pi-manifest.toml"
PI_EXTENSION="$PROJECT_DIR/Resources/luvus-plugin/pi-extension.ts"

replace_block() {
    local file="$1" start="$2" end="$3" content="$4" tmp
    tmp=$(mktemp "${file}.XXXXXX")
    awk -v start="$start" -v end="$end" -v content="$content" '
        index($0, start) > 0 {
            print $0
            while ((getline line < content) > 0) print line
            close(content)
            skip = 1
            next
        }
        skip && index($0, end) > 0 { print $0; skip = 0; next }
        !skip { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

tmp_pi_manifest=$(mktemp)
{
    printf "cat << 'MUH_PI_MANIFEST' > \"\$LUVUS_MANIFESTS_DIR/pi.toml\"\n"
    cat "$PI_MANIFEST"
    printf "MUH_PI_MANIFEST\n"
} > "$tmp_pi_manifest"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED PI MANIFEST' \
    '# END GENERATED PI MANIFEST' \
    "$tmp_pi_manifest"
rm -f "$tmp_pi_manifest"

tmp_pi_ext=$(mktemp)
{
    printf "cat << 'MUH_PI_EXTENSION' > \"\$PI_EXTENSIONS_DIR/luvus-agent-state.ts\"\n"
    cat "$PI_EXTENSION"
    printf "MUH_PI_EXTENSION\n"
} > "$tmp_pi_ext"
replace_block "$SETUP_SCRIPT" \
    '# BEGIN GENERATED PI EXTENSION' \
    '# END GENERATED PI EXTENSION' \
    "$tmp_pi_ext"
rm -f "$tmp_pi_ext"

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
