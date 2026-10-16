return {
  "codethread/qmk.nvim",
  config = function()
    require("qmk").setup({
      name = "LAYOUT_voyager", -- Specific layout name for Voyager
      layout = {
        "x x x x x x _ _ _ x x x x x x",
        "x x x x x x _ _ _ x x x x x x",
        "x x x x x x _ _ _ x x x x x x",
        "x x x x x x _ _ _ x x x x x x",
        "_ _ _ _ _ x x _ x x _ _ _ _ _", -- Thumb cluster row
      },
      comment_preview = {
        position = "inside", -- Places the visual preview inside comments
      },
    })
  end,
}
