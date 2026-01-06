local config = require("todoer.config")

local M = {
  buf             = nil,
  win             = nil,
  header_len      = 0,
  preview_enabled = true,
  _results        = {},
}

return M
