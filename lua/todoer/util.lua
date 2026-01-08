local M = {}

local CONTINUATION_MARK = " ⏎"

local function dispw(s)
  return vim.fn.strdisplaywidth(s or "")
end

local STATUS_MAP = {
  OPEN = "O",
  IN_PROGRESS = "I",
  DONE = "D",
}

local PRIORITY_MAP = {
  LOW = "L",
  MEDIUM = "M",
  HIGH = "H",
}

local function status_char(it)
  return STATUS_MAP[it.task_status] or "·"
end

local function priority_char(it)
  return PRIORITY_MAP[it.task_priority] or "·"
end

function M.format_aligned_results(results)
  local lines = {}
  if not results or #results == 0 then return lines end

  -- compute max widths for: status(1), priority(1), loc, tag
  local locs, max_loc_w = {}, 0
  local tags, max_tag_w = {}, 0

  for i, it in ipairs(results) do
    local loc = ("%s:%d:%d"):format(it.display_path or it.path, it.lnum, it.col)
    locs[i] = loc
    max_loc_w = math.max(max_loc_w, dispw(loc))

    local tag = it.tag and ("[%s]"):format(it.tag) or ""
    tags[i] = tag
    max_tag_w = math.max(max_tag_w, dispw(tag))
  end

  -- render aligned lines
  for i, it in ipairs(results) do
    local st = status_char(it)
    local pr = priority_char(it)

    local loc = locs[i]
    local loc_pad = max_loc_w - dispw(loc)

    local tag = tags[i]
    local tag_pad = max_tag_w - dispw(tag)

    local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
    first = tostring(first):gsub("[\r\n]+", " ")
    if it.desc_lines and #it.desc_lines > 1 then
      first = first .. CONTINUATION_MARK
    end

    -- status + space + priority + 2 spaces + loc + pad + 2 + tag + pad + 2 + message
    lines[i] =
      st
      .. " "
      .. pr
      .. "  "
      .. loc
      .. string.rep(" ", loc_pad)
      .. "  "
      .. tag
      .. string.rep(" ", tag_pad)
      .. "  "
      .. first
  end

  return lines
end

return M
