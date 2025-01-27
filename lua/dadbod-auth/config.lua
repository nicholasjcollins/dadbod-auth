local config = {}

config.options = {
	aliases = {},
    custom_types = {},
}

function config.setup(user_opts)
	config.options = vim.tbl_deep_extend("force", config.options, user_opts or {})

	vim.api.nvim_create_user_command("DBConnect", function(opts)
		require("dadbod-auth").setup_db_connection(opts.args)
	end, {
		nargs = 1, -- requires an argument (the name of the 1Password item)
		desc = "Load connection information for vim dadbod via 1Password",
	})
end

return config
