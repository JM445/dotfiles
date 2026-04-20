#!/usr/bin/env sh

echo "Creating links for the Forge Intern repository..."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "use flake $SCRIPT_DIR/" > .envrc

if [[ -f ./.git/info/exclude ]]; then
    mv ./.git/info/exclude ./.git/info/exclude_old
    echo "Old git exclude file backuped !"
fi

ln -s $SCRIPT_DIR/exclude ./.git/info/exclude

echo "Done"
