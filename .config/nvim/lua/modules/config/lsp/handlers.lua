local M = {}

M.setup = function()
  vim.diagnostic.config({
    virtual_text = true,
    float = { severity_sort = true },
    update_in_insert = true,
    underline = true,
    severity_sort = true,
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
  -- Mappings.
  local opts = { noremap = true, silent = true }
  vim.keymap.set("n", "<space>e", vim.diagnostic.open_float, opts)
  vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
  vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

  local bufopts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
  vim.keymap.set({ "n", "i" }, "<C-k>", vim.lsp.buf.signature_help, bufopts)
  vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
  vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
  vim.keymap.set("n", "<space>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, bufopts)
  vim.keymap.set("n", "<space>D", vim.lsp.buf.type_definition, bufopts)
  vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
  vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
  vim.keymap.set("n", "<leader>f", function()
    vim.lsp.buf.format({ async = false })
  end, bufopts)

  if client.name == "clangd" then
    vim.keymap.set("n", "<space>z", "<cmd>ClangdSwitchSourceHeader<CR>", opts)
  end

  if client.name == "tsserver" then
    client.server_capabilities.documentFormattingProvider = false -- 0.8 and later
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
  vim.api.nvim_create_augroup("format_on_save", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = "format_on_save",
    callback = function()
      vim.lsp.buf.format({ async = false })
    end,
  })
  -- vim.notify("Enabled format on save")
end

function M.disable_format_on_save()
  vim.api.nvim_del_augroup_by_name("format_on_save")
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

vim.api.nvim_create_user_command("LspEnableAutoFormat", M.enable_format_on_save, {})
vim.api.nvim_create_user_command("LspDisableAutoFormat", M.disable_format_on_save, {})
vim.api.nvim_create_user_command("LspToggleAutoFormat", M.toggle_format_on_save, {})
vim.api.nvim_create_user_command("LspToggleVirtualText", M.toggle_virtual_text, {})

return M
