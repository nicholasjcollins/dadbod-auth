local config = require("dadbod-auth.config")
local M = {}

local default_types = {
  mysql = { header = "mysql", suppress_pw = true, pw_env_var = "MYSQL_PWD", },
  mssqlserver = { header = "sqlserver", },
  mssqlserverentra = { header = "sqlserver", params = "authentication=ActiveDirectoryAzCli'"},
  oracle = { header = "oracle", },
  postgresql = { header = "postgresql" },
}

config.options = config.options or {}
config.options.aliases = config.options.aliases or {}
config.options.custom_types = config.options.custom_types or {}

local function url_encode(str)
    return str:gsub("[^%w%-._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function resolve_item_name(alias_or_item)
	return config.options.aliases[alias_or_item] or alias_or_item
end

local function normalize_type(type)
    local remove_spaces = string.gsub(type, "[^%w_]", "")
    return string.lower(remove_spaces)
end

local function fetch_db_credentials(item_name)
    local ext = config.options.force_exe and '.exe' or ''
	local opcmd = string.format('op%s item get "', ext)
		.. item_name
		.. '" --fields label=type,label=username,label=password,label=dbname,label=server --format json'
	local handle = io.popen(opcmd)
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		vim.notify("Failed to retrieve credentials from 1Password:" .. opcmd, vim.log.levels.ERROR)
		return nil
	end

	-- Parse the JSON response to extract username, password, and host
	local ok, credential_data = pcall(vim.fn.json_decode, result)
	if not ok then
		vim.notify("Error decoding 1Password response", vim.log.levels.ERROR)
		return nil
	end

	local type = credential_data[1].value
	local username = credential_data[2].value
	local password = credential_data[3].value
	local dbname = credential_data[4].value
	local host = credential_data[5].value

    -- Check if database type is valid
    local nt = normalize_type(type)
    local type_data = config.options.custom_types[nt]
    if type_data == nil then type_data = default_types[nt] end
    if type_data == nil then
        vim.notify("No adapter info found for database type:" .. type, vim.log.levels.ERROR)
        return nil
    end

	return {
		type = type_data,
		username = username,
		password = password,
		dbname = dbname,
		host = host,
	}
end

function M.setup_db_connection(item_name)
	local resolved_item_name = resolve_item_name(item_name)
	local creds = fetch_db_credentials(resolved_item_name)
	if not creds then
		return
	end
    local db_string = string.format("%s://", creds.type.header)
    local server_prefix = ""
    if not creds.type.suppress_user then
        db_string = db_string .. creds.username
        server_prefix = '@'
    end
    if creds.type.pw_env_var then vim.env[creds.type.pw_env_var] = creds.password
    elseif not creds.type.suppress_pw  then db_string = db_string .. ':' .. url_encode(creds.password) end
    db_string = db_string .. string.format("%s%s/%s", server_prefix, creds.host, creds.dbname)
    if creds.type.params then db_string = db_string .. '?' .. creds.type.params end
	-- Set the connection for vim-dadbod
	vim.t.db = db_string
	vim.notify("database credentials configured!", vim.log.levels.INFO)
end

return M
