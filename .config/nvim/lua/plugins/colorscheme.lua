return {
  "Zeioth/neon.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    -- 1. Set the colorscheme first
    vim.cmd.colorscheme("neon-cyberpunk-night")

    -- 2. Define a function to clear backgrounds
    local function make_transparent()
      local groups = {
        "Normal", -- Main editor background
        "NormalNC", -- Non-current windows (splits)
        "NormalFloat", -- Floating windows (menus, some explorers)
        "SignColumn", -- Git/Debug column
        "EndOfBuffer", -- The ~ lines at the bottom
        "SnacksExplorer", -- Specific to snacks.nvim explorer (if it uses this)
        "SnacksPicker", -- Specific to snacks.nvim picker
      }

      for _, group in ipairs(groups) do
        -- Use pcall to avoid errors if a group doesn't exist in this theme version
        pcall(vim.api.nvim_set_hl, 0, group, { bg = "NONE", ctermbg = "NONE" })
      end

      -- 3. Specific fix for Snacks.nvim backdrop if using zen/picker modes
      -- If snacks uses a backdrop window, this ensures it doesn't draw a solid color
      pcall(vim.api.nvim_set_hl, 0, "SnacksBackdrop", { bg = "NONE" })
    end

    -- 4. Apply immediately
    make_transparent()

    -- 5. Re-apply automatically if the colorscheme changes or UI loads later
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = make_transparent,
    })

    -- 6. Optional: Re-apply on BufEnter to catch lazy-loaded plugins like snacks
    vim.api.nvim_create_autocmd("BufEnter", {
      callback = make_transparent,
    })
  end,
}
