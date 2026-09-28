-- The only plugins, managed by nvim 0.12's built-in vim.pack (:h vim.pack).
-- No plugin manager, no lazy-loading layer.
--
--   vim.pack.add() --> clone into ~/.local/share/nvim/site/pack/core/opt/
--        |             at the commit in nvim-pack-lock.json (tracked in the
--        |             repo next to init.lua), then :packadd
--        v
--   plugin setup below
--
-- Nothing ever updates on its own: every machine gets the locked commits,
-- and only an explicit update moves them:
--   :lua vim.pack.update()   review the changelog buffer; :w applies, :q aborts
--   then commit nvim-pack-lock.json so the other machines follow
-- `version` only steers what an update may move to.

vim.pack.add({
  -- Releases are frequent and semver-tagged; 2.x keeps an update from
  -- crossing a breaking major on its own.
  { src = "https://github.com/lewis6991/gitsigns.nvim", version = vim.version.range("2") },
  -- Tags lag far behind (master was 221 commits past v3.0.0 on 2026-09-24),
  -- so follow the development branch, as upstream expects.
  { src = "https://github.com/NeogitOrg/neogit", version = "master" },
  -- Last tag 2.0.0 trails main by 122 commits (2026-09-24), so follow main.
  { src = "https://github.com/ellisonleao/gruvbox.nvim", version = "main" },
  -- Only its picker module is used (setup below). Semver releases, main
  -- only 11 commits past v2.31.0 (2026-09-27), so stay on 2.x like gitsigns.
  { src = "https://github.com/folke/snacks.nvim", version = vim.version.range("2") },
}, {
  -- The lockfile already pins what gets installed, so a fresh machine
  -- installs without asking (a prompt would also hang a headless nvim).
  confirm = false,
})

-- Colorscheme: classic gruvbox, matched to Ghostty's Gruvbox Light/Dark themes
-- (home/.config/ghostty/config). Its default contrast is the palette those
-- themes use: dark bg #282828 / fg #ebdbb2, light bg #fbf1c7 / fg #3c3836.
-- Light or dark follows 'background', which nvim detects from the terminal at
-- startup (or ~/.my_colors, core/options.lua). Gruvbox Material was tried
-- first on 2026-09-24 and looked off.
vim.cmd.colorscheme("gruvbox")

-- gitsigns: hunks against the index, shown with the defaults - bars in the
-- sign column (dimmer for staged hunks), line numbers left plain. Keys are the
-- pre-2024 ones on the v2 API: stage_hunk on a staged hunk unstages it
-- (replaces undo_stage_hunk), and preview_hunk_inline replaces toggle_deleted.
require("gitsigns").setup({
  on_attach = function(bufnr)
    local gs = require("gitsigns")
    local function map(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr })
    end

    -- ]c / [c: next/previous hunk, but keep the built-in jump in diff mode
    -- (git dt, :diffthis).
    map("n", "]c", function()
      if vim.wo.diff then
        vim.cmd.normal({ "]c", bang = true })
      else
        gs.nav_hunk("next")
      end
    end)
    map("n", "[c", function()
      if vim.wo.diff then
        vim.cmd.normal({ "[c", bang = true })
      else
        gs.nav_hunk("prev")
      end
    end)

    -- Stage/reset a hunk, or just the selected lines in visual mode.
    map("n", "<leader>hs", gs.stage_hunk)
    map("n", "<leader>hr", gs.reset_hunk)
    map("v", "<leader>hs", function()
      gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end)
    map("v", "<leader>hr", function()
      gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end)
    map("n", "<leader>hS", gs.stage_buffer)
    map("n", "<leader>hR", gs.reset_buffer)

    -- Look at changes: popup, inline deleted lines, blame, diff against the
    -- index (hd) or the last commit (hD).
    map("n", "<leader>hp", gs.preview_hunk)
    map("n", "<leader>hi", gs.preview_hunk_inline)
    map("n", "<leader>hb", function()
      gs.blame_line({ full = true })
    end)
    map("n", "<leader>tb", gs.toggle_current_line_blame)
    map("n", "<leader>hd", gs.diffthis)
    map("n", "<leader>hD", function()
      gs.diffthis("~")
    end)

    -- ih: the hunk under the cursor as a text object (dih, yih, vih).
    map({ "o", "x" }, "ih", gs.select_hunk)
  end,
})

-- neogit: Magit-style status buffer (:Neogit). s/u stage/unstage the file,
-- hunk or visual selection under the cursor; c commits. Side-by-side review
-- stays with `git dt` (home/.config/git/config.shared), so no diffview.
require("neogit").setup({})
-- ,gg opens the status tab (leader is ","); plain gg stays "first line".
vim.keymap.set("n", "<leader>gg", "<cmd>Neogit<cr>", { desc = "Neogit status" })

-- snacks.nvim: only the picker; every other snacks module stays off. The
-- <space> keys are the ones the old telescope setup had (3456c4f4^):
--
--   <space>f  smart: open buffers, then recent files, then all files (fd),
--             frecency-ranked with a cwd bonus (was telescope smart_open)
--   <space>b  open buffers
--   <space>g  live grep: rg reruns as you type (was live_grep_args)
--   <space>G  grep the word under the cursor, or the visual selection
--
-- rg reads home/.config/ripgrep/rc first and snacks' own flags come after, so
-- snacks wins on conflicts: its default --no-hidden would hide dotfiles while
-- the rc's --no-ignore-vcs still searched node_modules. hidden = true lines
-- grep up with the rc (hidden and git-ignored files, never .git). Files get
-- hidden = true too, as the old `fd --hidden` picker did; fd still skips
-- .gitignore'd files and snacks excludes .git.
local snacks = require("snacks")
snacks.setup({
  picker = {
    enabled = true,
    sources = {
      files = { hidden = true },
      grep = { hidden = true },
      grep_word = { hidden = true },
    },
  },
})
vim.keymap.set("n", "<space>f", function()
  snacks.picker.smart()
end, { desc = "Find file" })
vim.keymap.set("n", "<space>b", function()
  snacks.picker.buffers()
end, { desc = "Find buffer" })
vim.keymap.set("n", "<space>g", function()
  snacks.picker.grep()
end, { desc = "Live grep" })
vim.keymap.set({ "n", "x" }, "<space>G", function()
  snacks.picker.grep_word()
end, { desc = "Grep word or selection" })
