-- Pet Simulator (2018) | ZoneHub 1.4 ADAPTIVE AUTO FARM
-- Static, standalone GUI. No HttpGet, loadstring, or external dependencies.
-- IMPORTANT: Mine/PetMovement packets came from prior in-game observations;
-- their current server acceptance cannot be guaranteed without testing.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("ZoneHub_PetSim")
if old then old:Destroy() end
local previous = getgenv and getgenv().ZoneHubShutdown
if type(previous) == "function" then pcall(previous) end
local alive = true
local farming = false
local connections = {}
local activeCoins = {}
local logLines = {}
local stats = {attempts=0, movement=0, coins=0, failures=0}
local testBusy = false
local lastReport = "Тестов пока нет"
local captureState = nil
local captureInfo = nil
local learned = {} -- populated only by observing manual successful Mine/PetMovement calls
local learnedValidated = {} -- successful HP decrease in a controlled learning test
local learnedTarget = {}
local startAutoFarm -- forward declaration: button bound before auto-farm controller
local farmSession = 0
local reservedCoins = {}
local farmStats = {damage=0, completed=0, rejected=0, live=0}

local cfg = {
    minX = -3218.733, maxX = -2832.849,
    minZ = -1747.956, maxZ = -1468.381,
    groundY = 144.810,
    ids = {"15883528", "25214651", "92565120", "95608754"},
    idAsNumber = true,
    mineArg = 3720891.577866316,
    interval = .42,
    mode = "Near",
}
local function now() return os.date("%H:%M:%S") end
local statusText
local function log(message, bad)
    table.insert(logLines, 1, (bad and "! " or "• ") .. now() .. "  " .. tostring(message))
    while #logLines > 7 do table.remove(logLines) end
    if statusText then statusText.Text = table.concat(logLines, "\n") end
    if bad then stats.failures += 1 end
end
local function partOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end
local function root()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function gameNodes()
    local things = workspace:FindFirstChild("__THINGS")
    local coins = things and things:FindFirstChild("Coins")
    local remotes = workspace:FindFirstChild("__REMOTES")
    local node = remotes and remotes:FindFirstChild("Game")
    local coinRemote = node and node:FindFirstChild("Coins")
    local petRemote = node and node:FindFirstChild("Pets")
    if coinRemote and not coinRemote:IsA("RemoteEvent") then coinRemote = nil end
    if petRemote and not petRemote:IsA("RemoteEvent") then petRemote = nil end
    return coins, coinRemote, petRemote
end
local function inside(pos)
    return pos.X >= cfg.minX and pos.X <= cfg.maxX and pos.Z >= cfg.minZ and pos.Z <= cfg.maxZ
end
local function coinHealth(obj)
    for _, label in ipairs({"Health", "HP", "Hp", "health"}) do
        local inst = obj:FindFirstChild(label, true)
        if inst and (inst:IsA("NumberValue") or inst:IsA("IntValue")) then
            return inst.Value
        end
        local attr = obj:GetAttribute(label)
        if type(attr) == "number" then return attr end
    end
    return nil
end
local function scan()
    local folder = gameNodes()
    local good, total = {}, 0
    if not folder then return good, total end
    for _, coin in ipairs(folder:GetChildren()) do
        total += 1
        local p = partOf(coin)
        if p and inside(p.Position) and (coinHealth(coin) or 1) > 0 then
            good[#good+1] = {object=coin, pos=p.Position, hp=coinHealth(coin)}
        end
    end
    return good, total
end
local function sortCoins(coins)
    local r = root()
    local origin = r and r.Position or Vector3.new((cfg.minX+cfg.maxX)/2, cfg.groundY, (cfg.minZ+cfg.maxZ)/2)
    table.sort(coins, function(a,b)
        if cfg.mode == "LowHP" and a.hp and b.hp then return a.hp < b.hp end
        if cfg.mode == "HighHP" and a.hp and b.hp then return a.hp > b.hp end
        return (a.pos-origin).Magnitude < (b.pos-origin).Magnitude
    end)
end
local function castId(s) return cfg.idAsNumber and tonumber(s) or tostring(s) end
local function stopMine()
    -- IMPORTANT: stop only local sending. Calling remote StopMine previously
    -- coincided with an unexpected UI disappearance. Never send it here.
    farming = false
    farmSession += 1
    table.clear(reservedCoins)
    table.clear(activeCoins)
end
local function tryMine(coins, single)
    local _, mineRemote, petRemote = gameNodes()
    if not mineRemote then return false, "Нет workspace.__REMOTES.Game.Coins (RemoteEvent)" end
    if not petRemote then return false, "Нет workspace.__REMOTES.Game.Pets (RemoteEvent)" end
    if #cfg.ids == 0 then return false, "Нет ID питомцев" end
    if #coins == 0 then return false, "В зоне нет обнаруженных монет" end
    sortCoins(coins)
    local limit = math.min(#coins, #cfg.ids)
    local sent = 0
    local assigned = {}
    for i=1,limit do
        local info = coins[i]
        local petId = castId(cfg.ids[i])
        if petId then
            local coinId = info.object.Name
            local pos = info.pos
            local ok, err = pcall(function()
                -- The Mine and PetMovement argument structure was observed in this user's game.
                mineRemote:FireServer("Mine", coinId, cfg.mineArg, petId)
                petRemote:FireServer({{"PetMovement", player, petId, CFrame.new(pos + Vector3.new(0,2,0)), false, 1}})
            end)
            if ok then
                assigned[coinId] = true
                stats.attempts += 1
                stats.movement += 1
                sent += 1
            else
                log("Ошибка отправки: " .. tostring(err):sub(1,70), true)
            end
        end
    end
    -- No automatic remote StopMine: its server behavior isn't verified.
    activeCoins = assigned
    if sent == 0 then return false, "Ни один запрос не отправлен" end
    return true, "Отправлено " .. sent .. " пар команд (результат проверяй в игре)"
end

-- UI primitives
local C = {
    bg=Color3.fromRGB(13,16,27), panel=Color3.fromRGB(22,27,42),
    panel2=Color3.fromRGB(30,36,54), line=Color3.fromRGB(48,56,77),
    white=Color3.fromRGB(239,245,255), dim=Color3.fromRGB(155,169,193),
    blue=Color3.fromRGB(92,150,255), teal=Color3.fromRGB(67,224,192),
    red=Color3.fromRGB(255,107,126), gold=Color3.fromRGB(255,205,121)
}
local function rounded(obj, radius)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,radius or 12) c.Parent=obj
end
local function stroke(obj, color)
    local s=Instance.new("UIStroke") s.Color=color or C.line s.Thickness=1 s.Parent=obj
end
local function pad(obj, n)
    local p=Instance.new("UIPadding") p.PaddingTop=UDim.new(0,n) p.PaddingBottom=UDim.new(0,n)
    p.PaddingLeft=UDim.new(0,n) p.PaddingRight=UDim.new(0,n) p.Parent=obj
end
local function newFrame(parent, height, bg)
    local f=Instance.new("Frame") f.BackgroundColor3=bg or C.panel f.BorderSizePixel=0
    f.Size=UDim2.new(1,0,0,height) f.Parent=parent rounded(f,13)
    return f
end
local function label(parent, text, y, height, size, color, bold)
    local t=Instance.new("TextLabel") t.BackgroundTransparency=1 t.BorderSizePixel=0
    t.Position=UDim2.fromOffset(12,y) t.Size=UDim2.new(1,-24,0,height)
    t.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    t.Text=text t.TextColor3=color or C.white t.TextSize=size or 13
    t.TextWrapped=true t.TextXAlignment=Enum.TextXAlignment.Left
    t.Parent=parent
    return t
end
local function button(parent, text, y, action, color, width, x)
    local b=Instance.new("TextButton") b.AutoButtonColor=false b.BorderSizePixel=0
    b.BackgroundColor3=color or C.panel2 b.Text=text b.TextColor3=C.white
    b.TextSize=13 b.Font=Enum.Font.GothamSemibold
    b.Position=UDim2.new(x or 0, (x and 0 or 12), 0, y)
    b.Size=UDim2.new(width or 1, width and -7 or -24, 0, 38)
    b.Parent=parent rounded(b,10)
    b.MouseButton1Click:Connect(function()
        if not alive then return end
        local ok,err=pcall(action)
        if not ok then log("UI: " .. tostring(err):sub(1,90),true) end
    end)
    b.MouseEnter:Connect(function() if alive then TweenService:Create(b,TweenInfo.new(.15),{BackgroundColor3=C.blue}):Play() end end)
    b.MouseLeave:Connect(function() if alive then TweenService:Create(b,TweenInfo.new(.15),{BackgroundColor3=color or C.panel2}):Play() end end)
    return b
end
local function edit(parent, heading, value, y, onSubmit, placeholder)
    label(parent,heading,y,18,12,C.dim)
    local box=Instance.new("TextBox")
    box.Size=UDim2.new(1,-24,0,38) box.Position=UDim2.fromOffset(12,y+22)
    box.BackgroundColor3=C.panel2 box.TextColor3=C.white box.PlaceholderColor3=C.dim
    box.ClearTextOnFocus=false box.Font=Enum.Font.Code box.TextSize=13
    box.TextXAlignment=Enum.TextXAlignment.Left
    box.Text=tostring(value) box.PlaceholderText=placeholder or ""
    box.Parent=parent rounded(box,9) pad(box,10)
    box.FocusLost:Connect(function()
        if not alive then return end
        local ok,err=pcall(onSubmit,box.Text)
        if not ok then log(tostring(err),true) end
    end)
    return box
end
local function number(text, fallback)
    return tonumber((tostring(text):gsub(",","."))) or fallback
end
local function isValidBounds()
    return cfg.minX < cfg.maxX and cfg.minZ < cfg.maxZ
end
local gui=Instance.new("ScreenGui") gui.Name="ZoneHub_PetSim" gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true gui.DisplayOrder=250 gui.Parent=pg
local screen=Instance.new("Frame") screen.BackgroundColor3=C.bg screen.BorderSizePixel=0
screen.AnchorPoint=Vector2.new(.5,.5) screen.Position=UDim2.fromScale(.5,.5)
screen.Size=UDim2.fromOffset(385,555) screen.Parent=gui rounded(screen,18) stroke(screen,C.line)
local scale=Instance.new("UIScale") scale.Scale=.94 scale.Parent=screen
local function updateScale()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    scale.Scale=math.min(.96, (v.X-22)/400, (v.Y-24)/575)
end
updateScale()
connections[#connections+1]=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
local header=Instance.new("Frame") header.BackgroundColor3=C.panel header.BorderSizePixel=0
header.Size=UDim2.new(1,0,0,76) header.Parent=screen rounded(header,18)
label(header,"✦  ZONE HUB",12,27,21,C.white,true)
label(header,"PET SIMULATOR • LOCAL TOOL",43,17,10,C.dim,true)
local hide=button(header,"—",17,function() screen.Visible=false; gui.Float.Visible=true end,C.panel2,.13,.83)
hide.Size=UDim2.new(.13,-7,0,35)
-- Drag with mouse or touch on the header, without interfering with tab buttons.
local dragging, dragStart, startPos, dragInput
connections[#connections+1]=header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true dragStart=input.Position startPos=screen.Position dragInput=input
    end
end)
connections[#connections+1]=header.InputEnded:Connect(function(input)
    if input==dragInput then dragging=false end
end)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragStart or not startPos then return end
    if input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput then
        local d=input.Position-dragStart
        local sc=math.max(scale.Scale,.3)
        screen.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X/sc,
                                  startPos.Y.Scale,startPos.Y.Offset+d.Y/sc)
    end
end)
local dot=Instance.new("Frame") dot.Size=UDim2.fromOffset(7,7) dot.Position=UDim2.new(1,-16,0,58)
dot.BackgroundColor3=C.teal dot.BorderSizePixel=0 dot.Parent=header rounded(dot,10)
local tabs=Instance.new("Frame") tabs.BackgroundTransparency=1 tabs.Size=UDim2.new(1,-20,0,42)
tabs.Position=UDim2.fromOffset(10,82) tabs.Parent=screen
local pages={}
local tabButtons={}
local tabNames={"Фарм","Питомцы","Точки","Диагностика"}
local function showTab(name)
    for tab,p in pairs(pages) do p.Visible=(tab==name) end
    for tab,b in pairs(tabButtons) do
        TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=tab==name and C.blue or C.panel2}):Play()
    end
end
for i,name in ipairs(tabNames) do
    local b=Instance.new("TextButton") b.AutoButtonColor=false b.Text=name
    b.Font=Enum.Font.GothamSemibold b.TextSize=11 b.TextColor3=C.white
    b.BackgroundColor3=C.panel2 b.BorderSizePixel=0 b.Size=UDim2.new(.25,-5,1,0)
    b.Position=UDim2.new((i-1)*.25,2,0,0) b.Parent=tabs rounded(b,9)
    b.MouseButton1Click:Connect(function() showTab(name) end)
    tabButtons[name]=b
    local scroll=Instance.new("ScrollingFrame") scroll.Name=name
    scroll.Position=UDim2.fromOffset(10,130) scroll.Size=UDim2.new(1,-20,1,-198)
    scroll.BackgroundTransparency=1 scroll.BorderSizePixel=0
    scroll.ScrollBarThickness=3 scroll.ScrollBarImageColor3=C.blue
    scroll.CanvasSize=UDim2.fromOffset(0,0) scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
    scroll.Parent=screen
    local layout=Instance.new("UIListLayout") layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Padding=UDim.new(0,9) layout.Parent=scroll
    pages[name]=scroll
end
local footer=Instance.new("Frame") footer.BackgroundColor3=C.panel footer.BorderSizePixel=0
footer.Position=UDim2.new(0,10,1,-62) footer.Size=UDim2.new(1,-20,0,52) footer.Parent=screen rounded(footer,11)
statusText=label(footer,"Готово к проверке",6,42,11,C.dim)
statusText.TextYAlignment=Enum.TextYAlignment.Top
local floating=Instance.new("TextButton") floating.Name="Float" floating.Visible=false
floating.AnchorPoint=Vector2.new(1,.5) floating.Position=UDim2.new(1,-12,.52,0)
floating.Size=UDim2.fromOffset(60,52) floating.Text="✦ HUB" floating.Font=Enum.Font.GothamBold
floating.TextSize=13 floating.TextColor3=C.white floating.BackgroundColor3=C.blue
floating.Parent=gui rounded(floating,14) stroke(floating,C.line)
floating.MouseButton1Click:Connect(function() screen.Visible=true floating.Visible=false end)

-- Tab 1 | Farm
local farm=pages["Фарм"]
local summary=newFrame(farm,92)
label(summary,"Фарм в заданной зоне",10,23,16,C.white,true)
local counter=label(summary,"Проверка монет...",36,20,12,C.dim)
local operating=label(summary,"● ОСТАНОВЛЕН",61,18,11,C.red,true)
local control=newFrame(farm,100)
local start=button(control,"▶  ЗАПУСТИТЬ",12,function()
    if farming then stopMine() log("Фарм остановлен. Окно остаётся открытым") return end
    if not isValidBounds() then log("Неправильные границы зоны",true) return end
    local cs, r, pr=gameNodes()
    if not cs or not r or not pr then log("Нет монет или нужных RemoteEvent",true) return end
    if not startAutoFarm then log("Модуль фарма ещё не готов",true) return end
    startAutoFarm()
end,C.blue)
local once=button(control,"Однократный тест Mine",56,function()
    log("Разовый подтверждённый тест: Диагностика → 2. Один тест с записанными аргументами")
end,C.panel2)
local choose=newFrame(farm,105)
label(choose,"Приоритет объектов",9,19,13,C.white,true)
local modes={{"Ближайшие","Near"},{"Меньше HP","LowHP"},{"Больше HP","HighHP"}}
for i,v in ipairs(modes) do
    local b=button(choose,v[1],38,function() cfg.mode=v[2] log("Приоритет: "..v[1]) end,C.panel2,.333,(i-1)*.333)
    b.Position=UDim2.new((i-1)*.333,8,0,39) b.Size=UDim2.new(.333,-11,0,37)
    b.TextSize=10
end
local params=newFrame(farm,158)
edit(params,"Интервал команд (сек.)",cfg.interval,10,function(s)
    cfg.interval=math.clamp(number(s,cfg.interval),.40,5)
    log("Интервал: "..cfg.interval.." с")
end)
label(params,"Автофарм использует только записанные аргументы Mine, порядок Movement → Mine и подтверждение по HP. 0.42 с — интервал из ручной добычи; рекомендуем не уменьшать.",77,65,12,C.dim)
local zone=newFrame(farm,294)
label(zone,"Границы прямоугольника",9,20,14,C.white,true)
label(zone,"Фильтрация по X/Z • высота не влияет",31,22,11,C.dim)
local zFields={
    {"minX","X MIN",61},{"maxX","X MAX",114},{"minZ","Z MIN",167},{"maxZ","Z MAX",220}
}
for _,e in ipairs(zFields) do
    local key,t,y=e[1],e[2],e[3]
    local box=edit(zone,t,cfg[key],y,function(s)
        cfg[key]=number(s,cfg[key])
        if not isValidBounds() then log("Min должен быть меньше Max",true) end
    end)
    box.Size=UDim2.new(1,-24,0,28)
    box.Position=UDim2.fromOffset(12,y+19)
end

-- Tab 2 | Pets
local pets=pages["Питомцы"]
local pHead=newFrame(pets,90)
label(pHead,"4 питомца из твоих логов",12,25,15,C.white,true)
label(pHead,"ID можно менять. Скрипт не экипирует питомцев — только отправляет команды добычи.",37,43,11,C.dim)
local pEdit=newFrame(pets,116)
local petInput=edit(pEdit,"ID через запятую",table.concat(cfg.ids,", "),11,function(s)
    local arr={}
    for id in tostring(s):gmatch("[^,%s;]+") do
        if #arr<20 then arr[#arr+1]=id end
    end
    if #arr==0 then log("Введи хотя бы один ID",true) return end
    cfg.ids=arr log("ID питомцев: "..#arr)
end)
petInput.TextSize=11
label(pEdit,"Это идентификаторы экземпляров питомцев, а не названия пород.",79,26,10,C.dim)
local pType=newFrame(pets,105)
label(pType,"Тип ID при вызове RemoteEvent",12,22,13,C.white,true)
local toggle -- Lua requires forward declaration so callback captures this local
 toggle=button(pType,"Тип ID: ЧИСЛО",42,function()
    cfg.idAsNumber=not cfg.idAsNumber
    toggle.Text=cfg.idAsNumber and "Тип ID: ЧИСЛО" or "Тип ID: СТРОКА"
    toggle.BackgroundColor3=cfg.idAsNumber and C.blue or C.panel2
    log("Тип ID действительно установлен: "..(cfg.idAsNumber and "ЧИСЛО" or "СТРОКА"))
end,C.panel2)
local pInfo=newFrame(pets,143)
label(pInfo,"Важно",12,21,15,C.gold,true)
label(pInfo,"Список IDs собран по предыдущему тестированию. Игра должна иметь этих питомцев в твоём инвентаре. Доказательством работы считается движение питомцев и снижение HP монеты, а не успешный FireServer.",42,92,12,C.dim)

-- Tab 3 | Teleport
local point=pages["Точки"]
local tHead=newFrame(point,72)
label(tHead,"Локальный телепорт",10,23,15,C.white,true)
label(tHead,"Может откатываться сервером. Миры не разблокирует.",33,25,11,C.dim)
local saved
local function teleport(pos)
    local r=root()
    if not r then log("Персонаж не появился",true) return end
    r.CFrame=CFrame.new(pos)
    log(string.format("Переход: %.1f / %.1f / %.1f",pos.X,pos.Y,pos.Z))
end
local spots=newFrame(point,178)
button(spots,"Центр зоны",12,function()
    teleport(Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY+4,(cfg.minZ+cfg.maxZ)/2))
end,C.blue)
button(spots,"Сохранить мою позицию",56,function()
    local r=root()
    if not r then log("Персонаж не найден",true) return end
    saved=r.CFrame log("Позиция сохранена")
end,C.panel2)
button(spots,"Вернуться на сохранённую точку",101,function()
    if saved then teleport(saved.Position) else log("Сначала сохрани точку",true) end
end,C.panel2)
local coords=newFrame(point,269)
label(coords,"Свои координаты",10,26,14,C.white,true)
local cur=root()
local xInp=edit(coords,"X",cur and math.floor(cur.Position.X) or 0,42,function() end)
local yInp=edit(coords,"Y",cur and math.floor(cur.Position.Y) or cfg.groundY,104,function() end)
local zInp=edit(coords,"Z",cur and math.floor(cur.Position.Z) or 0,166,function() end)
button(coords,"Телепорт по координатам",225,function()
    local x,y,z=number(xInp.Text),number(yInp.Text),number(zInp.Text)
    if not x or not y or not z then log("Введи три числа",true) return end
    teleport(Vector3.new(x,y,z))
end,C.blue)

-- Tab 4 | Diagnostics
local diag=pages["Диагностика"]
local dHead=newFrame(diag,93)
label(dHead,"Диагностика игры",9,24,15,C.white,true)
local dSummary=label(dHead,"Ещё не проверено",34,50,12,C.dim)
local dBtns=newFrame(diag,110)
button(dBtns,"Проверить монеты и события",12,function()
    local found,total=scan()
    local folder,r,p=gameNodes()
    dSummary.Text=string.format("Всего: %d  |  В зоне: %d\nCoins: %s  |  Pets: %s",total,#found,r and "ДА" or "НЕТ",p and "ДА" or "НЕТ")
    log("Проверка выполнена; см. диагностическую сводку")
end,C.blue)
button(dBtns,"■  Остановить локальный фарм (без StopMine)",57,function()
    stopMine()
    log("Локальный фарм остановлен. Окно остаётся открытым")
end,C.panel2)
local dStats=newFrame(diag,90)
local statsLabel=label(dStats,"Отправленных Mine: 0\nОтправленных PetMovement: 0",14,60,13,C.white)
-- Diagnostic tests: restricted to ONE candidate coin and ONE pet per click.
-- No unverified StopMine calls, no auto-spam, no removal of the UI.
local testing = newFrame(diag, 338)
label(testing,"Старые диагностические тесты (отключены)",9,26,13,C.gold,true)
label(testing,"Их параметры оказались недостоверными. Новый тест обучения находится ниже, после записи ручной добычи.",38,46,11,C.dim)
local testResult = label(testing,"Проверка ещё не проводилась",88,67,11,C.white)
local function testOne(kind)
    if testBusy then log("Предыдущий тест ещё анализируется",true) return end
    local coins = scan()
    if #coins == 0 then log("Для теста нет монет в зоне",true) return end
    local folder, mineRemote, petRemote = gameNodes()
    if not mineRemote or not petRemote then log("События Coins / Pets не найдены",true) return end
    if not cfg.ids[1] then log("ID питомца не задан",true) return end
    sortCoins(coins)
    local picked=coins[1]
    local c=picked.object
    local id=castId(cfg.ids[1])
    local hpBefore=coinHealth(c)
    local name=c.Name
    local info="Монета: "..name.." | ID: "..tostring(id).." ("..type(id)..")"
    testBusy=true
    testResult.Text=info.."\nHP до: "..tostring(hpBefore).."; отправляю "..kind.."..."
    local ok,err=pcall(function()
        if kind=="Mine" then
            mineRemote:FireServer("Mine",name,cfg.mineArg,id)
            stats.attempts+=1
        elseif kind=="Movement" then
            petRemote:FireServer({{"PetMovement", player, id, CFrame.new(picked.pos+Vector3.new(0,2,0)), false, 1}})
            stats.movement+=1
        elseif kind=="Both" then
            mineRemote:FireServer("Mine",name,cfg.mineArg,id)
            stats.attempts+=1
            petRemote:FireServer({{"PetMovement", player, id, CFrame.new(picked.pos+Vector3.new(0,2,0)), false, 1}})
            stats.movement+=1
        end
    end)
    if not ok then
        testBusy=false
        testResult.Text="Ошибка отправки: "..tostring(err)
        log("Ошибка теста "..kind..": "..tostring(err),true)
        return
    end
    log("Тест "..kind.." отправлен. Замер HP через 3 с")
    task.delay(3,function()
        testBusy=false
        if not alive then return end
        local after=coinHealth(c)
        local delta=(hpBefore and after) and (hpBefore-after) or nil
        local verdict
        if delta and delta>0 then verdict="HP СНИЗИЛСЯ на "..tostring(delta)
        elseif delta and delta==0 then verdict="HP НЕ изменился (серверный приём не подтверждён)"
        elseif not c.Parent then verdict="Объект исчез: возможно добыт или выгружен"
        else verdict="HP не виден в клиентских значениях; проверь визуально" end
        lastReport=info.."\nТест: "..kind.." | HP: "..tostring(hpBefore).." -> "..tostring(after).."\n"..verdict
        testResult.Text=lastReport
        log("Тест "..kind..": "..verdict)
    end)
end
button(testing,"1. Старый тест Mine (не рекомендуется)",163,function() log("Для диагностики используй обученный тест ниже",true) end,C.panel2)
button(testing,"2. Старый тест Movement",207,function() log("Для диагностики используй обученный тест ниже",true) end,C.panel2)
button(testing,"3. Старый тест Both",251,function() log("Для диагностики используй обученный тест ниже",true) end,C.panel2)
button(testing,"Скопировать последний отчёт",295,function()
    local textReport=lastReport.."\nCoin Remote: workspace.__REMOTES.Game.Coins; Pet Remote: workspace.__REMOTES.Game.Pets".."\nMineArg="..tostring(cfg.mineArg).."; idAsNumber="..tostring(cfg.idAsNumber)
    if type(setclipboard)=="function" then
        local ok,err=pcall(setclipboard,textReport)
        if ok then log("Отчёт скопирован") else log("Не удалось копировать: "..tostring(err),true) end
    else
        log("В Delta нет setclipboard — сделай скриншот",true)
    end
end,C.panel2)
-- Manual-capture diagnostic: observes only the two Pet Simulator game remotes.
-- Does not send any command; the user manually clicks a coin while recording.
local capturePanel = newFrame(diag, 366)
label(capturePanel,"Запись успешной ручной добычи",10,24,14,C.gold,true)
label(capturePanel,"1. Включи запись. 2. В игре вручную нажми на монету и дождись добычи. 3. Останови и скопируй отчёт.",38,62,11,C.dim)
local captureStatus=label(capturePanel,"Запись выключена. Серверные вызовы не перехватываются.",108,57,12,C.white)
local env = (type(getgenv)=="function" and getgenv()) or nil
-- Persistent monitor prevents stacking duplicate __namecall hooks on each GUI reload.
if env then
    if type(env.__ZoneHubManualCapture)~="table" then
        env.__ZoneHubManualCapture={recording=false,hooked=false,lines={},coins=nil,pets=nil,error=nil}
    end
    captureState=env.__ZoneHubManualCapture
else
    captureState={recording=false,hooked=false,lines={},coins=nil,pets=nil,error=nil}
end
local function shorten(s,limit)
    s=tostring(s)
    if #s>limit then return s:sub(1,limit).."…" end
    return s
end
local function printArgument(v,level,seen)
    level=level or 0
    seen=seen or {}
    local t=typeof(v)
    if t=="string" then return string.format("%q",shorten(v,380)) end
    if t=="number" then return string.format("%.17g",v) end
    if t=="boolean" or t=="nil" then return tostring(v) end
    if t=="Instance" then
        local ok,full=pcall(function()return v:GetFullName()end)
        return t.."("..shorten(ok and full or v.Name,250)..")"
    end
    if t=="Vector3" then return string.format("Vector3(%.6f, %.6f, %.6f)",v.X,v.Y,v.Z) end
    if t=="CFrame" then
        local components={v:GetComponents()}
        local strings={}
        for _,x in ipairs(components) do strings[#strings+1]=string.format("%.7f",x) end
        return "CFrame("..table.concat(strings,", ")..")"
    end
    if t=="table" then
        if seen[v] then return "{<цикл>}" end
        if level>=4 then return "{... глубина >4}" end
        seen[v]=true
        local out={}
        local n=0
        for k,val in pairs(v) do
            n+=1
            if n>45 then out[#out+1]="... ещё элементы" break end
            out[#out+1]="["..printArgument(k,level+1,seen).."]="..printArgument(val,level+1,seen)
        end
        seen[v]=nil
        return "{"..table.concat(out,", ").."}"
    end
    return t.."("..shorten(v,250)..")"
end
local function captureReport()
    local lines=captureState.lines or {}
    local out={"ZoneHub 1.3 | Ручная добыча | События Coins/Pets", "Записано событий: "..tostring(#lines)}
    for i,event in ipairs(lines) do
        out[#out+1]=string.format("\n[%d] %s:%s | %s | аргументов: %d", i,event.remote,event.method,event.clock,event.args.n)
        for n=1,event.args.n do
            local val=event.args[n]
            local ok,printed=pcall(printArgument,val,0,{})
            out[#out+1]=string.format("  #%d <%s> = %s",n,typeof(val),ok and printed or "ошибка форматирования")
        end
    end
    if #lines==0 then out[#out+1]="Вызовы не обнаружены. Возможно, Delta не поддерживает перехват или игра использует другой способ отправки." end
    return table.concat(out,"\n")
end
local function installCaptureHook()
    if captureState.hooked then return true end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
        return false,"В этой версии Delta нет hookmetamethod / getnamecallmethod"
    end
    local newClosure = type(newcclosure)=="function" and newcclosure or function(f)return f end
    local old
    local ok,err=pcall(function()
        old=hookmetamethod(game,"__namecall",newClosure(function(self,...)
            -- Keep the hook lightweight; never do UI work, network calls or logging inside it.
            if captureState.recording and (self==captureState.coins or self==captureState.pets) then
                local method=getnamecallmethod()
                if method=="FireServer" or method=="InvokeServer" then
                    local args=table.pack(...)
                    pcall(function()
                        if #captureState.lines<80 then
                            captureState.lines[#captureState.lines+1]={remote=self.Name,method=method,args=args,clock=tostring(os.clock())}
                        end
                    end)
                end
            end
            return old(self,...)
        end))
    end)
    if not ok then return false,tostring(err) end
    captureState.hooked=true
    return true
end
button(capturePanel,"● НАЧАТЬ ЗАПИСЬ РУЧНОЙ ДОБЫЧИ",172,function()
    local _,coins,pets=gameNodes()
    if not coins or not pets then log("Не найдены события Coins и Pets",true) return end
    local ok,err=installCaptureHook()
    if not ok then captureStatus.Text="Ошибка установки записи: "..tostring(err);log(err,true);return end
    captureState.coins=coins captureState.pets=pets
    captureState.lines={} captureState.recording=true
    captureStatus.Text="ЗАПИСЬ ВКЛЮЧЕНА. Сверни окно кнопкой — и нажми монету ВРУЧНУЮ."
    log("Запись включена. Теперь нажми на монету вручную")
end,C.blue)
button(capturePanel,"■ ОСТАНОВИТЬ ЗАПИСЬ (окно останется)",218,function()
    captureState.recording=false
    local n=#captureState.lines
    captureStatus.Text="Запись остановлена. Событий: "..n..". Нажми «Скопировать отчёт»."
    log("Запись остановлена, событий: "..n)
end,C.panel2)
button(capturePanel,"Скопировать отчёт ручной добычи",264,function()
    captureState.recording=false
    local report=captureReport()
    if type(setclipboard)=="function" then
        local ok,err=pcall(setclipboard,report)
        if ok then log("Отчёт ("..#captureState.lines.." событий) скопирован") else log("Ошибка копирования: "..tostring(err),true) end
    else
        captureStatus.Text="setclipboard недоступен. Событий: "..#captureState.lines
        log("Копирование недоступно; нужен снимок экрана",true)
    end
end,C.panel2)
label(capturePanel,"Записываются только Coins и Pets из workspace.__REMOTES.Game; максимум 80 вызовов. Запись отключается при повторном запуске ZoneHub.",310,45,10,C.dim)
if captureState then captureState.recording=false end

-- Learner interprets actual manual activity: movement FIRST, then repeating Mine packets.
-- It does not guess missing IDs or invent damage; for each pet it retains observed samples.
local trainingPanel=newFrame(diag,430)
label(trainingPanel,"Обучение по ручной добыче",10,24,14,C.gold,true)
label(trainingPanel,"У тебя уже есть захваченные данные двух питомцев. Нажми «Загрузить отчёт», затем «Тест». Для остальных ID можно дополнительно записать ручную добычу.",39,70,11,C.dim)
local learnedText=label(trainingPanel,"Обученных питомцев: 0/4. Нажми «Загрузить отчёт».",114,110,12,C.white)
local reportText="Обучение пока не проводилось"
local function examineCapture()
    local remotes=captureState.lines or {}
    local temp={}
    local pending={}
    local mineIds={}
    local coinFolder=gameNodes()
    for _,event in ipairs(remotes) do
        if event.remote=="Pets" and event.method=="FireServer" then
            local a=event.args[1]
            if typeof(a)=="table" then
                for _,mv in pairs(a) do
                    if typeof(mv)=="table" and mv[1]=="PetMovement" and typeof(mv[3])=="number" and typeof(mv[4])=="CFrame" and typeof(mv[6])=="number" then
                        local id=mv[3]
                        pending[id]={frame=mv[4],speed=mv[6]}
                        temp[id]=temp[id] or {samples={},sourceCoins={}}
                        temp[id].movement=pending[id]
                    end
                end
            end
        elseif event.remote=="Coins" and event.method=="FireServer" then
            local a=event.args
            if a[1]=="Mine" and typeof(a[2])=="string" and typeof(a[3])=="number" and typeof(a[4])=="number" then
                local id=a[4]
                temp[id]=temp[id] or {samples={},sourceCoins={}}
                local info=temp[id]
                info.sourceCoins[a[2]]=true
                mineIds[a[2]]=true
                if #info.samples < 30 then info.samples[#info.samples+1]=a[3] end
                if info.movement and coinFolder then
                    local obj=coinFolder:FindFirstChild(a[2])
                    local cp=partOf(obj)
                    if cp then
                        info.offset=info.movement.frame.Position-cp.Position
                        info.offsetCoin=a[2]
                    end
                end
            end
        end
    end
    local details={}
    local count=0
    for id,info in pairs(temp) do
        if info.movement and #info.samples>0 then
            learned[id]=info
            learnedValidated[id]=nil -- new capture must be checked by HP during actual farm
            table.insert(details,tostring(id)..": Mine="..#info.samples..", Move=да, arg6="..string.format("%.3f",info.movement.speed)..(info.offset and ", смещение="..tostring(info.offset) or ", смещение неизвестно"))
        else
            table.insert(details,tostring(id)..": недостаточно событий (Move/Mine)")
        end
    end
    for coinName in pairs(mineIds) do learnedTarget[coinName]=true end
    for id in pairs(learned) do count+=1 end
    if type(getgenv)=="function" then
        local env=getgenv()
        env.ZoneHubLearnedProfiles=learned
        env.ZoneHubLearnedSources=learnedTarget
    end
    table.sort(details)
    learnedText.Text="Обученных питомцев: "..count.."/4\n"..table.concat(details,"\n")
    reportText="ZoneHub v1.3 | Обучение\n"..learnedText.Text.."\nДоступно событий: "..#remotes
    if count==0 then log("Не удалось связать Mine и PetMovement. Запиши ещё раз",true) else log("Обучено питомцев: "..count..". Можно сделать одиночный тест") end
end
-- Preloaded from the user's actual 16-event capture (not guessed packet values).
-- This is observed client traffic, NOT proof of reusable server-side damage arguments.
button(trainingPanel,"1. Загрузить твой отчёт (2 питомца)",232,function()
    local coinFolder=gameNodes()
    local observed={
        {id=25214651,source="c1052",x=-3031,y=141.9644012,z=-1597,speed=3.5815804004669189,
         samples={145.05895256996155,175907.17931485176,176728.10179138184,176806.94916629791,176403.91777682304,176601.13730049133,176758.326618433,176452.94467020035}},
        {id=95608754,source="c2187",x=-3033,y=141.9645081,z=-1566,speed=4.7751576900482178,
         samples={122.49581408500671,168272.95349677405,168949.72115047774,168528.27377120656}},
    }
    local details={}
    for _,v in ipairs(observed) do
        local mv={frame=CFrame.new(v.x,v.y,v.z),speed=v.speed}
        local record={samples=v.samples,sourceCoins={[v.source]=true},movement=mv}
        local source=coinFolder and coinFolder:FindFirstChild(v.source)
        local part=partOf(source)
        if part then record.offset=mv.frame.Position-part.Position end
        learned[v.id]=record
        learnedTarget[v.source]=true
        details[#details+1]=tostring(v.id)..": "..#v.samples.." Mine; Movement; "..(record.offset and "смещение найдено" or "смещение неизвестно")
    end
    learnedText.Text="Из твоего отчёта: 2/4 (добавленные вручную питомцы сохранены)\n"..table.concat(details,"\n")
    reportText="ZoneHub v1.3\n"..learnedText.Text
    log("Загружены реальные вызовы двух питомцев. Можно сделать ОДИН тест")
end,C.blue)
button(trainingPanel,"Разобрать новую запись ручной добычи",276,function()
    captureState.recording=false
    examineCapture()
end,C.blue)
local function learnedTest()
    if testBusy then log("Предыдущий тест ещё выполняется",true) return end
    if not learnedTarget then log("Сначала нажми «Загрузить отчёт» или «Разобрать запись»",true) return end
    local id,info
    -- Pick a pet with both movement and at least two Mine calls, prioritizing user's ID order.
    for _,idString in ipairs(cfg.ids) do
        local petId=tonumber(idString)
        if petId and learned[petId] and #learned[petId].samples>0 then
            id,info=petId,learned[petId];break
        end
    end
    if not id then log("Нет обученных ID из списка питомцев",true) return end
    local options=scan()
    sortCoins(options)
    local target
    for _,c in ipairs(options) do
        if not learnedTarget[c.object.Name] and c.hp and c.hp>0 then target=c;break end
    end
    if not target then log("Не найдена новая монета с HP вне ручных целей",true) return end
    local _,coinRemote,petRemote=gameNodes()
    if not coinRemote or not petRemote then log("RemoteEvent отсутствуют",true) return end
    testBusy=true
    local hpStart=coinHealth(target.object)
    local name=target.object.Name
    local pos=target.pos+(info.offset or Vector3.new(0,0,0))
    local function sequence()
        -- Reproduce observed packet order: PetMovement first, Mine second.
        petRemote:FireServer({{"PetMovement",player,id,CFrame.new(pos),false,info.movement.speed}})
        stats.movement+=1
        task.wait(.06)
        -- A bounded sequence of captured REAL values (never guessed numeric values).
        for i=1,math.min(#info.samples,5) do
            if not alive then break end
            coinRemote:FireServer("Mine",name,info.samples[i],id)
            stats.attempts+=1
            task.wait(.42)
        end
    end
    task.spawn(function()
        local ok,err=pcall(sequence)
        task.wait(.7)
        testBusy=false
        if not alive then return end
        if not ok then log("Ошибка обучения: "..tostring(err),true);return end
        local hpAfter=coinHealth(target.object)
        local decline=hpStart and hpAfter and hpStart>hpAfter
        reportText=string.format("Обученный тест v1.3\nМонета %s | питомец %s (number)\nHP: %s → %s\nЗахвачено Mine образцов: %d\nПорядок: Movement → Mine × %d\nРезультат: %s", name,tostring(id),tostring(hpStart),tostring(hpAfter),#info.samples,math.min(#info.samples,5),decline and "HP уменьшился" or "Нет подтверждённого изменения HP")
        learnedText.Text=reportText
        log(decline and "Обученный тест: HP монеты уменьшился" or "Обученный тест: HP не изменился; нужна проверка протокола",not decline)
        if decline then learnedValidated[id]=true end
    end)
end
button(trainingPanel,"2. Один тест с записанными аргументами",320,learnedTest,C.blue)
button(trainingPanel,"3. Скопировать отчёт теста",364,function()
    if type(setclipboard)=="function" then
        local ok,err=pcall(setclipboard,reportText)
        if ok then log("Отчёт обучения скопирован") else log("Ошибка буфера: "..tostring(err),true) end
    else log("Буфер обмена недоступен",true) end
end,C.panel2)

-- ZoneHub v1.4. Controlled, asynchronous per-pet workers.
-- Each worker checks numeric HP, confines every target to the configured rectangle,
-- and stops after repeated no-progress cases. This reuses observed numeric packets,
-- not a claim that server-side validation is understood or guaranteed.
local farmProgress = newFrame(farm,180)
label(farmProgress,"Автоматический режим (обученные питомцы)",9,22,13,C.gold,true)
local progressText=label(farmProgress,"Готово: 2 питомца из 4. Остальных обучи через Диагностику.",34,77,12,C.white)
button(farmProgress,"Скопировать отчёт автофарма",127,function()
    local lines={
        "ZoneHub v1.4 | Автофарм",
        "Активен: "..tostring(farming).." | Потоков: "..tostring(farmStats.live),
        string.format("HP снято: %.3f | исчезло целей: %d | без прогресса: %d",farmStats.damage,farmStats.completed,farmStats.rejected),
        "Mine: "..stats.attempts.." | PetMovement: "..stats.movement,
        "Обучены: "..table.concat((function()
            local arr={}
            for _,idString in ipairs(cfg.ids) do
                local id=tonumber(idString)
                if id and learned[id] and #learned[id].samples>0 then
                    arr[#arr+1]=tostring(id).." ("..#learned[id].samples.." Mine)"
                end
            end
            return arr
        end)(),", "),
        "Зона X: "..cfg.minX..".."..cfg.maxX.."; Z: "..cfg.minZ..".."..cfg.maxZ,
        "Состояние: "..progressText.Text,
        "Журнал: "..table.concat(logLines," | "),
    }
    local report=table.concat(lines,"\n")
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,report)
        log(ok and "Отчёт автофарма скопирован" or "Не удалось скопировать отчёт",not ok)
    else log("Буфер обмена недоступен. Пришли скриншот",true) end
end,C.panel2)

local function availableLearnedIds()
    local ids={}
    for _,idString in ipairs(cfg.ids) do
        local id=tonumber(idString)
        local inf=id and learned[id]
        if inf and inf.movement and inf.samples and #inf.samples > 0 then
            ids[#ids+1]=id
        end
    end
    return ids
end
local function chooseTarget(petId)
    local options=scan()
    sortCoins(options)
    for _,item in ipairs(options) do
        local obj=item.object
        if obj and obj.Parent and inside(item.pos) and not reservedCoins[obj]
            and type(item.hp)=="number" and item.hp>0 then
            reservedCoins[obj]=petId
            return obj
        end
    end
    return nil
end
local function validTarget(obj)
    if not obj or not obj.Parent then return false end
    local part=partOf(obj)
    local hp=coinHealth(obj)
    return part ~= nil and inside(part.Position) and type(hp)=="number" and hp>0
end
local function activeSession(epoch)
    return alive and farming and farmSession==epoch and gui.Parent~=nil
end
local function farmWorker(epoch,petId)
    local info=learned[petId]
    local object=nil
    local failedTargets=0
    local consecutiveFails=0
    while activeSession(epoch) do
        if not object or not validTarget(object) then
            if object and reservedCoins[object]==petId then reservedCoins[object]=nil end
            object=chooseTarget(petId)
            consecutiveFails=0
            if not object then
                task.wait(1.0)
                continue
            end
        end
        local _,coinRemote,petRemote=gameNodes()
        if not coinRemote or not petRemote then
            log("Потеряны игровые события; фарм остановлен",true)
            stopMine()
            break
        end
        local coinName=object.Name
        local hpBefore=coinHealth(object)
        local part=partOf(object)
        if not part or not hpBefore then
            if reservedCoins[object]==petId then reservedCoins[object]=nil end
            object=nil
            task.wait(.2)
            continue
        end
        local location=part.Position + (info.offset or Vector3.new(0,0,0))
        local ok,err=pcall(function()
            petRemote:FireServer({{"PetMovement",player,petId,CFrame.new(location),false,info.movement.speed}})
            stats.movement+=1
        end)
        if not ok then
            log("Movement питомца "..petId..": "..tostring(err):sub(1,80),true)
            break
        end
        task.wait(.06)
        local sent=0
        for i=1,math.min(#info.samples,5) do
            if not activeSession(epoch) or not validTarget(object) then break end
            local value=info.samples[i]
            if type(value)~="number" then break end
            local succeeded,errMine=pcall(function()
                coinRemote:FireServer("Mine",coinName,value,petId)
            end)
            if not succeeded then
                log("Mine питомца "..petId..": "..tostring(errMine):sub(1,80),true)
                break
            end
            sent+=1
            stats.attempts+=1
            task.wait(cfg.interval)
        end
        task.wait(.55)
        if not activeSession(epoch) then break end
        local hpAfter=coinHealth(object)
        if validTarget(object) and type(hpAfter)=="number" and hpAfter<hpBefore then
            local delta=hpBefore-hpAfter
            farmStats.damage+=delta
            consecutiveFails=0
            learnedValidated[petId]=true
            progressText.Text=string.format("Работают: %d | HP снято: %.0f | Объектов: %d\nПитомец %s → %s: −%.0f HP (%d Mine)", farmStats.live,farmStats.damage,farmStats.completed,tostring(petId),coinName,delta,sent)
        elseif not validTarget(object) then
            -- Disappearance can mean mining completion, unloading, or another player.
            farmStats.completed+=1
            if reservedCoins[object]==petId then reservedCoins[object]=nil end
            object=nil
            consecutiveFails=0
        else
            consecutiveFails+=1
            if consecutiveFails>=2 then
                failedTargets+=1
                farmStats.rejected+=1
                log("Питомец "..petId..": нет HP-прогресса на "..coinName.." ("..failedTargets.."/3)",true)
                if reservedCoins[object]==petId then reservedCoins[object]=nil end
                object=nil
                consecutiveFails=0
                if failedTargets>=3 then
                    log("Питомец "..petId.." приостановлен: 3 цели без прогресса",true)
                    break
                end
            end
        end
    end
    if object and reservedCoins[object]==petId then reservedCoins[object]=nil end
    if farmSession==epoch then
        farmStats.live=math.max(0,farmStats.live-1)
        if farmStats.live==0 then
            farming=false
            log("Все обученные питомцы остановлены; проверь Диагностику")
        end
    end
end
startAutoFarm=function()
    if farming then return end
    local ids=availableLearnedIds()
    if #ids==0 then
        log("Нет обученных питомцев. Диагностика → 1. Загрузить твой отчёт",true)
        return
    end
    local coins=scan()
    if #coins==0 then log("В зоне нет доступных монет",true) return end
    local _,coinRemote,petRemote=gameNodes()
    if not coinRemote or not petRemote then log("Нет игровых RemoteEvent",true) return end
    farmSession+=1
    local epoch=farmSession
    farming=true
    table.clear(reservedCoins)
    farmStats={damage=0,completed=0,rejected=0,live=#ids}
    captureState.recording=false -- prevent collecting our own injected packets as manual samples
    progressText.Text="Запущено: "..#ids.." обученных питомцев из "..#cfg.ids..". Проверяю HP каждой цели..."
    log("Auto Farm v1.4: "..#ids.." обученных питомцев; остановка без StopMine")
    for _,id in ipairs(ids) do
        task.spawn(function()
            local ok,err=pcall(farmWorker,epoch,id)
            if not ok then
                log("Ошибка потока питомца "..id..": "..tostring(err):sub(1,90),true)
                if farmSession==epoch then
                    farmStats.live=math.max(0,farmStats.live-1)
                    if farmStats.live==0 then farming=false end
                end
            end
        end)
    end
end
-- Preload numeric samples actually captured by the user; two pets are trained.
-- Other two are NOT fabricated and join only after their manual capture.
local captureDefaults={
    {id=25214651,source="c1052",x=-3031,y=141.9644012,z=-1597,speed=3.5815804004669189,
     samples={145.05895256996155,175907.17931485176,176728.10179138184,176806.94916629791,176403.91777682304,176601.13730049133,176758.326618433,176452.94467020035}},
    {id=95608754,source="c2187",x=-3033,y=141.9645081,z=-1566,speed=4.7751576900482178,
     samples={122.49581408500671,168272.95349677405,168949.72115047774,168528.27377120656}},
}
for _,v in ipairs(captureDefaults) do
    learned[v.id]={samples=v.samples,sourceCoins={[v.source]=true},movement={frame=CFrame.new(v.x,v.y,v.z),speed=v.speed}}
    learnedTarget[v.source]=true
end
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubLearnedProfiles)=="table" then
        for id,info in pairs(env.ZoneHubLearnedProfiles) do
            if type(id)=="number" and type(info)=="table" and type(info.samples)=="table" and info.movement then
                learned[id]=info
            end
        end
    end
    if type(env.ZoneHubLearnedSources)=="table" then
        for coinName in pairs(env.ZoneHubLearnedSources) do learnedTarget[coinName]=true end
    end
end
local trainedCount=0
for id in pairs(learned) do trainedCount+=1 end
learnedText.Text="Обучено "..trainedCount.."/4 питомцев. Для остальных запиши ручную добычу и нажми «Разобрать новую запись»."
progressText.Text="Готово: "..trainedCount.." питомца(ев) из "..#cfg.ids..". Запусти тест и смотри HP."

local warning=newFrame(diag,150)
label(warning,"Что подтверждается, а что нет",10,24,13,C.gold,true)
label(warning,"✓ HP снизился в тесте питомца 25214651\n✓ Фарм только обученными ID в пределах зоны\n? Второй питомец и повторные циклы проверяются в игре\n✗ Автооткрытие яиц и шляп пока не подтверждено",40,98,11,C.dim)

local function refresh()
    local found,total=scan()
    counter.Text=string.format("Монет: %d всего  •  %d в зоне  •  питомцев: %d",total,#found,#cfg.ids)
    operating.Text=farming and ("● ФАРМ: "..farmStats.live.." ПИТОМЦЕВ") or "● ОСТАНОВЛЕН"
    operating.TextColor3=farming and C.teal or C.red
    start.Text=farming and "■  ОСТАНОВИТЬ" or "▶  ЗАПУСТИТЬ"
    start.BackgroundColor3=farming and C.red or C.blue
    statsLabel.Text=string.format("Mine: %d  |  Movement: %d\nОшибок клиента: %d",stats.attempts,stats.movement,stats.failures)
end
local lastMine=0
local lastRefresh=0
local conn=RunService.Heartbeat:Connect(function(dt)
    if not alive or not gui.Parent then return end
    local current=os.clock()
    if current-lastRefresh > 1.1 then lastRefresh=current refresh() end
    if false and farming and current-lastMine>=cfg.interval then
        lastMine=current
        local coins=scan()
        if #coins>0 then
            local ok,msg=tryMine(coins,false)
            if not ok then log(msg,true) end
        end
    end
end)
connections[#connections+1]=conn
local function shutdown()
    farming=false alive=false
    pcall(stopMine)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if getgenv then getgenv().ZoneHubShutdown=shutdown end
showTab("Фарм")
refresh()
log("v1.4: обучено "..trainedCount.."/4; Фарм → ▶ ЗАПУСТИТЬ")
