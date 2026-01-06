local config = require("todoer.config")

local M = {
  buf = nil,
  win = nil,
  pattern = config.opts.pattern,
  _results = {},
  header_len = 0,
}

return M
