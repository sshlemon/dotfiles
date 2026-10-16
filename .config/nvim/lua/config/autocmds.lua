-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "yaml",
  callback = function()
    if vim.fn.findfile("ansible.cfg", ".;") ~= "" then
      vim.bo.filetype = "yaml.ansible"
      vim.opt_local.shiftwidth = 1
      vim.opt_local.tabstop = 1
      vim.opt_local.softtabstop = 1
      vim.opt_local.expandtab = true
      vim.opt_local.autoindent = true
      vim.opt_local.smartindent = true
    end
  end,
})
