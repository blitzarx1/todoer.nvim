local config     = require("todoer.config")
local root       = require("todoer.root")
local matching   = require("todoer.matching")
local task_index = require("todoer.task_index")

local M = {}

local TODO_PATTERN = "TODO:(\\[[^]]+\\])?"

local file_cache = {}

local function read_lines(path)
  if file_cache[path] then return file_cache[path] end
  local ok, lines = pcall(vim.fn.readfile, path)
  lines = ok and lines or {}
  file_cache[path] = lines
  return lines
end

local function enrich_results(results)
  file_cache = {} -- clear cache per search

  for _, it in ipairs(results) do
    local lines = read_lines(it.path)
    local info = matching.extract(lines, it.lnum)
    if info then
      it.tag = info.tag
      it.desc = info.desc
      it.desc_lines = info.desc_lines
    else
      -- reasonable defaults so renderers can rely on fields existing
      it.tag = nil
      it.desc_lines = { it.text or "" }
      it.desc = it.text or ""
    end
  end

  return results
end

local function parse_rg_vimgrep(stdout, cwd)
  local results = {}

  for line in stdout:gmatch("[^\r\n]+") do
    -- rg --vimgrep: file:line:col:match
    local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
    if file and lnum and col then
      local abs = file
      if not vim.startswith(abs, "/") then
        abs = cwd .. "/" .. file
      end

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

function M.search(cb)
  local cwd = root.project_root()

  local cmd = { "rg" }
  vim.list_extend(cmd, config.opts.rg_args)
  table.insert(cmd, TODO_PATTERN)

  vim.system(cmd, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 and res.code ~= 1 then
        cb(("rg error (exit %d): %s"):format(
          res.code,
          (res.stderr or ""):gsub("%s+$", "")
        ), {})
        return
      end

      local results = parse_rg_vimgrep(res.stdout or "", cwd)
      results = enrich_results(results)

      local idx = task_index.build_index()
      results = task_index.attach(results, idx)

      cb(nil, results)
    end)
  end)
end

return M
