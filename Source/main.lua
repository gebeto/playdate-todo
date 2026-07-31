import "CoreLibs/graphics"
import "CoreLibs/keyboard"

local gfx <const> = playdate.graphics

-- Layout constants
local SCREEN_W <const> = 400
local SCREEN_H <const> = 240
local HEADER_H <const> = 30
local FOOTER_H <const> = 20
local ROW_H <const> = 24
local LIST_TOP <const> = HEADER_H + 4
local MARGIN <const> = 8

local SAVE_KEY <const> = "todos"

-- State
local todos = { active = {}, completed = {} }
local currentTab = "active" -- "active" | "completed"
local selection = 1

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local function saveTodos()
    playdate.datastore.write(todos, SAVE_KEY)
end

local function loadTodos()
    local data = playdate.datastore.read(SAVE_KEY)
    if data then
        todos.active = data.active or {}
        todos.completed = data.completed or {}
    else
        todos.active = {}
        todos.completed = {}
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Returns the list for the current tab.
local function currentList()
    return todos[currentTab]
end

-- Keep the selection within the bounds of the current list (>= 1).
local function clampSelection()
    local n = #currentList()
    if selection > n then selection = n end
    if selection < 1 then selection = 1 end
end

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function addTodo(title)
    title = trim(title or "")
    if #title == 0 then return end
    table.insert(todos.active, { title = title })
    saveTodos()
end

local function completeSelected()
    local list = todos.active
    local item = list[selection]
    if not item then return end
    table.remove(list, selection)
    table.insert(todos.completed, item)
    clampSelection()
    saveTodos()
end

local function uncompleteSelected()
    local list = todos.completed
    local item = list[selection]
    if not item then return end
    table.remove(list, selection)
    table.insert(todos.active, item)
    clampSelection()
    saveTodos()
end

local function toggleSelected()
    if currentTab == "active" then
        completeSelected()
    else
        uncompleteSelected()
    end
end

local function switchTab(tab)
    if currentTab ~= tab then
        currentTab = tab
        selection = 1
        clampSelection()
    end
end

--------------------------------------------------------------------------------
-- Text entry (on-screen keyboard)
--------------------------------------------------------------------------------

local function showAddKeyboard()
    playdate.keyboard.show("")
end

playdate.keyboard.keyboardWillHideCallback = function(ok)
    if ok then
        addTodo(playdate.keyboard.text)
        switchTab("active")
        selection = #todos.active
        clampSelection()
    end
end

--------------------------------------------------------------------------------
-- System menu
--------------------------------------------------------------------------------

local function setupMenu()
    local menu = playdate.getSystemMenu()
    menu:addMenuItem("Add todo", function()
        showAddKeyboard()
    end)
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

function playdate.leftButtonDown()
    switchTab("active")
end

function playdate.rightButtonDown()
    switchTab("completed")
end

function playdate.upButtonDown()
    selection = selection - 1
    clampSelection()
end

function playdate.downButtonDown()
    selection = selection + 1
    clampSelection()
end

function playdate.AButtonDown()
    toggleSelected()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function drawHeader()
    local tabW = SCREEN_W / 2
    local labels = {
        { tab = "active", text = "Active (" .. #todos.active .. ")", x = 0 },
        { tab = "completed", text = "Completed (" .. #todos.completed .. ")", x = tabW },
    }
    for _, t in ipairs(labels) do
        if currentTab == t.tab then
            gfx.fillRect(t.x, 0, tabW, HEADER_H)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        gfx.drawTextInRect(t.text, t.x, 8, tabW, HEADER_H, nil, nil, kTextAlignment.center)
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.drawLine(0, HEADER_H, SCREEN_W, HEADER_H)
    gfx.drawLine(tabW, 0, tabW, HEADER_H)
end

local function drawFooter()
    local y = SCREEN_H - FOOTER_H
    gfx.drawLine(0, y, SCREEN_W, y)
    local action = (currentTab == "active") and "Ⓐ done" or "Ⓐ undo"
    gfx.drawTextInRect("⬅➡ tabs  ⬆⬇ move  " .. action .. "  Menu: add",
        0, y + 3, SCREEN_W, FOOTER_H, nil, nil, kTextAlignment.center)
end

local function drawList()
    local list = currentList()

    if #list == 0 then
        local msg = (currentTab == "active")
            and "No todos.\nOpen the menu to add one."
            or "No completed todos yet."
        gfx.drawTextInRect(msg, MARGIN, LIST_TOP + 40, SCREEN_W - MARGIN * 2, 60,
            nil, nil, kTextAlignment.center)
        return
    end

    local prefix = (currentTab == "completed") and "[x] " or "[ ] "
    for i, item in ipairs(list) do
        local y = LIST_TOP + (i - 1) * ROW_H
        if y + ROW_H > SCREEN_H - FOOTER_H then break end -- simple clipping

        if i == selection then
            gfx.fillRect(MARGIN - 2, y, SCREEN_W - (MARGIN - 2) * 2, ROW_H)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        gfx.drawTextInRect(prefix .. item.title, MARGIN + 4, y + 4,
            SCREEN_W - (MARGIN + 4) * 2, ROW_H, nil, "...", kTextAlignment.left)
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function playdate.update()
    gfx.clear()
    drawHeader()
    drawList()
    drawFooter()
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

local function init()
    loadTodos()
    clampSelection()
    setupMenu()
end

init()

function playdate.gameWillTerminate()
    saveTodos()
end

function playdate.deviceWillSleep()
    saveTodos()
end
