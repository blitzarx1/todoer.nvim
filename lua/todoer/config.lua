local M = {}

-- TODO:[mvp] add opt to exclude certain paths or filetypes from search

M.opts = {
  root_markers = { ".git", "go.mod", "package.json" },
  open_cmd = "tabnew",
  rg_args = { "--vimgrep", "--no-heading", "--smart-case", "--hidden", "--glob", "!.git/" },
  buffer_name = "Todoer",
  keymaps = nil,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
