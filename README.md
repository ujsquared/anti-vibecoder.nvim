# anti-vibecoder.nvim

A Neovim plugin that provides LLM-based code guidance, helping junior developers learn and improve their code through senior engineer-like mentorship.

## !!! 🚨🚨🚨Irony Alert 🚨🚨🚨!!!
I have vibe coded this. 🤣🤣🤣🤣🤣

# Credits
Credits to Tusharsingh Baghel [@tusharamasingh](https://x.com/tusharamasingh) for his [post](https://x.com/tusharamasingh/status/1913992056680374404) that inspired me to create something similar for neovim.


## Features

- Extracts code from current buffer or git repository
- Provides an interactive floating window for LLM communication
- Guides developers with mentorship-style responses instead of direct solutions
- Easy-to-use interface with customizable prompts
- Powered by Google's Gemini Pro model

## Requirements

- Neovim 0.7.0 or higher
- Google Gemini API key
- `curl` command-line tool

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua

"ujsquared/anti-vibecoder.nvim",
    opts = {
        api_key = "your-gemini-api-key-here",
        model = "gemini-2.0-flash",
        max_tokens = 1000,
        temperature = 0.7,
    },
    -- Optional: lazy load on command
    cmd = "AntiVibeCoder",
    -- Optional: lazy load on keymap
    keys = {
        { "<leader>av", "<cmd>AntiVibeCoder<cr>", desc = "Start AntiVibeCoder interaction" }
    }
}
```

## Usage

1. Open a file or navigate to a git repository
2. Use one of the following methods to start the interaction:
   - Command: `:AntiVibeCoder`
   - Keymap: `<leader>av` (default)
3. A floating window will appear with the initial prompt
4. Press `<CR>` to send your message to the LLM
5. Press `q` to close the interaction window

## Configuration

You can configure the plugin by passing options to the setup function:

```lua
{
    "ujsquared/anti-vibecoder.nvim",
    opts = {
        api_key = "your-gemini-api-key-here",  -- Required: Your Gemini API key
        model = "gemini-pro",                  -- The Gemini model to use
        max_tokens = 1000,                     -- Maximum response length
        temperature = 0.7,                     -- Response creativity (0.0 to 1.0)
    }
}
```

## Getting a Gemini API Key

1. Go to the [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Create a new API key
3. Copy the API key and use it in your plugin configuration

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
