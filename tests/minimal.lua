-- Minimal config for interactive checks: nvim -u tests/minimal.lua tests/fixtures/gitar.md
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(root)

vim.o.termguicolors = true
vim.o.number = false
vim.o.signcolumn = "no"
vim.o.foldcolumn = "0"
vim.o.laststatus = 0
vim.o.showmode = false

vim.api.nvim_create_autocmd("FileType", {
	callback = function()
		pcall(vim.treesitter.start)
	end,
})

require("render-html").setup({ keymap = "<CR>" })
