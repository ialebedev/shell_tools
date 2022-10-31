#!/bin/bash

find ${1} -type f \( -name '._*' -o -name '.DS_Store' -o -name '.nfs*' -o -iname '*.nk~*' -o -iname '*.nk.autosave' -o -name '*afanasy*' -o -iname '*.blend?' -o -name '*.mtl' \) -exec rm -fv {} +
find ${1} -type d \( -name '__MACOS*' -o -name '.TemporaryItems' -o -name '.Trash*' \) -exec rm -rfv {} +
