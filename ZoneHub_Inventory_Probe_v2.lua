-- ZoneHub Inventory Probe v2 | Pet Simulator (2018)
-- READ-ONLY. No buying, deleting, trading, spoofing, or changing inventory.
-- Verified gamepass IDs: Roblox game passes +100=4918520, +500=5042851, VIP=4918538.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end

local previous
pcall(function() previous = CoreGui:FindFirstChild("ZoneHub_Inventory_Probe_v2") end)
if not previous then
    pcall(function() previous = player:WaitForChild("PlayerGui",3):FindFirstChild("ZoneHub_Inventory_Probe_v2") end)
end
if previous then pcall(function() previous:Destroy() end) end

local gui = Instance.new("ScreenGui")
gui.Name="ZoneHub_Inventory_Probe_v2"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local okGui = pcall(function() gui.Parent = CoreGui end)
if not okGui then gui.Parent=player:WaitForChild("PlayerGui") end

local function elem(class, props, parent)
    local x=Instance.new(class)
    for k,v in pairs(props) do x[k]=v end
    x.Parent=parent
    return x
end
local function corners(x,r)
    elem("UICorner",{CornerRadius=UDim.new(0,r or 10)},x)
end
local function textButton(parent,text,pos,size,color)
    local b=elem("TextButton",{
        Position=pos,Size=size,BackgroundColor3=color or Color3.fromRGB(94,75,210),
        Text=text,TextColor3=Color3.fromRGB(255,255,255),TextSize=13,
        Font=Enum.Font.GothamBold,AutoButtonColor=true,BorderSizePixel=0
    },parent)
    corners(b,8)
    return b
end
local main=elem("Frame",{
    Position=UDim2.new(.5,-255,.5,-235),Size=UDim2.fromOffset(510,470),
    BackgroundColor3=Color3.fromRGB(17,20,32),BorderSizePixel=0,ClipsDescendants=true
},gui)
corners(main,14)
elem("UIStroke",{Color=Color3.fromRGB(81,78,125),Thickness=1},main)
local top=elem("Frame",{
    Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,54),
    BackgroundColor3=Color3.fromRGB(29,34,52),BorderSizePixel=0
},main)
elem("TextLabel",{
    Position=UDim2.fromOffset(15,5),Size=UDim2.new(1,-100,0,24),BackgroundTransparency=1,
    Text="ZONEHUB · ИНВЕНТАРЬ",TextColor3=Color3.fromRGB(255,255,255),
    Font=Enum.Font.GothamBold,TextSize=16,TextXAlignment=Enum.TextXAlignment.Left
},top)
elem("TextLabel",{
    Position=UDim2.fromOffset(15,29),Size=UDim2.new(1,-100,0,17),BackgroundTransparency=1,
    Text="Диагностика лимита • без покупок и удаления",TextColor3=Color3.fromRGB(171,180,207),
    Font=Enum.Font.Gotham,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left
},top)
local hide=textButton(top,"−",UDim2.new(1,-43,0,10),UDim2.fromOffset(32,32),Color3.fromRGB(57,64,90))
local open=textButton(gui,"📦",UDim2.fromOffset(22,190),UDim2.fromOffset(52,45),Color3.fromRGB(47,49,77))
open.Visible=false
hide.MouseButton1Click:Connect(function() main.Visible=false open.Visible=true end)
open.MouseButton1Click:Connect(function() main.Visible=true open.Visible=false end)

local start=textButton(main,"1. ПРОВЕРИТЬ ЛИМИТ И ПРОПУСКИ",UDim2.fromOffset(14,65),UDim2.new(.65,-22,0,42),Color3.fromRGB(102,75,218))
local copy=textButton(main,"2. КОПИРОВАТЬ",UDim2.new(.65,0,0,65),UDim2.new(.35,-13,0,42),Color3.fromRGB(53,95,121))
local status=elem("TextLabel",{
    Position=UDim2.fromOffset(15,112),Size=UDim2.new(1,-30,0,36),BackgroundTransparency=1,
    Text="Нажми «Проверить». Сервер получит только запросы чтения.",
    TextColor3=Color3.fromRGB(212,212,230),Font=Enum.Font.Gotham,
    TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left
},main)
local sc=elem("ScrollingFrame",{
    Position=UDim2.fromOffset(14,154),Size=UDim2.new(1,-28,1,-168),
    BackgroundColor3=Color3.fromRGB(24,28,43),BorderSizePixel=0,ScrollBarThickness=5,
    ScrollBarImageColor3=Color3.fromRGB(119,109,202),CanvasSize=UDim2.fromOffset(0,800)
},main)
corners(sc,9)
local reportLabel=elem("TextLabel",{
    Position=UDim2.fromOffset(12,10),Size=UDim2.new(1,-25,0,760),
    BackgroundTransparency=1,Text="Результат появится здесь.\n\nНи один питомец не будет изменён.",
    TextColor3=Color3.fromRGB(231,235,246),Font=Enum.Font.Code,TextSize=13,
    TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top
},sc)
local currentReport="ZoneHub Inventory Probe v2: проверка не запускалась"
local function setReport(s)
    currentReport=s
    reportLabel.Text=s
    local count=1
    for _ in s:gmatch("\n") do count=count+1 end
    local height=math.max(360,count*20+80)
    reportLabel.Size=UDim2.new(1,-25,0,height)
    sc.CanvasSize=UDim2.fromOffset(0,height+22)
end
copy.MouseButton1Click:Connect(function()
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,currentReport)
        status.Text=ok and "Отчёт скопирован. Отправь сюда текст." or "Буфер обмена недоступен. Сделай скриншот."
    else
        status.Text="Delta не предоставила setclipboard. Сделай скриншот отчёта."
    end
    print(currentReport)
end)

-- Mobile dragging: only the header responds, not the content/buttons.
local dragging=false
local dragOrigin, frameOrigin
local function updateDrag(input)
    if not dragging or not dragOrigin or not frameOrigin then return end
    local delta=input.Position-dragOrigin
    local screen=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800,600)
    local x=math.clamp(frameOrigin.X.Offset+delta.X,0,math.max(0,screen.X-140))
    local y=math.clamp(frameOrigin.Y.Offset+delta.Y,0,math.max(0,screen.Y-100))
    main.Position=UDim2.fromOffset(x,y)
end
top.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragOrigin=input.Position
        local p=main.AbsolutePosition
        frameOrigin=UDim2.fromOffset(p.X,p.Y)
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false
                if conn then conn:Disconnect() end
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then
        updateDrag(input)
    end
end)

local function readServer()
    local remotes=workspace:FindFirstChild("__REMOTES")
    local core=remotes and remotes:FindFirstChild("Core")
    local remote=core and core:FindFirstChild("Get Other Stats")
    if not remote or not remote:IsA("RemoteFunction") then
        return nil,"Не найден Workspace.__REMOTES.Core['Get Other Stats']"
    end
    local ok,data=pcall(function() return remote:InvokeServer() end)
    if not ok then return nil,"Ошибка Get Other Stats: "..tostring(data) end
    local account=type(data)=="table" and data[player.Name]
    local save=type(account)=="table" and account.Save
    if type(save)~="table" or type(save.Pets)~="table" then
        return nil,"Ответ не содержит [имя].Save.Pets"
    end
    local count, equipped, unique =0,0,{}
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" then
            count=count+1
            if pet.e==true or pet.e==1 then equipped=equipped+1 end
            local id=tonumber(pet.id)
            if id then unique[id]=true end
        end
    end
    local uniqueCount=0
    for _ in pairs(unique) do uniqueCount=uniqueCount+1 end
    return {count=count,unique=uniqueCount,equipped=equipped,slots=save.PetSlots,save=save,account=account}
end
local passData={
    {label="+100 Max Pets",id=4918520,slots=100},
    {label="+500 Max Pets",id=5042851,slots=500},
    {label="VIP (+35)",id=4918538,slots=35}
}
local function checkPass(id)
    local ok,v=pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId,id)
    end)
    if not ok then return nil,tostring(v):sub(1,100) end
    if type(v)~="boolean" then return nil,"Неожиданный ответ: "..tostring(v) end
    return v,nil
end
local function fields(x,prefix,result,depth)
    if type(x)~="table" or depth>1 then return end
    local keys={}
    for key in pairs(x) do
        if type(key)=="string" then
            local low=key:lower()
            if low:find("slot",1,true) or low:find("pass",1,true) or
               low:find("vip",1,true) or low:find("capacity",1,true) or
               low:find("limit",1,true) or low:find("inventory",1,true) then
                keys[#keys+1]=key
            end
        end
    end
    table.sort(keys)
    for i=1,math.min(12,#keys) do
        local key=keys[i]
        local v=x[key]
        local full=prefix.."."..key
        if type(v)=="table" then
            result[#result+1]=full.." = {таблица}"
            if depth==0 then fields(v,full,result,1) end
        elseif type(v)=="number" or type(v)=="boolean" then
            result[#result+1]=full.." = "..tostring(v)
        else
            result[#result+1]=full.." = ["..type(v).."]"
        end
    end
end
local running=false
start.MouseButton1Click:Connect(function()
    if running then return end
    running=true
    start.Text="ЧИТАЮ ДАННЫЕ..."
    status.Text="Проверяю два ответа сервера и три Gamepass. Без покупок."
    task.spawn(function()
        local ok,err=pcall(function()
            local lines={"ZONEHUB INVENTORY PROBE v2","Тест: только чтение • никаких действий с питомцами",""}
            local a,e1=readServer()
            if not a then
                lines[#lines+1]="ОШИБКА: "..tostring(e1)
                setReport(table.concat(lines,"\n"))
                return
            end
            lines[#lines+1]=string.format("Сервер, снимок 1: %d / %s",a.count,tostring(a.slots))
            lines[#lines+1]=string.format("Экипировано: %d • уникальных ID: %d",a.equipped,a.unique)
            task.wait(1.0)
            local b,e2=readServer()
            if b then
                lines[#lines+1]=string.format("Сервер, снимок 2: %d / %s",b.count,tostring(b.slots))
                if a.slots~=b.slots or a.count~=b.count then
                    lines[#lines+1]="ВНИМАНИЕ: данные изменились между чтениями"
                else
                    lines[#lines+1]="Оба серверных снимка совпали"
                end
            else
                lines[#lines+1]="Повторное чтение: "..tostring(e2)
            end
            lines[#lines+1]=""
            lines[#lines+1]="ПРОВЕРКА GAMEPASS (Roblox API):"
            local allKnown,extras=true,0
            for _,pass in ipairs(passData) do
                local owned,passErr=checkPass(pass.id)
                if owned==true then extras=extras+pass.slots end
                if owned==nil then allKnown=false end
                local suffix=owned==nil and ("ОШИБКА: "..tostring(passErr)) or (owned and "КУПЛЕН" or "НЕ КУПЛЕН")
                lines[#lines+1]="• "..pass.label.." ("..pass.id.."): "..suffix
            end
            lines[#lines+1]=""
            if allKnown then
                local expected=35+extras
                lines[#lines+1]="Ожидаемый лимит по пропускам: "..expected
                lines[#lines+1]="Лимит из Save.PetSlots: "..tostring(a.slots)
                if type(a.slots)=="number" and a.slots==expected then
                    lines[#lines+1]="СОВПАДАЕТ: лимит соответствует обнаруженным пропускам."
                elseif type(a.slots)=="number" then
                    lines[#lines+1]="РАСХОЖДЕНИЕ: исследовать бонусы/синхронизацию."
                else
                    lines[#lines+1]="Нет числового PetSlots; нужно уточнить источник лимита."
                end
            else
                lines[#lines+1]="Часть проверок Gamepass недоступна; вычислить ожидаемый лимит нельзя."
            end
            lines[#lines+1]=""
            lines[#lines+1]="ПОЛЯ, ОТНОСЯЩИЕСЯ К ЛИМИТУ:"
            local meta={}
            fields(a.save,"Save",meta,0)
            fields(a.account,"Account",meta,0)
            if #meta==0 then
                lines[#lines+1]="Дополнительных полей не найдено."
            else
                for i=1,math.min(20,#meta) do lines[#lines+1]="• "..meta[i] end
            end
            lines[#lines+1]=""
            lines[#lines+1]="ВЫВОД: значение 635 не устанавливалось. Это диагностика, не обход ограничения."
            setReport(table.concat(lines,"\n"))
            status.Text="Проверка завершена. Нажми «Копировать» и отправь отчёт."
        end)
        if not ok then
            setReport("ОШИБКА ПРОВЕРКИ: "..tostring(err))
            status.Text="Ошибка чтения. Скопируй результат."
        end
        running=false
        start.Text="1. ПРОВЕРИТЬ ЛИМИТ И ПРОПУСКИ"
    end)
end)
