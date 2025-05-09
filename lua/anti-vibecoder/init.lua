local M = {}

-- Configuration
local config = {
    api_key = nil,
    model = "gemini-2.0-flash", -- updated to use the working model
    max_tokens = 8192,
    temperature = 0.7,
}

-- Store conversation state
local conversation_state = {
    content = nil,  -- Original file content
    history = {},   -- Conversation history
}

-- Setup function
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Get current buffer content
local function get_buffer_content()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return table.concat(lines, "\n")
end

-- Build tree structure from file list
local function build_file_tree(files)
    local tree = {}
    
    -- Sort files to ensure directories come before their contents
    table.sort(files)
    
    for _, file in ipairs(files) do
        local parts = {}
        for part in file:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        
        local current = tree
        local path = ""
        
        for i, part in ipairs(parts) do
            path = path .. (i > 1 and "/" or "") .. part
            if i == #parts then
                -- It's a file
                table.insert(current, {
                    type = "file",
                    name = part,
                    path = file,
                    selected = false
                })
            else
                -- It's a directory
                local found = false
                for _, node in ipairs(current) do
                    if node.type == "dir" and node.name == part then
                        current = node.children
                        found = true
                        break
                    end
                end
                
                if not found then
                    local new_dir = {
                        type = "dir",
                        name = part,
                        path = path,
                        children = {},
                        expanded = false,
                        selected = false
                    }
                    table.insert(current, new_dir)
                    current = new_dir.children
                end
            end
        end
    end
    
    return tree
end

-- Get list of git files
local function get_git_files()
    local handle = io.popen("git ls-files 2>/dev/null")
    if not handle then return {} end
    local files = {}
    for file in handle:lines() do
        table.insert(files, file)
    end
    handle:close()
    return files
end

-- Get content of selected files
local function get_selected_files_content(selected_files)
    local content = {}
    for _, file in ipairs(selected_files) do
        local handle = io.open(file, "r")
        if handle then
            local file_content = handle:read("*a")
            handle:close()
            table.insert(content, string.format("=== File: %s ===\n%s", file, file_content))
        end
    end
    return table.concat(content, "\n\n")
end

-- Convert tree to display lines
local function tree_to_lines(tree, level, lines)
    level = level or 0
    lines = lines or {}
    
    for _, node in ipairs(tree) do
        local prefix = string.rep("  ", level)
        local marker = node.type == "dir" and (node.expanded and "▼" or "▶") or " "
        local checkbox = node.selected and "[X]" or "[ ]"
        local line = string.format("%s%s %s %s", prefix, marker, checkbox, node.name)
        table.insert(lines, line)
        
        if node.type == "dir" and node.expanded then
            tree_to_lines(node.children, level + 1, lines)
        end
    end
    
    return lines
end

-- Get all selected files from tree
local function get_selected_files_from_tree(tree, selected_files)
    selected_files = selected_files or {}
    
    for _, node in ipairs(tree) do
        if node.selected then
            if node.type == "file" then
                table.insert(selected_files, node.path)
            elseif node.type == "dir" then
                -- Add all files in directory
                local function add_dir_files(dir_node)
                    for _, child in ipairs(dir_node.children) do
                        if child.type == "file" then
                            table.insert(selected_files, child.path)
                        elseif child.type == "dir" then
                            add_dir_files(child)
                        end
                    end
                end
                add_dir_files(node)
            end
        elseif node.type == "dir" then
            get_selected_files_from_tree(node.children, selected_files)
        end
    end
    
    return selected_files
end

-- Create a floating window for file selection
local function create_file_selection_window(files)
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_option(buf, "buftype", "prompt")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)

    -- Set window options
    vim.api.nvim_win_set_option(win, "wrap", true)
    vim.api.nvim_win_set_option(win, "linebreak", true)
    vim.api.nvim_win_set_option(win, "number", true)

    -- Add instructions
    local lines = {
        "Select files to include in your prompt:",
        "Press <Space> to toggle selection",
        "Press <Enter> to expand/collapse directory",
        "Press <C-CR> to confirm selection",
        "Press <Esc> to cancel",
        "",
        "Files:",
        ""
    }
    
    -- Build and display tree
    local tree = build_file_tree(files)
    local tree_lines = tree_to_lines(tree)
    for _, line in ipairs(tree_lines) do
        table.insert(lines, line)
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    return buf, win, tree
end

-- Create a floating window for LLM interaction
local function create_interaction_window()
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_option(buf, "buftype", "prompt")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)

    -- Set window options
    vim.api.nvim_win_set_option(win, "wrap", true)
    vim.api.nvim_win_set_option(win, "linebreak", true)
    vim.api.nvim_win_set_option(win, "number", true)

    return buf, win
end

-- Split string into lines
local function split_lines(str)
    local lines = {}
    for line in str:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- Send content to Gemini API
local function send_to_llm(content, prompt)
    if not config.api_key then
        return {"Error: API key not configured. Please set your Gemini API key in the plugin configuration."}
    end

    local curl = vim.fn.system({
        "curl",
        "-s",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "https://generativelanguage.googleapis.com/v1beta/models/" .. config.model .. ":generateContent?key=" .. config.api_key,
        "-d", vim.fn.json_encode({
            contents = {
                {
                    parts = {
                        {
                            text = prompt
                        }
                    }
                }
            },
            generationConfig = {
                temperature = config.temperature,
                maxOutputTokens = config.max_tokens,
            }
        })
    })

    -- Parse the JSON response
    local success, response = pcall(vim.fn.json_decode, curl)
    if not success then
        return {"Error: Failed to parse API response", curl}
    end

    -- Extract the text from the response
    if response.candidates and response.candidates[1] and 
       response.candidates[1].content and response.candidates[1].content.parts and 
       response.candidates[1].content.parts[1] then
        local text = response.candidates[1].content.parts[1].text
        return split_lines(text)
    end

    -- If we couldn't extract the text, return the raw response for debugging
    local lines = {}
    for line in curl:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    table.insert(lines, 1, "=== Error: Could not extract text from response ===")
    return lines
end

-- Find node in tree by line number
local function find_node_at_line(tree, target_line, current_line, start_line)
    current_line = current_line or 0
    start_line = start_line or 0
    
    for _, node in ipairs(tree) do
        current_line = current_line + 1
        local absolute_line = current_line + start_line
        if absolute_line == target_line then
            return node, current_line
        end
        
        if node.type == "dir" and node.expanded then
            local found_node, new_line = find_node_at_line(node.children, target_line, current_line, start_line)
            if found_node then
                return found_node, new_line
            end
            current_line = new_line
        end
    end
    
    return nil, current_line
end

-- Update tree display
local function update_tree_display(buf, tree)
    local lines = {
        "Select files to include in your prompt:",
        "Press <Space> to toggle selection",
        "Press <Enter> to expand/collapse directory",
        "Press <C-CR> to confirm selection",
        "Press <Esc> to cancel",
        "",
        "Files:",
        ""
    }
    
    local tree_lines = tree_to_lines(tree)
    for _, line in ipairs(tree_lines) do
        table.insert(lines, line)
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Start interaction with selected content
local function start_interaction_with_content(content)
    local buf, win = create_interaction_window()
    
    -- Store the content in conversation state
    conversation_state.content = content
    conversation_state.history = {}
    
    -- Set up the initial prompt
    local initial_prompt = "Act like a senior engineer guiding a junior dev in the correct direction instead of directly solving it. Here's the code:\n\n" .. content
    local initial_lines = split_lines(initial_prompt)
    
    -- Clear the buffer and set initial content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Press c to send prompt to LLM",
        "Press A to add more files",
        "Press q to close this window",
        "",
        "---",
        ""
    })
    
    -- Append the initial prompt
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, initial_lines)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, {"", "---", ""})

    -- Set up key mappings for the interaction window
    local function setup_keymaps()
        local opts = { buffer = buf, silent = true }
        
        -- Send prompt to LLM
        vim.keymap.set("n", "c", function()
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            local prompt = table.concat(lines, "\n")
            
            -- Add to conversation history
            table.insert(conversation_state.history, {
                role = "user",
                content = prompt
            })
            
            local response_lines = send_to_llm(conversation_state.content, prompt)
            
            -- Add response to conversation history
            table.insert(conversation_state.history, {
                role = "assistant",
                content = table.concat(response_lines, "\n")
            })
            
            -- If this is the first response, clean up the buffer
            if #conversation_state.history == 2 then
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                    "Press c to send prompt to LLM",
                    "Press a to add more files",
                    "Press q to close this window",
                    "",
                    "---",
                    ""
                })
            end
            
            -- Append response
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, {""})
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, response_lines)
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, {"", "---", ""})
            
            -- Scroll to bottom
            vim.api.nvim_command("normal! G")
        end, opts)

        -- Add more files
        vim.keymap.set("n", "A", function()
            -- Store current window and buffer
            local current_win = win
            local current_buf = buf
            
            -- Get git files
            local files = get_git_files()
            if #files == 0 then
                vim.notify("No files found in git repository", vim.log.levels.ERROR)
                return
            end

            -- Create file selection window
            local select_buf, select_win, tree = create_file_selection_window(files)
            local start_line = 9  -- Line where tree starts

            -- Set up key mappings for file selection
            local function setup_selection_keymaps()
                local opts = { buffer = select_buf, silent = true }
                
                local function handle_node_action(action)
                    local line = vim.api.nvim_win_get_cursor(select_win)[1]
                    if line >= start_line then
                        local node, _ = find_node_at_line(tree, line, 0, start_line - 1)
                        if node then
                            if action == "toggle" then
                                node.selected = not node.selected
                            elseif action == "expand" and node.type == "dir" then
                                node.expanded = not node.expanded
                            end
                            update_tree_display(select_buf, tree)
                            -- Restore cursor position
                            vim.api.nvim_win_set_cursor(select_win, {line, 0})
                        end
                    end
                end

                -- z to toggle selection
                vim.keymap.set("n", "z", function()
                    handle_node_action("toggle")
                end, opts)

                -- x to expand/collapse directory
                vim.keymap.set("n", "x", function()
                    handle_node_action("expand")
                end, opts)

                -- c to show confirmation window
                vim.keymap.set("n", "c", function()
                    local selected_files = get_selected_files_from_tree(tree)
                    if #selected_files == 0 then
                        vim.notify("Please select at least one file", vim.log.levels.WARN)
                        return
                    end
                    
                    -- Show confirmation message
                    local confirm_buf = vim.api.nvim_create_buf(false, true)
                    local confirm_win = vim.api.nvim_open_win(confirm_buf, true, {
                        relative = "editor",
                        width = 50,
                        height = 3,
                        row = math.floor((vim.o.lines - 3) / 2),
                        col = math.floor((vim.o.columns - 50) / 2),
                        style = "minimal",
                        border = "rounded",
                    })

                    vim.api.nvim_buf_set_lines(confirm_buf, 0, -1, false, {
                        "Selected " .. #selected_files .. " files. Press:",
                        "y - Add to conversation",
                        "n - Cancel"
                    })

                    -- Set up confirmation keymaps
                    local confirm_opts = { buffer = confirm_buf, silent = true }
                    vim.keymap.set("n", "y", function()
                        vim.api.nvim_win_close(confirm_win, true)
                        vim.api.nvim_win_close(select_win, true)
                        
                        -- Get content of selected files
                        local new_content = get_selected_files_content(selected_files)
                        
                        -- Append to existing content
                        conversation_state.content = conversation_state.content .. "\n\n=== Additional Files ===\n\n" .. new_content
                        
                        -- Add a message about the new files
                        local file_names = table.concat(selected_files, ", ")
                        local message = "Added " .. #selected_files .. " new file(s) to the conversation:\n" .. file_names
                        vim.api.nvim_buf_set_lines(current_buf, -1, -1, false, {""})
                        vim.api.nvim_buf_set_lines(current_buf, -1, -1, false, split_lines(message))
                        vim.api.nvim_buf_set_lines(current_buf, -1, -1, false, {"", "---", ""})
                        
                        -- Focus back on conversation window
                        vim.api.nvim_set_current_win(current_win)
                    end, confirm_opts)

                    vim.keymap.set("n", "n", function()
                        vim.api.nvim_win_close(confirm_win, true)
                    end, confirm_opts)
                end, opts)

                vim.keymap.set("n", "<Esc>", function()
                    vim.api.nvim_win_close(select_win, true)
                end, opts)
            end

            setup_selection_keymaps()
        end, opts)

        -- Close window
        vim.keymap.set("n", "q", function()
            vim.api.nvim_win_close(win, true)
        end, opts)
    end

    setup_keymaps()
    
    -- Make sure the window is visible and focused
    vim.api.nvim_set_current_win(win)
end

-- Main function to start the interaction
function M.start_interaction()
    -- If we have an existing conversation, restore it
    if conversation_state.content and #conversation_state.history > 0 then
        local buf, win = create_interaction_window()
        
        -- Set up the buffer with conversation history
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Press c to send prompt to LLM",
            "Press q to close this window",
            "",
            "---",
            ""
        })
        
        -- Add conversation history to buffer
        for _, message in ipairs(conversation_state.history) do
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, split_lines(message.content))
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, {"", "---", ""})
        end
        
        -- Set up key mappings
        local function setup_keymaps()
            local opts = { buffer = buf, silent = true }
            
            -- Send prompt to LLM
            vim.keymap.set("n", "c", function()
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                local prompt = table.concat(lines, "\n")
                
                -- Add to conversation history
                table.insert(conversation_state.history, {
                    role = "user",
                    content = prompt
                })
                
                local response_lines = send_to_llm(conversation_state.content, prompt)
                
                -- Add response to conversation history
                table.insert(conversation_state.history, {
                    role = "assistant",
                    content = table.concat(response_lines, "\n")
                })
                
                -- Append response
                vim.api.nvim_buf_set_lines(buf, -1, -1, false, {""})
                vim.api.nvim_buf_set_lines(buf, -1, -1, false, response_lines)
                vim.api.nvim_buf_set_lines(buf, -1, -1, false, {"", "---", ""})
                
                -- Scroll to bottom
                vim.api.nvim_command("normal! G")
            end, opts)

            -- Close window
            vim.keymap.set("n", "q", function()
                vim.api.nvim_win_close(win, true)
            end, opts)
        end

        setup_keymaps()
        vim.api.nvim_set_current_win(win)
        return
    end

    -- If no existing conversation, start a new one
    local files = get_git_files()
    if #files == 0 then
        vim.notify("No files found in git repository", vim.log.levels.ERROR)
        return
    end

    -- Create file selection window
    local select_buf, select_win, tree = create_file_selection_window(files)
    local start_line = 9  -- Line where tree starts

    -- Set up key mappings for file selection
    local function setup_selection_keymaps()
        local opts = { buffer = select_buf, silent = true }
        
        local function handle_node_action(action)
            local line = vim.api.nvim_win_get_cursor(select_win)[1]
            if line >= start_line then
                local node, _ = find_node_at_line(tree, line, 0, start_line - 1)
                if node then
                    if action == "toggle" then
                        node.selected = not node.selected
                    elseif action == "expand" and node.type == "dir" then
                        node.expanded = not node.expanded
                    end
                    update_tree_display(select_buf, tree)
                    -- Restore cursor position
                    vim.api.nvim_win_set_cursor(select_win, {line, 0})
                end
            end
        end

        -- z to toggle selection
        vim.keymap.set("n", "z", function()
            handle_node_action("toggle")
        end, opts)

        -- x to expand/collapse directory
        vim.keymap.set("n", "x", function()
            handle_node_action("expand")
        end, opts)

        -- c to show confirmation window
        vim.keymap.set("n", "c", function()
            local selected_files = get_selected_files_from_tree(tree)
            if #selected_files == 0 then
                vim.notify("Please select at least one file", vim.log.levels.WARN)
                return
            end
            
            -- Show confirmation message
            local confirm_buf = vim.api.nvim_create_buf(false, true)
            local confirm_win = vim.api.nvim_open_win(confirm_buf, true, {
                relative = "editor",
                width = 50,
                height = 3,
                row = math.floor((vim.o.lines - 3) / 2),
                col = math.floor((vim.o.columns - 50) / 2),
                style = "minimal",
                border = "rounded",
            })

            vim.api.nvim_buf_set_lines(confirm_buf, 0, -1, false, {
                "Selected " .. #selected_files .. " files. Press:",
                "y - Confirm and proceed",
                "n - Cancel"
            })

            -- Set up confirmation keymaps
            local confirm_opts = { buffer = confirm_buf, silent = true }
            vim.keymap.set("n", "y", function()
                vim.api.nvim_win_close(confirm_win, true)
                vim.api.nvim_win_close(select_win, true)
                local content = get_selected_files_content(selected_files)
                -- Add a small delay to ensure windows are closed
                vim.defer_fn(function()
                    start_interaction_with_content(content)
                end, 50)
            end, confirm_opts)

            vim.keymap.set("n", "n", function()
                vim.api.nvim_win_close(confirm_win, true)
            end, confirm_opts)
        end, opts)

        vim.keymap.set("n", "<Esc>", function()
            vim.api.nvim_win_close(select_win, true)
        end, opts)
    end

    setup_selection_keymaps()
end

return M 
