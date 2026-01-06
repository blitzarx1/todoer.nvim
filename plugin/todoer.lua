local state = {
  buf = nil,
  win = nil,
  pattern = "TODO",
  _results = {},
  header_len = 0, -- number of non-selectable header/info lines
}

local function project_root()
  return vim.fs.root(0, { ".git", "go.mod", "package.json" }) or vim.loop.cwd()
end

local function ensure_rg()
  if vim.fn.executable("rg") ~= 1 then
    vim.notify(
      "[Todoer] ripgrep (rg) not found. Install it (e.g. `brew install ripgrep`).",
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

local function parse_rg_vimgrep(stdout, cwd)
  local results = {}
  for line in stdout:gmatch("[^\r\n]+") do
    -- rg --vimgrep format: file:line:col:match
    local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
    if file and lnum and col then
      local abs = file
      if not vim.startswith(abs, "/") then
        abs = cwd .. "/" .. file
      end

      table.insert(results, {
        path         = vim.fn.fnamemodify(abs, ":p"), -- absolute for opening
        display_path = file,                          -- relative for display
        lnum         = tonumber(lnum),
        col          = tonumber(col),
        text         = vim.trim(text or ""),
      })
    end
  end
  return results
end

local function ensure_panel_tab()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    -- If it's already visible somewhere, jump to it
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == state.buf then
        vim.api.nvim_set_current_win(win)
        state.win = win
        return
      end
    end
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state.buf, "Todoer")

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
  vim.api.nvim_set_option_value("filetype", "todoer", { buf = state.buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = state.buf })
  vim.api.nvim_set_option_value("wrap", false, { win = state.win })

  vim.cmd("tabnew")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)

  -- Close / refresh
  vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = state.buf, silent = true })
  vim.keymap.set("n", "r", function() vim.cmd("Todoer") end, { buffer = state.buf, silent = true })

  -- Movement that skips header (only moves within selectable list)
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

  -- Open selected item in a NEW tab (stable) and jump to line
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local header = state.header_len or 0
    local idx = row - header
    local item = (state._results or {})[idx]
    if not item then return end

    -- Open in new tab at line
    vim.cmd(("tabnew +%d %s"):format(item.lnum, vim.fn.fnameescape(item.path)))

    -- Jump to the match column (rg reports 1-based columns)
    local col0 = math.max((item.col or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(0, { item.lnum, col0 })

    -- Center the line
    vim.cmd("normal! zz")
  end, { buffer = state.buf, silent = true })
end

local function format_aligned_results(results)
  local lines = {}
  if not results or #results == 0 then
    return lines
  end

  -- Build location strings and compute max display width
  local locs = {}
  local maxw = 0

  for i, it in ipairs(results) do
    local loc = ("%s:%d:%d"):format(it.display_path or it.path, it.lnum, it.col)
    locs[i] = loc

    local w = vim.fn.strdisplaywidth(loc)
    if w > maxw then
      maxw = w
    end
  end

  -- Build aligned output lines
  for i, it in ipairs(results) do
    local loc = locs[i]
    local pad = maxw - vim.fn.strdisplaywidth(loc)
    lines[i] = loc .. string.rep(" ", pad) .. "  " .. (it.text or "")
  end

  return lines
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

  local results = state._results or {}
  local out_lines = vim.list_extend({}, header)

  if #results == 0 then
    table.insert(out_lines, "No matches.")
  else
    local formatted = format_aligned_results(results)
    vim.list_extend(out_lines, formatted)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, out_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = state.buf })

  -- Highlight “path:line:col”
  vim.api.nvim_set_hl(0, "TodoerLink", { underline = true })
  vim.api.nvim_buf_call(state.buf, function()
    vim.fn.clearmatches()
    vim.fn.matchadd("TodoerLink", [[\v^\S+:\d+:\d+]])
  end)

  -- Initial cursor position: first selectable row
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local total = vim.api.nvim_buf_line_count(state.buf)
    local first_item_row = state.header_len + 1
    if first_item_row <= total then
      vim.api.nvim_win_set_cursor(state.win, { first_item_row, 0 })
    end
  end
end

local function run_search(pattern)
  local cwd = project_root()
  state.pattern = pattern
  state._results = {}

  render(("Searching in %s …"):format(cwd))

  local cmd = {
    "rg",
    "--vimgrep",
    "--no-heading",
    "--smart-case",
    "--hidden",
    "--glob", "!.git/",
    pattern,
  }

  vim.system(cmd, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      -- rg exit codes: 0 matches, 1 no matches, 2+ error
      if res.code ~= 0 and res.code ~= 1 then
        state._results = {}
        render(("rg error (exit %d): %s"):format(
          res.code,
          (res.stderr or ""):gsub("%s+$", "")
        ))
        return
      end

      state._results = parse_rg_vimgrep(res.stdout or "", cwd)
      render(("%d matches.  (<CR> open, j/k move, r refresh, q close)"):format(#state._results))
    end)
  end)
end

vim.api.nvim_create_user_command("Todoer", function(opts)
  if not ensure_rg() then return end
  ensure_panel_tab()

  local pat = (opts.args ~= "" and opts.args) or state.pattern
  run_search(pat)
end, { nargs = "?" })
