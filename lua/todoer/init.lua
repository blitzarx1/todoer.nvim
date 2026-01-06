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


local function apply_keymaps()
  local maps = config.opts.keymaps
  if not maps or maps == false then
    return
  end

  for _, m in ipairs(maps) do
    -- allow short form: { "<leader>td", "Todoer", "desc" }
    if type(m[1]) == "string" and type(m[2]) == "string" then
      local lhs, cmd, desc = m[1], m[2], m[3]
      vim.keymap.set("n", lhs, "<cmd>" .. cmd .. "<cr>", {
        silent = true,
        desc = desc,
      })
    else
      local mode = m.mode or "n"
      local lhs = assert(m.lhs, "todoer keymap missing lhs")
      local rhs

      if m.rhs then
        rhs = m.rhs
      elseif m.cmd then
        rhs = "<cmd>" .. m.cmd .. "<cr>"
      else
        error("todoer keymap must have rhs or cmd")
      end

      local opts = vim.tbl_extend("force", {
        silent = true,
        desc = m.desc,
      }, m.opts or {})

      vim.keymap.set(mode, lhs, rhs, opts)
    end
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
  apply_keymaps()
end

function M.open(args)
  panel.open(args)
end

return M
