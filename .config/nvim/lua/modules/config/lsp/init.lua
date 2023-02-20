local lspconfig = require("lspconfig")
local handlers = require("modules.config.lsp.handlers")
handlers.setup()
-- handlers.enable_format_on_save()

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
}

local servers = { "clangd", "pyright", "jsonls", "bashls", "tsserver", "eslint" }

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
