-- Файл: <папка с init.vim>/lua/plugins-setup.lua
-- (то есть если init.vim лежит в ~/.dotfile/.config/nvim/init.vim,
--  этот файл должен лежать в ~/.dotfile/.config/nvim/lua/plugins-setup.lua)

-- ===== neo-tree =====
require("neo-tree").setup({
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = true },
    hijack_netrw_behavior = "open_default",
  },
})
vim.keymap.set('n', '<C-n>', ':Neotree toggle<CR>', { silent = true, desc = "Toggle file tree" })

-- ===== which-key =====
require("which-key").setup({})

-- ===== nvim-surround =====
-- ys<motion><char> - добавить обрамление, cs<old><new> - заменить, ds<char> - удалить
require("nvim-surround").setup({})

-- ===== telescope =====
require('telescope').setup({})
pcall(require('telescope').load_extension, 'fzf')

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = "Find files" })
vim.keymap.set('n', '<leader>fg', builtin.live_grep,  { desc = "Grep in project" })
vim.keymap.set('n', '<leader>fb', builtin.buffers,    { desc = "Buffers" })
vim.keymap.set('n', '<leader>fh', builtin.help_tags,  { desc = "Help" })

-- ===== nvim-cmp =====
local cmp = require('cmp')
cmp.setup({
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>']      = cmp.mapping.confirm({ select = true }),
    ['<Tab>']     = cmp.mapping.select_next_item(),
    ['<S-Tab>']   = cmp.mapping.select_prev_item(),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'buffer' },
    { name = 'path' },
  }),
})
