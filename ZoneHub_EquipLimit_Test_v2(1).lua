-- ZoneHub | Equip-limit probe v2.0 | Original Pet Simulator (2018)
-- Safe, separate diagnostic; does not trade, unequip automatically, delete pets or call guessed remotes.
-- Requirements: Delta supports hookmetamethod, getnamecallmethod and the game's existing save data API.
-- One real manual equip capture -> ONE replay for another pet -> verify server-side equipped flags.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteRoot = workspace:FindFirstChild("__REMOTES")
local statsRemote = remoteRoot and remoteRoot:FindFirstChild("Core") and remoteRoot.Core:FindFirstChild("Get Other Stats")

local previous = playerGui:FindFirstChild("ZoneHub_EquipProbeV2")
if previous then previous:Destroy() end

local env = type(getgenv)=="function" and getgenv() or _G
local S = env.__ZoneHubEquipProbeV2
if type(S)~="table" then
    S={hooked=false,recording=false,events={},phase="idle"}
    env.__ZoneHubEquipProbeV2=S
end
S.recording=false
S.events={}
S.phase="idle"
S.sourceId=nil
S.template=nil
S.target=nil
S.lastReport="Нет результатов"

local function petId(v)
    local n=tonumber(v)
    if n and n>0 and n%1==0 then return n end
    return nil
end
local function snapshot()
    if not statsRemote or not statsRemote:IsA("RemoteFunction") then
        return nil,"Не найден __REMOTES.Core['Get Other Stats']"
    end
    local ok,data=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,"Ошибка чтения сервера: "..tostring(data) end
    local save=type(data)=="table" and type(data[player.Name])=="table" and data[player.Name].Save
    if type(save)~="table" or type(save.Pets)~="table" then return nil,"Нет Save.Pets в ответе сервера" end
    local out={pets={},equipped={},equippedCount=0,total=0}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=petId(p.id)
            if id and not out.pets[id] then
                local entry={id=id,name=tostring(p.n or "?"),level=tonumber(p.l) or 0,equipped=(p.e==true)}
                out.pets[id]=entry
                out.total+=1
                if entry.equipped then out.equipped[id]=true;out.equippedCount+=1 end
            end
        end
    end
    return out
end
local function matchesId(v,source,depth,seen)
    depth=depth or 0
    if depth>6 then return false end
    if type(v)=="number" and v==source then return true end
    if type(v)=="string" and v==tostring(source) then return true end
    if type(v)~="table" then return false end
    seen=seen or {}
    if seen[v] then return false end
    seen[v]=true
    for k,value in pairs(v) do
        if matchesId(k,source,depth+1,seen) or matchesId(value,source,depth+1,seen) then
            seen[v]=nil
            return true
        end
    end
    seen[v]=nil
    return false
end
local function hasEquipMarker(v,depth,seen)
    depth=depth or 0
    if depth>6 then return false end
    if type(v)=="string" then
        local str=string.lower(v)
        return string.find(str,"equip",1,true)~=nil or string.find(str,"wear",1,true)~=nil
    end
    if type(v)~="table" then return false end
    seen=seen or {}
    if seen[v] then return false end
    seen[v]=true
    for k,value in pairs(v) do
        if hasEquipMarker(k,depth+1,seen) or hasEquipMarker(value,depth+1,seen) then
            seen[v]=nil
            return true
        end
    end
    seen[v]=nil
    return false
end
local function isMiningPacket(args)
    if args[1]=="Mine" or args[1]=="StopMine" then return true end
    if type(args[1])=="table" then
        for _,v in pairs(args[1]) do
            if type(v)=="table" and (v[1]=="PetMovement" or v[1]=="Mine") then return true end
        end
    end
    return false
end
local function cloneReplacing(v,from,to,depth,seen)
    if type(v)=="number" and v==from then return to end
    if type(v)=="string" and v==tostring(from) then return tostring(to) end
    if type(v)~="table" then return v end
    if depth>=8 then error("Слишком глубокая таблица аргументов") end
    if seen[v] then error("Циклическая таблица аргументов") end
    seen[v]=true
    local out={}
    for k,value in pairs(v) do
        out[cloneReplacing(k,from,to,depth+1,seen)]=cloneReplacing(value,from,to,depth+1,seen)
    end
    seen[v]=nil
    return out
end
local function shortValue(v,depth,seen)
    depth=depth or 0
    if depth>3 then return "..." end
    if typeof(v)=="Instance" then return "Instance("..v.Name..")" end
    if type(v)=="string" then return string.format("%q",v:sub(1,90)) end
    if type(v)~="table" then return tostring(v) end
    seen=seen or {}
    if seen[v] then return "{цикл}" end
    seen[v]=true
    local parts,limit={},0
    for k,val in pairs(v) do
        limit+=1
        if limit>12 then parts[#parts+1]="...";break end
        parts[#parts+1]="["..shortValue(k,depth+1,seen).."]="..shortValue(val,depth+1,seen)
    end
    seen[v]=nil
    return "{"..table.concat(parts,",").."}"
end
local function describeEvent(e)
    if not e then return "нет" end
    local parts={}
    for i=1,math.min(e.args.n,4) do parts[#parts+1]="#"..i.."="..shortValue(e.args[i]) end
    return e.remote:GetFullName()..":"..e.method.." ("..table.concat(parts," ")..")"
end
local function installHook()
    if S.hooked then return true end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
        return false,"Delta не поддерживает перехват вызовов"
    end
    -- IMPORTANT: Never call Instance methods (including :IsDescendantOf())
    -- from within __namecall. Such calls can re-enter this hook and freeze the game.
    -- Ancestor checks use only .Parent property reads, and the original call always runs.
    local function isRemoteDescendant(inst)
        local node=inst
        for _=1,12 do
            if node==remoteRoot then return true end
            if node==nil then return false end
            node=node.Parent
        end
        return false
    end
    local wrap=type(newcclosure)=="function" and newcclosure or function(f)return f end
    local old
    local ok,err=pcall(function()
        old=hookmetamethod(game,"__namecall",wrap(function(self,...)
            if S.recording then
                local method=getnamecallmethod()
                if (method=="FireServer" or method=="InvokeServer") and typeof(self)=="Instance"
                    and self~=statsRemote and remoteRoot and isRemoteDescendant(self) then
                    local args=table.pack(...)
                    if not isMiningPacket(args) and #S.events<35 then
                        -- This block must not perform any Instance:Method() calls.
                        S.events[#S.events+1]={remote=self,method=method,args=args,clock=os.clock()}
                    end
                end
            end
            return old(self,...)
        end))
    end)
    if ok then S.hooked=true;return true end
    return false,tostring(err)
end

-- UI
local C={bg=Color3.fromRGB(13,18,30),panel=Color3.fromRGB(24,32,49),line=Color3.fromRGB(53,68,90),text=Color3.fromRGB(235,241,255),muted=Color3.fromRGB(164,178,203),accent=Color3.fromRGB(94,151,255),green=Color3.fromRGB(71,194,156),red=Color3.fromRGB(240,113,125)}
local gui=Instance.new("ScreenGui") gui.Name="ZoneHub_EquipProbeV2" gui.ResetOnSpawn=false gui.DisplayOrder=9999 gui.Parent=playerGui
local frame=Instance.new("Frame") frame.Name="Window" frame.Size=UDim2.fromOffset(420,418) frame.AnchorPoint=Vector2.new(.5,.5) frame.Position=UDim2.fromScale(.5,.5) frame.BackgroundColor3=C.bg frame.BorderSizePixel=0 frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,17)
local stroke=Instance.new("UIStroke",frame) stroke.Color=C.line stroke.Thickness=1
local scale=Instance.new("UIScale",frame)
local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800,600)
scale.Scale=math.clamp(math.min(viewport.X/460,viewport.Y/465),.65,1)
local function createText(parent,text,size,pos,sz,color,bold)
    local l=Instance.new("TextLabel") l.BackgroundTransparency=1 l.Text=text l.TextSize=size l.TextColor3=color or C.text
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham l.TextXAlignment=Enum.TextXAlignment.Left l.TextYAlignment=Enum.TextYAlignment.Center
    l.TextWrapped=true l.Position=pos l.Size=sz l.Parent=parent return l
end
local top=Instance.new("Frame") top.Size=UDim2.new(1,0,0,58) top.BackgroundColor3=C.panel top.BorderSizePixel=0 top.Parent=frame
Instance.new("UICorner",top).CornerRadius=UDim.new(0,17)
createText(top,"🐾  ZoneHub · Лимит экипировки",16,UDim2.fromOffset(15,5),UDim2.new(1,-68,0,28),C.text,true)
createText(top,"Проверка без трейда · одно действие",11,UDim2.fromOffset(16,32),UDim2.new(1,-72,0,18),C.muted)
local mini=Instance.new("TextButton") mini.Size=UDim2.fromOffset(37,34) mini.Position=UDim2.new(1,-47,0,11) mini.Text="−" mini.TextSize=23 mini.Font=Enum.Font.GothamBold mini.TextColor3=C.text mini.BackgroundColor3=C.line mini.Parent=top
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,9)
local bubble=Instance.new("TextButton") bubble.Size=UDim2.fromOffset(64,52) bubble.Position=UDim2.new(1,-78,0,90) bubble.Text="🐾" bubble.TextSize=25 bubble.BackgroundColor3=C.panel bubble.TextColor3=C.text bubble.Visible=false bubble.Parent=gui
Instance.new("UICorner",bubble).CornerRadius=UDim.new(1,0)
mini.MouseButton1Click:Connect(function() frame.Visible=false bubble.Visible=true end)
bubble.MouseButton1Click:Connect(function() frame.Visible=true bubble.Visible=false end)
local dragging,startInput,startPos
local function dragArea(area)
    area.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true startInput=input.Position startPos=frame.Position
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    area.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
            local d=input.Position-startInput
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end
dragArea(top)
local instruction=createText(frame,"1. Останови Auto Farm. В игре сними одного питомца.\n2. Нажми «Начать запись» и вручную надень его обратно.\n3. Нажми «Завершить», затем «Проверить +1».",12,UDim2.fromOffset(15,64),UDim2.new(1,-30,0,69),C.muted)
local countLabel=createText(frame,"Инвентарь: не считан",13,UDim2.fromOffset(15,135),UDim2.new(1,-30,0,28),C.text,true)
local function makeBtn(text,x,y,w,callback)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.GothamBold b.TextSize=12 b.TextColor3=C.text b.BackgroundColor3=C.panel b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,40) b.BorderSizePixel=0 b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
    b.MouseButton1Click:Connect(function()
        TweenService:Create(b,TweenInfo.new(.12),{BackgroundColor3=C.accent}):Play()
        task.delay(.17,function() if b.Parent then TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=C.panel}):Play() end end)
        callback()
    end)
    return b
end
local status=createText(frame,"Готово к проверке. Никакие серверные команды не отправляются автоматически.",12,UDim2.fromOffset(16,264),UDim2.new(1,-32,0,46),C.muted)
local reportLabel=createText(frame,"",11,UDim2.fromOffset(15,356),UDim2.new(1,-30,0,48),C.muted)
local function message(s) status.Text=s end
local function setReport(r)
    S.lastReport=r
    reportLabel.Text=r:sub(1,140)
    print("[ZoneHub EquipProbe v2] "..r)
end
local function refresh()
    local snap,err=snapshot()
    if not snap then message(err);return nil end
    countLabel.Text=string.format("Инвентарь: %d  |  экипировано: %d",snap.total,snap.equippedCount)
    return snap
end
local beforeManual=nil
makeBtn("1. Обновить",15,170,121,function() refresh() end)
makeBtn("2. Начать запись",147,170,258,function()
    if S.recording then message("Запись уже идёт") return end
    local snap=refresh()
    if not snap then return end
    local ok,err=installHook()
    if not ok then message("Нет перехвата: "..err);return end
    beforeManual=snap
    S.template=nil; S.sourceId=nil; S.events={}; S.recording=true
    message("Запись включена. Надень одного снятого питомца, затем заверши запись. Только один эксперимент.")
end)
makeBtn("3. Завершить запись",15,218,190,function()
    S.recording=false
    if not beforeManual then message("Сначала нажми «Начать запись»") return end
    local after=refresh()
    if not after then return end
    local added={}
    for id in pairs(after.equipped) do if not beforeManual.equipped[id] then added[#added+1]=id end end
    if #added~=1 then
        message("Нужно одно новое экипирование за время записи. Обнаружено: "..#added..". Попробуй ещё раз.")
        setReport("Неудачная запись: новых ID="..#added..", событий="..#S.events)
        return
    end
    S.sourceId=added[1]
    local eligible={}
    for _,ev in ipairs(S.events) do
        local hasId=false
        for i=1,ev.args.n do if matchesId(ev.args[i],S.sourceId) then hasId=true;break end end
        if hasId and (hasEquipMarker(ev.remote.Name) or hasEquipMarker(ev.args)) then eligible[#eligible+1]=ev end
    end
    if #eligible~=1 then
        message("Экипировка подтверждена, но не удалось однозначно определить её серверную команду. Событий: "..#S.events..", подходящих: "..#eligible..". Скопируй отчёт.")
        local lines={"ZoneHub EquipProbe v2 | CAPTURE", "Источник="..tostring(S.sourceId),"Подходящих="..#eligible,"Всего событий="..#S.events}
        for i,ev in ipairs(S.events) do lines[#lines+1]=i..". "..describeEvent(ev) end
        setReport(table.concat(lines,"\n"))
        return
    end
    S.template=eligible[1]
    message("Команда экипировки распознана. Экипировано: "..after.equippedCount..". Теперь можно один раз проверить слот сверх четырёх.")
    setReport("ZoneHub EquipProbe v2 | CAPTURE OK\nИсточник: "..S.sourceId.."\nКоманда: "..describeEvent(S.template))
end)
makeBtn("4. Проверить +1",215,218,190,function()
    if S.recording then message("Сначала заверши запись") return end
    if not S.template or not S.sourceId then message("Нет проверенной команды экипировки. Сначала запиши ручное надевание.") return end
    local current=refresh()
    if not current then return end
    if current.equippedCount<4 then message("Сейчас экипировано меньше 4: сначала заполни обычные слоты.") return end
    local options={}
    for id,p in pairs(current.pets) do
        if not p.equipped then options[#options+1]=p end
    end
    table.sort(options,function(a,b)
        if a.level~=b.level then return a.level<b.level end
        return a.id<b.id
    end)
    if #options==0 then message("Нет свободного питомца для безопасного теста") return end
    local target=options[1] -- lowest-level un-equipped; only ONE request
    S.target=target.id
    local ev=S.template
    local args={n=ev.args.n}
    local okCopy,errCopy=pcall(function()
        for i=1,ev.args.n do args[i]=cloneReplacing(ev.args[i],S.sourceId,target.id,0,{}) end
    end)
    if not okCopy then message("Копирование аргументов не удалось: "..tostring(errCopy));return end
    local okSend,ret=pcall(function()
        if ev.method=="InvokeServer" and ev.remote:IsA("RemoteFunction") then
            return ev.remote:InvokeServer(table.unpack(args,1,args.n))
        elseif ev.method=="FireServer" and ev.remote:IsA("RemoteEvent") then
            ev.remote:FireServer(table.unpack(args,1,args.n));return "FireServer вызван"
        end
        error("Неверный тип серверного события")
    end)
    if not okSend then message("Ошибка запроса: "..tostring(ret));setReport("Ошибка отправки: "..tostring(ret));return end
    message("Проверяется результат одной команды для ID "..target.id..". Это не подтверждение принятия сервером.")
    task.delay(1.3,function()
        local after,err=snapshot()
        if not after then message(err);return end
        countLabel.Text=string.format("Инвентарь: %d  |  экипировано: %d",after.total,after.equippedCount)
        local success=after.equipped[target.id] and after.equippedCount>current.equippedCount
        if success then
            message("ПОДТВЕРЖДЕНО: сервер показывает "..after.equippedCount.." экипированных вместо "..current.equippedCount.."! Перезайди для проверки сохранения.")
        else
            message("Превышение НЕ подтверждено. Было "..current.equippedCount..", стало "..after.equippedCount.."; ID "..target.id.." не добавился сверх лимита.")
        end
        setReport(table.concat({
            "ZoneHub EquipProbe v2 | РЕЗУЛЬТАТ",
            "До="..current.equippedCount.." / После="..after.equippedCount,
            "ID цели="..target.id.." ("..target.name..", уровень "..target.level..")",
            "ID экипирован после="..tostring(after.equipped[target.id]==true),
            "Сервер подтвердил превышение="..tostring(success),
            "Метод="..describeEvent(ev),
            "Ответ вызова="..tostring(ret),
            "Выполнена ровно одна попытка; обмены и удаление питомцев не выполнялись."
        },"\n"))
    end)
end)
makeBtn("Скопировать отчёт",15,360,390,function()
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,S.lastReport or "Нет отчёта")
        message(ok and "Отчёт скопирован в буфер обмена" or "Копирование не удалось; отчёт смотри в консоли")
    else
        message("Delta не поддерживает setclipboard. Отчёт выведен в консоль.")
    end
end)
reportLabel.Position=UDim2.fromOffset(15,310)
reportLabel.Size=UDim2.new(1,-30,0,43)
refresh()
message("Сними в игре ОДНОГО питомца, затем нажми «Начать запись» и надень его обратно. Не используй ценных питомцев для эксперимента.")
print("[ZoneHub EquipProbe v2] Готово. Скрипт не выполняет трейды и не отключает игроков.")
