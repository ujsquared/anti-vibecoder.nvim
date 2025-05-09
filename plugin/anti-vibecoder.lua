local anti_vibecoder = require('anti-vibecoder')

-- Create the command
vim.api.nvim_create_user_command('AntiVibeCoder', function()
    anti_vibecoder.start_interaction()
end, {
    desc = 'Start interaction with LLM for code guidance'
})

-- Set up default keymap
vim.keymap.set('n', '<leader>av', '<cmd>AntiVibeCoder<cr>', {
    desc = 'Start AntiVibeCoder interaction'
}) 