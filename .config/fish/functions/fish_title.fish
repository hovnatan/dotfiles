function fish_title
    set out ""
    if [ $_ = "fish" ]
        set out $PWD
    else
        set out $_
    end
    echo $out
    if [ $TMUX ]
        set outde (echo $out | sed -e 's:.*/::' | sed -e 's/^\(.\{10\}\).*/\1/' )
        tmux rename-window "In $outde"
    end
end
