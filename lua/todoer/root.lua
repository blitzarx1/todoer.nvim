local config = require("todoer.config")

local M = {}

function M.project_root()
  return vim.fs.root(vim.loop.cwd(), config.opts.root_markers) or vim.loop.cwd()
end

return M
