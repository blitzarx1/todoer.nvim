local config = require("todoer.config")
local root = require("todoer.root")

local M = {}

local function ensure_rg()
  if vim.fn.executable("rg") ~= 1 then
    vim.notify("[Todoer] ripgrep (rg) not found. Install it (e.g. `brew install ripgrep`).", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function parse_rg_vimgrep(stdout, cwd)
  local results = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
    if file and lnum and col then
      local abs = file
      if not vim.startswith(abs, "/") then abs = cwd .. "/" .. file end
      table.insert(results, {
        path = vim.fn.fnamemodify(abs, ":p"),
        display_path = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = vim.trim(text or ""),
      })
    end
  end
  return results
end

function M.search(pattern, cb)
  if not ensure_rg() then
    cb("rg not found", {})
    return
  end

  local cwd = root.project_root()
  local cmd = { "rg" }
  vim.list_extend(cmd, config.opts.rg_args)
  table.insert(cmd, pattern)
  -- no "." needed because cwd is set

  vim.system(cmd, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 and res.code ~= 1 then
        cb(("rg error (exit %d): %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")), {})
        return
      end
      cb(nil, parse_rg_vimgrep(res.stdout or "", cwd))
    end)
  end)
end

return M
