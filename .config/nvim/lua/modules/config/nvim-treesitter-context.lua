require("treesitter-context").setup({
  mode = "topline",
  max_lines = 5,
  multiline_threshold = 1,
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
