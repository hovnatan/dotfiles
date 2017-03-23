function fish_title
    set out ""
    if [ $_ = "fish" ]
        set out (basename $PWD)
    else
        set out $_ 
    end
    echo $out
    if [ $TMUX ]
        set outde (echo $out | sed -e 's/.*\(...............\)/\1/' | sed -e 's/-*\(.*\)/\1/g' )
        tmux rename-window "$outde" 
    end
end
