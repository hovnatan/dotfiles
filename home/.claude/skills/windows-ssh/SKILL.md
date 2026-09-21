---
name: windows-ssh
description: "Run commands, PowerShell scripts, audits or uninstalls on a Windows machine over ssh (a box whose ssh shell is cmd.exe). Load before the first remote call."
---

# Windows over ssh

The remote shell is cmd.exe, which parses the line before PowerShell sees it. Every
failure mode below comes from that. The safe path is a script file.

## Steps

1. **Write the script to a file, ship it, run it by path.** Never inline PowerShell in `-Command`.

   ```bash
   scp -q job.ps1 'host:AppData/Local/Temp/job/'      # mkdir first: ssh host 'mkdir %TEMP%\job'
   ssh -o ConnectTimeout=20 host 'powershell -NoProfile -ExecutionPolicy Bypass -File %TEMP%\job\job.ps1'
   ```

   `-o ConnectTimeout` is the guard on any client; `timeout` is not on every one.

2. **Lint the file on the remote before running it.** PSScriptAnalyzer catches the classic
   silent bugs (automatic-variable shadowing, aliases). Install once per box, then:

   ```powershell
   Install-PackageProvider NuGet -Force -Scope CurrentUser; Set-PSRepository PSGallery -InstallationPolicy Trusted
   Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
   Invoke-ScriptAnalyzer -Path $env:TEMP\job\job.ps1 -Severity Warning,Error
   ```

   `PSAvoidAssignmentToAutomaticVariable` is a bug, fix it before running.

3. **Cap every remote action.** A GUI or UAC prompt on the far side hangs forever over ssh
   and nobody can click it. Wrap each launch:

   ```powershell
   function Invoke-Capped($exe, $argList, $label, $cap = 60) {
     $p = if ($argList) { Start-Process $exe -ArgumentList $argList -PassThru -WindowStyle Hidden } else { Start-Process $exe -PassThru -WindowStyle Hidden }
     if ($p.WaitForExit($cap * 1000)) { "$label exit=$($p.ExitCode)" } else { Stop-Process -Id $p.Id -Force; "$label TIMEOUT killed" }
   }
   ```

   A batch longer than two minutes runs detached with output to a log that you poll;
   the ssh call itself returns at once.

4. **Verify from the client, not only from the box.** Port state: `nc -z -w 4 host 22`
   (works with BSD and GNU netcat).
   A fresh session that bypasses the multiplexed master: `ssh -o ControlPath=none -o BatchMode=yes host echo ok`.

5. **Report done only after the verify block in the script prints.** Every script ends
   with a verify section that re-reads the state it changed.

## Connection

- The master connection dies when the box sleeps. Test with `ssh -o BatchMode=yes host echo ok`.
  If the box uses password auth, only the user can re-open it: ask them to type
  `! ssh -o ControlPersist=4h host exit` in the prompt.
- A sleeping box cannot be woken from here unless a NIC is wake-armed. Say so and wait.

## Uninstalling

- Order of preference: `msiexec /x {code} /qn /norestart`; the registry `UninstallString` with `/S`;
  manual removal (program folder, `%LOCALAPPDATA%` data, the uninstall key, Run entries, scheduled tasks).
- winget hangs on uninstallers that want a prompt. If it does, `taskkill /IM winget.exe /F` and fall back.
- Store apps: `Remove-AppxPackage` then `Remove-AppxProvisionedPackage -Online`, or the next
  feature update reinstalls them.
- Sync clients (Dropbox, OneDrive): deleting the local folder while linked deletes in the cloud.
  Uninstall, delete the client config, confirm no process, then touch the folder. OneDrive's
  folder backup redirects Desktop, Documents and Pictures: read
  `HKCU:\...\Explorer\User Shell Folders` and move them back.
- Files held open by Explorer (shell extension DLLs) cannot be deleted live. Leave them for the
  reboot; killing Explorer over ssh leaves the user without a shell.

## Gotchas

- `powershell -Command -` reads stdin line by line: multi-line blocks are dropped silently.
- cmd owns `|`, `&`, `%`, `"` on the command line, so inline `-Command` strings with them break.
- `$args`, `$input`, `$matches`, `$_` are automatic variables. Parameter names must differ.
- `-f` binds tighter than `/`: write `($_.Size/1GB)` inside a format argument list.
- `wsl.exe` prints UTF-16: `(wsl --list) -replace "`0",''`.
- Firewall scoping: restrict a rule by `-RemoteAddress` (the VPN or overlay network's range)
  with `-Profile Any`, so it stops depending on the Public/Private label of the network.
