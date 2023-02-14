local cmp = safe_require("cmp")
local t = function(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end
cmp.setup({
  snippet = {
    -- REQUIRED - you must specify a snippet engine
    expand = function(args)
      -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
      -- require("luasnip").lsp_expand(args.body) -- For `luasnip` users.
      -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
      -- require'snippy'.expand_snippet(args.body) -- For `snippy` users.
    end,
  },
  mapping = {
    ["<C-d>"] = cmp.mapping(cmp.mapping.scroll_docs(-4), { "i", "c" }),
    ["<C-f>"] = cmp.mapping(cmp.mapping.scroll_docs(4), { "i", "c" }),
    ["<C-e>"] = cmp.mapping.close(),
    ["<CR>"] = cmp.mapping.confirm(),
    ["<Tab>"] = cmp.mapping(cmp.mapping.select_next_item(), { "i", "s" }),
    ["<C-n>"] = cmp.mapping({
      c = function()
        if cmp.visible() then
          cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
        else
          vim.api.nvim_feedkeys(t("<Down>"), "n", true)
        end
      end,
      i = function(fallback)
        if cmp.visible() then
          cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
        else
          fallback()
        end
      end,
    }),
    ["<C-p>"] = cmp.mapping({
      c = function()
        if cmp.visible() then
          cmp.select_prev_item({ behavior = cmp.SelectBehavior.Insert })
        else
          vim.api.nvim_feedkeys(t("<Up>"), "n", true)
        end
      end,
      i = function(fallback)
        if cmp.visible() then
          cmp.select_prev_item({ behavior = cmp.SelectBehavior.Insert })
        else
          fallback()
        end
      end,
    }),
  },
  -- sorting = {
  --   priority_weight = 2,
  --   comparators = {
  --     cmp.config.compare.locality,
  --     cmp.config.compare.recently_used,
  --     cmp.config.compare.score,
  --   },
  -- },
  sources = {
    -- { name = "luasnip", max_item_count = 5 },
    { name = "path", keyword_length = 2, max_item_count = 5 },
    -- { name = "treesitter", keyword_length = 2, max_item_count = 15 },
    { name = "nvim_lsp", keyword_length = 2, max_item_count = 15 },
    {
      name = "buffer",
      keyword_length = 2,
      max_item_count = 5,
      option = {
        get_bufnrs = function()
          return vim.api.nvim_list_bufs()
        end,
      },
    },
    { name = "tmux", keyword_length = 2, max_item_count = 5, option = { all_panes = true } },
  },
  view = {
    entries = { name = "custom", selection_order = "near_cursor" },
  },
  formatting = {
    format = function(entry, vim_item)
      vim_item.kind = vim_item.kind
      vim_item.menu = ({
        nvim_lsp = "[LSP]",
        buffer = "[BUF]",
        tmux = "[TMUX]",
        treesitter = "[TS]",
        path = "[PATH]",
      })[entry.source.name]
      return vim_item
    end,
  },
})
