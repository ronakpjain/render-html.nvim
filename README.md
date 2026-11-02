# render-html.nvim

Render inline HTML in Neovim buffers the way [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
renders markdown: tags are hidden with extmarks, content gets real highlights, and
`<details>` blocks fold shut like they do on GitHub.

This exists because bot comments on GitHub are often raw HTML (`<details>`, `<summary>`,
`<kbd>`, `<img>`, ...). Inside a `guh.nvim` PR buffer those tags are just noise.

Before:

```
<details>
<summary><b>Code Review</b> <kbd>✅ Approved</kbd> <kbd>4 closed / 4 findings</kbd></summary>

<kbd>🟡 Medium risk</kbd> · Everything is fine.
...
</details>
```

After:

```
▸ Code Review ✅ Approved 4 closed / 4 findings  ·  45 lines
```

Press `za` (or the configured keymap) to expand, and nested `<details>` blocks stay
folded until you open them too.

## Requirements

- Neovim 0.10+ (extmarks + `vim.pack` optional).
- `tree-sitter-html` parser installed for Neovim.
- An injection query that feeds markdown `html_block` nodes to the `html` parser.
  `nvim-treesitter` ships one; without it no HTML tree is ever produced.

## Install

With `vim.pack`:

```lua
vim.pack.add({
	"https://github.com/ronakpjain/render-html.nvim",
}, { confirm = false, load = true })

require("render-html").setup()
```

Then make sure the parsers exist:

```vim
:TSInstall markdown markdown_inline html
```

## Configuration

```lua
require("render-html").setup({
	-- Attach to these filetypes. `markdown` covers guh.nvim PR/issue buffers.
	file_types = { markdown = true, pi = true, gitcommit = true },

	-- Buffer-local key that toggles the <details> block under the cursor.
	-- Set to false to only use :za / :zo / :zc.
	keymap = "<CR>",

	details = {
		fold = true,
	},

	-- Fold line text. Return a plain string.
	fold = {
		format = function(info) -- { summary = "Code Review ...", lines = 45 }
			return (" ▸ %s  ·  %d lines"):format(info.summary, info.lines)
		end,
	},

	-- Per-tag rendering. Tags not listed are concealed with no styling.
	tags = {
		summary = { content = "RenderHtmlSummary" },
		kbd = { content = "RenderHtmlKbd", pad = true },
		code = { content = "RenderHtmlCode" },
		b = { content = "RenderHtmlBold" },
		img = { icon = "🖼 ", alt = true },
		br = { icon = " " },
	},
})
```

Each tag accepts:

| Key        | Meaning                                                  |
| ---------- | -------------------------------------------------------- |
| `enabled`  | `false` disables all handling for the tag                |
| `conceal`  | hide the start/end tags (default `true`)                 |
| `icon`     | inline text shown where the tag was                      |
| `highlight`| highlight for `icon`/padding                             |
| `content`  | highlight for the text between the tags                  |
| `pad`      | add a space on both sides (used for `kbd` chips)         |
| `alt`      | use the `alt` attribute as text (`img` only)             |

Highlights are created with `default = true`, so a colorscheme loaded later can
override them. Pass `highlights = false` to `setup()` to skip them entirely.

## Commands

| Command               | Effect                                   |
| --------------------- | ---------------------------------------- |
| `:RenderHtml toggle`  | toggle rendering in the current buffer   |
| `:RenderHtml enable`  | render the current buffer                |
| `:RenderHtml disable` | show raw HTML in the current buffer      |
| `:RenderHtml refresh` | re-parse and re-render                   |

## How it works

1. The buffer's treesitter parser is parsed with injections, and every `html`
   language tree is walked (`element`, `self_closing_tag`, `comment`).
2. Tags are concealed with extmarks, content is highlighted, `kbd`/`img`/`br` get
   inline virtual text.
3. `<details>` ranges are turned into fold levels through a buffer-local
   `foldexpr`, so nesting maps onto nested folds. `foldtext` shows the `<summary>`
   text instead of raw markup.
4. Window options (`conceallevel`, `foldmethod`, `foldexpr`, `foldtext`) are saved
   per window and restored when the buffer leaves the window.

Like render-markdown.nvim, the cursor line shows the raw source because
`concealcursor` is empty. Move off the line to see it rendered.

## Limitations

- Concealment only works for tags that do not span multiple lines.
- HTML inside fenced code blocks is left alone (it is not parsed as HTML).
- `<pre>`/`<script>`/`<style>` content is not reformatted, only their tags are hidden.