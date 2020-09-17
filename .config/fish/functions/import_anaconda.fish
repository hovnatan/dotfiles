function import_anaconda
  if not string match -q "*anaconda3*" $PATH
    eval ~/anaconda3/bin/conda "shell.fish" "hook" $argv | source
    bass source ~/anaconda3/etc/conda/activate.d/activate-gcc_linux-64.sh
    bass source ~/anaconda3/etc/conda/activate.d/activate-gxx_linux-64.sh
    bass source ~/anaconda3/etc/conda/activate.d/activate-binutils_linux-64.sh
    bass source ~/anaconda3/etc/conda/activate.d/nvcc_linux-64_activate.sh
  else
    echo "anaconda3 already in PATH."
  end
end
