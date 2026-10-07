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
  -- Only its picker, explorer and bigfile modules are used (setup below). Semver releases, main
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
-- Light or dark follows 'background', which nvim detects from the terminal.
-- Gruvbox Material was tried first on 2026-09-24 and looked off.
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

-- snacks.nvim: only the picker, the explorer (a picker in disguise) and
-- bigfile; every other snacks module stays off. The <space> keys are the ones
-- the old telescope setup had (3456c4f4^):
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
      -- Dotfiles shown like the files picker (this repo is mostly home/.*).
      -- Git-ignored files are shown too: the tree is for seeing what is on
      -- disk (e.g. captured logs under a .gitignore'd dir), unlike the
      -- pickers above, which still skip them. I toggles ignored, H hidden.
      -- Inside the tree, - goes up a directory as vim-vinegar's did.
      -- <CR> / l keep the cursor in the tree so several files open in a row;
      -- snacks' confirm alone jumps into the file (<C-w>l gets there).
      -- Width is a quarter of the screen, never under 60 columns
      -- (snacks defaults to a fixed 40, which cut long filenames off): 300
      -- cols -> 75, 100 cols -> 60. A function, because { width = 0.25,
      -- min_width = 60 } loses min_width: the sidebar's wrapper box copies
      -- only width/height (snacks/layout.lua M.new), so 100 cols gave 25.
      -- <C-w>> widens it for the session, <A-m> maximizes it.
      explorer = {
        hidden = true,
        ignored = true,
        layout = {
          layout = {
            width = function()
              return math.max(60, math.floor(vim.o.columns * 0.25))
            end,
          },
        },
        actions = {
          confirm_stay = { action = { "confirm", "focus_list" }, desc = "Open, stay in tree" },
        },
        win = {
          list = {
            keys = {
              ["-"] = "explorer_up",
              ["<CR>"] = "confirm_stay",
              ["l"] = "confirm_stay",
            },
          },
        },
      },
    },
  },
  -- Also opens on `nvim <dir>` or :e <dir> (netrw itself is off,
  -- core/options.lua). Deletes go to the system trash.
  explorer = { enabled = true },
  -- A file over 1 MB, or a minified one (lines over 1000 chars on average),
  -- gets filetype "bigfile" instead of its own, so no ftplugin, syntax or
  -- treesitter loads, and a notification says so. Everything set here is
  -- local to that buffer: the old hand-written guard set eventignore=all
  -- globally and never reset it, so one big file switched off every autocmd
  -- for the rest of the session. Undo stays on and the file stays writable:
  -- the guard's undolevels=-1 + nowrite pair (a 2019 Vim tip) bought little
  -- speed, and with the line-length rule it made a 20 KB one-line JSON
  -- unsaveable. Snacks' default NoMatchParen is left out, as it is global.
  bigfile = {
    enabled = true,
    size = 1024 * 1024,
    setup = function(ctx)
      local bo = vim.bo[ctx.buf]
      bo.swapfile = false
      bo.bufhidden = "unload"
    end,
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

-- ,u<key>: option toggles (Snacks.toggle, a utility that needs no setup
-- entry). The keys follow LazyVim's <leader>u set; each press echoes the new
-- state ("Enabled **wrap**"). Window options (wrap, list, numbers) and spell
-- flip for the current window/buffer only, background for the whole session.
--   ,uw wrap    ,us spell    ,ul line numbers    ,uL relative numbers
--   ,ui invisible chars (list)    ,ub light/dark background    ,ua non-ASCII
snacks.toggle.option("wrap", { name = "wrap" }):map("<leader>uw")
snacks.toggle.option("spell", { name = "spell" }):map("<leader>us")
snacks.toggle.line_number():map("<leader>ul")
snacks.toggle.option("relativenumber", { name = "relative number" }):map("<leader>uL")
snacks.toggle.option("list", { name = "invisible chars" }):map("<leader>ui")
snacks.toggle.option("background", { off = "light", on = "dark", name = "dark background" }):map("<leader>ub")

-- ,ua: non-ASCII highlight, the feature itself is core/non_ascii.lua.
local non_ascii = require("core.non_ascii")
snacks.toggle.new({ name = "non-ASCII highlight", get = non_ascii.enabled, set = non_ascii.set }):map("<leader>ua")

-- -: sidebar tree with the current file revealed (vim-vinegar's key, 2b52bdee).
-- Pressing it outside the tree while it is open closes it; q closes it too.
--   l / <CR> open, cursor stays    h close dir    - / <BS> up    a add (dir/ for a dir)
--   r rename    d delete    c copy    m move    y / p yank and paste files
vim.keymap.set("n", "-", function()
  snacks.explorer()
end, { desc = "File explorer" })
