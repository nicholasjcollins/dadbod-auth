# dadbod-auth
## Installation
### Using Lazy

```lua
use {
  'nicholasjcollins/dadbod-auth',
  config = function()
    require('dadbod-auth').setup({
      -- user options
      aliases = {
        mydb = "Name of item in vault",
        -- this isn't required but otherwise requires you to provide the whole vault item name
      },
    })
  end
}
```

## Example Usage
### Authenticating to a particular server
`:DBA alias`
### Swapping target database
`:DBS database-name` or just `:DBS` to open a picker (requires Telescope)


## Configuration
### In 1Password
You need to have the 1Password CLI configured and installed for this to work.
All items in your vault that you wish to use as database connections will use the following field names:
- username (required)
- password (typically required)
- server (required)
- database (typically required)
- type: The type of server you're connecting to. This field drives the bulk of the logic for this plugin. You can set your own rules, or override the defaults, by defining custom types in the config (see below) 

### Configuration in Neovim
```lua
  'nicholasjcollins/dadbod-auth',
  config = function()
    require('dadbod-auth').setup({
      -- user options
      aliases = {
        mydb = "Name of item in vault",
        prod = "Another 1Password vault name"
      },
      custom_types = {
        type_name_in_1p = { -- this is normalized to lower case with all non alphanumeric and _ chars removed
            suppress_usr = true',
            pw_env_var = 'ENV_VAR_NAME', -- if you want to use an Envoronment Variable instead of injecting the pw into the connection string and your db supports it (default for MySQL) this automatically suppresses pw
            suppress_pw = true, -- if you don't need it included in you custom connection
            -- Default Types can also be overridden by including them as custom types if your connection needs don't work with the default
        },
      }
    })
  end
}
```

