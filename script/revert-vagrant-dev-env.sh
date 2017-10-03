#!/bin/bash

for i in $(find /usr/ -name "*.orig"); do
    f=${i%.orig};
    if [ -L "$f" ]; then
        echo "reverting $i to $f"
        rm $f
        mv $i $f
    fi
done
