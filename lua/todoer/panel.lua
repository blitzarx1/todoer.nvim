local config = require("todoer.config")
local state = require("todoer.state")
local util = require("todoer.util")
local search = require("todoer.search")
local root = require("todoer.root")

local M = {}

local function get_selected_item()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local idx = row - (state.header_len or 0)
  return (state._results or {})[idx]
end

local function find_preview_win_in_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ok, is_preview = pcall(vim.api.nvim_get_option_value, "previewwindow", { win = win })
    if ok and is_preview then
      return win
    end
  end
  return nil
end

local function ensure_preview_for_item(item)
  if not state.preview_enabled then
    return
  end

  if not item then
    pcall(vim.cmd, "silent! pclose")
    state.preview_win = nil
    state.preview_buf = nil
    return
  end

  local list_win = vim.api.nvim_get_current_win()

  -- Open/update preview window on the RIGHT without changing focus
  local old_splitright = vim.o.splitright
  vim.o.splitright = true
  vim.cmd(("silent! rightbelow vert pedit +%d %s"):format(item.lnum, vim.fn.fnameescape(item.path)))
  vim.o.splitright = old_splitright

  local pwin = find_preview_win_in_tab()
  if not pwin then
    vim.api.nvim_set_current_win(list_win)
    return
  end

  local pbuf = vim.api.nvim_win_get_buf(pwin)
  state.preview_win = pwin
  state.preview_buf = pbuf

  -- Ensure filetype/highlighting in preview
  local ft = vim.filetype.match({ filename = item.path })
  if ft and ft ~= "" then
    vim.bo[pbuf].filetype = ft
  end
  vim.api.nvim_buf_call(pbuf, function()
    vim.cmd("filetype detect")
  end)

  -- Window-local cosmetics
  vim.api.nvim_set_option_value("wrap", false, { win = pwin })
  vim.api.nvim_set_option_value("number", false, { win = pwin })
  vim.api.nvim_set_option_value("relativenumber", false, { win = pwin })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = pwin })
  vim.api.nvim_set_option_value("cursorline", false, { win = pwin })

  -- Resize preview to ~40% of the combined (list + preview) width (stable)
  local list_w = vim.api.nvim_win_get_width(list_win)
  local prev_w = vim.api.nvim_win_get_width(pwin)
  local total_w = list_w + prev_w
  local target = math.max(20, math.floor(total_w * 0.4))
  if math.abs(prev_w - target) > 1 then
    pcall(vim.api.nvim_win_set_width, pwin, target)
  end
  vim.api.nvim_set_option_value("winfixwidth", true, { win = pwin })

  -- Define highlight group (safe to call multiple times)
  if vim.fn.hlexists("CurSearch") == 1 then
    vim.api.nvim_set_hl(0, "TodoerPreviewMatch", { link = "CurSearch" })
  else
    vim.api.nvim_set_hl(0, "TodoerPreviewMatch", { link = "Search" })
  end

  pcall(vim.api.nvim_win_call, pwin, function()
    -- clear only this window's matches we added by clearing all matches in preview window
    vim.fn.clearmatches()

    local lnum0 = item.lnum - 1
    local line = vim.api.nvim_buf_get_lines(pbuf, lnum0, lnum0 + 1, false)[1] or ""

    -- find TODO: with optional [TAG]
    local s, e = line:find("TODO:%b[]")
    if not s then
      s, e = line:find("TODO:")
    end
    if not s then
      return
    end

    -- matchaddpos uses (line, col, len) with 1-based col
    local col1 = s
    local len = e - s + 1
    vim.fn.matchaddpos("TodoerPreviewMatch", { { item.lnum, col1, len } })
  end)

  -- Put cursor on match column and center in preview (zz)
  local col0 = math.max((item.col or 1) - 1, 0)
  pcall(vim.api.nvim_win_set_cursor, pwin, { item.lnum, col0 })
  pcall(vim.api.nvim_win_call, pwin, function()
    vim.cmd("normal! zz")
  end)

  -- Always restore focus to list
  vim.api.nvim_set_current_win(list_win)
end

local function ensure_panel_tab()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == state.buf then
        vim.api.nvim_set_current_win(win)
        state.win = win
        return
      end
    end
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.buf, config.opts.buffer_name)

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
  vim.api.nvim_set_option_value("filetype", "todoer", { buf = state.buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = state.buf })

  vim.cmd(config.opts.open_cmd)
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_set_option_value("wrap", false, { win = state.win })

  vim.keymap.set("n", "q", function()
    pcall(vim.cmd, "silent! pclose")
    vim.cmd("tabclose")
  end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "r", function() require("todoer").open("") end, { buffer = state.buf, silent = true })

  local function move_sel(delta)
    local header = state.header_len or 0
    local total = vim.api.nvim_buf_line_count(state.buf)
    if total <= header then return end

    local min_row = header + 1
    local max_row = total
    local row = vim.api.nvim_win_get_cursor(0)[1]

    if row < min_row then row = min_row end
    if row > max_row then row = max_row end

    local new_row = row + delta
    if new_row < min_row then new_row = min_row end
    if new_row > max_row then new_row = max_row end

    vim.api.nvim_win_set_cursor(0, { new_row, 0 })
  end

  vim.keymap.set("n", "j", function() move_sel(1) end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "<C-n>", function() move_sel(1) end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "k", function() move_sel(-1) end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "<C-p>", function() move_sel(-1) end, { buffer = state.buf, silent = true })

  vim.keymap.set("n", "p", function()
    state.preview_enabled = not state.preview_enabled

    -- Toggle preview
    if not state.preview_enabled then
      -- Disable preview: close it
      pcall(vim.cmd, "silent! pclose")
      state.preview_win = nil
      state.preview_buf = nil
      vim.notify("Todoer preview disabled", vim.log.levels.INFO)
    else
      -- Enable preview: show immediately for current item
      vim.notify("Todoer preview enabled", vim.log.levels.INFO)
      ensure_preview_for_item(get_selected_item())
    end
  end, { buffer = state.buf, silent = true })

  -- Navigate to location of selected item
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local idx = row - (state.header_len or 0)
    local item = (state._results or {})[idx]
    if not item then return end

    vim.cmd(("tabnew +%d %s"):format(item.lnum, vim.fn.fnameescape(item.path)))
    local col0 = math.max((item.col or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(0, { item.lnum, col0 })
    vim.cmd("normal! zz")
  end, { buffer = state.buf, silent = true })

  -- Auto-refresh preview when moving in list
  local aug = vim.api.nvim_create_augroup("TodoerPreview", { clear = false })
  vim.api.nvim_clear_autocmds({ group = aug, buffer = state.buf })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    buffer = state.buf,
    callback = function()
      -- only update when list window is current
      if vim.api.nvim_get_current_buf() ~= state.buf then return end

      if state.preview_enabled then
        ensure_preview_for_item(get_selected_item())
      end
    end,
  })

  -- If someone enters the preview window, jump back to list (best-effort "non-focusable")
  vim.api.nvim_create_autocmd("WinEnter", {
    group = aug,
    callback = function()
      if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
        if vim.api.nvim_get_current_win() == state.preview_win and state.win and vim.api.nvim_win_is_valid(state.win) then
          vim.api.nvim_set_current_win(state.win)
        end
      end
    end,
  })
end

local function render(status_line)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

  local header = {
    "Todoer",
    "======",
    status_line or "",
    "",
  }
  state.header_len = #header

  local out_lines = vim.list_extend({}, header)
  if #(state._results or {}) == 0 then
    table.insert(out_lines, "No matches.")
  else
    vim.list_extend(out_lines, util.format_aligned_results(state._results))
  end

  if #(state._results or {}) == 0 then
    ensure_preview_for_item(nil)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, out_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = state.buf })

  vim.api.nvim_set_hl(0, "TodoerLink", { underline = true })
  pcall(function()
    vim.api.nvim_buf_call(state.buf, function()
      vim.fn.clearmatches()
      vim.fn.matchadd("TodoerLink", [[\v^\S+:\d+:\d+]])
    end)
  end)

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local first_item_row = state.header_len + 1
    if first_item_row <= vim.api.nvim_buf_line_count(state.buf) then
      vim.api.nvim_win_set_cursor(state.win, { first_item_row, 0 })
      ensure_preview_for_item(get_selected_item())
    end
  end
end

function M.open(args)
  ensure_panel_tab()

  state._results = {}

  render(("Searching in %s …"):format(root.project_root()))

  search.search(function(err, results)
    if err then
      state._results = {}
      render(err)
      return
    end
    state._results = results
    render(("%d TODOs found.  (<CR> open, j/k move, p preview, r refresh, q close)"):format(#results))
  end)
end

return M
