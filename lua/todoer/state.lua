local config = require("todoer.config")

local M = {
  buf             = nil,
  win             = nil,
  restore_idx     = nil,
  header_len      = 0,
  preview_enabled = true,
  _results        = {},
}

return M
