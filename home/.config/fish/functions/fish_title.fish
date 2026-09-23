function fish_title
    set out ""
    if test (status current-command) = fish
        set out $PWD
    else
        set out (status current-command)
    end
    echo $out
end
