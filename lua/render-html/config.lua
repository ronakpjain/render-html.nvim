---@class render-html.Tag
---@field enabled? boolean
---@field conceal? boolean Conceal the start/end tags.
---@field icon? string Inline text shown where the tag was.
---@field highlight? string Highlight for `icon` and padding.
---@field content? string Highlight for the text between the tags.
---@field pad? boolean Add a space on both sides of the content (kbd chips).
---@field alt? boolean Use the `alt`/`title` attribute as text (img).

---@class render-html.Config
---@field file_types table<string, boolean>
---@field keymap string|false
---@field debounce integer
---@field tags table<string, render-html.Tag>
---@field default render-html.Tag
---@field details render-html.Details
---@field fold render-html.Fold

---@class render-html.Details
---@field fold boolean

---@class render-html.Fold
---@field format fun(info: render-html.FoldInfo): string

---@class render-html.FoldInfo
---@field summary string
---@field lines integer

local M = {}

---@type render-html.Config
M.default = {
	file_types = { markdown = true, pi = true, gitcommit = true },

	-- Buffer-local keymap that toggles the <details> block under the cursor.
	-- Everything else is passed through to the original mapping.
	keymap = false,

	-- Milliseconds to wait before re-rendering after a change.
	debounce = 120,

	details = {
		fold = true,
	},

	fold = {
		---@param info render-html.FoldInfo
		---@return string
		format = function(info)
			local text = info.summary ~= "" and info.summary or "details"
			return (" %s %s  ·  %d lines"):format("▸", text, info.lines)
		end,
	},

	-- Tags not listed here are concealed without any styling.
	tags = {
		details = { icon = "▏", highlight = "RenderHtmlFold", content = "RenderHtmlBlock" },
		summary = { content = "RenderHtmlSummary" },
		kbd = { content = "RenderHtmlKbd", pad = true },
		code = { content = "RenderHtmlCode" },
		samp = { content = "RenderHtmlCode" },
		tt = { content = "RenderHtmlCode" },
		b = { content = "RenderHtmlBold" },
		strong = { content = "RenderHtmlBold" },
		i = { content = "RenderHtmlItalic" },
		em = { content = "RenderHtmlItalic" },
		u = { content = "RenderHtmlUnderline" },
		ins = { content = "RenderHtmlUnderline" },
		s = { content = "RenderHtmlStrikethrough" },
		del = { content = "RenderHtmlStrikethrough" },
		strike = { content = "RenderHtmlStrikethrough" },
		a = { content = "RenderHtmlLink" },
		img = { icon = "🖼 ", highlight = "RenderHtmlIcon", alt = true },
		br = { icon = " " },
		hr = { icon = "─────", highlight = "RenderHtmlBlock" },
		sub = { content = "RenderHtmlSmall" },
		sup = { content = "RenderHtmlSmall" },
		small = { content = "RenderHtmlSmall" },
		mark = { content = "RenderHtmlMark" },
		p = { content = "RenderHtmlBlock" },
		div = { content = "RenderHtmlBlock" },
		section = { content = "RenderHtmlBlock" },
		span = {},
		blockquote = { content = "RenderHtmlQuote" },
		ul = {},
		ol = {},
		li = {},
		table = {},
		thead = {},
		tbody = {},
		tr = {},
		td = {},
		th = { content = "RenderHtmlBold" },
		pre = {},
	},

	default = { conceal = true },
}

M.highlights = {
	RenderHtmlFold = { link = "Function", default = true },
	RenderHtmlBlock = { link = "Comment", default = true },
	RenderHtmlSummary = { link = "Title", default = true },
	RenderHtmlKbd = { link = "Pmenu", default = true },
	RenderHtmlCode = { link = "@markup.raw", default = true },
	RenderHtmlBold = { link = "Bold", default = true },
	RenderHtmlItalic = { link = "Italic", default = true },
	RenderHtmlUnderline = { underline = true, default = true },
	RenderHtmlStrikethrough = { strikethrough = true, default = true },
	RenderHtmlLink = { link = "@markup.link.label", default = true },
	RenderHtmlIcon = { link = "Special", default = true },
	RenderHtmlSmall = { link = "@markup.raw", default = true },
	RenderHtmlMark = { link = "Visual", default = true },
	RenderHtmlQuote = { link = "Comment", default = true },
}

---@param opts? table
---@return render-html.Config
function M.resolve(opts)
	opts = opts or {}
	local config = vim.deepcopy(M.default)
	config.tags = vim.tbl_extend("force", config.tags, opts.tags or {})
	config.details = vim.tbl_extend("force", config.details, opts.details or {})
	config.fold = vim.tbl_extend("force", config.fold, opts.fold or {})
	config.default = vim.tbl_extend("force", config.default, opts.default or {})
	config.file_types = vim.tbl_extend("force", config.file_types, opts.file_types or {})
	if opts.keymap ~= nil then
		config.keymap = opts.keymap
	end
	if opts.debounce then
		config.debounce = opts.debounce
	end
	return config
end

function M.setup_highlights()
	for name, spec in pairs(M.highlights) do
		vim.api.nvim_set_hl(0, name, spec)
	end
end

return M
