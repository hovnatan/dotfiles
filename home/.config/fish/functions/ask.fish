# One-shot question to Claude Sonnet at medium effort: print the answer, exit.
#   ask how do I list a tar archive without extracting it
#   git diff | ask summarize this diff     # piped stdin rides along as context
#   ask are all git repos up to date here  # tools on: it can run git, read files
# Tools run in auto permission mode (the settings.json default; nobody is there
# to answer a prompt). Instruction files (CLAUDE.md, AGENTS.md) load as in an
# interactive session. The session is saved and its id printed first, so a
# follow-up continues it from the same directory:
#   claude -p --resume <id> 'and the nested repos?'
#
# Progress: claude streams JSON events; jq turns the session id and each tool
# call into a line on stderr and prints only the final answer on stdout, so
# `ask ... > f` keeps a clean answer while the steps still show in the terminal:
#   claude --output-format stream-json --> jq --+--> stderr  [  0s] session 1b2c...
#                                               |            [  4s] Bash: Show latest commit
#                                               +--> stdout  <final answer>
function ask --description 'One-shot question to Claude Sonnet (medium effort)'
    if test (count $argv) -eq 0
        echo 'usage: ask <question...>' >&2
        return 2
    end

    # Dim the progress lines only when they land on a terminal.
    set -l dim ''
    set -l reset ''
    if isatty stderr
        set dim (set_color brblack)
        set reset (set_color normal)
    end

    # A tool call is labeled by its most telling input: the Bash description,
    # else the command, path, pattern, url or query, cut to one short line.
    # A failed run (max turns, API error) prints its result to stderr and
    # makes jq exit 1.
    claude -p --model sonnet --effort medium --permission-mode auto \
        --output-format stream-json --verbose -- "$argv" |
        jq -nj --unbuffered --arg dim "$dim" --arg reset "$reset" '
            now as $t0
            | def progress(msg):
                "\($dim)[\(now - $t0 | floor | tostring | " " * (3 - length) + .)s] \(msg)\($reset)\n"
                | stderr | empty;
              inputs
            | if .type == "system" and .subtype == "init" then
                progress("session \(.session_id)")
              elif .type == "assistant" then
                .message.content[]
                | select(.type == "tool_use")
                | (.input | .description // .command // .file_path // .pattern // .url // .query // ""
                   | tostring | split("\n")[0] | .[0:100]) as $what
                | progress("\(.name): \($what)")
              elif .type == "result" then
                if .is_error or .subtype != "success" then
                    "ask: claude failed (\(.subtype)): \(.result // "")\n" | halt_error(1)
                else
                    .result + "\n"
                end
              else
                empty
              end'

    # Report the first failing stage: claude's own exit status, else jq's.
    set -l st $pipestatus
    test $st[1] -ne 0; and return $st[1]
    return $st[2]
end
