-- ZoneHub | Single corrupt pet removal | 2026-11-02
-- Original Pet Simulator (2018). ONE SPECIFIC pet ID ONLY: 28522935.
-- Manual preview + two-click confirmation. NO automatic deletion on load.
-- Server data must still show l=nil and xp=-10; any mismatch ABORTS.
-- The one mutating call is: Game.Inventory:InvokeServer("Delete", 28522935).
-- WARNING: server-side deletion is irreversible; no restore operation is provided.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local TARGET_ID = 28522935
local GUI_NAME = "ZoneHub_OnlyDelete_28522935"

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 10050
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(354, 478)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(18, 25, 36)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
local edge = Instance.new("UIStroke", frame)
edge.Color = Color3.fromRGB(77, 91, 108)
edge.Thickness = 1
local scale = Instance.new("UIScale", frame)
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
scale.Scale = math.clamp(math.min(viewport.X / 370, viewport.Y / 504), 0.68, 1)

local function makeLabel(message, y, h, size, color, bold)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -22, 0, h)
    l.Position = UDim2.fromOffset(11, y)
    l.BackgroundTransparency = 1
    l.Text = message
    l.TextColor3 = color or Color3.fromRGB(231, 239, 248)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = size or 13
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = frame
    return l
end

local function makeButton(caption, y, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -22, 0, 44)
    b.Position = UDim2.fromOffset(11, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Text = caption
    b.TextSize = 13
    b.Font = Enum.Font.GothamBold
    b.TextWrapped = true
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    return b
end

makeLabel("ZONEHUB | УДАЛЕНИЕ ОДНОГО ПИТОМЦА", 8, 29, 15, nil, true)
makeLabel("Только ID 28522935 • XP=-10 • l=nil", 36, 24, 13, Color3.fromRGB(255, 193, 125), true)
makeLabel("Без торговли, скрещивания, покупки и снятия экипировки.\nУдаление навсегда. Сначала проверь данные.", 67, 52, 12)
local checkBtn = makeButton("1. ПРОВЕРИТЬ ID НА СЕРВЕРЕ", 123, Color3.fromRGB(40, 94, 157))
local deleteBtn = makeButton("2. УДАЛИТЬ ТОЛЬКО ID 28522935", 174, Color3.fromRGB(145, 58, 59))
local copyBtn = makeButton("3. КОПИРОВАТЬ ОТЧЁТ", 225, Color3.fromRGB(58, 72, 87))
local status = makeLabel("Статус: ожидание проверки.", 274, 46, 12, Color3.fromRGB(176, 197, 221), true)

local output = Instance.new("TextBox")
output.Size = UDim2.new(1, -22, 0, 143)
output.Position = UDim2.fromOffset(11, 324)
output.BackgroundColor3 = Color3.fromRGB(11, 18, 26)
output.BorderSizePixel = 0
output.TextColor3 = Color3.fromRGB(233, 237, 248)
output.Font = Enum.Font.Code
output.TextSize = 12
output.TextWrapped = true
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.MultiLine = true
output.TextEditable = false
output.ClearTextOnFocus = false
output.Parent = frame
Instance.new("UICorner", output).CornerRadius = UDim.new(0, 8)

local report = {
    "ZoneHub SinglePetDelete | ID=" .. TARGET_ID,
    "Действия только по нажатию: чтение / одно Delete.",
    "Условия защиты: ID точный, l=nil, xp=-10, не экипирован.",
}
local busy = false
local used = false
local prepared = false
local armedUntil = 0
local expectedCount = nil
local statsRemote, inventoryRemote = nil, nil

local function log(s)
    report[#report + 1] = tostring(s)
    local last = {}
    for i = math.max(1, #report - 10), #report do
        last[#last + 1] = report[i]
    end
    output.Text = table.concat(last, "\n")
    print("[ZoneHub SinglePetDelete] " .. tostring(s))
end
local function statusText(s)
    status.Text = s
    log(s)
end
local function getRemotes()
    local root = workspace:FindFirstChild("__REMOTES")
    local core = root and root:FindFirstChild("Core")
    local gameFolder = root and root:FindFirstChild("Game")
    local stats = core and core:FindFirstChild("Get Other Stats")
    local inv = gameFolder and gameFolder:FindFirstChild("Inventory")
    if not stats or not stats:IsA("RemoteFunction") then
        return nil, nil, "Не найден Core['Get Other Stats']"
    end
    if not inv or not inv:IsA("RemoteFunction") then
        return nil, nil, "Не найден Game.Inventory"
    end
    return stats, inv
end
local function snapshot()
    local s, inv, err = getRemotes()
    if not s then return nil, err end
    statsRemote, inventoryRemote = s, inv
    local ok, result = pcall(function() return s:InvokeServer() end)
    if not ok then return nil, "Чтение сервера: " .. tostring(result) end
    local entry = type(result) == "table" and result[player.Name]
    local save = type(entry) == "table" and entry.Save
    if type(save) ~= "table" or type(save.Pets) ~= "table" then
        return nil, "Сервер не вернул Save.Pets"
    end
    local count, found, equipped = 0, {}, 0
    for _, pet in pairs(save.Pets) do
        if type(pet) == "table" then
            count = count + 1
            if pet.e == true then equipped = equipped + 1 end
            if pet.id == TARGET_ID then found[#found + 1] = pet end
        end
    end
    return {count = count, found = found, equipped = equipped,
        slots = save.PetSlots, maxPets = save.MaxPets}
end
local function checkTarget(s)
    if #s.found ~= 1 then
        return false, "ОТМЕНА: ID " .. TARGET_ID .. " найден " .. #s.found .. " раз(а)."
    end
    local p = s.found[1]
    if type(p.id) ~= "number" or p.id ~= TARGET_ID then
        return false, "ОТМЕНА: ID записан неверно."
    end
    if p.l ~= nil or type(p.xp) ~= "number" or p.xp ~= -10 then
        return false, "ОТМЕНА: данные изменились (l=" .. tostring(p.l) .. ", xp=" .. tostring(p.xp) .. ")."
    end
    if p.e == true then return false, "ОТМЕНА: питомец сейчас экипирован." end
    if p.lock == true or p.locked == true or p.lk == true or p.fav == true then
        return false, "ОТМЕНА: питомец заблокирован или отмечен избранным."
    end
    return true, "Подтверждено: ID=" .. TARGET_ID .. "; type=" .. tostring(p.n)
        .. "; l=nil; xp=-10; equipped=false; всего=" .. s.count
        .. "; экипировано=" .. s.equipped .. "."
end
local function resetConfirmation()
    prepared = false
    armedUntil = 0
    deleteBtn.Text = "2. УДАЛИТЬ ТОЛЬКО ID 28522935"
end

checkBtn.MouseButton1Click:Connect(function()
    if busy or used then return end
    resetConfirmation()
    busy = true
    statusText("Читаю данные сервера...")
    task.spawn(function()
        local snap, err = snapshot()
        if not snap then
            statusText("Проверка не удалась: " .. tostring(err))
        else
            local valid, message = checkTarget(snap)
            log(message)
            if valid then
                expectedCount = snap.count
                prepared = true
                statusText("ГОТОВО: нажми красную кнопку ДВА РАЗА, чтобы удалить один ID.")
            else
                statusText("Ничего не удалено. Защитная проверка не пройдена.")
            end
        end
        busy = false
    end)
end)

deleteBtn.MouseButton1Click:Connect(function()
    if busy or used then return end
    if not prepared then
        statusText("Сначала нажми 1 и дождись успешной проверки!")
        return
    end
    if os.clock() > armedUntil then
        armedUntil = os.clock() + 20
        deleteBtn.Text = "ПОДТВЕРЖДАЮ УДАЛЕНИЕ 28522935 (20 СЕК)"
        statusText("ВНИМАНИЕ: необратимо! Второе нажатие удалит ID 28522935.")
        return
    end

    -- Disarm and prevent any duplicate submissions BEFORE doing network work.
    prepared = false
    armedUntil = 0
    busy = true
    used = true
    deleteBtn.Text = "ЗАПРОС ОТПРАВЛЯЕТСЯ ОДИН РАЗ"
    task.spawn(function()
        local before, err = snapshot()
        if not before then
            statusText("ОТМЕНА: повторное чтение не удалось: " .. tostring(err))
            busy = false
            return
        end
        local valid, message = checkTarget(before)
        if not valid then
            statusText(message .. " Запрос Delete НЕ отправлен.")
            busy = false
            return
        end
        -- Do not delete if inventory count changed between preview and confirmation.
        if before.count ~= expectedCount then
            statusText("ОТМЕНА: общее число питомцев изменилось с " ..
                tostring(expectedCount) .. " на " .. tostring(before.count) .. ".")
            busy = false
            return
        end
        log("ОДНА КОМАНДА: Game.Inventory:InvokeServer('Delete', " .. TARGET_ID .. ")")
        local ok, response = pcall(function()
            return inventoryRemote:InvokeServer("Delete", TARGET_ID)
        end)
        log("Ответ Delete: ok=" .. tostring(ok) .. ", response=" .. tostring(response))
        local final, lastErr = nil, nil
        for i = 1, 6 do
            task.wait(i == 1 and 0.35 or 0.65)
            local candidate, readErr = snapshot()
            if candidate then
                final = candidate
                if #candidate.found == 0 then break end
            else
                lastErr = readErr
            end
        end
        if final and #final.found == 0 then
            statusText("ПОДТВЕРЖДЕНО: ID 28522935 удалён. Питомцев " ..
                tostring(before.count) .. " -> " .. tostring(final.count) ..
                ". Экипировано=" .. tostring(final.equipped) .. ". Перезайди и проверь UI.")
        elseif final then
            statusText("НЕ ПОДТВЕРЖДЕНО: ID всё ещё найден. Питомцев=" ..
                tostring(final.count) .. ". Автоповтора НЕ БУДЕТ.")
        else
            statusText("НЕИЗВЕСТНЫЙ РЕЗУЛЬТАТ: сервер не ответил на проверку: " ..
                tostring(lastErr) .. ". Повторно Delete не вызывается.")
        end
        busy = false
    end)
end)

copyBtn.MouseButton1Click:Connect(function()
    local text = table.concat(report, "\n")
    if type(setclipboard) == "function" then
        local ok = pcall(function() setclipboard(text) end)
        if ok then log("Отчёт скопирован.") else log("Не удалось скопировать; выдели текст отчёта.") end
    else
        log("setclipboard недоступен; выдели текст в поле отчёта.")
    end
end)

log("Скрипт загружен. НИЧЕГО не удалено. Нажми '1. ПРОВЕРИТЬ'.")
