function import_anaconda
  if not string match -q "*anaconda3*" $PATH
    source ~/anaconda3/etc/fish/conf.d/conda.fish
    conda activate base
    # eval ~/anaconda3/bin/conda "shell.fish" "hook" | source
    # replay source ~/anaconda3/etc/conda/activate.d/activate-gcc_linux-64.sh
    # replay source ~/anaconda3/etc/conda/activate.d/activate-gxx_linux-64.sh
    # replay source ~/anaconda3/etc/conda/activate.d/activate-binutils_linux-64.sh
    # replay source ~/anaconda3/etc/conda/activate.d/nvcc_linux-64_activate.sh
  else
    echo "anaconda3 already in PATH."
  end
end
