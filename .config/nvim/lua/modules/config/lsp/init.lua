return function()
  local handlers = require("modules.config.lsp.handlers")
  handlers.setup()
  -- handlers.enable_format_on_save()

  local servers_config = {
    efm = {
      filetypes = { "lua", "javascript", "python", "typescript", "html", "markdown" },
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
            {
              lintCommand = "pylint --output-format text --score no --msg-template {path}:{line}:{column}:{C}:{msg} ${INPUT}",
              lintStdin = false,
              lintFormats = { "%f:%l:%c:%t:%m" },
              lintOffsetColumns = 1,
              lintCategoryMap = { I = "H", R = "I", C = "I", W = "W", E = "E", F = "E" },
            },
          },
          javascript = { { formatCommand = "prettier --stdin-filepath .js", formatStdin = true } },
          typescript = { { formatCommand = "prettier --stdin-filepath .ts", formatStdin = true } },
          html = { { formatCommand = "prettier --stdin-filepath .html", formatStdin = true } },
          markdown = { { formatCommand = "prettier --stdin-filepath .md", formatStdin = true } },
        },
      },
    },
    clangd = {
      flags = { debounce_text_changes = 150 },
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
      flags = { debounce_text_changes = 150 },
      settings = {
        python = {
          analysis = {
            autoSearchPaths = true,
            stubPath = os.getenv("HOME") .. "/.dotfiles/python/stubs",
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

  local servers = { "clangd", "pyright", "efm", "jsonls", "bashls", "tsserver", "eslint" }

  local lspconfig = require("lspconfig")
  for _, name in pairs(servers) do
    local config = servers_config[name] or {}
    config.capabilities = handlers.capabilities
    config.on_attach = handlers.on_attach
    lspconfig[name].setup(config)
  end
end
