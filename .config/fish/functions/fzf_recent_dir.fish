function fzf_recent_dir -d "List files and folders"
    begin
        eval "__z -l | awk '{print \$2}' | "(__fzfcmd) "-m $FZF_DEFAULT_OPTS" --no-sort | while read -l s; set results $results $s; end
    end

    if test -z "$results"
        return
    else
        cd $results
    end
end
