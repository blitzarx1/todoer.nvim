vim.api.nvim_create_user_command("Todoer", function(opts)
  require("todoer").open(opts.args)
end, { nargs = "?" })
