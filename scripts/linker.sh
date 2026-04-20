#!/usr/bin/env sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOTDIR="$SCRIPT_DIR/../"

if [[ "$#" -lt 1 ]]; then
    echo "Usage: linker.sh pathToDots"
    exit
fi

echo "$DOTDIR"

if [[ -d $DOTDIR/$1 ]]; then
    $DOTDIR/$1/link.sh
else
    echo "Path to dots not found in dotfiles dir !"
fi
