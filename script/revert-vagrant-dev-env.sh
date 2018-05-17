#!/bin/bash

while IFS= read -r -d '' i ; do
    f=${i%.orig};
    if [ -L "$f" ]; then
        echo "reverting $i to $f"
        rm "$f"
        mv "$i" "$f"
    fi
done < <(find /usr/ -name "*.orig" -print0)
