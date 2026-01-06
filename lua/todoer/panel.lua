local config = require("todoer.config")
local state = require("todoer.state")
local util = require("todoer.util")
local search = require("todoer.search")
local root = require("todoer.root")

local M = {}

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

  vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = state.buf, silent = true })
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
end

local function render(status_line)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

  local header = {
    "Todoer",
    "======",
    ("Pattern: %s"):format(state.pattern),
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
    end
  end
end

function M.open(args)
  ensure_panel_tab()

  local pat = (args and args ~= "") and args or state.pattern
  state.pattern = pat
  state._results = {}

  render(("Searching in %s …"):format(root.project_root()))

  search.search(pat, function(err, results)
    if err then
      state._results = {}
      render(err)
      return
    end
    state._results = results
    render(("%d matches.  (<CR> open, j/k move, r refresh, q close)"):format(#results))
  end)
end

return M
