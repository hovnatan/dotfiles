-- Format Lua with stylua on save, in projects that opt in with a stylua.toml
-- or .stylua.toml (this repo's is at its root). A Lua file anywhere else is
-- left alone: stylua's defaults (tabs) would restyle a project that never
-- asked for it.
--
--   BufWritePre *.lua --> project root with a stylua config? --no--> write as is
--                                     | yes
--                         stylua - (buffer on stdin, cwd = root)
--                           |                       |
--                        formatted              parse error
--                           |                       |
--             apply only the changed hunks     notify, write as is
--             (cursor, marks, folds stay put)

local config_names = { "stylua.toml", ".stylua.toml" }

local function format(buf)
  -- Resolve symlinks: ~/.config/nvim is a link into ~/.dotfiles, and the
  -- config sits at the repo root, above the link target.
  local path = vim.fn.resolve(vim.api.nvim_buf_get_name(buf))
  local root = vim.fs.root(path, config_names)
  if root == nil then
    return
  end
  if vim.fn.executable("stylua") == 0 then
    error("format: stylua is not on PATH; it comes from nix/flake.nix in ~/.dotfiles (run `dotup`)")
  end

  local old = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local res = vim
    .system({ "stylua", "--stdin-filepath", path, "--respect-ignores", "-" }, {
      cwd = root,
      stdin = table.concat(old, "\n") .. "\n",
      text = true,
    })
    :wait()

  -- A half-edited file often does not parse. Saving it anyway beats losing
  -- the work, so this reports and lets the write go through unformatted.
  if res.code ~= 0 then
    vim.notify("stylua: " .. vim.trim(res.stderr), vim.log.levels.ERROR)
    return
  end

  -- Replace hunk by hunk, bottom first so earlier line numbers stay valid.
  -- Rewriting the whole buffer would drop marks and send the cursor to line 1.
  local new = vim.split(res.stdout, "\n")
  if new[#new] == "" then
    table.remove(new)
  end
  local hunks = vim.text.diff(table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n", {
    result_type = "indices",
  })
  for i = #hunks, 1, -1 do
    local a_start, a_count, b_start, b_count = unpack(hunks[i])
    -- For a pure insertion (a_count == 0), a_start is the line it goes after.
    local first = a_count == 0 and a_start or a_start - 1
    vim.api.nvim_buf_set_lines(buf, first, first + a_count, false, vim.list_slice(new, b_start, b_start + b_count - 1))
  end
end

vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("format_on_save", { clear = true }),
  pattern = "*.lua",
  callback = function(args)
    format(args.buf)
  end,
})
