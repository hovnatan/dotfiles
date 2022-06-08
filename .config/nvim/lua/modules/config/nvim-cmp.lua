return function()
  local cmp = safe_require("cmp")
  cmp.setup({
    snippet = {
      -- REQUIRED - you must specify a snippet engine
      expand = function(args)
        vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
        -- require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
        -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
        -- require'snippy'.expand_snippet(args.body) -- For `snippy` users.
      end,
    },
    mapping = {
      ["<C-d>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.close(),
      ["<CR>"] = cmp.mapping.confirm({ select = true }),
      ["<Tab>"] = cmp.mapping(cmp.mapping.select_next_item(), { "i", "s" }),
    },
    sources = {
      { name = "path", max_item_count = 2 },
      { name = "nvim_lsp", max_item_count = 15 },
      {
        name = "buffer",
        max_item_count = 2,
        option = {
          get_bufnrs = function()
            return vim.api.nvim_list_bufs()
          end,
        },
      },
      { name = "tmux", max_item_count = 2, option = { all_panes = true } },
    },
    view = {
      entries = { name = "custom", selection_order = "near_cursor" },
    },
    formatting = {
      format = function(entry, vim_item)
        vim_item.menu = entry.source.name
        return vim_item
      end,
    },
  })
end
