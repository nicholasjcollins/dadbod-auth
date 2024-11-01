local config = {}

config.options = {
	aliases = {},
}

function config.setup(user_opts)
	config.options = vim.tbl_deep_extend("force", config.options, user_opts or {})
end

return config
