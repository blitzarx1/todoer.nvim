local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize any text to a stable single-line representation.
--- Also strips trailing "(path:line:col)" suffix used in description bullets.
function M.normalize_text(s)
  s = tostring(s or "")
  s = s:gsub("\r", "")
  s = s:gsub("\n", " ")
  s = s:gsub("%s+", " ")
  s = trim(s)

  -- strip " (path:line:col)" suffix if present
  s = s:gsub("%s*%([^%)]+:%d+:%d+%)%s*$", "")
  return s
end

function M.normalize_tag(tag)
  tag = M.normalize_text(tag)
  tag = tag:lower()
  return tag
end

function M.hash(s)
  local ok, h = pcall(vim.fn.sha256, s)
  return ok and h or s
end

function M.short_id(s, n)
  n = n or 8
  s = tostring(s or "")
  if #s <= n then return s end
  return s:sub(1, n)
end

--- Task identity:
--- - tagged => "tag:<normalized-tag>"
--- - untagged => "untagged:<hash(first-line)>"
function M.task_key(tag, first_line)
  if tag and tag ~= "" then
    return "tag:" .. M.normalize_tag(tag)
  end
  return "untagged:" .. M.hash(M.normalize_text(first_line))
end

--- Todo entry identity:
--- - tagged => "tag:<tag>|t:<hash(first-line)>"
--- - untagged => same as task key (already keyed by first-line)
function M.todo_key(tag, first_line)
  local tk = M.task_key(tag, first_line)
  if tag and tag ~= "" then
    return tk .. "|t:" .. M.hash(M.normalize_text(first_line))
  end
  return tk
end

return M
