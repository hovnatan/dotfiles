# Plan: move the event logs to the system log

Written 2026-11-18 on the Mac (macOS 27.2.1, Hammerspoon 1.1.1). **Considered and
declined that day, not started**: the files do the job. A line costs 0.0015 ms to write
and 13 ms to read back, is kept as long as wanted, and works the same on Linux and in
CI; the move would buy one merged timeline for a compiled helper, a second backend and
long lines to split. This records the design and the measurements behind it, for a later
session to build if that timeline comes to be wanted. Nothing in the repo depends on it.

## What changes

Every line the event logs write (`scripts/lib/event_log.sh`,
`home/.hammerspoon/event_log.lua`) goes to the system's own log instead of a file: the
unified log on macOS, journald on Linux. No `events.log` is written any more.

- All modules read as one timeline, next to the system's own events, in Console.app,
  `log show` / `log stream`, or `journalctl`.
- One module, or one run of it, is a predicate away.
- `~/.dotfiles/.logs/<run>/` stays, for what is not a log: READMEs, results, artifacts.
  A run with none of those makes no directory.

## What is given up

Stated plainly, so the trade is taken knowingly:

- **Keeping a log.** Retention is the system's: trimmed by size, about 30 days here. A
  run whose log should outlive that must be exported into its run directory while it is
  still in the store (see Reading it back).
- **Long lines.** The unified log stores at most 1018 bytes of a line and cuts the rest
  without a word (measured). The helper must split longer ones. In 14 days of today's
  logs 1 line in 50541 was longer (1303 bytes, in a test).
- **Reading speed.** A query takes about 0.8 s where `tail` of a file takes 13 ms.
- **Privacy of the lines.** The files are the user's own; the unified log is readable by
  any admin of the Mac and is part of a sysdiagnose. Window titles and paths are logged
  today.
- **One backend.** macOS and Linux need different ones, and a third is needed where
  neither exists (see Open decisions).

## Design

```text
Hammerspoon module --log()--> event_log.lua --> pipe, kept open for the load --+
                                                                               |
shell script ------log()--> event_log.sh ----> fd, kept open for the run ------+
                                                                               |
                                                                               v
                                             macOS: oslog_sink <subsystem>  (one per writer)
                                                    --> unified log:
                                                        [subsystem:category] run-id message
                                             Linux: systemd-cat -t <name>
                                                    --> journald: <name>: run-id message
```

- **Helper (macOS)**: a small compiled program, `oslog_sink <subsystem>`, that reads
  `category<TAB>message` lines on stdin and calls `os_log` with a real subsystem and
  category. Source below. It is needed because `logger -t <tag>` loses the tag on macOS
  (see Findings).
- **Subsystem**: one for the repo, e.g. `dotfiles`. **Category**: the log's name
  (`dock_cycle`, `tmux_hooks`).
- **Run id**: the UTC stamp a run directory is named by today (`20261118_155730`),
  written as the first word of each message. It names the directory too, when the run
  has artifacts.
- **Hammerspoon**: one helper for all modules, started at load by `event_log.lua` and
  written to line-buffered.
- **Shell**: one helper per script run, opened by `event_log_start`:

  ```bash
  exec 9> >(oslog_sink dotfiles)        # once: the helper's stdin on descriptor 9
  printf '%s\t%s %s\n' "$name" "$run" "$message" >&9   # each line: builtins only
  ```

  The helper exits by itself when the script's descriptors close. Process substitution
  works in bash 3.2, which `event_log.sh` must still run under; `exec {fd}>` does not
  (4.1), so the descriptor number is fixed.
- **A missing helper** is a broken install and fails at the start of the log. With no
  file behind it, logging silently nowhere is the state to rule out.
- **Tests**: 19 files under `scripts/tests/`, the hooks and Hammerspoon read
  `events.log` today. The sink becomes a replaceable command, and a test points it at a
  stand-in that appends to a file, so the assertions on lines stay as they are.
- **Pruning**: `scripts/prune_logs.sh` exists to remove directories that hold only
  `events.log`. Once the last of those has aged out (30 days after the move) it and its
  call at the start of every log go.

Reading it back (macOS):

```bash
log stream --predicate 'subsystem == "dotfiles"'
log show --last 1d --predicate 'subsystem == "dotfiles" AND category == "dock_cycle"'
log show --last 7d --predicate \
  'subsystem == "dotfiles" AND eventMessage BEGINSWITH "20261118_155730"'
```

The last one, redirected into `.logs/<run>/events.log`, is how a run's log is kept.

## Measurements (2026-11-18, this Mac)

Writing one line:

| Method | Cost per line |
| --- | --- |
| `os_log` called from compiled code | 0.0006 ms |
| Line-buffered file write from compiled code | 0.002 ms |
| File write from Hammerspoon's Lua (today) | 0.015 ms |
| bash, file append opened per line (today's shape) | 0.0245 ms |
| Lua, one helper kept open on a pipe | 0.0005 ms |
| bash, one `logger` kept open for the script | 0.0047 ms |
| bash, named pipe to a `logger` already running | 0.0049 ms |
| Starting a process that does nothing | 2.2 ms |
| `logger` started once per line | 2.8 ms |

A bash script that logs one line took 6.0 ms either way (own `logger`, or file append):
the script does not wait for the helper to start.

Reading:

| Query | Time |
| --- | --- |
| `tail` of an `events.log` | 13 ms |
| by subsystem, last hour | 0.8 s |
| by subsystem and message prefix, last hour | 0.8 s |
| by subsystem, last day | 1.1 s |
| by subsystem, last 7 days | 2.1 s |
| by subsystem, a 5-minute window 3 days back | 0.8 s |

Stored length of one line:

| Written | Stored |
| --- | --- |
| 500 bytes | 500 |
| 1000 bytes | 1000 |
| 1024, 2000, 4000, 30000 bytes | 1018, ending in a cut mark |

## Findings

- The cost of logging through `logger` is the process start, not the logging: kept open,
  it is cheaper than the file append.
- `logger -t <tag>` drops the tag: the stored entry has process `logger`, empty subsystem
  and category, and the tag nowhere. Tagging needs a compiled `os_log_create`.
- Lines written through a kept-open pipe were readable in the system log while the pipe
  was still open (line-buffered writer).
- Filtering on the subsystem and category returned exactly the lines of that category
  (1000 of 2000 written alternately).
- Hammerspoon has nothing built in for this: `hs.logger` writes to its own console.
- Volume is small: about 3600 lines a day across all logs, the busiest
  (`ghostty_tmux_snapshot`, `tmux_hooks`) about 500 each.

## Not verified

- **A dead helper and Hammerspoon.** A write to a closed pipe raises SIGPIPE, which by
  default ends the writer. Whether Hammerspoon ignores it was not checked (the check
  risks killing the running instance). Settle this first; if it does not, write through
  `hs.task` with a stdin stream.
- **Building the helper.** `cc` with the Command Line Tools built it. A derivation in
  `nix/flake.nix` (macOS only, it needs the SDK's `os/log.h`) would pin it like the rest
  of the tools; not tried.
- **Linux.** `systemd-cat -t <name>` on a kept-open descriptor should give journald a
  tag per log, read with `journalctl --user -t <name>`; none of it was tried, nor
  journald's retention and line limit.
- **A named pipe shared by all scripts** removes the per-script start but blocks a
  writer while no reader runs, and macOS keeps concurrent writes apart only up to 512
  bytes. The per-script helper has neither problem and is the one planned.

## Open decisions

- **Where neither log exists** (CI runners, the devcontainer, a Docker image without
  systemd): the lines need somewhere to go. Standard error is the candidate, since CI
  keeps it; it is a third backend to write and test.
- **Lines over 1018 bytes**: split by the helper into numbered parts (planned), or
  refused at the writer.
- **What must not land in a sysdiagnose**: whether any log's lines should be marked
  private (`%{private}s`), which hides them from `log show` without a profile.

## Helper source (as tested)

```c
// Reads "category<TAB>message" lines on stdin and writes each to the unified
// log under the subsystem given as argv[1], one os_log_t kept per category.
#include <os/log.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: oslog_sink <subsystem>\n"); return 2; }
  char line[4096], names[32][64]; os_log_t logs[32]; int n = 0;
  while (fgets(line, sizeof line, stdin)) {
    char *tab = strchr(line, '\t');
    if (!tab) { fprintf(stderr, "oslog_sink: no tab in: %s", line); return 1; }
    *tab = 0; char *msg = tab + 1; msg[strcspn(msg, "\n")] = 0;
    int i = 0; while (i < n && strcmp(names[i], line)) i++;
    if (i == n) {
      if (n == 32) { fprintf(stderr, "oslog_sink: over 32 categories\n"); return 1; }
      strlcpy(names[n], line, 64); logs[n++] = os_log_create(argv[1], line);
    }
    os_log(logs[i], "%{public}s", msg);
  }
  return 0;
}
```

`%{public}s` keeps the message from being stored as `<private>`. As tested it neither
splits a line over 1018 bytes nor copes with one over 4095 (`fgets` would cut it in
two); both need doing before it is the only place a line goes.

## Steps, if built

1. Settle the SIGPIPE question for Hammerspoon. **Done when** it is known what a write
   to a dead helper does there, and the write path is chosen accordingly.
2. Settle the open decisions above. **Done when** each has an answer written here.
3. Add the helper, with long lines split, and its build to the install. **Done when** a
   fresh `dotup` on a Mac leaves `oslog_sink` in place,
   `printf 'probe\thello\n' | oslog_sink dotfiles` shows under
   `log show --last 1m --predicate 'subsystem == "dotfiles"'`, and a 3000-byte line
   reads back whole across its parts.
4. Try the Linux side in the Vagrant guest. **Done when** a line written through a
   kept-open `systemd-cat -t probe` reads back with `journalctl --user -t probe`.
5. Make the sink a replaceable command in `event_log.sh` and `event_log.lua`, and point
   the tests at a file stand-in. **Done when** `scripts/check.sh` passes with the files
   still being written as well.
6. Switch the writers to the system log and stop writing `events.log`. **Done when** a
   Hammerspoon reload shows each module's lines under its own category, a tmux hook's
   line shows under `category == "tmux_hooks"`, no new `events.log` appears under
   `~/.dotfiles/.logs/`, and `scripts/check.sh` passes on the Mac and in the guest.
7. Rewrite AGENTS.md's logging entry (where logs go, how to read them, how to keep
   one), and the headers of `event_log.sh` and `event_log.lua`.
8. Thirty days later, remove `scripts/prune_logs.sh`, its test and its calls. **Done
   when** no directory under `~/.dotfiles/.logs/` holds only an `events.log`.
