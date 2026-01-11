local root = require("todoer.root")
local config = require("todoer.config")
local keys = require("todoer.keys")

local M = {}

local function now_rfc3339_utc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
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

local function first_line_text(it)
  local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
  return keys.normalize_text(first)
end

local function loc_string(it)
  return ("%s:%d:%d"):format(it.display_path or it.path, it.lnum or 1, it.col or 1)
end

-- ---------- IDs (explicit + encapsulated) ----------

-- Stable todo identity (does NOT include position)
local function todo_id(tag, first_line_norm)
  return keys.todo_key(tag, first_line_norm)
end

-- Stable per-file group key for counting/refresh
local function todo_file_key(tid, file)
  return ("%s|%s"):format(tid, file)
end

-- ---------- meta ----------

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

-- ---------- description parsing / formatting ----------

local function extract_loc_suffix(text)
  -- expects "... (path:line:col)" at end
  return text:match("%(([^%)]+:%d+:%d+)%)%s*$")
end

local function strip_loc_suffix(text)
  -- remove trailing " (path:line:col)" if present
  return (tostring(text or ""):gsub("%s*%([^%)]+:%d+:%d+%)%s*$", ""))
end

local function loc_to_file(loc)
  if not loc then return nil end
  -- remove trailing :line:col
  return (loc:gsub(":%d+:%d+$", ""))
end

local function parse_loc_line_col(loc)
  if not loc then return nil, nil end
  local lnum, col = loc:match(":(%d+):(%d+)$")
  return tonumber(lnum), tonumber(col)
end

local function parse_description(desc_lines, task_tag)
  local bullets = {}

  for idx, l in ipairs(desc_lines or {}) do
    local chk, text = l:match("^%s*%-%s*%[([ xX])%]%s*(.+)$")
    if chk and text and text ~= "" then
      local loc = extract_loc_suffix(text)
      local file = loc_to_file(loc)

      local todo_text = keys.normalize_text(strip_loc_suffix(text))
      local tid = todo_id(task_tag, todo_text)

      table.insert(bullets, {
        line_index = idx,
        raw = l,
        checked = (chk ~= " "),
        text = text, -- original (may include loc)
        todo_text = todo_text,
        tid = tid,
        file = file,
        loc = loc,
      })
    end
  end

  return bullets
end

local function format_bullet(checked, todo_text, loc)
  local mark = checked and "x" or " "
  todo_text = keys.normalize_text(todo_text)

  if checked then
    -- Completed todos should not show location
    return ("- [%s] %s"):format(mark, todo_text)
  end

  if loc and loc ~= "" then
    return ("- [%s] %s (%s)"):format(mark, todo_text, loc)
  end

  return ("- [%s] %s"):format(mark, todo_text)
end

-- ---------- task dir helpers ----------

local function todo_root_dir(project)
  return project .. "/" .. (config.opts.todo_dir or ".todo")
end

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

  local task_key = keys.task_key(tag, first_line_norm)
  local existing = find_task_dir_by_task_key(todo_root, task_key)
  if existing then
    return existing, nil
  end

  local folder_name
  if tag and tag ~= "" then
    folder_name = sanitize_dirname(tag)
  else
    folder_name = sanitize_dirname(first_line_norm)
    if #folder_name > 80 then folder_name = folder_name:sub(1, 80) end
    if folder_name == "" then folder_name = "task" end
  end

  local base = todo_root .. "/" .. folder_name
  local task_dir = base
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

-- ---------- create/update from item ----------

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

  -- merge locations (keeps exact last-known locs, useful for jumping)
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

  -- read existing description
  local existing_desc_lines = readfile(desc_path) or {}
  local existing_bullets = parse_description(existing_desc_lines, meta.tag)

  -- Count existing instances per (todo_id, file)
  local existing_count = {}
  for _, b in ipairs(existing_bullets) do
    if b.file then
      local gk = todo_file_key(b.tid, b.file)
      existing_count[gk] = (existing_count[gk] or 0) + 1
    end
  end

  -- Build scan occurrences per (todo_id, file)
  local scan_occ = {}
  local scan_todo_text = {} -- representative text to print for that group
  for _, it in ipairs(items) do
    local todo_text = first_line_text(it)
    local tid = todo_id(meta.tag, todo_text)
    local file = it.display_path or it.path
    local gk = todo_file_key(tid, file)

    scan_occ[gk] = scan_occ[gk] or {}
    table.insert(scan_occ[gk], loc_string(it))

    scan_todo_text[gk] = scan_todo_text[gk] or todo_text
  end

  -- sort each group's occurrences by (line, col) for stable bullet additions
  for gk, occs in pairs(scan_occ) do
    table.sort(occs, function(a, b)
      local la, ca = parse_loc_line_col(a)
      local lb, cb = parse_loc_line_col(b)
      if (la or 0) ~= (lb or 0) then return (la or 0) < (lb or 0) end
      return (ca or 0) < (cb or 0)
    end)
  end

  -- Header should be unhashed identifier:
  local header = (meta.tag and meta.tag ~= "" and meta.tag) or selected_first or now

  local desc_lines = {
    ("# %s"):format(header),
    "",
  }

  -- Keep existing content except old header
  for _, l in ipairs(existing_desc_lines) do
    if not l:match("^%s*#%s+") then
      table.insert(desc_lines, l)
    end
  end

  if desc_lines[3] and desc_lines[3] ~= "" then
    table.insert(desc_lines, 3, "")
  end

  -- Append missing instances based on counts
  local keys_sorted = {}
  for gk, _ in pairs(scan_occ) do
    table.insert(keys_sorted, gk)
  end
  table.sort(keys_sorted)

  local appended_any = false
  for _, gk in ipairs(keys_sorted) do
    local want = #scan_occ[gk]
    local have = existing_count[gk] or 0
    if want > have then
      for i = have + 1, want do
        local todo_text = scan_todo_text[gk] or ""
        local loc = scan_occ[gk][i]
        table.insert(desc_lines, format_bullet(false, todo_text, loc))
        appended_any = true
      end
    end
  end

  if appended_any then
    table.insert(desc_lines, "")
  end

  local ok1 = writefile(meta_path, meta_to_lines(meta))
  local ok2 = writefile(desc_path, desc_lines)

  if not (ok1 and ok2) then
    vim.notify(("[Todoer] Failed writing task files in %s"):format(task_dir), vim.log.levels.ERROR)
    return
  end

  vim.notify(("[Todoer] Task updated: %s"):format(task_dir), vim.log.levels.INFO)
end

-- ---------- sync from scan ----------

--- Sync tasks against latest scan results.
--- Mechanic:
--- 1) Completed bullets lose their location.
--- 2) Open bullets get refreshed locations based on current scan (shift-safe).
--- 3) For each (todo_id, file), if scan finds N occurrences, keep instances 1..N open.
---    Any additional instances in description.md get auto-ticked (and location removed).
--- 4) If all bullets are ticked, set task status to DONE.
function M.sync_from_scan(results)
  local project = root.project_root()
  local todo_root = todo_root_dir(project)
  if vim.fn.isdirectory(todo_root) ~= 1 then return end

  -- Build scan occurrences (not just counts) per (todo_id, file)
  local scan_occ = {}
  for _, it in ipairs(results or {}) do
    if it then
      local todo_text = first_line_text(it)
      local tid = todo_id(it.tag, todo_text)
      local file = it.display_path or it.path
      local gk = todo_file_key(tid, file)

      scan_occ[gk] = scan_occ[gk] or {}
      table.insert(scan_occ[gk], loc_string(it))
    end
  end

  -- sort occurrences so instance 1..N maps stably
  for gk, occs in pairs(scan_occ) do
    table.sort(occs, function(a, b)
      local la, ca = parse_loc_line_col(a)
      local lb, cb = parse_loc_line_col(b)
      if (la or 0) ~= (lb or 0) then return (la or 0) < (lb or 0) end
      return (ca or 0) < (cb or 0)
    end)
  end

  local dirs = vim.fn.globpath(todo_root, "*", false, true) or {}
  local now = now_rfc3339_utc()

  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      local meta_path = dir .. "/meta"
      local desc_path = dir .. "/description.md"

      if vim.fn.filereadable(meta_path) == 1 and vim.fn.filereadable(desc_path) == 1 then
        local meta = parse_meta(readfile(meta_path) or {})
        local desc_lines = readfile(desc_path) or {}

        local bullets = parse_description(desc_lines, meta.tag)

        -- instance index per (todo_id, file) within THIS task
        local seen_idx = {}

        local total = 0
        local done = 0
        local changed_desc = false

        for _, b in ipairs(bullets) do
          total = total + 1

          local is_checked = b.checked

          if not b.file then
            -- no file info -> can't refresh; still enforce "completed has no location"
            if is_checked then
              local new_line = format_bullet(true, b.todo_text, nil)
              if desc_lines[b.line_index] ~= new_line then
                desc_lines[b.line_index] = new_line
                changed_desc = true
              end
            end
          else
            local gk = todo_file_key(b.tid, b.file)
            seen_idx[gk] = (seen_idx[gk] or 0) + 1
            local idx = seen_idx[gk]

            local occs = scan_occ[gk] or {}
            local allowed_open = #occs

            if is_checked then
              -- Completed: remove location
              local new_line = format_bullet(true, b.todo_text, nil)
              if desc_lines[b.line_index] ~= new_line then
                desc_lines[b.line_index] = new_line
                changed_desc = true
              end
            else
              if idx > allowed_open then
                -- This instance no longer exists in code -> auto-check + remove location
                local new_line = format_bullet(true, b.todo_text, nil)
                desc_lines[b.line_index] = new_line
                changed_desc = true
                is_checked = true
              else
                -- Still exists -> refresh location to current scan
                local new_loc = occs[idx]
                local new_line = format_bullet(false, b.todo_text, new_loc)
                if desc_lines[b.line_index] ~= new_line then
                  desc_lines[b.line_index] = new_line
                  changed_desc = true
                end
              end
            end
          end

          if is_checked then done = done + 1 end
        end

        local meta_changed = false
        if total > 0 and done == total and meta.status ~= "DONE" then
          meta.status = "DONE"
          meta.updated = now
          meta_changed = true
        end

        if changed_desc then
          writefile(desc_path, desc_lines)
        end
        if meta_changed then
          writefile(meta_path, meta_to_lines(meta))
        end
      end
    end
  end
end

return M
