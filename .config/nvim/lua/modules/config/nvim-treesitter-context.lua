return function()
  require("treesitter-context").setup({
    patterns = {
      python = {
        "with",
        "try",
      },
    },
  })
end
