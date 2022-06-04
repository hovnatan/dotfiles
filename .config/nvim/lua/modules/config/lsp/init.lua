return function() 

local on_attach = function(client, bufnr)
  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end
  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

  -- Mappings.
  local opts = { noremap = true, silent = true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap("n", "gD", "<Cmd>lua vim.lsp.buf.declaration()<CR>", opts)
  buf_set_keymap("n", "gd", "<Cmd>lua vim.lsp.buf.definition()<CR>", opts)
  buf_set_keymap("n", "K", "<Cmd>lua vim.lsp.buf.hover()<CR>", opts)
  buf_set_keymap("n", "gi", "<cmd>lua vim.lsp.buf.implementation()<CR>", opts)
  buf_set_keymap("n", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
  buf_set_keymap("i", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
  buf_set_keymap("n", "<space>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
  buf_set_keymap("n", "<space>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
  buf_set_keymap("n", "<space>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
  buf_set_keymap("n", "<space>D", "<cmd>lua vim.lsp.buf.type_definition()<CR>", opts)
  buf_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
  buf_set_keymap("n", "<space>ca", "<cmd>lua vim.lsp.buf.code_action()<CR>", opts)
  buf_set_keymap("n", "gr", "<cmd>lua vim.lsp.buf.references()<CR>", opts)
  buf_set_keymap("n", "<space>e", '<cmd>lua vim.diagnostic.open_float(0, {scope="line"})<CR>', opts)
  buf_set_keymap("n", "[d", "<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>", opts)
  buf_set_keymap("n", "]d", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>", opts)
  buf_set_keymap("n", "<space>z", "<cmd>ClangdSwitchSourceHeader<CR>", opts)
  buf_set_keymap("n", "<space>q", "<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>", opts)
  buf_set_keymap("n", "<leader>f", "<cmd>lua vim.lsp.buf.formatting()<CR>", opts)
end
local lspconfig = require("lspconfig")
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

lspconfig.clangd.setup({
  on_attach = on_attach,
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
  capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities()),
})
lspconfig.pyright.setup({
  on_attach = on_attach,
  flags = { debounce_text_changes = 150 },
  capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities()),
})
lspconfig.jsonls.setup({ on_attach = on_attach })

end
