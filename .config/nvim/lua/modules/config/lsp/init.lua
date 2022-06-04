lspconfig.efm.setup({
  filetypes = { "lua", "javascript", "python" },
  on_attach = on_attach,
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
})
