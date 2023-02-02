require("treesitter-context").setup({
  patterns = {
    python = {
      "with",
      "try",
      "except",
      "elif",
      "else",
    },
  },
})
