local M = {}

function M.format_aligned_results(results)
  local lines = {}
  if not results or #results == 0 then return lines end

  local locs, maxw = {}, 0
  for i, it in ipairs(results) do
    local loc = ("%s:%d:%d"):format(it.display_path or it.path, it.lnum, it.col)
    locs[i] = loc
    local w = vim.fn.strdisplaywidth(loc)
    if w > maxw then maxw = w end
  end

  for i, it in ipairs(results) do
    local loc = locs[i]
    local pad = maxw - vim.fn.strdisplaywidth(loc)
    lines[i] = loc .. string.rep(" ", pad) .. "  " .. (it.text or "")
  end

  return lines
end

return M
