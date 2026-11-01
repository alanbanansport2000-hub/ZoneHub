-- ZoneHub Equip Repair Probe v2: single explicitly confirmed Unequip request.
-- Not affiliated with BIG Games. No delete, purchase, fuse, or trading calls.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local core = workspace:WaitForChild("__REMOTES"):WaitForChild("Core")
local gameRemotes = workspace.__REMOTES:WaitForChild("Game")
local statsRemote = core:WaitForChild("Get Other Stats")
local inventoryRemote = gameRemotes:WaitForChild("Inventory")

local old = playerGui:FindFirstChild("ZoneHub_EquipRepairProbe_v2")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ZoneHub_EquipRepairProbe_v2"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(340, 415)
frame.Position = UDim2.new(0.5, -170, 0.5, -207)
frame.BackgroundColor3 = Color3.fromRGB(26, 31, 39)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-14,0,45)
title.Position = UDim2.fromOffset(7,5)
title.BackgroundTransparency = 1
title.Text = "ZoneHub | Equip Repair v2\nОДИН запрос Unequip, без удаления"
title.TextSize = 15
title.TextColor3 = Color3.new(1,1,1)
title.Font = Enum.Font.GothamBold
title.Parent = frame

local function button(y, label)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-18,0,36)
    b.Position=UDim2.fromOffset(9,y)
    b.Text=label
    b.TextSize=14
    b.Font=Enum.Font.GothamSemibold
    b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(43,92,144)
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    return b
end
local scan=button(53,"1. Проверить сервер и выбрать ID")
local box=Instance.new("TextBox")
box.Size=UDim2.new(1,-18,0,34)
box.Position=UDim2.fromOffset(9,96)
box.PlaceholderText="ID питомца (можно изменить)"
box.Text=""
box.TextSize=16
box.TextColor3=Color3.new(1,1,1)
box.BackgroundColor3=Color3.fromRGB(52,58,69)
box.ClearTextOnFocus=false
box.Parent=frame
Instance.new("UICorner",box).CornerRadius=UDim.new(0,7)
local run=button(138,"2. Снять ОДНОГО (подтверди 2 раза)")
run.BackgroundColor3=Color3.fromRGB(140,89,47)
local recheck=button(180,"3. Повторный снимок")
local copy=button(222,"4. Копировать отчёт")
local status=Instance.new("TextLabel")
status.Size=UDim2.new(1,-18,0,135)
status.Position=UDim2.fromOffset(9,267)
status.TextWrapped=true
status.TextXAlignment=Enum.TextXAlignment.Left
status.TextYAlignment=Enum.TextYAlignment.Top
status.TextColor3=Color3.fromRGB(232,236,245)
status.TextSize=13
status.Font=Enum.Font.Code
status.BackgroundTransparency=1
status.Text="Сначала нажми 1. Никаких изменений без двойного подтверждения."
status.Parent=frame

local lines={"ZONEHUB EQUIP REPAIR PROBE v2", "Операция: Inventory:InvokeServer('Unequip', ID), строго один раз", "Удаление/Fuse/Shop/Trade: НЕТ"}
local snapshotBefore=nil
local chosen=nil
local armedID=nil
local attempted=false
local busy=false

local function log(s)
    table.insert(lines,tostring(s))
    local msg={}
    for i=math.max(1,#lines-6),#lines do table.insert(msg,lines[i]) end
    status.Text=table.concat(msg,"\n")
end
local function getSnapshot()
    local ok,raw=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,"ошибка чтения Get Other Stats: "..tostring(raw) end
    if type(raw)~="table" then return nil,"Get Other Stats не вернул таблицу" end
    local entry=raw[player.Name]
    if not entry or type(entry)~="table" or type(entry.Save)~="table" then
        return nil,"не найден Save для "..player.Name
    end
    local save=entry.Save
    if type(save.Pets)~="table" then return nil,"Save.Pets отсутствует" end
    local s={count=0,equipped=0,ids={},pets={},slots=save.PetSlots,limit=save.MaxPets}
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" and pet.id~=nil then
            local id=tostring(pet.id)
            s.count+=1
            s.ids[id]=true
            s.pets[id]={e=pet.e==true, l=tonumber(pet.l) or 0, n=pet.n}
            if pet.e==true then s.equipped+=1 end
        end
    end
    return s
end
local function choose(s)
    local selected=nil
    -- Choose the weakest equipped candidate, but never automatic mutation.
    for id,pet in pairs(s.pets) do
        if pet.e and (not selected or pet.l < s.pets[selected].l or (pet.l==s.pets[selected].l and id<selected)) then
            selected=id
        end
    end
    return selected
end
local function snapText(prefix,s)
    return string.format("%s: %d/%s, экипировано %d/%s",prefix,s.count,tostring(s.slots),s.equipped,tostring(s.limit))
end
scan.MouseButton1Click:Connect(function()
    if busy then return end
    busy=true
    local s,err=getSnapshot()
    busy=false
    if not s then log("ОШИБКА: "..err);return end
    snapshotBefore=s
    chosen=choose(s)
    armedID=nil
    if chosen then box.Text=chosen end
    log(snapText("СНИМОК",s))
    log("Предложенный слабый экипированный ID="..tostring(chosen))
    log("Запросов Unequip ещё не было")
end)
box:GetPropertyChangedSignal("Text"):Connect(function() armedID=nil end)
run.MouseButton1Click:Connect(function()
    if busy then return end
    if attempted then log("БЛОК: запрос уже отправлялся; перезайди для нового отдельного опыта");return end
    if not snapshotBefore then log("Сначала нажми 1");return end
    local id=box.Text:gsub("%s+","")
    if not id:match("^%d+$") then log("Введите числовой ID");return end
    if not snapshotBefore.pets[id] then log("ID отсутствует в снимке сервера");return end
    if not snapshotBefore.pets[id].e then log("Питомец не отмечен экипированным");return end
    if armedID~=id then
        armedID=id
        log("ПОДТВЕРЖДЕНИЕ 1/2: ID "..id..". Нажми ещё раз, чтобы отправить один Unequip")
        return
    end
    armedID=nil
    attempted=true
    busy=true
    log("ОТПРАВЛЯЮ ОДИН Unequip для ID="..id)
    local ok,result=pcall(function() return inventoryRemote:InvokeServer("Unequip",tonumber(id)) end)
    log("pcall="..tostring(ok).." | ответ="..tostring(result))
    task.wait(1)
    local s,err=getSnapshot()
    if s then
        log(snapText("ПОСЛЕ",s))
        log("ID существует="..tostring(s.ids[id]~=nil).." | e="..tostring(s.pets[id] and s.pets[id].e))
        local missing=0
        for prevID in pairs(snapshotBefore.ids) do if not s.ids[prevID] then missing+=1 end end
        log("Исчезнувших ID="..missing.." | delta экипированных="..tostring(s.equipped-snapshotBefore.equipped))
        if missing>0 then log("ВНИМАНИЕ: исчезли записи, больше не выполняй действия") end
    else log("ПОСЛЕ: ошибка "..err) end
    busy=false
end)
recheck.MouseButton1Click:Connect(function()
    if busy then return end
    busy=true
    local s,err=getSnapshot()
    busy=false
    if not s then log("ОШИБКА ПОВТОРА: "..err);return end
    log(snapText("ПОВТОР",s))
    local id=box.Text:gsub("%s+","")
    log("ID="..id.." | e="..tostring(s.pets[id] and s.pets[id].e))
end)
copy.MouseButton1Click:Connect(function()
    local report=table.concat(lines,"\n")
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,report)
        if ok then log("Отчёт скопирован") else log("Ошибка буфера обмена; текст в консоли") end
    else log("Нет setclipboard; отчёт в консоли") end
    print(report)
end)
log("Готово. Начни со снимка. ОПАСНОСТЬ: операция Unequip не подтверждена именно для этой игры.")
