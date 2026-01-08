local root = require("todoer.root")
local config = require("todoer.config")
local keys = require("todoer.keys")

local M = {}

local function now_rfc3339_utc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function now_rfc3339_for_dir()
  -- safe for folder names
  return os.date("!%Y-%m-%dT%H-%M-%SZ")
end

local function sanitize_dirname(s)
  s = tostring(s or "")
  s = s:gsub("%s+", "_")
  s = s:gsub("[^%w%._%-]", "_")
  s = s:gsub("_+", "_")
  s = s:gsub("^_+", ""):gsub("_+$", "")
  if s == "" then s = "task" end
  return s
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 1 then return true end
  local ok = pcall(vim.fn.mkdir, path, "p")
  return ok and vim.fn.isdirectory(path) == 1
end

local function readfile(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function writefile(path, lines)
  local ok = pcall(vim.fn.writefile, lines, path)
  return ok
end

local function loc_string(it)
  return ("%s:%d:%d"):format(it.display_path or it.path, it.lnum or 1, it.col or 1)
end

local function first_line_text(it)
  local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
  return keys.normalize_text(first)
end

local function parse_meta(meta_lines)
  local meta = {
    id = nil,
    task_key = nil,
    tag = nil,
    status = nil,
    priority = nil,
    created = nil,
    updated = nil,
    locations = {},
  }

  local in_locations = false
  for _, l in ipairs(meta_lines or {}) do
    if l:match("^%s*locations%s*:%s*$") then
      in_locations = true
    elseif in_locations then
      local loc = l:match("^%s*%-%s*(.+)%s*$")
      if loc and loc ~= "" then table.insert(meta.locations, loc) end
    else
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
  end

  return meta
end

local function meta_to_lines(meta)
  local lines = {
    ("id: %s"):format(meta.id or ""),
    ("task_key: %s"):format(meta.task_key or ""),
    ("tag: %s"):format(meta.tag or ""),
    ("status: %s"):format(meta.status or "OPEN"),
    ("priority: %s"):format(meta.priority or "MEDIUM"),
    ("created: %s"):format(meta.created or now_rfc3339_utc()),
    ("updated: %s"):format(meta.updated or now_rfc3339_utc()),
    "locations:",
  }
  for _, loc in ipairs(meta.locations or {}) do
    table.insert(lines, ("  - %s"):format(loc))
  end
  return lines
end

local function parse_description(desc_lines)
  local bullets = {}
  for _, l in ipairs(desc_lines or {}) do
    local chk, text = l:match("^%s*%-%s*%[([ xX])%]%s*(.+)$")
    if chk and text and text ~= "" then
      table.insert(bullets, {
        raw = l,
        checked = (chk ~= " "),
        text = text,
      })
    end
  end
  return bullets
end

local function format_bullet(checked, todo_text, loc)
  local mark = checked and "x" or " "
  return ("- [%s] %s (%s)"):format(mark, keys.normalize_text(todo_text), loc)
end

local function todo_root_dir(project)
  return project .. "/" .. (config.opts.todo_dir or ".todo")
end

-- Find existing task dir by task_key (works for both tagged and untagged)
local function find_task_dir_by_task_key(todo_root, want_key)
  if vim.fn.isdirectory(todo_root) ~= 1 then return nil end
  local dirs = vim.fn.globpath(todo_root, "*", false, true) or {}
  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      local meta_path = dir .. "/meta"
      if vim.fn.filereadable(meta_path) == 1 then
        local meta = parse_meta(readfile(meta_path) or {})
        if meta.task_key == want_key then
          return dir
        end
      end
    end
  end
  return nil
end

local function ensure_task_dir(project, tag, first_line_norm)
  local todo_root = todo_root_dir(project)
  if not ensure_dir(todo_root) then
    return nil, ("[Todoer] Failed to create %s"):format(todo_root)
  end

  -- If task exists by task_key (works even if folder naming changes later)
  local task_key = keys.task_key(tag, first_line_norm)
  local existing = find_task_dir_by_task_key(todo_root, task_key)
  if existing then
    return existing, nil
  end

  -- Otherwise create a new folder.
  -- Tagged tasks keep tag-based folder.
  -- Untagged tasks use a slug of the first line (unhashed).
  local folder_name
  if tag and tag ~= "" then
    folder_name = sanitize_dirname(tag)
  else
    -- Unhashed task id folder name
    folder_name = sanitize_dirname(first_line_norm)

    -- Avoid absurdly long paths
    if #folder_name > 80 then
      folder_name = folder_name:sub(1, 80)
    end

    if folder_name == "" then
      folder_name = "task"
    end
  end

  local base = todo_root .. "/" .. folder_name
  local task_dir = base

  -- Ensure uniqueness if something already exists
  if vim.fn.isdirectory(task_dir) == 1 then
    for i = 2, 999 do
      local cand = ("%s-%d"):format(base, i)
      if vim.fn.isdirectory(cand) ~= 1 then
        task_dir = cand
        break
      end
    end
  end

  if not ensure_dir(task_dir) then
    return nil, ("[Todoer] Failed to create task dir: %s"):format(task_dir)
  end
  return task_dir, nil
end

--- Create or update task folder + files from one selected item.
--- `results` is current TODO matches list.
function M.create_from_item(item, results)
  if not item then
    vim.notify("[Todoer] No TODO under cursor.", vim.log.levels.WARN)
    return
  end

  local project = root.project_root()

  local selected_tag = item.tag
  local selected_first = first_line_text(item)
  local task_key = keys.task_key(selected_tag, selected_first)
  local id = keys.hash(task_key)

  local task_dir, err = ensure_task_dir(project, selected_tag, selected_first)
  if not task_dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local meta_path = task_dir .. "/meta"
  local desc_path = task_dir .. "/description.md"

  local existing_meta = nil
  if vim.fn.filereadable(meta_path) == 1 then
    existing_meta = parse_meta(readfile(meta_path) or {})
  end

  local now = now_rfc3339_utc()

  -- Preserve existing status/priority/created if present
  local meta = {
    id = (existing_meta and existing_meta.id) or id,
    task_key = (existing_meta and existing_meta.task_key) or task_key,
    tag = (existing_meta and existing_meta.tag) or selected_tag,
    status = (existing_meta and existing_meta.status) or "OPEN",
    priority = (existing_meta and existing_meta.priority) or "MEDIUM",
    created = (existing_meta and existing_meta.created) or now,
    updated = now,
    locations = {},
  }

  -- Decide which TODOs belong to this task:
  -- tagged: all results with same tag
  -- untagged: all results with NO tag and same normalized first line
  local items = {}
  for _, it in ipairs(results or {}) do
    if it then
      local it_first = first_line_text(it)
      local it_tag = it.tag

      local belongs = false
      if selected_tag and selected_tag ~= "" then
        belongs = (it_tag == selected_tag)
      else
        belongs = (not it_tag or it_tag == "") and (it_first == selected_first)
      end

      if belongs then
        table.insert(items, it)
      end
    end
  end

  -- Merge locations: keep all unique locations (this is what you want!)
  local loc_seen = {}
  if existing_meta and existing_meta.locations then
    for _, loc in ipairs(existing_meta.locations) do
      if loc and loc ~= "" and not loc_seen[loc] then
        loc_seen[loc] = true
        table.insert(meta.locations, loc)
      end
    end
  end
  for _, it in ipairs(items) do
    local loc = loc_string(it)
    if not loc_seen[loc] then
      loc_seen[loc] = true
      table.insert(meta.locations, loc)
    end
  end

  -- Read existing description and preserve checkbox state PER-LOCATION.
  -- Key = normalized first line + "|" + location
  local existing_bullets = parse_description(readfile(desc_path) or {})
  local existing_by_loc_key = {}
  for _, b in ipairs(existing_bullets) do
    local text_norm = keys.normalize_text(b.text)
    local loc = b.text:match("%(([^%)]+:%d+:%d+)%)%s*$") -- extract location at end
    if loc then
      local k = text_norm .. "|" .. loc
      existing_by_loc_key[k] = b.checked
    end
  end

  local header = meta.tag and meta.tag ~= "" and meta.tag or (existing_meta and existing_meta.created) or now
  local desc_lines = {
    ("# %s"):format(header),
    "",
  }

  -- Emit bullets for ALL locations (dedupe only by location)
  local emitted_loc = {}

  -- Keep existing bullets first (so you don't reorder user edits)
  for _, b in ipairs(existing_bullets) do
    table.insert(desc_lines, b.raw)
    local text_norm = keys.normalize_text(b.text)
    local loc = b.text:match("%(([^%)]+:%d+:%d+)%)%s*$")
    if loc then emitted_loc[text_norm .. "|" .. loc] = true end
  end

  -- Add missing bullets from current scan
  for _, it in ipairs(items) do
    local first = first_line_text(it)
    local loc = loc_string(it)
    local k = first .. "|" .. loc
    if not emitted_loc[k] then
      emitted_loc[k] = true
      local checked = existing_by_loc_key[k] or false
      table.insert(desc_lines, format_bullet(checked, first, loc))
    end
  end

  table.insert(desc_lines, "")

  -- Write files
  local ok1 = writefile(meta_path, meta_to_lines(meta))
  local ok2 = writefile(desc_path, desc_lines)

  if not (ok1 and ok2) then
    vim.notify(("[Todoer] Failed writing task files in %s"):format(task_dir), vim.log.levels.ERROR)
    return
  end

  vim.notify(("[Todoer] Task updated: %s"):format(task_dir), vim.log.levels.INFO)
end

return M
