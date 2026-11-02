-- Headless smoke test: nvim --headless -u NONE -l tests/smoke.lua
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)

local render_html = require("render-html")
render_html.setup({ keymap = "<CR>", file_types = { markdown = true } })

vim.cmd("edit tests/fixtures/gitar.md")
vim.bo.filetype = "markdown"

local buf = vim.api.nvim_get_current_buf()
local filetype = vim.bo[buf].filetype
assert(filetype == "markdown", "expected markdown filetype")

-- Force a synchronous render.
render_html.refresh(buf)

local ns = vim.api.nvim_create_namespace("render-html")
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
local conceal, virt = 0, 0
for _, m in ipairs(marks) do
	local d = m[4]
	if d.conceal ~= nil then
		conceal = conceal + 1
	end
	if d.virt_text then
		virt = virt + 1
	end
end

print(("extmarks=%d conceal=%d virt=%d"):format(#marks, conceal, virt))
assert(conceal > 20, "expected many concealed tags, got " .. conceal)
assert(virt > 3, "expected virt_text icons, got " .. virt)

-- Fold levels: <details> starts a fold, nested details nest deeper.
local starts = {}
for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
	local level = render_html.fold_level_for(buf, row)
	if level > 0 then
		starts[#starts + 1] = ("%d:%d"):format(row + 1, level)
	end
end
print("foldlevels " .. table.concat(starts, " "):sub(1, 300))
assert(#starts > 10, "expected folded details rows")

-- Render a couple of lines the way Neovim would display them.
local function displayed(row)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	local pieces = {}
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })) do
		local col, d = m[3], m[4]
		if d.conceal ~= nil then
			pieces[#pieces + 1] = { col, d.end_col, "" }
		end
		if d.virt_text and d.virt_text_pos == "inline" then
			pieces[#pieces + 1] = { col, col, d.virt_text[1][1] }
		end
	end
	table.sort(pieces, function(a, b)
		return a[1] < b[1]
	end)
	local out, cursor = {}, 1
	for _, p in ipairs(pieces) do
		if p[1] >= cursor - 1 then
			out[#out + 1] = line:sub(cursor, p[1])
			out[#out + 1] = p[3]
		end
		cursor = math.max(cursor, p[2] + 1)
	end
	out[#out + 1] = line:sub(cursor)
	return table.concat(out)
end

for _, row in ipairs({ 0, 1, 4, 8, 10 }) do
	print(("L%d: %s"):format(row + 1, displayed(row)))
end

-- Fold text for the outer <details> block.
local foldtext = render_html.fold_text_for(buf, 1)
print("foldtext: " .. tostring(foldtext))
assert(foldtext:find("Code Review", 1, true), "fold text should contain the summary")

print("OK")
vim.cmd("qall!")
