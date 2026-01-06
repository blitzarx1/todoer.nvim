local M = {}

local CONTINUATION_MARK = " ⏎"

function M.format_aligned_results(results)
  local lines = {}
  if not results or #results == 0 then return lines end

  -- 1) compute max widths for loc and tag columns
  local locs, max_loc_w = {}, 0
  local tags, max_tag_w = {}, 0

  for i, it in ipairs(results) do
    local loc = ("%s:%d:%d"):format(it.display_path or it.path, it.lnum, it.col)
    locs[i] = loc
    local lw = vim.fn.strdisplaywidth(loc)
    if lw > max_loc_w then max_loc_w = lw end

    local tag = it.tag and ("[%s]"):format(it.tag) or ""
    tags[i] = tag
    local tw = vim.fn.strdisplaywidth(tag)
    if tw > max_tag_w then max_tag_w = tw end
  end

  -- 2) render aligned lines
  for i, it in ipairs(results) do
    local loc = locs[i]
    local loc_pad = max_loc_w - vim.fn.strdisplaywidth(loc)

    local tag = tags[i]
    local tag_pad = max_tag_w - vim.fn.strdisplaywidth(tag)

    local first = (it.desc_lines and it.desc_lines[1]) or it.text or ""
    if it.desc_lines and #it.desc_lines > 1 then
      first = first .. CONTINUATION_MARK
    end

    -- loc + two spaces + tag column + spaces + two spaces + message
    lines[i] = loc
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
