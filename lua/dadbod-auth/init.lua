local config = require("dadbod-auth.config")
local M = {}

local default_types = {
  mysql = { header = "mysql", suppress_pw = true, pw_env_var = "MYSQL_PWD", },
  mssqlserver = { header = "sqlserver", },
  mssqlserverentra = { header = "sqlserver", suppress_pw = true, params = "authentication=ActiveDirectoryAzCli"},
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
    if not type then return nil end
    local remove_spaces = string.gsub(type, "[^%w_]", "")
    return string.lower(remove_spaces)
end

local function fetch_db_credentials(item_name)
    local ext = config.options.force_exe and '.exe' or ''
    local opcmd = string.format("op%s item get %q --format json", ext, item_name)
	local handle = io.popen(opcmd)
    if not handle then return nil end
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		vim.notify("Failed to retrieve credentials from 1Password:" .. opcmd, vim.log.levels.ERROR)
		return nil
	end

	local ok, credential_data = pcall(vim.fn.json_decode, result)
	if not ok then
		vim.notify("Error decoding 1Password response", vim.log.levels.ERROR)
		return nil
	end

    local credentials = {}

    if credential_data.fields then
        for _, field in ipairs(credential_data.fields) do
            if field.label and field.value then
                credentials[field.label] = field.value
            end
        end
    end

    return credentials
end

local function get_type_data(type_string)
    local nt = normalize_type(type_string)
    local data = config.options.custom_types[nt]
    if data == nil then data = default_types[nt] end
    return data
end

function M.setup_db_connection(item_name)
	local resolved_item_name = resolve_item_name(item_name)
	local creds = fetch_db_credentials(resolved_item_name)
	if not creds then return end
    local type_data = get_type_data(creds.type)
    if type_data == nil then
        vim.notify("No adapter info found for database type: " .. type, vim.log.levels.ERROR)
        return
    end

    local db_string = string.format("%s://", type_data.header)
    local server_prefix = ""
    if not type_data.suppress_user and creds.username then
        db_string = db_string .. creds.username
        server_prefix = '@'
    end
    if creds.password then
        if type_data.pw_env_var then vim.env[type_data.pw_env_var] = creds.password
        elseif not type_data.suppress_pw  then db_string = db_string .. ':' .. url_encode(creds.password) end
    end
    db_string = db_string .. string.format("%s%s/%s", server_prefix, creds.server, creds.database)
    if creds.port then
        db_string = db_string .. string.format(":%s", creds.port)
    end
    if type_data.params then db_string = db_string .. '?' .. type_data.params end
	-- Set the connection for vim-dadbod
	vim.t.db = db_string
	vim.notify("database credentials configured!", vim.log.levels.INFO)
end

return M
