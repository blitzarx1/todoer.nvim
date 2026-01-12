local config  = require("todoer.config")
local state   = require("todoer.state")
local util    = require("todoer.util")
local search  = require("todoer.search")
local root    = require("todoer.root")
local preview = require("todoer.preview")
local task    = require("todoer.task")

local M = {}

local function get_selected_item()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local idx = row - (state.header_len or 0)
  return (state._results or {})[idx]
end

local function refresh_preview()
  if not state.preview_enabled then return end
  preview.update(get_selected_item(), {
    enabled = true,
    list_win = state.win,
    ratio = 0.4,
  })
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
  vim.api.nvim_buf_set_name(state.buf, config.opts.buffer_name_list)

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
    preview.close()
    vim.cmd("tabclose")
  end, { buffer = state.buf, silent = true })

  vim.keymap.set("n", "r", function()
    require("todoer").open("")
  end, { buffer = state.buf, silent = true })

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
    if not state.preview_enabled then
      preview.close()
    else
      refresh_preview()
    end
  end, { buffer = state.buf, silent = true })

  vim.keymap.set("n", "tn", function()
    local item = get_selected_item()
    if not item then return end

    -- store selected index (stable across header changes)
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    state.restore_idx = row - (state.header_len or 0)

    task.create_from_item(item, state._results or {})

    -- refresh list (async)
    require("todoer").open("")
  end, { buffer = state.buf, silent = true, desc = "Todoer: create task" })

  vim.keymap.set("n", "to", function()
    local item = get_selected_item()
    if not item then return end
    if not item.task_dir or item.task_dir == "" then
      vim.notify("[Todoer] No task found for this TODO. Create it with `tn` first.", vim.log.levels.WARN)
      return
    end

    local desc = item.task_dir .. "/description.md"
    if vim.fn.filereadable(desc) ~= 1 then
      vim.notify(("[Todoer] Task description not found: %s"):format(desc), vim.log.levels.ERROR)
      return
    end

    -- Open in a new buffer (tab), so the list stays available
    vim.cmd("tabnew " .. vim.fn.fnameescape(desc))
  end, { buffer = state.buf, silent = true, desc = "Todoer: open task description" })

  vim.keymap.set("n", "<CR>", function()
    local item = get_selected_item()
    if not item then return end

    vim.cmd(("tabnew +%d %s"):format(item.lnum, vim.fn.fnameescape(item.path)))
    local col0 = math.max((item.col or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(0, { item.lnum, col0 })
    vim.cmd("normal! zz")
  end, { buffer = state.buf, silent = true })

  local aug = vim.api.nvim_create_augroup("TodoerPanel", { clear = false })
  vim.api.nvim_clear_autocmds({ group = aug, buffer = state.buf })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    buffer = state.buf,
    callback = function()
      if vim.api.nvim_get_current_buf() ~= state.buf then return end
      refresh_preview()
    end,
  })

  -- Best-effort "non-focusable": if user enters the preview window, bounce back
  vim.api.nvim_create_autocmd("WinEnter", {
    group = aug,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local ok, is_preview = pcall(vim.api.nvim_get_option_value, "previewwindow", { win = win })
      if ok and is_preview and state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
      end
    end,
  })

  -- Keep preview highlight link correct when colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = aug,
    callback = function()
      if preview.on_colorscheme then preview.on_colorscheme() end
    end,
  })
  if preview.on_colorscheme then preview.on_colorscheme() end
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
    preview.close()
  else
    vim.list_extend(out_lines, util.format_aligned_results(state._results))
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
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        local header = state.header_len or 0
        local total = vim.api.nvim_buf_line_count(state.buf)
        local has_items = #(state._results or {}) > 0

        -- Always keep cursor off the header if there are list lines
        local min_row = header + 1
        if min_row > total then
          return
        end

        local row = min_row -- default

        -- Only restore selection when we actually have items rendered.
        if has_items and state.restore_idx and state.restore_idx >= 1 then
          row = header + state.restore_idx
        end

        -- Clamp
        if row < min_row then row = min_row end
        if row > total then row = total end

        vim.api.nvim_win_set_cursor(state.win, { row, 0 })

        -- IMPORTANT: only clear restore_idx after applying it on real results
        if has_items then
          state.restore_idx = nil
        end

        refresh_preview()
      end
    end
  end
end

function M.open(_)
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
    render(("%d TODOs found.  (<CR> open, to task, tn create task, j/k move, p preview, r refresh, q close)"):format(#results))
  end)
end

return M
