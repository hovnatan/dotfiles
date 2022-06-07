function fish_title
    set out ""
    if [ $_ = "fish" ]
        set out $PWD
    else
        set out $_
    end
    echo $out
end
