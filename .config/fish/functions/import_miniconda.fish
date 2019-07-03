function import_miniconda
  eval /home/hovnatan/miniconda3/bin/conda "shell.fish" "hook" $argv | source
  bass source /home/hovnatan/miniconda3/etc/conda/activate.d/activate-gcc_linux-64.sh
  bass source /home/hovnatan/miniconda3/etc/conda/activate.d/activate-gxx_linux-64.sh
  bass source /home/hovnatan/miniconda3/etc/conda/activate.d/activate-binutils_linux-64.sh
end
