function fish_right_prompt --description 'Write out the prompt'
    if set -q VIRTUAL_ENV
      printf "%s%s%s" (set_color 4B8BBE) "(" (basename "$VIRTUAL_ENV") ")" (set_color normal)
    end
  if set -q fish_command_timer_string
    echo "$fish_command_timer_string"
  end
end

