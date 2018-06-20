#!/bin/bash

last_arg="${@: -1}"
#echo $last_arg

extension="${last_arg##*.}"
#echo $extension
dir=$(dirname "${last_arg}")
filename=$(basename "${last_arg}")
#echo $dir1
#echo $filename1

length=$(($#-1))
array=${@:1:$length}
#echo $array
feh $array --start-at $dir/$filename $dir/*.$extension 2>/dev/null
