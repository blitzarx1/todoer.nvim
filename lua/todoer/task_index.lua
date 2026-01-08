local config = require("todoer.config")
local root = require("todoer.root")

local M = {}

local function readfile(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Normalize the "todo text" so it is stable across:
-- - whitespace changes
-- - your "(path:lnum:col)" suffix in description.md
local function normalize_todo_text(s)
  s = tostring(s or "")
  s = s:gsub("\r", "")
  s = s:gsub("\n", " ")
  s = s:gsub("%s+", " ")
  s = trim(s)

  -- If your description.md bullet includes " (path:line:col)", strip it:
  s = s:gsub("%s*%([^%)]+:%d+:%d+%)%s*$", "")

  return s
end

local function todo_key_from_text(s)
  local norm = normalize_todo_text(s)
  -- Optional hash key (compact, stable). Requires Vim built-in sha256().
  -- If sha256() not available, fallback to normalized text.
  local ok, h = pcall(vim.fn.sha256, norm)
  return ok and h or norm
end

local function parse_meta(meta_lines)
  local meta = { status = nil, priority = nil, created = nil, updated = nil }
  for _, l in ipairs(meta_lines or {}) do
    local k, v = l:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
    if k and v then
      if k == "status" then meta.status = v end
      if k == "priority" then meta.priority = v end
      if k == "created" then meta.created = v end
      if k == "updated" then meta.updated = v end
    end
  end
  return meta
end

local function extract_task_todos(desc_lines)
  local todos = {}
  for _, l in ipairs(desc_lines or {}) do
    -- matches: - [ ] text...   or  - [x] text...
    local text = l:match("^%s*%-%s*%[[ xX]%]%s*(.+)$")
    if text and text ~= "" then
      table.insert(todos, text)
    end
  end
  return todos
end

--- Scan .todo directory and build index: todo_key -> task meta
function M.build_index()
  local project = root.project_root()
  local todo_dir = config.opts.todo_dir or ".todo"
  local todo_root = project .. "/" .. todo_dir

  if vim.fn.isdirectory(todo_root) ~= 1 then
    return {} -- no tasks yet
  end

  local dirs = vim.fn.globpath(todo_root, "*", false, true) or {}
  local index = {}

  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      local meta_lines = readfile(dir .. "/meta") or {}
      local desc_lines = readfile(dir .. "/description.md") or {}

      local meta = parse_meta(meta_lines)
      meta.task_dir = dir

      for _, todo_text in ipairs(extract_task_todos(desc_lines)) do
        local key = todo_key_from_text(todo_text)
        -- If duplicates exist, keep the first one we see (simple rule).
        -- Later you can decide precedence by updated date etc.
        if not index[key] then
          index[key] = meta
        end
      end
    end
  end

  return index
end

--- Attach task metadata to todo results in-place.
--- Adds: it.task_status, it.task_priority, it.task_dir
function M.attach(results, index)
  index = index or M.build_index()
  for _, it in ipairs(results or {}) do
    local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
    local key = todo_key_from_text(first)
    local meta = index[key]
    if meta then
      it.task_status = meta.status
      it.task_priority = meta.priority
      it.task_dir = meta.task_dir
    else
      it.task_status = nil
      it.task_priority = nil
      it.task_dir = nil
    end
  end
  return results
end

return M
