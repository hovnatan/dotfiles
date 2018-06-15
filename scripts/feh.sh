#!/bin/bash


last_arg="${@: -1}"

extension="${last_arg##*.}"
#echo $extension
dir1=$(dirname "${last_arg}")
#echo $dir1

length=$(($#-1))
array=${@:1:$length}
#echo $array
feh $array --start-at $last_arg $dir1/*.$extension 2>/dev/null
