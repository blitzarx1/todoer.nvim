# todoer.nvim

Minimalistic code-first todo and task tracker Neovim plugin

## Configuration

```lua
return {
  { 
    'blitzarx1/todoer.nvim',
    keys = {
      { "<leader>tt", "<cmd>Todoer<cr>", desc = "Todoer list" },
    },
    config = function()
      require("todoer").setup({
        keymaps = false, -- don't create plugin-defined keymaps
      })
    end,
  }
}
```

## Dependencies

* Neovim >= 0.10
* ripgrep (rg) installed and available in PATH.

## Development

### Todoer MVP

- [ ] Command for Neovim to list all TODOs in the current project.
    - [x] Jump to the location of a TODO directly from the list.
    - [ ] Create a task from TODO. And move it accross different statuses.

- [ ] Create a task without a TODO location in code.

- [ ] Everything is rendered in readonly custom buffer with rendered links to files and commands to interact with tasks and navigate projects TODOs.
    - [x] Read only buffer with TODOs list and possibility to jump to code locations.
    - [ ] Possibility to create task from the buffer directly.

- [ ] Keymaps

    - Anywhere (user configurable):
        - [x] `<leader>tt` - open TODOs list.
        - [ ] `<leader>tn` - create a new task from selected TODO text or manually.

    - In `Todoer` buffer (buffer local and predefined):
        - [x] `<CR>` - jump to the TODO location in code. 
        - [x] `q`    - close the TODOs list buffer.
        - [x] `r`    - refresh the TODOs list. 
        - [x] `p`    - show/hide preview (default: show)
        - [x] `tn`   - create a new task.

- [ ] Configuration
    - [x] Keymaps configuration (enable/disable default keymaps).
    - [ ] Exclude paths

### Task

- Metadata with:
    - Status (OPEN, IN_PROGRESS, DONE) (required)
    - Priority (LOW, MEDIUM, HIGH) (required; default: MEDIUM)
    - Created datetime (required)
    - Updated datetime (required) 
    - Location entries containing file path and line number of the TODO in code. (optional)
- Description with:
    - Title is a tag from `TODO:[tag]` mark in code. If no tag provided title is the date of task creation.
    - Text from `TODO:[tag] [multiline text]` mark in code.

- [ ] Stateful tasks
    - [ ] Mark already created tasks in the TODOs list with their status and priority.
    - [ ] Do nothing if TODO is already converted to task and user tries to create a task from it again.
    - [ ] Track task progress based on the TODOs list changes. Updating task description filling ticks where user removed TODO lines from code.
