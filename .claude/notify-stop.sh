#!/bin/sh
# Claude Code Stop hook: ring the bell and post a Ghostty desktop
# notification (OSC 777) when Claude finishes responding. Hook processes
# may lack a controlling tty (/dev/tty fails), so walk up the process tree
# to the claude process and write to its terminal device directly. Inside
# tmux the OSC needs the passthrough envelope (allow-passthrough in
# .tmux.conf), while the bell is forwarded natively.
p=$PPID
t=""
i=0
while [ "$i" -lt 5 ] && [ -n "$p" ] && [ "$p" != "1" ]; do
  t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
  if [ -n "$t" ] && [ "$t" != "??" ]; then
    break
  fi
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
if [ -z "$t" ] || [ "$t" = "??" ]; then
  exit 0
fi
T="/dev/$t"
{
  printf '\a' > "$T"
  if [ -n "$TMUX" ]; then
    printf '\033Ptmux;\033\033]777;notify;Claude Code;Finished responding\007\033\\' > "$T"
  else
    printf '\033]777;notify;Claude Code;Finished responding\007' > "$T"
  fi
} 2>/dev/null
exit 0
