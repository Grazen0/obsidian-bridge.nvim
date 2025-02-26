local M = {}
local config = require("obsidian-bridge.config")
local curl = require("plenary.curl")
local uri = require("obsidian-bridge.uri")

-- Makes an API call to the local REST plugin
-- @param final_config
-- @param api_key
-- @param request_method valid value for plenary's curl.request method, "GET", "POST", etc
-- @param path
-- @param json_body
local make_api_call = function(final_config, api_key, request_method, path, json_body)
	local url = final_config.obsidian_server_address .. path
	local body = json_body and vim.fn.json_encode(json_body) or nil
	local method = string.lower(request_method) or "post"
	local raw_args = final_config.raw_args

	local result = curl.request({
		url = url,
		method = method,
		body = body,
		raw = raw_args,
		on_error = function()
			-- Ignore other errors for now, for instance if we can't contact obsidian server it's
			-- not running, that's often times probably intentional.
		end,
		headers = {
			content_type = "application/json",
			Authorization = "Bearer " .. api_key,
		},
	})

	if result.body and result.body ~= "" then
		local decoded = vim.fn.json_decode(result.body)
		if decoded and decoded.errorCode == 40101 then
			vim.api.nvim_err_writeln(
				"Error: authentication error, please check your " .. config.api_key_env_var_name .. " value."
			)
		else
			return decoded
		end
	end
end

M.scroll_into_view = function(line, final_config, api_key)
	local json_body = {
		center = true,
		range = {
			from = { ch = 0, line = line },
			to = { ch = 0, line = line },
		},
	}

	local path = uri.EncodeURI("/editor/scroll-into-view")
	return make_api_call(final_config, api_key, "POST", path, json_body)
end

M.execute_command = function(final_config, api_key, request_method, command)
	local path = uri.EncodeURI("/commands/" .. command)
	return make_api_call(final_config, api_key, request_method, path)
end

M.pick_command = function(final_config, api_key)
	local commands = M.execute_command(final_config, api_key, "GET", "")
	if commands == nil or commands.commands == nil then
		vim.notify("Get commands list failed")
		return
	end
	commands = commands.commands
	local command_name_id_map = {}
	local command_names = {}
	for _, command in pairs(commands) do
		command_name_id_map[command.name] = command.id
		table.insert(command_names, command.name)
	end

	if final_config.picker == "telescope" then
		if not pcall(require, "telescope") then
			vim.notify("telescope.nvim is not installed")
			return
		end

		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local telescope_conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		local obsidian_commands = function(opts)
			opts = opts or {}
			pickers
				.new(opts, {
					prompt_title = "Obsidian Commands",
					finder = finders.new_table({
						results = command_names,
					}),
					sorter = telescope_conf.generic_sorter(opts),
					attach_mappings = function(prompt_bufnr, _)
						actions.select_default:replace(function()
							actions.close(prompt_bufnr)
							local selection = action_state.get_selected_entry()
							M.execute_command(final_config, api_key, "POST", command_name_id_map[selection[1]])
						end)
						return true
					end,
				})
				:find()
		end
		obsidian_commands(require("telescope.themes").get_dropdown({}))
	elseif final_config.picker == "fzf-lua" then
		if not pcall(require, "fzf-lua") then
			vim.notify("fzf-lua is not installed")
			return
		end

		local fzf_lua = require("fzf-lua")

		local opts = {}
		opts.prompt = "Obsidian Commands>"
		opts.actions = {
			["default"] = function(selected)
				local cmd_id = command_name_id_map[selected[1]]
				M.execute_command(final_config, api_key, "POST", cmd_id)
			end,
		}

		fzf_lua.fzf_exec(command_names, opts)
	end
end

M.open_in_obsidian = function(filename, final_config, api_key)
	local path = uri.EncodeURI("/open/" .. filename)
	make_api_call(final_config, api_key, "POST", path)
end

return M
