local root = require("todoer.root")
local config = require("todoer.config")

local M = {}

local function now_rfc3339_utc()
  -- UTC timestamp in RFC3339
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function now_rfc3339_for_dir()
  -- filesystem-friendly UTC timestamp
  return os.date("!%Y-%m-%dT%H-%M-%SZ")
end

local function sanitize_dirname(s)
  -- Keep it simple: letters, numbers, underscore, dash, dot.
  -- Replace everything else with underscore.
  s = tostring(s or "")
  s = s:gsub("%s+", "_")
  s = s:gsub("[^%w%._%-]", "_")
  s = s:gsub("_+", "_")
  s = s:gsub("^_+", ""):gsub("_+$", "")
  if s == "" then s = "task" end
  return s
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 1 then
    return true
  end
  local ok = pcall(vim.fn.mkdir, path, "p")
  return ok and vim.fn.isdirectory(path) == 1
end

local function unique_dir(path)
  if vim.fn.isdirectory(path) ~= 1 then
    return path
  end
  for i = 2, 999 do
    local candidate = ("%s-%d"):format(path, i)
    if vim.fn.isdirectory(candidate) ~= 1 then
      return candidate
    end
  end
  return path .. "-9999"
end

local function loc_string(it)
  return ("%s:%d:%d"):format(it.display_path or it.path, it.lnum or 1, it.col or 1)
end

local function first_line_text(it)
  -- Prefer extracted structured description preview; fallback to rg text.
  local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
  first = tostring(first):gsub("[\r\n]+", " ")
  return vim.trim(first)
end

--- Create task folder + files from one selected item.
--- `results` is the current list of TODO matches; used to gather same-tag TODOs.
function M.create_from_item(item, results)
  if not item then
    vim.notify("[Todoer] No TODO under cursor.", vim.log.levels.WARN)
    return
  end

  local project = root.project_root()
  local todo_dir = (config.opts and config.opts.todo_dir) or ".todo"
  local todo_root = project .. "/" .. todo_dir

  if not ensure_dir(todo_root) then
    vim.notify(("[Todoer] Failed to create %s"):format(todo_root), vim.log.levels.ERROR)
    return
  end

  local tag = item.tag
  local created = now_rfc3339_utc()
  local updated = created

  local folder_name
  if tag and tag ~= "" then
    folder_name = sanitize_dirname(tag)
  else
    folder_name = now_rfc3339_for_dir()
  end

  local task_path = unique_dir(todo_root .. "/" .. folder_name)
  if not ensure_dir(task_path) then
    vim.notify(("[Todoer] Failed to create task dir: %s"):format(task_path), vim.log.levels.ERROR)
    return
  end

  -- Collect todos for this task:
  -- if tag exists => all items with same tag
  -- else => only this item
  local items = {}
  if tag and tag ~= "" then
    for _, it in ipairs(results or {}) do
      if it and it.tag == tag then
        table.insert(items, it)
      end
    end
  else
    table.insert(items, item)
  end

  -- meta file (simple YAML-ish; easy to parse later)
  local meta_lines = {
    ("status: %s"):format("OPEN"),
    ("priority: %s"):format("MEDIUM"),
    ("created: %s"):format(created),
    ("updated: %s"):format(updated),
    "locations:",
  }
  for _, it in ipairs(items) do
    table.insert(meta_lines, ("  - %s"):format(loc_string(it)))
  end

  -- description.md
  local header = tag and tag ~= "" and tag or folder_name
  local desc_lines = {
    ("# %s"):format(header),
    "",
  }
  for _, it in ipairs(items) do
    table.insert(desc_lines, ("- [ ] %s (%s)"):format(first_line_text(it), loc_string(it)))
  end
  table.insert(desc_lines, "")

  local meta_path = task_path .. "/meta"
  local desc_path = task_path .. "/description.md"

  local ok1 = pcall(vim.fn.writefile, meta_lines, meta_path)
  local ok2 = pcall(vim.fn.writefile, desc_lines, desc_path)

  if not (ok1 and ok2) then
    vim.notify(("[Todoer] Failed writing task files in %s"):format(task_path), vim.log.levels.ERROR)
    return
  end

  vim.notify(("[Todoer] Task created: %s"):format(task_path), vim.log.levels.INFO)
end

return M
