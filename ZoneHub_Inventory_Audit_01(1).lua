-- ZoneHub | Inventory & Entitlements Audit v0.1
-- READ ONLY: requests current account stats, never purchases, deletes, trades or changes state.
-- Original Pet Simulator (2018) | Delta / Android
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local previous = pg:FindFirstChild("ZoneHub_InventoryAudit")
if previous then previous:Destroy() end

local ui = Instance.new("ScreenGui")
ui.Name = "ZoneHub_InventoryAudit"
ui.ResetOnSpawn = false
ui.IgnoreGuiInset = true
ui.DisplayOrder = 601
ui.Parent = pg

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0.92, 0, 0.67, 0)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(14,19,35)
panel.BorderSizePixel=0
panel.Parent=ui
local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,13); c.Parent=panel
local size=Instance.new("UISizeConstraint")
size.MaxSize=Vector2.new(500,570)
size.MinSize=Vector2.new(265,280)
size.Parent=panel
local stroke=Instance.new("UIStroke")
stroke.Color=Color3.fromRGB(63,104,200)
stroke.Thickness=1.2
stroke.Parent=panel

local function label(text,position,height,color,fontSize)
    local t=Instance.new("TextLabel")
    t.Size=UDim2.new(1,-24,0,height)
    t.Position=UDim2.new(0,12,0,position)
    t.BackgroundTransparency=1
    t.Text=text
    t.TextColor3=color or Color3.fromRGB(233,238,255)
    t.Font=Enum.Font.Gotham
    t.TextSize=fontSize or 13
    t.TextXAlignment=Enum.TextXAlignment.Left
    t.TextWrapped=true
    t.Parent=panel
    return t
end
local title=label("📦 ZoneHub | Аудит слотов",9,28,Color3.fromRGB(188,210,255),17)
local subtitle=label("Только чтение данных • никаких покупок",36,22,Color3.fromRGB(146,161,193),11)
local close=Instance.new("TextButton")
close.Text="×"; close.Font=Enum.Font.GothamBold; close.TextSize=26
close.TextColor3=Color3.fromRGB(248,188,199)
close.BackgroundTransparency=1
close.Size=UDim2.new(0,34,0,32)
close.Position=UDim2.new(1,-40,0,4)
close.Parent=panel
close.MouseButton1Click:Connect(function() ui:Destroy() end)

local output=Instance.new("TextBox")
output.Name="Report"
output.Position=UDim2.new(0,12,0,66)
output.Size=UDim2.new(1,-24,1,-122)
output.BackgroundColor3=Color3.fromRGB(22,31,53)
output.TextColor3=Color3.fromRGB(234,241,255)
output.PlaceholderText="Читаю серверные параметры..."
output.Text="Читаю серверные параметры..."
output.Font=Enum.Font.Code
output.TextSize=13
output.TextXAlignment=Enum.TextXAlignment.Left
output.TextYAlignment=Enum.TextYAlignment.Top
output.TextWrapped=false
output.MultiLine=true
output.ClearTextOnFocus=false
output.TextEditable=true
output.Parent=panel
local oc=Instance.new("UICorner");oc.CornerRadius=UDim.new(0,7);oc.Parent=output
local op=Instance.new("UIPadding");op.PaddingTop=UDim.new(0,9);op.PaddingLeft=UDim.new(0,9);op.PaddingRight=UDim.new(0,9);op.Parent=output

local copy=Instance.new("TextButton")
copy.Text="СКОПИРОВАТЬ ОТЧЁТ"
copy.Font=Enum.Font.GothamBold
copy.TextSize=13
copy.TextColor3=Color3.fromRGB(255,255,255)
copy.BackgroundColor3=Color3.fromRGB(55,102,207)
copy.Size=UDim2.new(1,-24,0,34)
copy.Position=UDim2.new(0,12,1,-45)
copy.Parent=panel
local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,7);cc.Parent=copy
copy.MouseButton1Click:Connect(function()
    local setter = (type(setclipboard)=="function" and setclipboard) or (type(toclipboard)=="function" and toclipboard)
    if setter then
        local ok = pcall(setter, output.Text)
        copy.Text=ok and "СКОПИРОВАНО" or "НЕ УДАЛОСЬ СКОПИРОВАТЬ"
    else
        copy.Text="НЕТ API БУФЕРА • ВЫДЕЛИ ТЕКСТ"
        output:CaptureFocus()
    end
end)

-- Drag by top bar; works with touch and mouse.
local dragging, dragInput, startPos, panelPos = false,nil,nil,nil
panel.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        if input.Position.Y>panel.AbsolutePosition.Y+60 then return end
        dragging=true; dragInput=input; startPos=input.Position; panelPos=panel.Position
        input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then dragging=false end
        end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and dragInput and (input==dragInput or (dragInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local d=input.Position-startPos
        panel.Position=UDim2.new(panelPos.X.Scale,panelPos.X.Offset+d.X,panelPos.Y.Scale,panelPos.Y.Offset+d.Y)
    end
end)

local report={}
local function add(s) report[#report+1]=s end
local function val(v)
    if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
    if type(v)=="string" and #v<=35 then return v end
    return "["..type(v).."]"
end
local function relevant(k)
    local s=tostring(k):lower()
    return s:find("slot",1,true) or s:find("pass",1,true)
        or s:find("vip",1,true) or s:find("capacity",1,true)
        or s:find("hat",1,true) or s:find("maxpet",1,true)
        or s:find("luck",1,true) or s:find("clone",1,true)
        or s:find("boost",1,true) or s:find("premium",1,true)
        or s:find("triple",1,true) or s:find("inventory",1,true)
        or s:find("upgrade",1,true)
end
local function safeKey(k)
    local s=tostring(k):lower()
    return not (s:find("token") or s:find("cookie") or s:find("password") or s:find("secret") or s:find("session") or s:find("auth"))
end
local maxLines=100
local function scan(t,prefix,depth)
    if type(t)~="table" or depth>2 then return end
    local keys={}
    for k in pairs(t) do if safeKey(k) and relevant(k) then keys[#keys+1]=k end end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
        if #report >= maxLines then return end
        local v=t[k]
        add(prefix..tostring(k).." = "..val(v))
        if type(v)=="table" and depth<2 then
            local subKeys={}
            for kk in pairs(v) do
                if safeKey(kk) and (type(v[kk])=="boolean" or type(v[kk])=="number") then
                    subKeys[#subKeys+1]=kk
                end
            end
            table.sort(subKeys,function(a,b) return tostring(a)<tostring(b) end)
            for i=1,math.min(#subKeys,35) do
                if #report>=maxLines then return end
                local kk=subKeys[i]
                add("  "..prefix..tostring(k).."."..tostring(kk).." = "..val(v[kk]))
            end
        end
    end
end

local finished=false
task.delay(15,function()
    if not finished and output.Parent then
        output.Text="Запрос ещё выполняется. Если надпись долго не меняется, сервер может не отвечать.\nНикакие данные не изменены."
    end
end)
task.spawn(function()
    add("ZoneHub Audit v0.1 | оригинальный Pet Simulator (2018)")
    add("Аккаунт: "..tostring(player.Name))
    add("Время: "..os.date("%H:%M:%S"))
    add("-----------------------------")
    local remotes=workspace:FindFirstChild("__REMOTES") or workspace:WaitForChild("__REMOTES",8)
    local core=remotes and remotes:FindFirstChild("Core")
    local rf=core and core:FindFirstChild("Get Other Stats")
    if not rf or not rf:IsA("RemoteFunction") then
        add("ОШИБКА: не найден Core / Get Other Stats")
    else
        local ok,data=pcall(function() return rf:InvokeServer() end)
        if not ok then
            add("ОШИБКА: сервер не ответил на запрос статистики")
        else
            local own=type(data)=="table" and data[player.Name]
            local save=type(own)=="table" and own.Save
            if type(save)~="table" then
                add("ОШИБКА: нет Save для текущего аккаунта")
            else
                local n=0
                if type(save.Pets)=="table" then
                    for _,pet in pairs(save.Pets) do if type(pet)=="table" then n+=1 end end
                end
                add("Питомцев: "..tostring(n))
                add("Save.PetSlots: "..tostring(save.PetSlots or "не найдено"))
                add("Save.MaxPets: "..tostring(save.MaxPets or "не найдено"))
                add("Save.HatSlots: "..tostring(save.HatSlots or "не найдено"))
                add("-----------------------------")
                add("Сходные с улучшениями поля:")
                scan(save,"Save.",0)
                if type(own)=="table" then scan(own,"Stats.",0) end
                add("-----------------------------")
                add("Чтение выполнено. Поля Pass не доказывают право собственности без проверки Game Pass ID.")
            end
        end
    end
    finished=true
    if output.Parent then output.Text=table.concat(report,"\n") end
end)
