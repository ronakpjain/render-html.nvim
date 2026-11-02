local render_html = require("render-html")

local M = {}

---@param buf integer
---@param ft string
---@return vim.treesitter.LanguageTree?
local function parser_for(buf, ft)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, ft, { error = false })
	if ok and parser then
		return parser
	end
	return nil
end

---@return integer
local function scratch_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<details>", "<summary><b>x</b></summary>", "", "</details>" })
	return buf
end

function M.check()
	vim.health.start("render-html.nvim")

	local config = render_html.config()
	local filetypes = {}
	for ft in pairs(config.file_types) do
		filetypes[#filetypes + 1] = ft
	end
	table.sort(filetypes)

	-- Parser availability for the configured filetypes.
	local buf = scratch_buffer()
	vim.bo[buf].filetype = "markdown"

	if pcall(vim.treesitter.language.add, "html") then
		vim.health.ok("tree-sitter html parser is available")
	else
		vim.health.error("tree-sitter html parser is missing", { "Run :TSInstall html" })
	end

	-- markdown -> html injection: without it no html tree is ever produced.
	local injected = false
	local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown", { error = false })
	if ok and parser then
		pcall(parser.parse, parser, true)
		parser:for_each_tree(function(_, language_tree)
			if language_tree:lang() == "html" then
				injected = true
			end
		end)
	end
	if injected then
		vim.health.ok("markdown buffers inject an html tree")
	else
		vim.health.error("markdown buffers do not inject an html tree", {
			"The markdown injections query must map html_block to the html language.",
			"Run :TSInstall markdown html, then check that the html parser is installed.",
		})
	end
	pcall(vim.api.nvim_buf_delete, buf, { force = true })

	if not injected then
		return
	end

	local function check_ft(ft)
		if not config.file_types[ft] then
			return
		end
		local b = scratch_buffer()
		vim.bo[b].filetype = ft
		if parser_for(b, ft) then
			vim.health.ok(("%s buffers have a %s parser"):format(ft, ft))
		elseif parser_for(b, "markdown") then
			vim.health.ok(("%s buffers have no dedicated parser, using markdown"):format(ft))
		else
			vim.health.error(("%s buffers have no parser"):format(ft), { "Run :TSInstall markdown" })
		end
		pcall(vim.api.nvim_buf_delete, b, { force = true })
	end

	for _, ft in ipairs(filetypes) do
		check_ft(ft)
	end

	vim.health.info("Configured filetypes: " .. table.concat(filetypes, ", "))
	vim.health.info("Details folding: " .. (config.details.fold and "on" or "off"))
end

return M
