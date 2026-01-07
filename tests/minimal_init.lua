-- Minimal init for plenary.nvim tests
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/plenary"

-- Set up runtimepath to include the plugin
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Add plenary to runtimepath (adjust path as needed)
local plenary_paths = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}

for _, plenary_path in ipairs(plenary_paths) do
  if vim.fn.isdirectory(plenary_path) == 1 then
    vim.opt.runtimepath:prepend(plenary_path)
    break
  end
end

-- Ensure plenary is available
local ok, plenary = pcall(require, "plenary")
if not ok then
  print("ERROR: plenary.nvim is not available")
  print("Install it with your package manager or:")
  print("  git clone https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim")
  vim.cmd("cq 1")
end

-- Initialize shelter.nvim with default config
require("shelter").setup({
  skip_comments = true,
  mask_char = "*",
  default_mode = "full",
})
