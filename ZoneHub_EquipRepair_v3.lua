-- ZoneHub Equip Repair v3.0
-- Original Pet Simulator (2018). Verified on this user's account:
-- Inventory:InvokeServer("Unequip", petID) returned true, e changed true->false.
-- This program NEVER uses Delete/Trade/Fuse/Shop/Equip.
-- Reversible by normal game equip action when UI is functioning.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")
local remotes = workspace:WaitForChild("__REMOTES")
local statsRemote = remotes:WaitForChild("Core"):WaitForChild("Get Other Stats")
local inventoryRemote = remotes:WaitForChild("Game"):WaitForChild("Inventory")

local guiName = "ZoneHub_EquipRepair_v3"
local old = guiParent:FindFirstChild(guiName)
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(350, 525)
frame.Position = UDim2.new(0.5, -175, 0.5, -262)
frame.BackgroundColor3 = Color3.fromRGB(25, 31, 39)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local function label(text,y,height,size,bold)
    local v=Instance.new("TextLabel")
    v.Size=UDim2.new(1,-16,0,height)
    v.Position=UDim2.fromOffset(8,y)
    v.BackgroundTransparency=1
    v.Font=bold and Enum.Font.GothamBold or Enum.Font.Code
    v.TextSize=size or 13
    v.TextColor3=Color3.fromRGB(234,239,249)
    v.TextXAlignment=Enum.TextXAlignment.Left
    v.TextYAlignment=Enum.TextYAlignment.Center
    v.TextWrapped=true
    v.Text=text
    v.Parent=frame
    return v
end
local title=label("ZoneHub | Equip Repair v3 — до 4 питомцев",8,32,15,true)
local indicator=label("Режим: только Unequip. Сначала снимок.",42,35,12,false)
local function button(y,caption,color)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-18,0,37)
    b.Position=UDim2.fromOffset(9,y)
    b.BackgroundColor3=color or Color3.fromRGB(41,91,147)
    b.TextColor3=Color3.fromRGB(255,255,255)
    b.Font=Enum.Font.GothamBold
    b.TextSize=13
    b.Text=caption
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    return b
end
local scanBtn=button(82,"1. Прочитать сервер / предложить 4 оставить")
label("ОСТАВИТЬ ЭКИПИРОВАННЫМИ (4 ID через запятую)",123,22,11,true)
local keepBox=Instance.new("TextBox")
keepBox.Size=UDim2.new(1,-18,0,34)
keepBox.Position=UDim2.fromOffset(9,146)
keepBox.BackgroundColor3=Color3.fromRGB(50,59,73)
keepBox.TextColor3=Color3.fromRGB(245,245,245)
keepBox.TextSize=12
keepBox.Font=Enum.Font.Code
keepBox.Text=""
keepBox.ClearTextOnFocus=false
keepBox.PlaceholderText="Сначала нажми 1"
keepBox.Parent=frame
Instance.new("UICorner",keepBox).CornerRadius=UDim.new(0,8)
local previewBtn=button(186,"2. Предпросмотр: кого оставить и кого снять")
local batchBtn=button(230,"3. Снять до 5 (нажми 2 раза)",Color3.fromRGB(137,88,38))
local stopBtn=button(274,"СТОП / Сброс подтверждения",Color3.fromRGB(104,50,50))
local copyBtn=button(318,"4. Копировать отчёт")
local output=Instance.new("TextBox")
output.Size=UDim2.new(1,-18,0,151)
output.Position=UDim2.fromOffset(9,365)
output.BackgroundColor3=Color3.fromRGB(13,18,25)
output.TextColor3=Color3.fromRGB(226,236,246)
output.TextSize=12
output.Font=Enum.Font.Code
output.TextWrapped=true
output.TextXAlignment=Enum.TextXAlignment.Left
output.TextYAlignment=Enum.TextYAlignment.Top
output.TextEditable=false
output.MultiLine=true
output.ClearTextOnFocus=false
output.Parent=frame
Instance.new("UICorner",output).CornerRadius=UDim.new(0,8)

local report={"ZONEHUB EQUIP REPAIR v3 | ОТЧЁТ", "Только Inventory:InvokeServer('Unequip', ID)", "Delete / Shop / Fuse / Trade / Equip: НЕТ"}
local current=nil
local plan=nil
local busy=false
local armed=false
local cancelled=false
local batchNo=0
local MAX_BATCH=5
local function log(s)
    report[#report+1]=tostring(s)
    local start=math.max(1,#report-10)
    local chunks={}
    for i=start,#report do chunks[#chunks+1]=report[i] end
    output.Text=table.concat(chunks,"\n")
    print("[EquipRepair v3] "..tostring(s))
end
local function readServer()
    local ok,raw=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,"Get Other Stats error: "..tostring(raw) end
    local save=type(raw)=="table" and raw[player.Name] and raw[player.Name].Save
    if type(save)~="table" or type(save.Pets)~="table" then return nil,"Нет Save.Pets" end
    local s={count=0, equipped=0, petSlots=save.PetSlots, maxPets=save.MaxPets, pets={}, duplicates=0}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" and p.id~=nil then
            local id=tostring(p.id)
            if s.pets[id] then s.duplicates+=1 end
            s.pets[id]={e=p.e==true,level=tonumber(p.l) or 0,typ=tostring(p.n)}
            s.count+=1
            if p.e==true then s.equipped+=1 end
        end
    end
    return s
end
local function sameEntries(a,b)
    if not a or not b or a.count~=b.count or a.equipped~=b.equipped then return false end
    for id,p in pairs(a.pets) do
        if not b.pets[id] or p.e~=b.pets[id].e then return false end
    end
    return true
end
local function sortedEquipped(s)
    local arr={}
    for id,p in pairs(s.pets) do if p.e then arr[#arr+1]=id end end
    table.sort(arr,function(a,b)
        local pa,pb=s.pets[a],s.pets[b]
        if pa.level~=pb.level then return pa.level>pb.level end
        return a<b
    end)
    return arr
end
local function keepList(s)
    local seen,ids={},{}
    for token in string.gmatch(keepBox.Text,"[^,%s;]+") do
        if not string.match(token,"^%d+$") then return nil,"ID должен состоять из цифр: "..token end
        if seen[token] then return nil,"Повтор ID: "..token end
        if not s.pets[token] or not s.pets[token].e then return nil,"ID отсутствует или уже снят: "..token end
        ids[#ids+1]=token
        seen[token]=true
    end
    if #ids~=4 then return nil,"Нужно указать ровно 4 ID, сейчас: "..#ids end
    return seen,ids
end
local function checkSafe(s)
    if s.duplicates>0 then return false,"Найдены дубликаты ID" end
    if s.maxPets~=4 then return false,"MaxPets не равно 4 ("..tostring(s.maxPets)..")" end
    if s.equipped<4 then return false,"Экипировано меньше 4, автоматическое снятие запрещено" end
    return true
end
local function showSnapshot(s)
    indicator.Text=string.format("Сервер: %d/%s | Экипировано: %d/%s | осталось снять: %d",s.count,tostring(s.petSlots),s.equipped,tostring(s.maxPets),math.max(0,s.equipped-4))
end
local function preview()
    local s,err=readServer()
    if not s then log("ОШИБКА: "..err);return nil end
    local safe,reason=checkSafe(s)
    if not safe then log("БЛОК: "..reason);return nil end
    local keep,keepArr=keepList(s)
    if not keep then log("БЛОК: "..tostring(keepArr));return nil end
    local equipped=sortedEquipped(s)
    local toRemove={}
    for i=#equipped,1,-1 do
        local id=equipped[i]
        if not keep[id] then toRemove[#toRemove+1]=id end
    end
    local expected=s.equipped-4
    if #toRemove~=expected then log("БЛОК: расчёт не совпадает с количеством экипированных");return nil end
    current=s
    plan={keep=keep, keepArr=keepArr}
    armed=false
    showSnapshot(s)
    local protected={}
    for _,id in ipairs(keepArr) do
        local p=s.pets[id]
        protected[#protected+1]=string.format("%s(level %s/type %s)",id,tostring(p.level),p.typ)
    end
    log("ОСТАВЛЯЕМ 4: "..table.concat(protected,"; "))
    log("Остальных снять: "..#toRemove.."; следующая партия до "..MAX_BATCH)
    if #toRemove>0 then
        local nextIDs={}
        for i=1,math.min(MAX_BATCH,#toRemove) do nextIDs[#nextIDs+1]=toRemove[i] end
        log("СЛЕДУЮЩИЕ ID: "..table.concat(nextIDs,", "))
    else log("ГОТОВО: уже 4/4; ничего снимать не надо") end
    return s
end
scanBtn.MouseButton1Click:Connect(function()
    if busy then return end
    local s,err=readServer()
    if not s then log("ОШИБКА СНИМКА: "..err);return end
    current=s
    plan=nil
    armed=false
    showSnapshot(s)
    log(string.format("СНИМОК: %d/%s | экипировано %d/%s | дубликатов %d",s.count,tostring(s.petSlots),s.equipped,tostring(s.maxPets),s.duplicates))
    local eq=sortedEquipped(s)
    if #eq>=4 then
        local ids={}
        for i=1,4 do ids[#ids+1]=eq[i] end
        keepBox.Text=table.concat(ids,",")
        log("Предложены 4 с НАИБОЛЬШИМ УРОВНЕМ (не обязательно максимальный урон). Проверь ID!")
    end
end)
keepBox:GetPropertyChangedSignal("Text"):Connect(function()
    plan=nil
    armed=false
end)
previewBtn.MouseButton1Click:Connect(function()
    if busy then return end
    preview()
end)
stopBtn.MouseButton1Click:Connect(function()
    cancelled=true
    armed=false
    log("СТОП: новые операции не начнутся; текущий запрос завершится и будет проверен")
end)
batchBtn.MouseButton1Click:Connect(function()
    if busy then return end
    if not plan or not current then log("Сначала нажми 2 и проверь четыре сохраняемых ID");return end
    if not armed then
        armed=true
        cancelled=false
        log("ПОДТВЕРЖДЕНИЕ 1/2: нажми ещё раз, чтобы снять до 5. Питомцы останутся в инвентаре.")
        return
    end
    armed=false
    busy=true
    cancelled=false
    batchNo+=1
    log("ПАРТИЯ "..batchNo.." начинается")
    local startCount=current.count
    local made=0
    for step=1,MAX_BATCH do
        if cancelled then log("Остановлено пользователем");break end
        local s,err=readServer()
        if not s then log("СТОП: "..err);break end
        local safe,reason=checkSafe(s)
        if not safe then log("СТОП: "..reason);break end
        if s.count~=startCount then log("СТОП: изменилось количество питомцев");break end
        if not sameEntries(s,current) then log("СТОП: флаги экипировки изменены извне, обнови снимок");break end
        if s.equipped<=4 then log("УЖЕ 4/4. Готово");break end
        local retain=true
        for id in pairs(plan.keep) do
            if not (s.pets[id] and s.pets[id].e) then retain=false end
        end
        if not retain then log("СТОП: один из 4 защищённых питомцев изменился");break end
        local eq=sortedEquipped(s)
        local selected=nil
        for i=#eq,1,-1 do
            if not plan.keep[eq[i]] then selected=eq[i];break end
        end
        if not selected then log("СТОП: нет допустимого кандидата");break end
        local was=s.equipped
        log("Unequip ID="..selected.." (экипировано "..was..")")
        local ok,answer=pcall(function() return inventoryRemote:InvokeServer("Unequip",tonumber(selected)) end)
        if not ok or answer~=true then log("СТОП: ответ сервера pcall="..tostring(ok).." value="..tostring(answer));break end
        task.wait(0.65)
        local after,e=readServer()
        if not after then log("СТОП: нет снимка после операции: "..tostring(e));break end
        if after.count~=startCount then log("КРИТИЧНО: изменилось количество питомцев; немедленный стоп");break end
        local valid=after.equipped==was-1 and after.pets[selected] and after.pets[selected].e==false
        if valid then
            for id,p in pairs(s.pets) do
                if not after.pets[id] or (id~=selected and p.e~=after.pets[id].e) then valid=false;break end
            end
        end
        if not valid then log("СТОП: неожиданные изменения данных после Unequip ID="..selected);break end
        current=after
        made+=1
        showSnapshot(after)
        log("УСПЕХ: теперь экипировано "..after.equipped.."/4; питомцев "..after.count)
    end
    log("ПАРТИЯ "..batchNo.." закончена: снято="..made.."; сервер="..tostring(current and current.equipped).."/4")
    log("Для следующей партии нажми 2, затем 3 два раза. Если инвентарь исправился, можно остановиться.")
    busy=false
end)
copyBtn.MouseButton1Click:Connect(function()
    local txt=table.concat(report,"\n")
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,txt)
        if ok then log("Отчёт скопирован") else log("Буфер обмена недоступен") end
    else log("Буфер обмена недоступен, полный отчёт в консоли") end
    print(txt)
end)
log("ПРОВЕРЕННЫЙ СЕРВЕРОМ метод Unequip; сначала нажми 1. Не включай другие скрипты")
