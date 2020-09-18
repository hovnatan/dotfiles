function import_miniconda
  if not string match -q "*miniconda3*" $PATH
    eval ~/miniconda3/bin/conda "shell.fish" "hook" $argv | source
    bass source ~/miniconda3/etc/conda/activate.d/activate-gcc_linux-64.sh
    bass source ~/miniconda3/etc/conda/activate.d/activate-gxx_linux-64.sh
    bass source ~/miniconda3/etc/conda/activate.d/activate-binutils_linux-64.sh
    bass source ~/miniconda3/etc/conda/activate.d/nvcc_linux-64_activate.sh
  else
    echo "miniconda3 already in PATH."
  end
end
