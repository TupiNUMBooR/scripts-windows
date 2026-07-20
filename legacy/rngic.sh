#!/usr/bin/env bash

fails=0

for ((i=0;i<=10;i++)); do
    if (( RANDOM % 2 )); then
        echo "step $i : ok"
    else
        echo "step $i : fail"
        ((fails++))
        ((i=-1))
    fi
done

echo "finished in $fails fails"
