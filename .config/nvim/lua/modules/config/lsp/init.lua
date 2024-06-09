local lspconfig = require("lspconfig")
local handlers = require("modules.config.lsp.handlers")

handlers.setup()

-- Jump directly to the first available definition every time.
vim.lsp.handlers["textDocument/definition"] = function(_, result)
  if not result or vim.tbl_isempty(result) then
    print("[LSP] Could not find definition")
    return
  end

  if vim.tbl_islist(result) then
    vim.lsp.util.jump_to_location(result[1], "utf-8")
  else
    vim.lsp.util.jump_to_location(result, "utf-8")
  end
end

vim.api.nvim_create_user_command("LspLog", function()
  local path = vim.lsp.get_log_path()
  vim.cmd("tabedit " .. path)
end, { force = true, nargs = 0 })

local servers_config = {
  clangd = {
    flags = { debounce_text_changes = 1000 },
    init_options = { clangdFileStatus = true },
    cmd = {
      "clangd",
      "--compile-commands-dir=.",
      "--background-index",
      "--clang-tidy",
      "--completion-parse=always",
      "--completion-style=detailed",
      "--function-arg-placeholders",
      "--header-insertion-decorators",
      "--header-insertion=never",
      "--cross-file-rename",
      "--limit-results=0",
      "-j=4",
      "--pch-storage=memory",
    },
  },
  pyright = {
    flags = { debounce_text_changes = 1000 },
    -- cmd = { "pyright-langserver", "--stdio", "--project", os.getenv("HOME") .. "/.dotfiles/pyproject.toml" },
    settings = {
      python = {
        analysis = {
          stubPath = os.getenv("HOME") .. "/.dotfiles/python/stubs",
          autoImportCompletions = false,
          typeCheckingMode = "off",
        },
      },
    },
  },
}

local servers = { "clangd", "pyright", "jsonls", "bashls", "tsserver", "eslint", "ruff" }

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.py",
  callback = function()
    vim.lsp.buf.code_action({
      context = { only = { "source.fixAll.ruff" } },
      apply = true,
    })
  end,
})

for _, name in pairs(servers) do
  local config = servers_config[name] or {}
  config.capabilities = handlers.capabilities
  config.on_attach = handlers.on_attach
  lspconfig[name].setup(config)
end
