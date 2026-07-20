#!/usr/bin/env bash
set -u

COL_PATH=70
COL_SIZE=10
USERNAME=k

paths=(
"/mnt/c/Program Files/Docker"
"/mnt/c/Users/$USERNAME/AppData/Local/Docker"

"/mnt/c/Users/$USERNAME/ComfyUI"

"/mnt/c/Program Files (x86)/Steam"
"/mnt/c/Program Files (x86)/Steam/steamapps"

"/mnt/c/Users/$USERNAME/AppData/Local/Temp"
"/mnt/c/Windows/Temp"

"/mnt/c/Users/$USERNAME/.cache"
"/mnt/c/Users/$USERNAME/.m2"
"/mnt/c/Users/$USERNAME/.npm"
)

printf "%-${COL_PATH}s %${COL_SIZE}s\n" "PATH" "SIZE"
printf "%-${COL_PATH}s %${COL_SIZE}s\n" "$(printf '%.0s-' $(seq 1 $COL_PATH))" "$(printf '%.0s-' $(seq 1 $COL_SIZE))"

for pattern in "${paths[@]}"; do
    for dir in "$pattern"; do

        if [[ -d "$dir" ]]; then
            size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
            size=${size:-"-"}
        else
            size="-"
        fi

        printf "%-${COL_PATH}s %${COL_SIZE}s\n" "$dir" "$size"

    done
done
