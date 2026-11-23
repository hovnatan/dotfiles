# agy's defaults for every session started from fish. They are flags here
# because agy has no setting that turns Remote Control on at startup (1.5.15),
# the way claude has remoteControlAtStartup, and its settings.json is not
# tracked: agy rewrites it with this machine's trusted folders. Subcommands and
# -p accept the flags too.
#
# The model pin steps aside when the command line names a model or an effort:
# agy does not merge the two sources, and a full model id such as
# gemini-4-argon-low next to an --effort falls back to agy's own default without
# a word (`agy models` lists the ids).
function agy --wraps agy --description 'agy with Remote Control on and a pinned model'
    set -l pin --model gemini-4-neon --effort high
    if string match -qr -- '^--?(model|effort)(=|$)' $argv
        set pin
    end
    command agy --remote-control $pin $argv
end
