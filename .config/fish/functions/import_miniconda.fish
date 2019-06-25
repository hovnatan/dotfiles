function import_miniconda
  if test -d ~/miniconda3/bin
    set -U fish_user_paths ~/miniconda3/bin $fish_user_paths
    source (conda info --root)/etc/fish/conf.d/conda.fish
  else
    echo "No miniconda3 distribution found"
  end
end
