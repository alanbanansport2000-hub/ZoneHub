-- ZoneHub Inventory RaceProbe v3 | Original Pet Simulator (2018)
-- Experimental one-time test of two egg purchases against ONE remaining slot.
-- No deletes, trades, conversions, client-side capacity spoofing or gamepass changes.
-- CAUTION: Two purchases may cost currency even if only one pet is granted.

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end

local GUI_NAME = "ZoneHub_Inventory_RaceProbe_v3"
local old = nil
pcall(function() old = CoreGui:FindFirstChild(GUI_NAME) end)
if not old and player:FindFirstChild("PlayerGui") then
    pcall(function() old = player.PlayerGui:FindFirstChild(GUI_NAME) end)
end
if old then pcall(function() old:Destroy() end) end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okayGui = pcall(function() gui.Parent = CoreGui end)
if not okayGui then gui.Parent = player:WaitForChild("PlayerGui") end

local function add(class, props, parent)
    local obj = Instance.new(class)
    for k,v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function round(obj, n) add("UICorner",{CornerRadius=UDim.new(0,n or 10)},obj) end
local C = {bg=Color3.fromRGB(15,19,33),surface=Color3.fromRGB(27,32,51),ink=Color3.fromRGB(235,239,250),muted=Color3.fromRGB(176,185,210),blue=Color3.fromRGB(91,88,213),red=Color3.fromRGB(158,76,96),green=Color3.fromRGB(53,124,104)}
local main = add("Frame",{Position=UDim2.new(.5,-239,.5,-230),Size=UDim2.fromOffset(478,460),BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true},gui)
round(main,13)
add("UIStroke",{Thickness=1,Color=Color3.fromRGB(73,86,123)},main)
local header = add("Frame",{Size=UDim2.new(1,0,0,56),BackgroundColor3=C.surface,BorderSizePixel=0},main)
add("TextLabel",{Position=UDim2.fromOffset(14,5),Size=UDim2.new(1,-65,0,25),BackgroundTransparency=1,Text="ZONEHUB · ТЕСТ ЛИМИТА",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=C.ink,TextXAlignment=Enum.TextXAlignment.Left},header)
add("TextLabel",{Position=UDim2.fromOffset(14,30),Size=UDim2.new(1,-65,0,18),BackgroundTransparency=1,Text="v3 • два запроса при одном свободном слоте",Font=Enum.Font.Gotham,TextSize=11,TextColor3=C.muted,TextXAlignment=Enum.TextXAlignment.Left},header)
local function btn(parent,text,y,color,x,w)
    local b=add("TextButton",{Position=UDim2.new(x or 0, x and 0 or 13,0,y),Size=UDim2.new(w or 1,(w and -6 or -26),0,39),BackgroundColor3=color or C.blue,Text=text,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=C.ink,BorderSizePixel=0,AutoButtonColor=true},parent)
    round(b,8)
    return b
end
local hide=add("TextButton",{Position=UDim2.new(1,-48,0,11),Size=UDim2.fromOffset(34,34),Text="−",TextColor3=C.ink,TextSize=20,BackgroundColor3=Color3.fromRGB(56,64,87),BorderSizePixel=0},header)
round(hide,8)
local reopen=add("TextButton",{Position=UDim2.fromOffset(21,177),Size=UDim2.fromOffset(54,48),Text="📦",TextSize=19,BackgroundColor3=C.blue,TextColor3=C.ink,BorderSizePixel=0,Visible=false},gui)
round(reopen,10)
hide.MouseButton1Click:Connect(function() main.Visible=false reopen.Visible=true end)
reopen.MouseButton1Click:Connect(function() main.Visible=true reopen.Visible=false end)

local scan=btn(main,"1. СЧИТАТЬ ИНВЕНТАРЬ",65,C.blue)
local fill=btn(main,"2. ПОДГОТОВИТЬ 34/35 (НЕ УДАЛЯЕТ)",109,C.blue)
local race=btn(main,"3. ТЕСТ 2 ПОКУПОК (2 НАЖАТИЯ)",153,C.red)
local copy=btn(main,"4. КОПИРОВАТЬ ОТЧЁТ",197,C.green)
local help=add("TextLabel",{Position=UDim2.fromOffset(13,242),Size=UDim2.new(1,-26,0,46),BackgroundTransparency=1,Text="Подготовка покупает только дешёвые Tier 1 до 34/35. Тест покупает ЕЩЁ ДВА яйца одновременно. Без удаления питомцев.",TextColor3=C.muted,Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},main)
local scroll=add("ScrollingFrame",{Position=UDim2.fromOffset(13,291),Size=UDim2.new(1,-26,1,-302),BackgroundColor3=C.surface,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,300)},main)
round(scroll,8)
local output=add("TextLabel",{Position=UDim2.fromOffset(10,9),Size=UDim2.new(1,-22,0,280),BackgroundTransparency=1,Text="Тест ещё не запускался.\n\nНикаких команд покупки при открытии окна не отправляется.",Font=Enum.Font.Code,TextSize=12,TextColor3=C.ink,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},scroll)
local report="ZONEHUB INVENTORY RACEPROBE v3\nТест ещё не запускался"
local function show(text)
    report=text
    output.Text=text
    local lines=1
    for _ in text:gmatch("\n") do lines=lines+1 end
    local height=math.max(260,lines*18+28)
    output.Size=UDim2.new(1,-22,0,height)
    scroll.CanvasSize=UDim2.fromOffset(0,height+20)
    print(text)
end

-- Drag by header only, not by buttons.
local moving=false
local dragStart=nil
local posStart=nil
header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        moving=true
        dragStart=input.Position
        posStart=main.AbsolutePosition
        local connection
        connection=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                moving=false
                if connection then connection:Disconnect() end
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if moving and dragStart and posStart and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragStart
        main.Position=UDim2.fromOffset(math.max(0,posStart.X+delta.X),math.max(0,posStart.Y+delta.Y))
    end
end)

local function remotes()
    local root=workspace:FindFirstChild("__REMOTES")
    local core=root and root:FindFirstChild("Core")
    local gameR=root and root:FindFirstChild("Game")
    local get=core and core:FindFirstChild("Get Other Stats")
    local shop=gameR and gameR:FindFirstChild("Shop")
    if not (get and get:IsA("RemoteFunction")) then return nil,nil,"Нет Core / Get Other Stats" end
    if not (shop and shop:IsA("RemoteFunction")) then return nil,nil,"Нет Game / Shop" end
    return get,shop,nil
end
local function snapshot()
    local get,_,e=remotes()
    if e then return nil,e end
    local ok,data=pcall(function() return get:InvokeServer() end)
    if not ok then return nil,"Ошибка чтения: "..tostring(data) end
    local acc=type(data)=="table" and data[player.Name]
    local save=type(acc)=="table" and acc.Save
    if type(save)~="table" or type(save.Pets)~="table" or type(save.PetSlots)~="number" then
        return nil,"Не получен Save.Pets / Save.PetSlots"
    end
    local ids,count={},0
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            count=count+1
            if tonumber(p.id) then ids[tostring(p.id)]=tostring(p.n or "?") end
        end
    end
    return {count=count,cap=save.PetSlots,ids=ids},nil
end
local function newIds(before,after)
    local arr={}
    for id,kind in pairs(after.ids) do
        if not before.ids[id] then arr[#arr+1]=id.." ("..kind..")" end
    end
    table.sort(arr)
    return arr
end
local function purchase(shop)
    local ok,accepted,detail=pcall(function() return shop:InvokeServer("Buy","Eggs","Tier 1") end)
    return ok,accepted,detail
end
local busy=false
local armedAt=0
local attempted=false
local function lockButtons(value)
    busy=value
    scan.Active=not value
    fill.Active=not value
    race.Active=not value
end
local function run(taskFunction)
    if busy then return end
    lockButtons(true)
    task.spawn(function()
        local ok,err=pcall(taskFunction)
        if not ok then show("ZONEHUB RACEPROBE v3\nОШИБКА: "..tostring(err)) end
        lockButtons(false)
    end)
end
scan.MouseButton1Click:Connect(function()
    run(function()
        local snap,e=snapshot()
        if not snap then show("ОШИБКА: "..tostring(e)) return end
        show(string.format("ZONEHUB RACEPROBE v3\nСервер: %d/%d\nСвободно: %d\n\nЦель: ровно 34/35, затем 2 одновременные покупки.\nТест ещё не выполнялся.\nНичего не удаляется.",snap.count,snap.cap,math.max(0,snap.cap-snap.count)))
    end)
end)
fill.MouseButton1Click:Connect(function()
    run(function()
        local now,e=snapshot()
        if not now then show("Ошибка: "..tostring(e)) return end
        if now.cap~=35 then show("Остановка: лимит не 35, найдено "..tostring(now.cap)..". Этот эксперимент рассчитан только на 35 слотов.") return end
        local target=now.cap-1
        if now.count>=target then
            show("Подготовка не нужна. Сейчас "..now.count.."/"..now.cap..".\nДля теста нужно РОВНО 34/35.\nСкрипт ничего не удаляет.")
            return
        end
        local needed=target-now.count
        if needed>30 then show("Остановка: нужно более 30 покупок, вручную сократи разницу.") return end
        local _,shop,remoteErr=remotes()
        if remoteErr then show("Ошибка: "..remoteErr) return end
        local confirmed=0
        show(string.format("Подготовка до 34/35. Нужно купить %d дешёвых яиц.\nУдалений нет. Можно остановить, свернув окно и перезайдя в игру.",needed))
        for index=1,needed do
            local before,err=snapshot()
            if not before then show("Остановка на шаге "..index..": "..tostring(err)) return end
            if before.count>=target then break end
            local ok,accepted=purchase(shop)
            if not ok or accepted~=true then
                show(string.format("Остановка на покупке %d: ответ %s.\nКуплено с подтверждением: %d",index,tostring(accepted),confirmed))
                return
            end
            local advanced=false
            for tries=1,6 do
                task.wait(.15)
                local after=snapshot()
                if after and after.count==before.count+1 then
                    confirmed=confirmed+1
                    advanced=true
                    break
                end
            end
            if not advanced then
                local latest=snapshot()
                show("Остановка: сервер не подтвердил ровно +1 питомца.\nТекущий счёт: "..(latest and latest.count or "неизвестно").."\nПокупок подтверждено: "..confirmed)
                return
            end
            if index%5==0 then show("Подготовка: подтверждено "..confirmed.."/"..needed.." покупок.\nУдаления не выполнялись.") end
            task.wait(.08)
        end
        local done,err=snapshot()
        show("ПОДГОТОВКА ЗАВЕРШЕНА\nСейчас: "..(done and (done.count.."/"..done.cap) or tostring(err)).."\nПодтверждено покупок: "..confirmed.."\n\nЕсли ровно 34/35 — нажми тест дважды.")
    end)
end)

race.MouseButton1Click:Connect(function()
    if attempted then
        show(report.."\n\nПовторная попытка заблокирована в этой сессии для безопасности.")
        return
    end
    if busy then return end
    if armedAt==0 or os.clock()-armedAt>10 then
        armedAt=os.clock()
        race.Text="ПОДТВЕРДИ: 2 ПОКУПКИ (10 СЕК)"
        show("ПОДТВЕРЖДЕНИЕ\nНужен инвентарь 34/35.\nБудут отправлены ДВА запроса покупки Tier 1 одновременно.\nОба могут списать валюту, а питомец может добавиться только один.\nНичего не удаляем.\n\nНажми ту же кнопку ещё раз за 10 секунд.")
        return
    end
    armedAt=0
    race.Text="ТЕСТ УЖЕ ИСПОЛЬЗОВАН"
    attempted=true
    run(function()
        local before,e=snapshot()
        if not before then show("Тест не начат: "..tostring(e)) return end
        if before.cap~=35 or before.count~=34 then
            show(string.format("Тест не начат: инвентарь %d/%s. Нужно РОВНО 34/35. Покупки не отправлялись.",before.count,tostring(before.cap)))
            attempted=false
            race.Text="3. ТЕСТ 2 ПОКУПОК (2 НАЖАТИЯ)"
            return
        end
        local _,shop,err=remotes()
        if err then show("Тест не начат: "..err) attempted=false race.Text="3. ТЕСТ 2 ПОКУПОК (2 НАЖАТИЯ)" return end
        local results={}
        local finished=0
        local began=os.clock()
        show("ОТПРАВЛЕНО: 2 одновременные покупки Tier 1 при 34/35.\nОжидаю ответы сервера...")
        for index=1,2 do
            task.spawn(function()
                local ok,response,detail=purchase(shop)
                results[index]={ok=ok,response=response,kind=type(detail)}
                finished=finished+1
            end)
        end
        while finished<2 and os.clock()-began<14 do task.wait(.06) end
        local after=nil
        for tries=1,10 do
            task.wait(.25)
            after=snapshot()
            if after and after.count>before.count then
                -- Additional settling time ensures the second remote had time to apply.
                if tries>=4 then break end
            end
        end
        local lines={"ZONEHUB INVENTORY RACEPROBE v3 | ОТЧЁТ",string.format("До: %d/%d",before.count,before.cap)}
        lines[#lines+1]="Метод: 2 параллельных Shop:InvokeServer('Buy','Eggs','Tier 1')"
        lines[#lines+1]="Ответов: "..finished.."/2"
        for i=1,2 do
            local r=results[i]
            lines[#lines+1]="Покупка "..i..": "..(r and ("pcall="..tostring(r.ok)..", Shop="..tostring(r.response)..", данные="..tostring(r.kind)) or "тайм-аут (ответ ещё возможен)")
        end
        if after then
            local diff=newIds(before,after)
            lines[#lines+1]=string.format("После: %d/%d",after.count,after.cap)
            lines[#lines+1]="Новые ID: "..#diff
            for _,id in ipairs(diff) do lines[#lines+1]="  + "..id end
            if after.count>after.cap then
                lines[#lines+1]="РЕЗУЛЬТАТ: ПРЕВЫШЕНИЕ ЛИМИТА В СЕССИИ. Требуется проверить сохранение после перезахода."
            elseif after.count==after.cap then
                lines[#lines+1]="РЕЗУЛЬТАТ: 35/35; сервер не подтвердил превышение лимита при двух покупках."
            else
                lines[#lines+1]="РЕЗУЛЬТАТ: дополнительные питомцы не подтверждены."
            end
        else
            lines[#lines+1]="После: не удалось прочитать серверный инвентарь. Не повторяй тест до проверки вручную."
        end
        lines[#lines+1]="Выполнен только один опыт. Удалений, скрещивания и изменений Gamepass не было."
        show(table.concat(lines,"\n"))
    end)
end)
copy.MouseButton1Click:Connect(function()
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,report)
        if ok then copy.Text="СКОПИРОВАНО ✓" else copy.Text="ОШИБКА КОПИРОВАНИЯ" end
    else
        copy.Text="НЕТ КОПИРОВАНИЯ — СКРИНШОТ"
    end
    print(report)
end)
