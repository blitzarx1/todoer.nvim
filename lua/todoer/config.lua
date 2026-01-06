local M = {}

M.opts = {
  pattern = "TODO:",
  root_markers = { ".git", "go.mod", "package.json" },
  open_cmd = "tabnew", -- later: "vsplit", "split", etc.
  rg_args = { "--vimgrep", "--no-heading", "--smart-case", "--hidden", "--glob", "!.git/" },
  buffer_name = "Todoer",
  keymaps = nil,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
