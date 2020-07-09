if [[ $(ps --no-header --pid=$PPID --format=cmd) != "fish" ]] && [[ -z "$BASH_EXECUTION_STRING" ]]
then
    exec fish
fi
