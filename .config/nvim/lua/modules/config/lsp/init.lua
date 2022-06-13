return function()
  local handlers = require('modules.config.lsp.handlers')
  handlers.setup()

  local servers_config = {
    efm = {
      filetypes = { "lua", "javascript", "python" },
      init_options = { documentFormatting = true },
      settings = {
        rootMarkers = { ".git/" },
        languages = {
          lua = { { formatCommand = "stylua --search-parent-directories -", formatStdin = true } },
          python = {
            {
              formatCommand = "isort --stdout --profile black -",
              formatStdin = true,
            },
            { formatCommand = "black --fast -", formatStdin = true },
          },
          javascript = { { formatCommand = "prettier", formatStdin = true } },
        },
      },
    },
    clangd = {
      flags = { debounce_text_changes = 150 },
      init_options = { clangdFileStatus = true },
      cmd = {
        "/opt/homebrew/opt/llvm/bin/clangd",
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
      flags = { debounce_text_changes = 150 },
      settings = {
        python = {
          analysis = {
            autoSearchPaths = true,
            stubPath = os.getenv("HOME") .. "/work/stubs",
          },
        },
      },
    },
  }

  local servers = { "clangd", "pyright", "efm", "jsonls" }

  local lspconfig = require("lspconfig")
  for _, name in pairs(servers) do
    local config = servers_config[name] or {}
    config.capabilities = handlers.capabilities
    config.on_attach = handlers.on_attach
    lspconfig[name].setup(config)
  end
end
