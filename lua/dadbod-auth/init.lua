local config = require("dadbod-auth.config")
local M = {}

local function fetch_db_credentials(item_name)
	-- Replace `item_name` with the name of your database credentials stored in 1Password
	local handle = io.popen(
		"op item get '"
			.. item_name
			.. "'--fields label=servertype,label=username,label=password,label=dbname,label=host --format json"
	)
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		vim.notify("Failed to retrieve credentials from 1Password", vim.log.levels.ERROR)
		return nil
	end

	-- Parse the JSON response to extract username, password, and host
	local ok, credential_data = pcall(vim.fn.json_decode, result)
	if not ok then
		vim.notify("Error decoding 1Password response", vim.log.levels.ERROR)
		return nil
	end

	local type = credential_data.fields[1].value
	local username = credential_data.fields[2].value
	local password = credential_data.fields[3].value
	local dbname = credential_data.fields[4].value
	local host = credential_data.fields[5].value

	return {
		type = type,
		username = username,
		password = password,
		dbname = dbname,
		host = host,
	}
end

-- Function to set up the database connection with vim-dadbod.
function M.setup_db_connection(item_name)
	local creds = fetch_db_credentials(item_name)
	if not creds then
		return
	end

	-- Create a vim-dadbod connection string
	local db_string =
		string.format("%s://%s:%s@%s/%s", creds.type, creds.username, creds.password, creds.host, creds.dbname)

	-- Set the connection for vim-dadbod
	vim.g.db = db_string
	vim.notify("Connected to the database with vim-dadbod!", vim.log.levels.INFO)
end

-- You can create a Neovim command to trigger the connection setup
vim.api.nvim_create_user_command("DBConnect", function(opts)
	M.setup_db_connection(opts.args)
end, {
	nargs = 1, -- requires an argument (the name of the 1Password item)
	desc = "Connect to a database using vim-dadbod and 1Password",
})

return M
