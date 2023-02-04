vim.g.slime_no_mappings = 1
vim.keymap.set("n", "<C-c>v", "<Plug>SlimeConfig", { noremap = true, silent = true })
vim.keymap.set("x", "<C-c><C-c>", "<Plug>SlimeRegionSend", { noremap = true, silent = true })
vim.g.slime_target = "tmux"
-- tmux target pane should be the last digit of $TMUX + :, e.g., 8:. Need
-- "default" not "default " as tmux server
vim.g.slime_python_ipython = 1
vim.g.slime_default_config = { socket_name = "default", target_pane = "{last}" }
vim.g.slime_dont_ask_default = 1
