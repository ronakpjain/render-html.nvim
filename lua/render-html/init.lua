local config_mod = require("render-html.config")
local render = require("render-html.render")

local M = {}

---@class render-html.State
local state = {
	---@type render-html.Config
	config = nil,
	---@type table<integer, boolean>
	buffers = {},
	---@type table<integer, table<integer, integer>>
	levels = {},
	---@type table<integer, table<integer, { summary: string, lines: integer }>>
	folds = {},
	---@type table<integer, table<string, any>>
	windows = {},
	---@type table<integer, uv_timer_t>
	timers = {},
	enabled = true,
}

---@param buf integer
---@param fn fun()
local function debounce(buf, fn)
	local timer = state.timers[buf]
	if not timer then
		timer = vim.uv.new_timer()
		if not timer then
			return fn()
		end
		state.timers[buf] = timer
	end
	timer:stop()
	timer:start(
		state.config.debounce,
		0,
		vim.schedule_wrap(function()
			if vim.api.nvim_buf_is_valid(buf) and state.buffers[buf] then
				fn()
			end
		end)
	)
end

---@param buf integer
---@return boolean
function M.enabled(buf)
	if buf then
		return state.enabled and state.buffers[buf] == true
	end
	return state.enabled
end

---@param buf integer
---@return boolean
local function wants_folds(buf)
	if not state.config.details.fold then
		return false
	end
	local levels = state.levels[buf]
	return levels ~= nil and next(levels) ~= nil
end

local apply_window

---@param buf integer
function M.render(buf)
	if not state.config or not state.buffers[buf] then
		return
	end
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local details = render.render(buf, state.config)

	local levels = {}
	local folds = {}
	if state.config.details.fold then
		for _, info in ipairs(details) do
			for row = info.start_row, info.end_row do
				levels[row] = (levels[row] or 0) + 1
			end
			folds[info.start_row + 1] = {
				summary = info.summary,
				lines = info.end_row - info.start_row + 1,
			}
		end
	end

	state.levels[buf] = levels
	state.folds[buf] = folds

	-- Fold behavior is derived from the levels table, so update windows that
	-- changed between "has details" and "has no details".
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		apply_window(win, buf)
	end
end

---@param buf integer
function M.refresh(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	M.render(buf)
end

---@param win integer
---@return table<string, any>
local function save_window(win)
	return {
		conceallevel = vim.wo[win].conceallevel,
		concealcursor = vim.wo[win].concealcursor,
		foldmethod = vim.wo[win].foldmethod,
		foldexpr = vim.wo[win].foldexpr,
		foldtext = vim.wo[win].foldtext,
		foldenable = vim.wo[win].foldenable,
		foldlevel = vim.wo[win].foldlevel,
	}
end

---@param win integer
local function restore_folds(win)
	local saved = state.windows[win]
	if not saved then
		return
	end
	for _, name in ipairs({ "foldmethod", "foldexpr", "foldtext", "foldenable", "foldlevel" }) do
		pcall(function()
			vim.wo[win][name] = saved[name]
		end)
	end
	saved.folds = false
end

---@param win integer
local function restore_window(win)
	local saved = state.windows[win]
	if not saved then
		return
	end
	state.windows[win] = nil
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	for name, value in pairs(saved) do
		if type(value) ~= "table" then
			pcall(function()
				vim.wo[win][name] = value
			end)
		end
	end
end

---@param win integer
---@param buf integer
function apply_window(win, buf)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local saved = state.windows[win]
	local folds = wants_folds(buf)
	if not saved then
		saved = save_window(win)
		saved.buf = buf
		saved.folds = false
		state.windows[win] = saved
	end

	if vim.wo[win].conceallevel ~= 3 then
		vim.wo[win].conceallevel = 3
		vim.wo[win].concealcursor = ""
	end

	if saved.buf == buf and saved.folds == folds then
		return
	end
	saved.buf = buf
	if folds then
		vim.wo[win].foldmethod = "expr"
		vim.wo[win].foldexpr = "v:lua.require'render-html'.fold_level()"
		vim.wo[win].foldtext = "v:lua.require'render-html'.fold_text()"
		vim.wo[win].foldenable = true
		vim.wo[win].foldlevel = 0
		saved.folds = true
	else
		restore_folds(win)
	end
end

---@param buf integer
local function apply_windows(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		apply_window(win, buf)
	end
end

---@param buf integer
local function remove_windows(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		restore_window(win)
	end
end

---@param buf integer
local function set_keymap(buf)
	local lhs = state.config.keymap
	if not lhs then
		return
	end
	vim.keymap.set("n", lhs, function()
		local levels = state.levels[buf]
		local row = vim.api.nvim_win_get_cursor(0)[1] - 1
		if levels and (levels[row] or 0) > 0 then
			vim.cmd("normal! za")
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "n", false)
		end
	end, { buffer = buf, desc = "render-html: toggle details block" })
end

---@param buf integer
function M.attach(buf)
	if not state.enabled or not state.config then
		return
	end
	if state.buffers[buf] then
		return
	end
	state.buffers[buf] = true
	if state.config.keymap then
		set_keymap(buf)
	end
	apply_windows(buf)
	M.render(buf)
end

---@param buf integer
function M.detach(buf)
	if not state.buffers[buf] then
		return
	end
	state.buffers[buf] = nil
	state.levels[buf] = nil
	state.folds[buf] = nil
	remove_windows(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, render.ns, 0, -1)
	end
	local timer = state.timers[buf]
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		state.timers[buf] = nil
	end
end

---@param buf? integer
function M.enable(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	state.enabled = true
	M.attach(buf)
end

---@param buf? integer
function M.disable(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	M.detach(buf)
end

---@param buf? integer
function M.toggle(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if state.buffers[buf] then
		M.detach(buf)
	else
		M.attach(buf)
	end
end

---@return integer
function M.fold_level()
	return M.fold_level_for(vim.api.nvim_get_current_buf(), vim.v.lnum - 1)
end

---@param buf integer
---@param row integer 0-based row
---@return integer
function M.fold_level_for(buf, row)
	local levels = state.levels[buf]
	if not levels then
		return 0
	end
	return levels[row] or 0
end

---@return string
function M.fold_text()
	return M.fold_text_for(vim.api.nvim_get_current_buf(), vim.v.foldstart)
end

---@param buf integer
---@param start_row integer 1-based row
---@return string
function M.fold_text_for(buf, start_row)
	local folds = state.folds[buf]
	local info = folds and folds[start_row]
	if not info then
		return vim.api.nvim_eval("foldtext()")
	end
	return state.config.fold.format(info)
end

---@param opts? table
function M.setup(opts)
	state.config = config_mod.resolve(opts)
	if not (opts and opts.highlights == false) then
		config_mod.setup_highlights()
	end

	local group = vim.api.nvim_create_augroup("RenderHtml", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(args)
			if state.config.file_types[vim.bo[args.buf].filetype] then
				M.attach(args.buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
		group = group,
		callback = function(args)
			if state.buffers[args.buf] then
				debounce(args.buf, function()
					M.render(args.buf)
				end)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(args)
			if state.buffers[args.buf] then
				apply_windows(args.buf)
				M.render(args.buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = group,
		callback = function(args)
			remove_windows(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = group,
		callback = function(args)
			M.detach(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local win = tonumber(args.match)
			if win then
				state.windows[win] = nil
			end
		end,
	})

	vim.api.nvim_create_user_command("RenderHtml", function(args)
		local action = args.fargs[1] or "toggle"
		local buf = vim.api.nvim_get_current_buf()
		if action == "enable" then
			M.enable(buf)
		elseif action == "disable" then
			M.disable(buf)
		elseif action == "toggle" then
			M.toggle(buf)
		elseif action == "refresh" then
			M.refresh(buf)
		else
			vim.notify("RenderHtml: expected enable|disable|toggle|refresh", vim.log.levels.ERROR)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "enable", "disable", "toggle", "refresh" }
		end,
		desc = "Toggle render-html in the current buffer",
	})

	-- Attach to already-open buffers matching the configured filetypes.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and state.config.file_types[vim.bo[buf].filetype] then
			M.attach(buf)
		end
	end
end

return M
