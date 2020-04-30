from ranger.api.commands import Command


class fzf_select(Command):
    """
    :fzf_select

    Find a file using fzf.

    With a prefix argument select only directories.

    See: https://github.com/junegunn/fzf
    """
    def execute(self):
        import subprocess
        import os.path
        fzf = self.fm.execute_command(
            "fzf +m", universal_newlines=True, stdout=subprocess.PIPE
        )
        stdout, stderr = fzf.communicate()
        if fzf.returncode == 0:
            fzf_file = os.path.abspath(stdout.rstrip('\n'))
            if os.path.isdir(fzf_file):
                self.fm.cd(fzf_file)
            else:
                self.fm.select_file(fzf_file)


class autojump_select(Command):
    """
    :select a dir from autojump list using fzf
            "sort -r -t \| -k 3 ~/.local/share/z/data | cut -d\| -f1 |  fzf +m",
    """
    def execute(self):
        import subprocess
        import os.path
        fzf = self.fm.execute_command(
            "fish -c \"j --list\" | awk -F '  +' '{print $2}' | fzf +m",
            universal_newlines=True,
            stdout=subprocess.PIPE
        )
        stdout, stderr = fzf.communicate()
        if fzf.returncode == 0:
            fzf_dir = os.path.abspath(stdout.rstrip('\n'))
            self.fm.cd(fzf_dir)
