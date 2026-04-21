#!/usr/bin/env sh

echo "Creating links for the Forge NixPIE repository..."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [[ -f ./.git/info/exclude ]]; then
    mv ./.git/info/exclude ./.git/info/exclude_old
    echo "Old git exclude file backuped !"
fi

ln -s $SCRIPT_DIR/exclude ./.git/info/exclude

echo "Done"
