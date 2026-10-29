#!/usr/bin/env sh

echo "Creating links for the Forge NixPIE repository..."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

mkdir -p "$SCRIPT_DIR/claude-memory" .claude

if [[ -f ./.claude/settings.local.json ]]; then
    jq --arg dir "$SCRIPT_DIR/claude-memory" '.autoMemoryDirectory = $dir' ./.claude/settings.local.json > ./.claude/settings.local.json.tmp
    mv ./.claude/settings.local.json.tmp ./.claude/settings.local.json
else
    cat > ./.claude/settings.local.json <<SETTINGS
{
  "autoMemoryDirectory": "$SCRIPT_DIR/claude-memory"
}
SETTINGS
fi
echo "Claude Code memory directory linked to $SCRIPT_DIR/claude-memory"

if [[ -f ./.git/info/exclude ]]; then
    mv ./.git/info/exclude ./.git/info/exclude_old
    echo "Old git exclude file backuped !"
fi

ln -s $SCRIPT_DIR/exclude ./.git/info/exclude

echo "Done"
