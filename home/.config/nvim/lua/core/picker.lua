-- Plugin-free file and buffer picker on the built-in command line (nvim 0.12+),
-- standing in for telescope + smart-open (<space>f) and telescope buffers
-- (<space>b) from the old plugin setup.
--
--   <space>f -> ":find "  --CmdlineChanged--> wildtrigger() --> popup menu
--                                                  |
--                                   'findfunc' = Find(arg) on every keystroke
--                                                  |
--        recent files (open buffers by last use, then v:oldfiles under cwd)
--          ++ every other file from `fd` (respects .gitignore and fd's ignore)
--        each group fuzzy-filtered by matchfuzzy(), recent group always first
--
--   <space>b -> ":b "  --> buffer completion, fuzzy, most recently used first
--
-- Example: in ~/.dotfiles after editing scripts/update.sh, "<space>f upd"
-- lists scripts/update.sh above other matches such as a never-opened
-- docs/update-notes.md, even if the latter scores better on the text alone.

local M = {}

-- One snapshot per command line: 'findfunc' runs on every keystroke once
-- wildtrigger() is live, and walking the tree each time would lag in big repos.
local cache = nil

local function recent_files(cwd)
  local seen, out = {}, {}
  local function add(path)
    if path == "" or vim.fn.filereadable(path) == 0 then
      return
    end
    local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    if abs:sub(1, #cwd + 1) ~= cwd .. "/" or seen[abs] then
      return
    end
    seen[abs] = true
    table.insert(out, abs:sub(#cwd + 2))
  end

  -- This session's buffers first: v:oldfiles is only read from shada at
  -- startup, so files opened since then are missing from it. The current
  -- buffer is left out - it is the one file you are not looking for.
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(bufs, function(a, b)
    return a.lastused > b.lastused
  end)
  local current = vim.api.nvim_get_current_buf()
  for _, b in ipairs(bufs) do
    if b.bufnr ~= current then
      add(b.name)
    end
  end

  for _, f in ipairs(vim.v.oldfiles) do
    add(f)
  end
  return out, seen
end

local function all_files(cwd)
  local res = vim.system({ "fd", "--type", "f", "--hidden", "--color", "never" }, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    error(("picker: `fd` failed in %s (exit %d): %s"):format(cwd, res.code, res.stderr))
  end
  return vim.split(res.stdout, "\n", { trimempty = true })
end

local function snapshot()
  if cache == nil then
    local cwd = vim.fs.normalize(vim.fn.getcwd())
    local recent, seen = recent_files(cwd)
    local rest = {}
    for _, f in ipairs(all_files(cwd)) do
      if not seen[cwd .. "/" .. f] then
        table.insert(rest, f)
      end
    end
    cache = { recent = recent, rest = rest }
  end
  return cache
end

-- 'findfunc': called for completion (cmdcomplete = true) and again when the
-- command runs, where :find opens the first entry - so a partial name plus
-- <CR> opens the top match without selecting it in the menu.
function M.find(arg, _)
  local s = snapshot()
  if arg == "" then
    return vim.list_extend(vim.list_slice(s.recent), s.rest)
  end
  return vim.list_extend(vim.fn.matchfuzzy(s.recent, arg), vim.fn.matchfuzzy(s.rest, arg))
end

_G.PickerFind = M.find
vim.o.findfunc = "v:lua.PickerFind"

-- noselect: the popup shows without inserting its first entry, so typing keeps
-- narrowing. lastused: buffer completion lists the most recent buffer first.
-- fuzzy: :b and other command-line completion match fuzzily.
vim.o.wildmode = "noselect:lastused,full"
vim.o.wildoptions = "pum,fuzzy"

-- Pop the menu up live only for the picker commands; other : commands and
-- / ? searches keep the usual <Tab>-driven completion.
local picker_cmd = vim.regex([[\v^\s*(fin%[d]|sf%[ind]|tabf%[ind]|b%[uffer]|sb%[uffer])!?\s]])
local group = vim.api.nvim_create_augroup("picker", { clear = true })
vim.api.nvim_create_autocmd("CmdlineEnter", {
  group = group,
  pattern = ":",
  callback = function()
    cache = nil
  end,
})
vim.api.nvim_create_autocmd("CmdlineChanged", {
  group = group,
  pattern = ":",
  callback = function()
    if picker_cmd:match_str(vim.fn.getcmdline()) then
      vim.fn.wildtrigger()
    end
  end,
})

vim.keymap.set("n", "<space>f", ":find ")
vim.keymap.set("n", "<space>b", ":b ")

return M
