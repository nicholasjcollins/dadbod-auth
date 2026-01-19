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

local function has_telescope()
    return pcall(require, 'telescope')
end

local function url_encode(str)
    return str:gsub("[^%w%-._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
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
    local c = {}
    if credential_data.fields then
        for _, field in ipairs(credential_data.fields) do
            if field.label and field.value then
                c[field.label] = field.value
            end
        end
    end
    return c

end

local function get_type_data(type_string)
    local nt = normalize_type(type_string)
    local data = config.options.custom_types[nt]
    if data == nil then data = default_types[nt] end
    return data
end

local function build_connection_string()
    if not vim.t.database_credentials then return end
    local creds = vim.t.database_credentials
    local type_data = get_type_data(creds.type)
    if type_data == nil then
        vim.notify("No adapter info found for database type: " .. creds.type, vim.log.levels.ERROR)
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
    db_string = db_string .. string.format("%s%s", server_prefix, creds.server)
    if creds.port then
        db_string = db_string .. string.format(":%s", creds.port)
    end
    db_string = db_string .. string.format("/%s", creds.database)
    if type_data.params then db_string = db_string .. '?' .. type_data.params end
	-- Set the connection for vim-dadbod
	vim.t.db = db_string
	vim.notify("database credentials configured!", vim.log.levels.INFO)
end

local function change_target_db(new_db)
    if not vim.t.database_credentials or not new_db then return end
    vim.t.database_credentials.database = new_db
end


local function get_database_list()
    if not vim.t.database_credentials then
        vim.notify("No active database connection", vim.log.levels.WARN)
        return nil
    end
    
    local creds = vim.t.database_credentials
    local type_data = get_type_data(creds.type)
    if not type_data then return nil end
    
    local queries = {
        sqlserver = "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name",
        mysql = "SHOW DATABASES",
        postgresql = "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
    }
    
    local query = queries[type_data.header]
    if not query then
        vim.notify("Database listing not supported for type: " .. creds.type, vim.log.levels.WARN)
        return nil
    end
    
    -- Build command based on database type
    local cmd
    if type_data.header == "sqlserver" then
        cmd = string.format('sqlcmd -S %s -U %s -P "%s" -d %s -h -1 -W -Q "%s"',
            creds.server, creds.username or "", creds.password or "", creds.database, query)
    elseif type_data.header == "mysql" then
        -- Set MYSQL_PWD environment variable for mysql
        vim.env.MYSQL_PWD = creds.password
        cmd = string.format('mysql -h %s -u %s -sN -e "%s"',
            creds.server, creds.username, query)
    elseif type_data.header == "postgresql" then
        cmd = string.format('PGPASSWORD="%s" psql -h %s -U %s -d %s -t -A -c "%s"',
            creds.password, creds.server, creds.username, creds.database, query)
    end
    
    if not cmd then return nil end
    
    local handle = io.popen(cmd)
    if not handle then
        vim.notify("Failed to execute database query", vim.log.levels.ERROR)
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if not result or result == "" then
        vim.notify("No databases found", vim.log.levels.WARN)
        return nil
    end
    
    -- Parse results
    local databases = {}
    for line in result:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(databases, trimmed)
        end
    end
    
    return databases
end

function M.swap_db(db_name)
    if db_name and db_name ~= "" then
        change_target_db(db_name)
        vim.notify("Switched to database: " .. db_name, vim.log.levels.INFO)
        return
    end
    if not has_telescope() then
        vim.notify("Telescope is required for database picker. Provide database name directly: :DBHop <database>", vim.log.levels.ERROR)
        return
    end
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local databases = get_database_list()
    if not databases or #databases == 0 then
        vim.notify("No databases found", vim.log.levels.WARN)
        return
    end
    pickers.new({}, {
        prompt_title = 'Switch Database',
        finder = finders.new_table({
            results = databases,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    change_target_db(selection[1])
                    vim.notify("Switched to database: " .. selection[1], vim.log.levels.INFO)
                end
            end)
            return true
        end,
    }):find()
end

function M.setup_db_connection(item_name)
    local vault_item_name = config.options.aliases[item_name] or item_name
    vim.t.database_credentials = fetch_db_credentials(vault_item_name)
    build_connection_string()
end

return M
