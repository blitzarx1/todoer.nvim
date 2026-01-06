local config = require("todoer.config")
local panel = require("todoer.panel")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

function M.open(args)
  panel.open(args)
end

return M
