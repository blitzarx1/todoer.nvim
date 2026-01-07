local config = require("todoer.config")
local panel = require("todoer.panel")

local M = {}

local did_setup = false

local function ensure_version()
  if vim.fn.has("nvim-0.10") == 1 then
    return true
  end

  vim.notify("[Todoer] Neovim 0.10+ required", vim.log.levels.ERROR)
  return false
end

local function ensure_rg()
  if vim.fn.executable("rg") == 1 then
    return true
  end

  vim.notify("[Todoer] ripgrep (rg) not found. Install it (e.g. `brew install ripgrep`).", vim.log.levels.ERROR)
  return false
end

local function apply_global_mappings()
  local m = config.opts.mappings and config.opts.mappings.global
  if not m then return end

  if m.open then
    vim.keymap.set("n", m.open, "<cmd>Todoer<cr>", { silent = true, desc = "Todoer list" })
  end
end

function M.setup(user_opts)
  -- guard against multiple setup calls
  if did_setup then
    return
  end
  did_setup = true

  if not ensure_version() then
    return
  end
  if not ensure_rg() then
    return
  end

  config.setup(user_opts)
  apply_global_mappings()
end

function M.open(args)
  panel.open(args)
end

return M
