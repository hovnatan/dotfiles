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
    settings = {
      python = {
        analysis = {
          stubPath = os.getenv("HOME") .. "/.dotfiles/python/stubs",
          autoImportCompletions = false,
        },
      },
    },
  },
  pylsp = {
    settings = {
      pylsp = {
        plugins = {
          pylint = {
            enabled = true,
          },
          pyflakes = {
            enabled = false,
          },
          autopep8 = {
            enabled = false,
          },
          yapf = {
            enabled = false,
          },
          black = {
            enabled = true,
          },
          pycodestyle = {
            enabled = false,
          },
        },
      },
    },
  },
  ruff_lsp = {
    init_options = {
      settings = { args = { "--config=~/.dotfiles/pyproject.toml" } },
    },
  },
}

local servers = { "clangd", "jsonls", "bashls", "tsserver", "eslint", "ruff_lsp" }

for _, name in pairs(servers) do
  local config = servers_config[name] or {}
  config.capabilities = handlers.capabilities
  config.on_attach = handlers.on_attach
  lspconfig[name].setup(config)
end

local null_ls = require("null-ls")

null_ls.setup({
  sources = {
    null_ls.builtins.formatting.stylua,
    null_ls.builtins.formatting.black,
    null_ls.builtins.formatting.isort,
  },
  on_attach = handlers.on_attach,
})
