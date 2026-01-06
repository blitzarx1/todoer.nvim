local M = {}

local function parse_todo_header(text)
  -- 1) Tagged case
  local tag, rest = text:match("TODO:%[([^%]]+)%]%s*(.*)")
  if tag then
    return tag, rest or ""
  end

  -- 2) Untagged case
  local rest2 = text:match("TODO:%s*(.*)")
  if rest2 ~= nil then
    return nil, rest2 or ""
  end

  return nil
end

local function detect_line_comment_leader(line)
  return line:match("^%s*(//+)%s?") or
         line:match("^%s*(#+)%s?") or
         line:match("^%s*(%-%-+)%s?")
end

local function strip_line_comment(line, leader)
  if not leader then return line end
  return (line:gsub("^%s*" .. vim.pesc(leader) .. "%s?", ""))
end

local function strip_block_comment_line(line)
  line = line:gsub("^%s*/%*%s?", "")   -- opening /*
  line = line:gsub("^%s*%*%s?", "")    -- leading *
  line = line:gsub("%s*%*/%s*$", "")   -- trailing */
  return line
end

local function is_block_comment_todo(line)
  local todo_at = line:find("TODO:")
  local open_at = line:find("/%*")
  return todo_at and open_at and open_at < todo_at
end

--- Extract tag + multiline description starting at lnum (1-based).
--- Stops at "end of comment":
---   - line comments: first non-matching leader line
---   - block comments: line containing */
function M.extract(lines, lnum)
  local line = lines[lnum]
  if not line then return nil end

  local leader = detect_line_comment_leader(line)
  local block = (not leader) and is_block_comment_todo(line)

  local header_text
  if leader then
    header_text = strip_line_comment(line, leader)
  elseif block then
    header_text = strip_block_comment_line(line)
  else
    -- TODO not in a recognized comment; treat as single-line or ignore.
    header_text = line
  end

  local tag, first = parse_todo_header(header_text)
  if first == nil then return nil end

  local desc_lines = {}
  if first ~= "" then table.insert(desc_lines, vim.trim(first)) end

  if leader then
    local i = lnum + 1
    while i <= #lines do
      local l = lines[i]
      local l2 = detect_line_comment_leader(l)
      if l2 ~= leader then break end

      local content = vim.trim(strip_line_comment(l, leader))
      if content == "" then break end -- optional: blank comment line ends block
      table.insert(desc_lines, content)
      i = i + 1
    end
  elseif block then
    local i = lnum + 1
    while i <= #lines do
      local l = lines[i]
      local content = vim.trim(strip_block_comment_line(l))
      if content ~= "" then table.insert(desc_lines, content) end
      if l:find("%*/") then break end
      i = i + 1
    end
  end

  return {
    tag = tag,
    desc_lines = desc_lines,
    desc = table.concat(desc_lines, "\n"),
  }
end

return M
