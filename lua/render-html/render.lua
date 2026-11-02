local config_mod = require("render-html.config")

local M = {}

M.ns = vim.api.nvim_create_namespace("render-html")

---@param node TSNode
---@param name string
---@return TSNode?
local function child_of_type(node, name)
	for child in node:iter_children() do
		if child:type() == name then
			return child
		end
	end
	return nil
end

---Find the first descendent element with a given tag name.
---@param node TSNode
---@param buf integer
---@param name string
---@return TSNode?
local function find_element(node, buf, name)
	for child in node:iter_children() do
		if child:type() == "element" then
			local start_tag = child_of_type(child, "start_tag")
			local tag_name = start_tag and child_of_type(start_tag, "tag_name")
			if tag_name and vim.treesitter.get_node_text(tag_name, buf):lower() == name then
				return child
			end
		end
		if child:named_child_count() > 0 then
			local found = find_element(child, buf, name)
			if found then
				return found
			end
		end
	end
	return nil
end

---@param node TSNode
---@param buf integer
---@return string
local function text_of(node, buf)
	-- Only leaf text, so that folded summaries do not include raw tags.
	local parts = {}
	for child in node:iter_children() do
		local t = child:type()
		if t == "text" or t == "raw_text" then
			parts[#parts + 1] = vim.treesitter.get_node_text(child, buf)
		elseif child:named_child_count() > 0 then
			-- Element boundaries lose their surrounding whitespace in the html
			-- grammar; pad them so "Review</b> <kbd>" does not become "Review✅".
			parts[#parts + 1] = " " .. text_of(child, buf) .. " "
		end
	end
	return table.concat(parts)
end

---@param text string
---@return string
local function clean(text)
	return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

---@param node TSNode
---@param buf integer
---@param name string
---@return string?
function M.attribute(node, buf, name)
	for child in node:iter_children() do
		if child:type() == "attribute" then
			local key = child:field("attribute_name") or child:named_child(0)
			if key and vim.treesitter.get_node_text(key, buf) == name then
				local value = child:field("attribute_value") or child:named_child(1)
				if value then
					return (vim.treesitter.get_node_text(value, buf):gsub("^[\"']", ""):gsub("[\"']$", ""))
				end
			end
		end
	end
	return nil
end

---Conceal a single-line node.
---@param buf integer
---@param node TSNode
---@param highlight? string
---@return boolean
local function conceal(buf, node, highlight)
	local sr, sc, er, ec = node:range()
	if sr ~= er or (sc == ec) then
		return false
	end
	vim.api.nvim_buf_set_extmark(buf, M.ns, sr, sc, {
		end_col = ec,
		conceal = "",
		hl_group = highlight,
	})
	return true
end

---@param buf integer
---@param sr integer
---@param sc integer
---@param er integer
---@param ec integer
---@param highlight? string
local function highlight(buf, sr, sc, er, ec, highlight)
	if not highlight then
		return
	end
	if sc == ec and sr == er then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, M.ns, sr, sc, {
		end_row = er,
		end_col = ec,
		hl_group = highlight,
		priority = 10,
	})
end

---@param buf integer
---@param row integer
---@param col integer
---@param text string
---@param highlight? string
local function virt_inline(buf, row, col, text, highlight)
	if text == "" then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, M.ns, row, col, {
		virt_text = { { text, highlight } },
		virt_text_pos = "inline",
	})
end

---@param config render-html.Config
---@param name string
---@return render-html.Tag
local function tag_config(config, name)
	local user = config.tags[name] or config.default
	if user.enabled == false then
		return { enabled = false }
	end
	return vim.tbl_extend("force", { conceal = true }, config.default, user)
end

---@class render-html.Node
---@field start_row integer
---@field end_row integer
---@field summary string

---@param buf integer
---@param node TSNode
---@param config render-html.Config
---@param details render-html.Node[]
function M.walk(buf, node, config, details)
	local kind = node:type()

	if kind == "element" then
		local start_tag = child_of_type(node, "start_tag")
		local end_tag = child_of_type(node, "end_tag")
		local name = start_tag and child_of_type(start_tag, "tag_name")
		local tag = name and vim.treesitter.get_node_text(name, buf):lower() or nil
		if tag then
			local tag_conf = tag_config(config, tag)

			if tag == "details" and config.details.fold then
				local summary = find_element(node, buf, "summary")
				local sr, _, er = node:range()
				details[#details + 1] = {
					start_row = sr,
					end_row = er,
					summary = summary and clean(text_of(summary, buf)) or "",
				}
			end

			if tag_conf.enabled ~= false then
				if start_tag and tag_conf.conceal then
					conceal(buf, start_tag, tag_conf.highlight)
					if tag_conf.pad then
						local row, col = start_tag:range()
						virt_inline(buf, row, col, " ", tag_conf.highlight)
					end
					if tag_conf.icon then
						local row, col = start_tag:range()
						virt_inline(buf, row, col, tag_conf.icon, tag_conf.highlight)
					end
				end
				if end_tag and tag_conf.conceal then
					conceal(buf, end_tag, tag_conf.highlight)
					if tag_conf.pad then
						local row, col = end_tag:range()
						virt_inline(buf, row, col, " ", tag_conf.highlight)
					end
				end
				if start_tag and end_tag then
					local _, _, csr, csc = start_tag:range()
					local eer, eec = end_tag:range()
					highlight(buf, csr, csc, eer, eec, tag_conf.content)
				end
			end
		end
	elseif kind == "self_closing_tag" then
		local name = child_of_type(node, "tag_name")
		local tag = name and vim.treesitter.get_node_text(name, buf):lower() or nil
		if tag then
			local tag_conf = tag_config(config, tag)
			if tag_conf.enabled ~= false and tag_conf.conceal then
				local text = tag_conf.icon
				if text and tag_conf.alt then
					local alt = M.attribute(node, buf, "alt") or M.attribute(node, buf, "title")
					if alt and alt ~= "" then
						text = text .. alt
					end
				end
				if conceal(buf, node, tag_conf.highlight) and text then
					local row, col = node:range()
					virt_inline(buf, row, col, text, tag_conf.highlight)
				end
			end
		end
	elseif kind == "comment" then
		conceal(buf, node)
	elseif kind == "erroneous_end_tag" then
		conceal(buf, node)
	end

	for child in node:iter_children() do
		M.walk(buf, child, config, details)
	end
end

---@param buf integer
---@param ft string
---@return vim.treesitter.LanguageTree?
local function get_parser(buf, ft)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, ft, { error = false })
	if ok and parser then
		return parser
	end
	-- `pi` and other markdown-derived buffers have no parser of their own.
	ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown", { error = false })
	if ok and parser then
		return parser
	end
	return nil
end

---@param buf integer
---@param config render-html.Config
---@return render-html.Node[]
function M.render(buf, config)
	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

	local ok, parser = pcall(get_parser, buf, vim.bo[buf].filetype)
	if not ok or not parser then
		return {}
	end
	pcall(parser.parse, parser, true)

	---@type render-html.Node[]
	local details = {}
	local failed = false
	parser:for_each_tree(function(tree, language_tree)
		if language_tree:lang() ~= "html" then
			return
		end
		local root = tree:root()
		if root:has_error() then
			failed = true
		end
		local ok_walk = pcall(M.walk, buf, root, config, details)
		if not ok_walk then
			failed = true
		end
	end)

	if failed then
		vim.notify_once("render-html: skipped malformed html in buffer " .. buf, vim.log.levels.DEBUG)
	end
	return details
end

return M
