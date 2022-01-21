function import_miniconda
  eval /opt/anaconda3/bin/conda "shell.fish" "hook" | source
  # eval ~/miniconda3/bin/conda "shell.fish" "hook" | source
  # replay source ~/miniconda3/etc/conda/activate.d/activate-gcc_linux-64.sh
  # replay source ~/miniconda3/etc/conda/activate.d/activate-gxx_linux-64.sh
  # replay source ~/miniconda3/etc/conda/activate.d/activate-binutils_linux-64.sh
  # replay source ~/miniconda3/etc/conda/activate.d/nvcc_linux-64_activate.sh
end
