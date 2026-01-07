local M = {}

-- TODO:[mvp] add opt to exclude certain paths or filetypes from search

M.defaults = {
  root_markers     = { ".git", "go.mod", "package.json" },
  open_cmd         = "tabnew", -- command to open the todoer panel (e.g., "tabnew", "vsplit", "split")

  rg_args          = { "--vimgrep", "--no-heading", "--smart-case", "--hidden", "--glob", "!.git/" },

  buffer_name_list = "TodoerList",

  todo_dir = ".todo",

  mappings = {
    global = {
      open     = "<leader>tt", 
      new_task = "<leader>tn",
    },
  },
}

M.opts = vim.deepcopy(M.defaults)

local function validate(opts)
  if type(opts.open_cmd) ~= "string" then
    error("[Todoer] opts.open_cmd must be a string")
  end

  if type(opts.rg_args) ~= "table" then
    error("[Todoer] opts.rg_args must be a table of strings")
  end

  if opts.mappings ~= nil then
    if type(opts.mappings) ~= "table" then
      error("[Todoer] opts.mappings must be a table")
    end
    if opts.mappings.global ~= nil and type(opts.mappings.global) ~= "table" then
      error("[Todoer] opts.mappings.global must be a table")
    end
    if opts.mappings.global and opts.mappings.global.open ~= nil and type(opts.mappings.global.open) ~= "string" then
      error("[Todoer] opts.mappings.global.open must be a string or nil")
    end
  end
end

function M.setup(user_opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
  validate(merged)
  M.opts = merged
end

return M
