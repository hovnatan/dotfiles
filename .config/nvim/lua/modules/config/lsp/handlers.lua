local M = {}

M.setup = function()
  vim.diagnostic.config({
    virtual_text = false,
    signs = {
      active = signs,
    },
    update_in_insert = true,
    underline = true,
    severity_sort = true,
    float = {
      focusable = true,
      style = "minimal",
      border = "rounded",
      source = "always",
      header = "",
      prefix = "",
    },
  })

  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
  })

  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
    border = "rounded",
  })

  vim.lsp.handlers["textDocument/publishDiagnostics"] =
    vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, { update_in_insert = false })
end

M.on_attach = function(client, bufnr)
  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end

  -- Mappings.
  local opts = { noremap = true, silent = true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap("n", "gD", "<Cmd>lua vim.lsp.buf.declaration()<CR>", opts)
  buf_set_keymap("n", "gd", "<Cmd>lua vim.lsp.buf.definition()<CR>", opts)
  buf_set_keymap("n", "K", "<Cmd>lua vim.lsp.buf.hover()<CR>", opts)
  buf_set_keymap("n", "gi", "<cmd>lua vim.lsp.buf.implementation()<CR>", opts)
  buf_set_keymap("n", "<space>K", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
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
  buf_set_keymap("n", "<space>q", "<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>", opts)
  buf_set_keymap("n", "<leader>f", "<cmd>lua vim.lsp.buf.format()<CR>", opts)

  if client.name == "clangd" then
    buf_set_keymap("n", "<space>z", "<cmd>ClangdSwitchSourceHeader<CR>", opts)
  end

  if client.name == "tsserver" then
    client.server_capabilities.document_formatting = false
    -- client.server_capabilities.documentFormattingProvider = false -- 0.8 and later
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
local cmp_nvim_lsp = safe_require("cmp_nvim_lsp")
if cmp_nvim_lsp then
  capabilities = require("cmp_nvim_lsp").default_capabilities()
end
capabilities.textDocument.completion.completionItem.snippetSupport = false

M.capabilities = capabilities

function M.enable_format_on_save()
  vim.cmd([[
    augroup format_on_save
      au!
      au BufWritePre * lua vim.lsp.buf.format({async=true})
    augroup end
  ]])
  vim.notify("Enabled format on save")
end

function M.disable_format_on_save()
  vim.cmd("au! format_on_save")
  vim.notify("Disabled format on save")
end

function M.toggle_format_on_save()
  if vim.fn.exists("#format_on_save#BufWritePre") == 0 then
    M.enable_format_on_save()
  else
    M.disable_format_on_save()
  end
end

local diagnostic_show = true
function M.toggle_virtual_text()
  if diagnostic_show then
    vim.diagnostic.hide()
    diagnostic_show = false
  else
    vim.diagnostic.show()
    diagnostic_show = true
  end
end

vim.cmd([[command! LspEnableAutoFormat execute 'lua require("modules.config.lsp.handlers").enable_format_on_save()']])
vim.cmd([[command! LspDisableAutoFormat execute 'lua require("modules.config.lsp.handlers").disable_format_on_save()']])
vim.cmd([[command! LspToggleAutoFormat execute 'lua require("modules.config.lsp.handlers").toggle_format_on_save()']])
vim.cmd([[command! LspToggleVirtualText execute 'lua require("modules.config.lsp.handlers").toggle_virtual_text()']])

return M
