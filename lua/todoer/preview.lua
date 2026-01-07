local M = {}

-- window -> match_id (so we only delete what we added)
local win_match_id = {}

local function find_preview_win_in_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ok, is_preview = pcall(vim.api.nvim_get_option_value, "previewwindow", { win = win })
    if ok and is_preview then
      return win
    end
  end
  return nil
end

local function ensure_hl()
  if vim.fn.hlexists("CurSearch") == 1 then
    vim.api.nvim_set_hl(0, "TodoerPreviewMatch", { link = "CurSearch" })
  else
    vim.api.nvim_set_hl(0, "TodoerPreviewMatch", { link = "Search" })
  end
end

local function clear_our_match(pwin)
  local id = win_match_id[pwin]
  if not id then return end
  pcall(vim.api.nvim_win_call, pwin, function()
    pcall(vim.fn.matchdelete, id)
  end)
  win_match_id[pwin] = nil
end

local function apply_match_highlight(pwin, pbuf, item)
  ensure_hl()

  clear_our_match(pwin)

  pcall(vim.api.nvim_win_call, pwin, function()
    local lnum0 = item.lnum - 1
    local line = vim.api.nvim_buf_get_lines(pbuf, lnum0, lnum0 + 1, false)[1] or ""

    local s, e = line:find("TODO:%b[]")
    if not s then s, e = line:find("TODO:") end
    if not s then return end

    -- matchaddpos uses (line, col, len) with 1-based col
    local col1 = s
    local len = e - s + 1
    local id = vim.fn.matchaddpos("TodoerPreviewMatch", { { item.lnum, col1, len } })
    win_match_id[pwin] = id
  end)
end

local function ensure_filetype(pbuf, path)
  local ft = vim.filetype.match({ filename = path })
  if ft and ft ~= "" then
    vim.bo[pbuf].filetype = ft
  end
  vim.api.nvim_buf_call(pbuf, function()
    vim.cmd("filetype detect")
  end)
end

local function apply_window_opts(pwin)
  vim.api.nvim_set_option_value("wrap", false, { win = pwin })
  vim.api.nvim_set_option_value("number", true, { win = pwin })
  vim.api.nvim_set_option_value("relativenumber", false, { win = pwin })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = pwin })
  vim.api.nvim_set_option_value("cursorline", false, { win = pwin })
end

local function resize_preview(list_win, pwin, ratio)
  ratio = ratio or 0.4

  if not (list_win and vim.api.nvim_win_is_valid(list_win)) then
    return
  end

  local list_w = vim.api.nvim_win_get_width(list_win)
  local prev_w = vim.api.nvim_win_get_width(pwin)
  local total_w = list_w + prev_w

  local target = math.max(20, math.floor(total_w * ratio))
  if math.abs(prev_w - target) > 1 then
    pcall(vim.api.nvim_win_set_width, pwin, target)
  end
  vim.api.nvim_set_option_value("winfixwidth", true, { win = pwin })
end

local function center_on_item(pwin, item)
  local col0 = math.max((item.col or 1) - 1, 0)
  pcall(vim.api.nvim_win_set_cursor, pwin, { item.lnum, col0 })
  pcall(vim.api.nvim_win_call, pwin, function()
    vim.cmd("normal! zz")
  end)
end

function M.update(item, opts)
  opts = opts or {}
  if not opts.enabled then return end

  if not item then
    M.close()
    return
  end

  local list_win = opts.list_win or vim.api.nvim_get_current_win()
  local ratio = opts.ratio or 0.4

  -- Open/update preview on the right
  local old_splitright = vim.o.splitright
  vim.o.splitright = true
  vim.cmd(("silent! rightbelow vert pedit +%d %s"):format(item.lnum, vim.fn.fnameescape(item.path)))
  vim.o.splitright = old_splitright

  local pwin = find_preview_win_in_tab()
  if not pwin then
    if list_win and vim.api.nvim_win_is_valid(list_win) then
      vim.api.nvim_set_current_win(list_win)
    end
    return
  end

  local pbuf = vim.api.nvim_win_get_buf(pwin)

  ensure_filetype(pbuf, item.path)
  apply_window_opts(pwin)
  resize_preview(list_win, pwin, ratio)
  apply_match_highlight(pwin, pbuf, item)
  center_on_item(pwin, item)

  -- restore focus
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    vim.api.nvim_set_current_win(list_win)
  end
end

function M.close()
  local pwin = find_preview_win_in_tab()
  if pwin then
    clear_our_match(pwin)
  end
  pcall(vim.cmd, "silent! pclose")
end

function M.on_colorscheme()
  ensure_hl()
end

return M
