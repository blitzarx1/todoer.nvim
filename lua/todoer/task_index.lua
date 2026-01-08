local config = require("todoer.config")
local root = require("todoer.root")
local keys = require("todoer.keys")

local M = {}

local function readfile(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function parse_meta(meta_lines)
  local meta = { id = nil, task_key = nil, tag = nil, status = nil, priority = nil, created = nil, updated = nil }
  for _, l in ipairs(meta_lines or {}) do
    local k, v = l:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
    if k and v then
      if k == "id" then meta.id = v end
      if k == "task_key" then meta.task_key = v end
      if k == "tag" then meta.tag = (v ~= "" and v or nil) end
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
    local text = l:match("^%s*%-%s*%[[ xX]%]%s*(.+)$")
    if text and text ~= "" then
      table.insert(todos, text)
    end
  end
  return todos
end

function M.build_index()
  local project = root.project_root()
  local todo_root = project .. "/" .. (config.opts.todo_dir or ".todo")

  if vim.fn.isdirectory(todo_root) ~= 1 then
    return {}
  end

  local dirs = vim.fn.globpath(todo_root, "*", false, true) or {}
  local index = {}

  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      local meta_lines = readfile(dir .. "/meta") or {}
      local desc_lines = readfile(dir .. "/description.md") or {}

      local meta = parse_meta(meta_lines)
      meta.task_dir = dir

      local task_tag = meta.tag

      for _, todo_text in ipairs(extract_task_todos(desc_lines)) do
        local first = keys.normalize_text(todo_text)
        local k = keys.todo_key(task_tag, first)
        if not index[k] then
          index[k] = meta
        end
      end
    end
  end

  return index
end

function M.attach(results, index)
  index = index or M.build_index()

  for _, it in ipairs(results or {}) do
    local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
    first = keys.normalize_text(first)

    local k = keys.todo_key(it.tag, first)
    local meta = index[k]

    if meta then
      it.task_status = meta.status
      it.task_priority = meta.priority
      it.task_dir = meta.task_dir
      it.task_id = meta.id
      it.task_key = meta.task_key
    else
      it.task_status = nil
      it.task_priority = nil
      it.task_dir = nil
      it.task_id = nil
      it.task_key = nil
    end
  end

  return results
end

return M
