-- ZoneHub 1.9 | Pet Simulator 2018 | Farm + Egg Hatch tiers 1..12
-- No diagnostic probes, hooks, external libraries or client-side pet PivotTo.
-- Egg calls are based on Pet Simulator 1 community code, not yet live-verified on this account.
-- Uses observed numeric Mine packets. Server behavior can change; client HP is only a proxy.
-- Keeps the v1.7 on-device profile format and filename for all four pets.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- Stop prior ZoneHub workers BEFORE destroying the old GUI.
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubShutdown)=="function" then pcall(env.ZoneHubShutdown) end
end
local old = pg:FindFirstChild("ZoneHub_PetSim")
if old then old:Destroy() end

local alive, farming, session = true, false, 0
local eggRunning, eggEpoch, eggTier = false, 0, 1
local eggOpened, eggAttempts, eggInventory, eggCapacity = 0, 0, nil, nil
local eggMessage = "Выбери яйцо Tier 1–12"
local connections, reserved, learned = {}, {}, {}
local logLines = {}
local cfg = {
    ids={15883528,25214651,92565120,95608754},
    minX=-3218.733,maxX=-2832.849,minZ=-1747.956,maxZ=-1468.381,
    groundY=144.810,interval=.42,mode="Near"
}
local stats = {mine=0, move=0, clientErrors=0, damage=0, gone=0, noProgress=0, workers=0}
local PROFILE_FILE = "ZoneHub_profiles_v17.json" -- intentionally unchanged
local storageStatus = "Проверка сохранения..."
local function timestamp() return os.date("%H:%M:%S") end
local statusLabel
local function log(msg, bad)
    table.insert(logLines, 1, (bad and "! " or "• ")..timestamp().." "..tostring(msg))
    while #logLines>5 do table.remove(logLines) end
    if bad then stats.clientErrors+=1 end
    if statusLabel then statusLabel.Text=table.concat(logLines,"\n") end
end
local function partOf(o)
    if not o then return nil end
    if o:IsA("BasePart") then return o end
    if o:IsA("Model") then return o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart",true) end
    return o:FindFirstChildWhichIsA("BasePart",true)
end
local function root()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function nodes()
    local things=workspace:FindFirstChild("__THINGS")
    local coins=things and things:FindFirstChild("Coins")
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    local mine=gameRemotes and gameRemotes:FindFirstChild("Coins")
    local pets=gameRemotes and gameRemotes:FindFirstChild("Pets")
    if mine and not mine:IsA("RemoteEvent") then mine=nil end
    if pets and not pets:IsA("RemoteEvent") then pets=nil end
    return coins,mine,pets
end
local function inside(p)
    return p.X>=cfg.minX and p.X<=cfg.maxX and p.Z>=cfg.minZ and p.Z<=cfg.maxZ
end
local function health(o)
    if not o then return nil end
    for _,name in ipairs({"Health","HP","Hp","health"}) do
        local v=o:FindFirstChild(name,true)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return v.Value end
        local attr=o:GetAttribute(name)
        if type(attr)=="number" then return attr end
    end
    return nil
end
local function scan()
    local folder=nodes()
    local result,total={},0
    if not folder then return result,0 end
    for _,coin in ipairs(folder:GetChildren()) do
        total+=1
        local part=partOf(coin)
        if part and inside(part.Position) then
            local hp=health(coin)
            if type(hp)=="number" and hp>0 then
                result[#result+1]={object=coin,pos=part.Position,hp=hp}
            end
        end
    end
    return result,total
end
local function orderCoins(items)
    local r=root()
    local o=r and r.Position or Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY,(cfg.minZ+cfg.maxZ)/2)
    table.sort(items,function(a,b)
        if cfg.mode=="LowHP" and a.hp~=b.hp then return a.hp<b.hp end
        if cfg.mode=="HighHP" and a.hp~=b.hp then return a.hp>b.hp end
        return (a.pos-o).Magnitude<(b.pos-o).Magnitude
    end)
end
local function validCoin(o)
    if not o or not o.Parent then return false end
    local part=partOf(o)
    local hp=health(o)
    return part~=nil and inside(part.Position) and type(hp)=="number" and hp>0
end
local function availablePets()
    local result={}
    for _,id in ipairs(cfg.ids) do
        local p=learned[id]
        if p and p.movement and type(p.movement.speed)=="number" and type(p.samples)=="table" and #p.samples>0 then
            result[#result+1]=id
        end
    end
    return result
end
local function profileCount() return #availablePets() end

-- Same strict schema as v1.7; no fabricated Mine samples for pet 92565120.
local function loadProfiles(raw)
    if type(raw)~="string" or #raw>160000 then return false,"Неверный размер JSON" end
    local ok,obj=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(obj)~="table" or obj.schema~=1 or type(obj.profiles)~="table" then
        return false,"Формат профиля не распознан"
    end
    local allowed={}
    for _,id in ipairs(cfg.ids) do allowed[id]=true end
    local count=0
    for _,p in ipairs(obj.profiles) do
        if type(p)=="table" and allowed[p.id] and type(p.samples)=="table" and type(p.frame)=="table" and #p.frame==12
            and type(p.speed)=="number" then
            local comps,samples={},{}
            for j=1,12 do
                if type(p.frame[j])~="number" then comps=nil break end
                comps[j]=p.frame[j]
            end
            for j=1,math.min(30,#p.samples) do
                if type(p.samples[j])=="number" then samples[#samples+1]=p.samples[j] end
            end
            if comps and #samples>0 then
                local okFrame,frame=pcall(function() return CFrame.new(table.unpack(comps)) end)
                if okFrame then
                    learned[p.id]={samples=samples,movement={frame=frame,speed=p.speed}}
                    count+=1
                end
            end
        end
    end
    return count>0, count>0 and count or "Не найдено корректных профилей"
end
local function toJson()
    local payload={schema=1,profiles={}}
    for _,id in ipairs(cfg.ids) do
        local p=learned[id]
        if p and p.movement and typeof(p.movement.frame)=="CFrame" and #p.samples>0 then
            local item={id=id,samples={},frame={p.movement.frame:GetComponents()},speed=p.movement.speed,sources={}}
            for j=1,math.min(#p.samples,30) do
                if type(p.samples[j])=="number" then item.samples[#item.samples+1]=p.samples[j] end
            end
            payload.profiles[#payload.profiles+1]=item
        end
    end
    return HttpService:JSONEncode(payload)
end
local function saveProfiles()
    -- A missing fourth profile must never overwrite a valid saved 4/4 file.
    if profileCount()<4 then return false,"Сохранение заблокировано: найдено меньше 4/4 профилей" end
    if type(writefile)~="function" then return false,"Запись файлов недоступна" end
    local ok,err=pcall(writefile,PROFILE_FILE,toJson())
    if ok then return true,"Сохранено "..profileCount().."/4 профилей" end
    return false,"Ошибка сохранения: "..tostring(err):sub(1,80)
end
-- Three profiles come from the supplied successful manual captures.
local known={
    {id=25214651,speed=3.5815804004669189,frame=CFrame.new(-3031,141.9644012,-1597),samples={145.05895256996155,175907.17931485176,176728.10179138184,176806.94916629791,176403.91777682304,176601.13730049133,176758.326618433,176452.94467020035}},
    {id=95608754,speed=4.7751576900482178,frame=CFrame.new(-3033,141.9645081,-1566),samples={122.49581408500671,168272.95349677405,168949.72115047774,168528.27377120656}},
    {id=15883528,speed=4.7751576900482178,frame=CFrame.new(-3051,141.9645081,-1533),samples={140.39686107635498,189985.11974716187,190698.23972892761,190765.38130712509,190999.33968448639}},
}
for _,p in ipairs(known) do
    learned[p.id]={samples=p.samples,movement={frame=p.frame,speed=p.speed}}
end
-- Load saved file; do not overwrite it if only 3 fallback profiles are available.
if type(readfile)=="function" then
    local readOk,raw=pcall(readfile,PROFILE_FILE)
    if readOk then
        local ok,n=loadProfiles(raw)
        storageStatus=ok and ("Загружено сохранение ("..n.." проф.)") or ("Сохранение повреждено: "..tostring(n))
    else storageStatus="Файл сохранения не найден" end
else storageStatus="Чтение файлов недоступно" end
-- Optional current-session recovery from v1.7, without requiring diagnostic controls.
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubLearnedProfiles)=="table" then
        for _,id in ipairs(cfg.ids) do
            local p=env.ZoneHubLearnedProfiles[id]
            if p and type(p.samples)=="table" and #p.samples>0 and p.movement
                and typeof(p.movement.frame)=="CFrame" and type(p.movement.speed)=="number" then
                learned[id]=p
            end
        end
    end
    env.ZoneHubLearnedProfiles=learned -- preserve profiles for a reload in this session
end

-- Egg purchase and capacity: original Pet Simulator 1 protocol, distinct from newer PSX/PS99.
-- Known community client calls:
--   workspace.__REMOTES.Game.Shop:InvokeServer("Buy", "Eggs", "Tier 12")
--   workspace.__REMOTES.Core["Get Other Stats"]:InvokeServer()[player.Name].Save
-- These are tested defensively here; no buy commands are issued on script load.
local eggStatusLabel, eggSelectedLabel, eggCountLabel
local function stopEggs(reason)
    eggRunning=false
    eggEpoch+=1
    if reason then eggMessage=reason end
end
local function eggRemotes()
    local r=workspace:FindFirstChild("__REMOTES")
    local core=r and r:FindFirstChild("Core")
    local gr=r and r:FindFirstChild("Game")
    local statsRemote=core and core:FindFirstChild("Get Other Stats")
    local shopRemote=gr and gr:FindFirstChild("Shop")
    if not statsRemote or not statsRemote:IsA("RemoteFunction") then statsRemote=nil end
    if not shopRemote or not shopRemote:IsA("RemoteFunction") then shopRemote=nil end
    return statsRemote,shopRemote
end
local function getEggInventory()
    local statsRemote=eggRemotes()
    if not statsRemote then return nil,nil,"Не найден Core / Get Other Stats" end
    local ok,data=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,nil,"Ошибка получения инвентаря: "..tostring(data):sub(1,75) end
    local own=type(data)=="table" and data[player.Name]
    local save=type(own)=="table" and own.Save
    if type(save)~="table" or type(save.Pets)~="table" or type(save.PetSlots)~="number" then
        return nil,nil,"Сервер не вернул Save.Pets / Save.PetSlots"
    end
    local count=#save.Pets
    if count==0 then
        for _ in pairs(save.Pets) do count+=1 end
    end
    return count,save.PetSlots,nil
end
local function eggSessionActive(epoch)
    return alive and eggRunning and eggEpoch==epoch
end
local function startEggs(onlyOne)
    if eggRunning then
        eggMessage="Открытие уже запущено; сначала останови его"
        return
    end
    local _,shop=eggRemotes()
    if not shop then
        eggMessage="Не найден Game.Shop (RemoteFunction)"
        log(eggMessage,true)
        return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local tier=eggTier
    eggRunning=true
    eggAttempts=0
    eggOpened=0
    eggMessage=(onlyOne and "Открываю одно яйцо" or "Открываю до полного инвентаря").." • Tier "..tier
    log("Яйца: "..(onlyOne and "одно" or "до заполнения")..", Tier "..tier)
    task.spawn(function()
        local ok,err=pcall(function()
            local failures=0
            while eggSessionActive(epoch) do
                local count,capacity,errorText=getEggInventory()
                if not eggSessionActive(epoch) then break end
                if errorText then
                    eggMessage=errorText
                    break
                end
                eggInventory,eggCapacity=count,capacity
                if count>=capacity then
                    eggMessage="Инвентарь заполнен ("..count.."/"..capacity.."). Остановлено."
                    break
                end
                eggAttempts+=1
                local invoked,result,extra=pcall(function()
                    local success,pet=shop:InvokeServer("Buy","Eggs","Tier "..tier)
                    return success,pet
                end)
                if not eggSessionActive(epoch) then break end
                if not invoked then
                    eggMessage="Ошибка открытия: "..tostring(result):sub(1,95)
                    break
                end
                if result~=true then
                    eggMessage="Покупка не подтверждена сервером ("..tostring(result):sub(1,40).."). Возможно, не хватает монет или яйцо недоступно."
                    break
                end
                -- Give the server stats time to reflect the new pet. Count increase proves receipt.
                local latest,cap,newErr
                for tries=1,4 do
                    task.wait(.38)
                    if not eggSessionActive(epoch) then break end
                    latest,cap,newErr=getEggInventory()
                    if newErr or (latest and latest>count) then break end
                end
                if not eggSessionActive(epoch) then break end
                if newErr then
                    eggMessage="Открытие вызвано, но проверить инвентарь не удалось: "..newErr
                    break
                end
                eggInventory,eggCapacity=latest,cap
                if not latest or latest<=count then
                    failures+=1
                    eggMessage="Сервер вернул успех, но питомец в инвентаре не появился; остановлено во избежание повторных покупок"
                    break
                end
                failures=0
                eggOpened+=latest-count
                eggMessage=string.format("Tier %d • получено: %d • инвентарь: %d/%d",tier,eggOpened,latest,cap)
                if onlyOne then
                    eggMessage=eggMessage.." • готово (одно открытие)"
                    break
                end
                if latest>=cap then
                    eggMessage=eggMessage.." • инвентарь заполнен"
                    break
                end
                -- Conservative delay to avoid excessive purchases and allow UI/server updates.
                task.wait(.65)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            if not ok then
                eggMessage="Ошибка цикла яиц: "..tostring(err):sub(1,90)
                log(eggMessage,true)
            else log("Яйца: "..eggMessage) end
        end
    end)
end

local function stopFarm()
    farming=false
    session+=1
    table.clear(reserved)
end
local function claimCoin(id)
    local options=scan()
    orderCoins(options)
    for _,info in ipairs(options) do
        if not reserved[info.object] and validCoin(info.object) then
            reserved[info.object]=id
            return info.object
        end
    end
    return nil
end
local function active(epoch)
    return alive and farming and epoch==session
end
local progressLabel
local function worker(epoch,id)
    local profile=learned[id]
    local target=nil
    local misses,totalMisses=0,0
    while active(epoch) do
        if not validCoin(target) then
            if target and reserved[target]==id then reserved[target]=nil end
            target=claimCoin(id)
            misses=0
            if not target then task.wait(.8) continue end
        end
        local _,mineRemote,petRemote=nodes()
        if not mineRemote or not petRemote then
            log("Игровые события пропали, фарм остановлен",true)
            stopFarm()
            break
        end
        local part=partOf(target)
        local before=health(target)
        if not part or not before then
            if reserved[target]==id then reserved[target]=nil end
            target=nil
            task.wait(.15)
            continue
        end
        local coinName=target.Name
        local location=part.Position -- preserve v1.7 zero-offset behavior when unknown
        local ok,err=pcall(function()
            petRemote:FireServer({{"PetMovement",player,id,CFrame.new(location),false,profile.movement.speed}})
        end)
        if not ok then log("Movement "..id..": "..tostring(err):sub(1,70),true) break end
        stats.move+=1
        task.wait(.06)
        local sent=0
        for j=1,math.min(#profile.samples,5) do
            if not active(epoch) or not validCoin(target) then break end
            local value=profile.samples[j]
            if type(value)~="number" then break end
            local mineOk,mineErr=pcall(function()
                mineRemote:FireServer("Mine",coinName,value,id)
            end)
            if not mineOk then
                log("Mine "..id..": "..tostring(mineErr):sub(1,70),true)
                break
            end
            sent+=1
            stats.mine+=1
            task.wait(cfg.interval)
        end
        task.wait(.55)
        if not active(epoch) then break end
        local after=health(target)
        if validCoin(target) and type(after)=="number" and after<before then
            local delta=before-after
            stats.damage+=delta
            misses=0
            if progressLabel then
                progressLabel.Text=string.format("4/4 профилей: %d | HP снято: %.0f\n%s → %s (−%.0f HP, %d Mine)",profileCount(),stats.damage,id,coinName,delta,sent)
            end
        elseif not validCoin(target) then
            stats.gone+=1 -- target could disappear for multiple reasons
            if reserved[target]==id then reserved[target]=nil end
            target=nil
            misses=0
        else
            misses+=1
            if misses>=2 then
                stats.noProgress+=1
                totalMisses+=1
                if reserved[target]==id then reserved[target]=nil end
                target=nil
                misses=0
                if totalMisses>=3 then
                    log("Питомец "..id.." остановлен после 3 неудачных целей",true)
                    break
                end
            end
        end
    end
    if target and reserved[target]==id then reserved[target]=nil end
    if epoch==session then
        stats.workers=math.max(0,stats.workers-1)
        if stats.workers==0 then
            farming=false
            log("Все потоки завершили работу")
        end
    end
end
local function startFarm()
    if farming then return end
    local ids=availablePets()
    if #ids==0 then log("Нет сохранённых профилей питомцев",true) return end
    if cfg.minX>=cfg.maxX or cfg.minZ>=cfg.maxZ then log("Неверные границы зоны",true) return end
    local coins,mine,pets=nodes()
    if not coins or not mine or not pets then log("Монеты или RemoteEvent не найдены",true) return end
    local found=scan()
    if #found==0 then log("В зоне нет монет с HP",true) return end
    session+=1
    local epoch=session
    farming=true
    table.clear(reserved)
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.workers=#ids
    if progressLabel then progressLabel.Text="Фарм запущен: "..#ids.." питомца. Отслеживаю HP..." end
    log("Запущен фарм: "..#ids.."/4 питомцев")
    for _,id in ipairs(ids) do
        task.spawn(function()
            local ok,err=pcall(worker,epoch,id)
            if not ok then
                log("Ошибка потока "..id..": "..tostring(err):sub(1,80),true)
                if epoch==session then
                    stats.workers=math.max(0,stats.workers-1)
                    if stats.workers==0 then farming=false end
                end
            end
        end)
    end
end

-- Minimal mobile interface.
local C={
    bg=Color3.fromRGB(12,16,27),panel=Color3.fromRGB(23,29,46),panel2=Color3.fromRGB(33,41,62),
    line=Color3.fromRGB(53,62,83),white=Color3.fromRGB(238,245,255),dim=Color3.fromRGB(161,174,196),
    blue=Color3.fromRGB(92,148,255),green=Color3.fromRGB(73,222,186),red=Color3.fromRGB(240,106,126),gold=Color3.fromRGB(246,202,119)
}
local function corner(o,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=o
end
local function border(o)
    local s=Instance.new("UIStroke") s.Thickness=1 s.Color=C.line s.Parent=o
end
local function label(parent,text,y,h,size,color,bold)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1 l.Position=UDim2.fromOffset(12,y)
    l.Size=UDim2.new(1,-24,0,h)
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.Text=text l.TextSize=size or 12 l.TextColor3=color or C.white
    l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=parent
    return l
end
local function panel(parent,h)
    local f=Instance.new("Frame") f.BackgroundColor3=C.panel f.BorderSizePixel=0
    f.Size=UDim2.new(1,0,0,h) f.Parent=parent corner(f,12)
    return f
end
local function button(parent,text,y,fn,color)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.GothamSemibold b.TextSize=13
    b.TextColor3=C.white b.BackgroundColor3=color or C.panel2 b.BorderSizePixel=0
    b.Size=UDim2.new(1,-24,0,39) b.Position=UDim2.fromOffset(12,y)
    b.AutoButtonColor=true b.Parent=parent corner(b,9)
    local conn=b.MouseButton1Click:Connect(function()
        if not alive then return end
        local ok,err=pcall(fn)
        if not ok then log("Кнопка: "..tostring(err):sub(1,80),true) end
    end)
    connections[#connections+1]=conn
    return b
end
local function box(parent,text,y,value,change)
    label(parent,text,y,18,11,C.dim)
    local e=Instance.new("TextBox") e.ClearTextOnFocus=false
    e.Size=UDim2.new(1,-24,0,32) e.Position=UDim2.fromOffset(12,y+20)
    e.Text=tostring(value) e.TextColor3=C.white e.BackgroundColor3=C.panel2
    e.PlaceholderColor3=C.dim e.Font=Enum.Font.Code e.TextSize=12
    e.TextXAlignment=Enum.TextXAlignment.Left e.Parent=parent corner(e,8)
    local conn=e.FocusLost:Connect(function()
        if not alive then return end
        local ok,err=pcall(change,e.Text)
        if not ok then log("Параметр: "..tostring(err),true) end
    end)
    connections[#connections+1]=conn
    return e
end
local function numeric(s,default)
    return tonumber((tostring(s):gsub(",","."))) or default
end
local gui=Instance.new("ScreenGui") gui.Name="ZoneHub_PetSim" gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true gui.DisplayOrder=260 gui.Parent=pg
local main=Instance.new("Frame") main.BackgroundColor3=C.bg main.BorderSizePixel=0
main.AnchorPoint=Vector2.new(.5,.5) main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromOffset(390,548) main.Parent=gui corner(main,18) border(main)
local scale=Instance.new("UIScale") scale.Parent=main
local function fit()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    scale.Scale=math.min(.97,(v.X-20)/400,(v.Y-20)/570)
end
fit()
connections[#connections+1]=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
local top=panel(main,74)
top.Size=UDim2.new(1,0,0,74)
label(top,"✦  ZONEHUB",10,28,21,C.white,true)
label(top,"1.9 • ФАРМ + ЯЙЦА TIER 1–12",42,16,10,C.dim,true)
local float=Instance.new("TextButton") float.Name="Float" float.Visible=false
float.Size=UDim2.fromOffset(66,49) float.AnchorPoint=Vector2.new(1,.5)
float.Position=UDim2.new(1,-12,.5,0) float.Text="✦ HUB"
float.Font=Enum.Font.GothamBold float.TextSize=13 float.TextColor3=C.white
float.BackgroundColor3=C.blue float.Parent=gui corner(float,12)
local hide=Instance.new("TextButton") hide.Text="—" hide.TextColor3=C.white
hide.BackgroundColor3=C.panel2 hide.BorderSizePixel=0 hide.TextSize=19
hide.Size=UDim2.fromOffset(43,35) hide.Position=UDim2.new(1,-54,0,17)
hide.Parent=top corner(hide,9)
connections[#connections+1]=hide.MouseButton1Click:Connect(function() main.Visible=false float.Visible=true end)
connections[#connections+1]=float.MouseButton1Click:Connect(function() main.Visible=true float.Visible=false end)
-- Header dragging, touch and mouse.
local moving,startPos,originPos,touch
connections[#connections+1]=top.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
        moving=true startPos=i.Position originPos=main.Position touch=i
    end
end)
connections[#connections+1]=top.InputEnded:Connect(function(i) if i==touch then moving=false end end)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(i)
    if moving and startPos and originPos and (i==touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=(i.Position-startPos)/math.max(.3,scale.Scale)
        main.Position=UDim2.new(originPos.X.Scale,originPos.X.Offset+d.X,originPos.Y.Scale,originPos.Y.Offset+d.Y)
    end
end)
local pageTab=Instance.new("Frame") pageTab.BackgroundTransparency=1
pageTab.Size=UDim2.new(1,-20,0,40) pageTab.Position=UDim2.fromOffset(10,82) pageTab.Parent=main
local tabs,pages={},{}
for i,name in ipairs({"Фарм","Яйца","Телепорт","Настройки"}) do
    local b=Instance.new("TextButton") b.Text=name b.TextSize=12 b.Font=Enum.Font.GothamBold
    b.TextColor3=C.white b.BackgroundColor3=C.panel2 b.BorderSizePixel=0
    b.Position=UDim2.new((i-1)/4,3,0,0) b.Size=UDim2.new(1/4,-7,1,0)
    b.Parent=pageTab corner(b,9) tabs[name]=b
    local scroll=Instance.new("ScrollingFrame") scroll.Name=name scroll.Visible=false
    scroll.Position=UDim2.fromOffset(10,131) scroll.Size=UDim2.new(1,-20,1,-204)
    scroll.BackgroundTransparency=1 scroll.BorderSizePixel=0
    scroll.CanvasSize=UDim2.new() scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
    scroll.ScrollBarThickness=3 scroll.ScrollBarImageColor3=C.blue scroll.Parent=main
    local layout=Instance.new("UIListLayout") layout.Padding=UDim.new(0,9)
    layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Parent=scroll
    pages[name]=scroll
end
local function switch(name)
    for n,p in pairs(pages) do p.Visible=n==name end
    for n,b in pairs(tabs) do b.BackgroundColor3=n==name and C.blue or C.panel2 end
end
for name,b in pairs(tabs) do
    connections[#connections+1]=b.MouseButton1Click:Connect(function() switch(name) end)
end
local footer=panel(main,59)
footer.Position=UDim2.new(0,10,1,-67) footer.Size=UDim2.new(1,-20,0,57)
statusLabel=label(footer,"Готово",5,49,10,C.dim)
statusLabel.TextYAlignment=Enum.TextYAlignment.Top

local farmPage=pages["Фарм"]
local hero=panel(farmPage,107)
label(hero,"Автофарм • выбранная зона",10,23,16,C.white,true)
local coinCount=label(hero,"Ищу монеты...",40,21,12,C.dim)
local workLabel=label(hero,"● ОСТАНОВЛЕН",70,23,13,C.red,true)
local actions=panel(farmPage,78)
local startButton -- initialized below
startButton=button(actions,"▶  ЗАПУСТИТЬ АВТОФАРМ",18,function()
    if farming then stopFarm() log("Автофарм остановлен") else startFarm() end
end,C.blue)
local selection=panel(farmPage,112)
label(selection,"Выбор монет",10,23,14,C.white,true)
local selections={{"Ближайшие","Near"},{"Меньше HP","LowHP"},{"Больше HP","HighHP"}}
local selectedButtons={}
for i,item in ipairs(selections) do
    local b=button(selection,item[1],43,function()
        cfg.mode=item[2]
        for _,entry in ipairs(selectedButtons) do
            entry.button.BackgroundColor3=(cfg.mode==entry.mode) and C.blue or C.panel2
        end
        log("Приоритет: "..item[1])
    end,C.panel2)
    b.Position=UDim2.new((i-1)/3,7,0,43) b.Size=UDim2.new(1/3,-9,0,40)
    b.TextSize=11
    selectedButtons[#selectedButtons+1]={button=b,mode=item[2]}
end
selectedButtons[1].button.BackgroundColor3=C.blue
local progress=panel(farmPage,152)
label(progress,"Результаты",9,25,14,C.white,true)
progressLabel=label(progress,"Подготовлено профилей: "..profileCount().."/4",36,55,12,C.white)
local function farmReport()
    return table.concat({
        "ZoneHub v1.9 | Автофарм",
        "Активен: "..tostring(farming).." | Потоков: "..stats.workers,
        string.format("HP снято: %.3f | исчезло целей: %d | без прогресса: %d",stats.damage,stats.gone,stats.noProgress),
        "Mine: "..stats.mine.." | PetMovement: "..stats.move,
        "Профилей: "..profileCount().."/4 | "..storageStatus,
        "Зона X: "..cfg.minX..".."..cfg.maxX.."; Z: "..cfg.minZ..".."..cfg.maxZ,
        "Состояние: "..progressLabel.Text,
        "Журнал: "..table.concat(logLines," | ")
    },"\n")
end
button(progress,"Скопировать отчёт",102,function()
    if type(setclipboard)~="function" then log("Буфер обмена Delta недоступен",true) return end
    local ok=pcall(setclipboard,farmReport())
    log(ok and "Отчёт скопирован" or "Ошибка копирования",not ok)
end,C.panel2)
local tip=panel(farmPage,108)
label(tip,"Почему питомцы стоят на месте?",10,24,13,C.gold,true)
label(tip,"HP уменьшается через игровые серверные события. Локальную анимацию полёта мы отключили: она конфликтовала с игрой и вызывала дрожание моделей. На добычу это не влияет.",36,66,11,C.dim)


local eggsPage=pages["Яйца"]
local eggsIntro=panel(eggsPage,88)
label(eggsIntro,"🥚 Открытие яиц • первый мир",8,24,15,C.white,true)
label(eggsIntro,"Выбери тир от 1 до 12. Покупка идёт через игровой Shop и тратит обычную валюту. Не открывай платные яйца.",34,48,11,C.dim)
local tierPanel=panel(eggsPage,241)
label(tierPanel,"Выбери Tier",10,25,14,C.white,true)
eggSelectedLabel=label(tierPanel,"Выбран: Tier 1",33,18,11,C.gold,true)
local tierButtons={}
for i=1,12 do
    local t=i
    local b=button(tierPanel,"Tier "..i,54+math.floor((i-1)/3)*45,function()
        if eggRunning then
            eggMessage="Сначала останови открытие яиц"
            return
        end
        eggTier=t
        eggSelectedLabel.Text="Выбран: Tier "..eggTier
        for id,btn in ipairs(tierButtons) do
            btn.BackgroundColor3=id==eggTier and C.blue or C.panel2
        end
    end,i==1 and C.blue or C.panel2)
    local col=(i-1)%3
    b.Position=UDim2.new(col/3,7,0,54+math.floor((i-1)/3)*45)
    b.Size=UDim2.new(1/3,-10,0,37)
    b.TextSize=12
    tierButtons[#tierButtons+1]=b
end
local eggActions=panel(eggsPage,180)
label(eggActions,"Режим открытия",9,23,14,C.white,true)
button(eggActions,"🥚 Открыть ОДНО яйцо",39,function() startEggs(true) end,C.blue)
button(eggActions,"▶ Открывать ДО ПОЛНОГО инвентаря",84,function() startEggs(false) end,C.green)
button(eggActions,"■ ОСТАНОВИТЬ открытие",129,function()
    stopEggs("Остановлено вручную")
    log("Открытие яиц остановлено")
end,C.red)
local eggInfo=panel(eggsPage,150)
label(eggInfo,"Статус открытия",9,25,14,C.white,true)
eggStatusLabel=label(eggInfo,"Ожидаю запуска",37,69,12,C.dim)
eggCountLabel=label(eggInfo,"Инвентарь: ещё не проверен",113,22,11,C.gold,true)
local eggHint=panel(eggsPage,105)
label(eggHint,"Автостоп",8,24,13,C.gold,true)
label(eggHint,"Остановка при полном инвентаре, отказе покупки, ошибке получения статистики или отсутствии подтверждённого нового питомца. Останавливать можно в любой момент.",33,65,11,C.dim)

local tele=pages["Телепорт"]
local tMain=panel(tele,94)
label(tMain,"Телепорт персонажа",10,27,15,C.white,true)
label(tMain,"Перемещает только твоего персонажа; сервер может вернуть назад. Телепорты мира не разблокирует.",39,48,12,C.dim)
local savedPoint
local function go(pos)
    local r=root()
    if not r then log("Персонаж не найден",true) return end
    r.CFrame=CFrame.new(pos)
    log(string.format("Позиция: %.0f / %.0f / %.0f",pos.X,pos.Y,pos.Z))
end
local tButtons=panel(tele,174)
button(tButtons,"Перейти в центр зоны",13,function()
    go(Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY+4,(cfg.minZ+cfg.maxZ)/2))
end,C.blue)
button(tButtons,"Запомнить текущую точку",63,function()
    local r=root()
    if r then savedPoint=r.Position log("Точка сохранена") else log("Персонаж не найден",true) end
end)
button(tButtons,"Вернуться к сохранённой точке",113,function()
    if savedPoint then go(savedPoint) else log("Точка ещё не сохранена",true) end
end)
local coords=panel(tele,265)
label(coords,"Свои координаты",9,25,14,C.white,true)
local rt=root()
local xEntry=box(coords,"X",38,rt and rt.Position.X or 0,function()end)
local yEntry=box(coords,"Y",95,rt and rt.Position.Y or cfg.groundY,function()end)
local zEntry=box(coords,"Z",152,rt and rt.Position.Z or 0,function()end)
button(coords,"Телепортироваться",212,function()
    local x,y,z=numeric(xEntry.Text),numeric(yEntry.Text),numeric(zEntry.Text)
    if not x or not y or not z then log("Нужно указать все 3 координаты",true) return end
    go(Vector3.new(x,y,z))
end,C.blue)

local settings=pages["Настройки"]
local profilePanel=panel(settings,123)
label(profilePanel,"Профили питомцев",10,26,15,C.white,true)
local profileLabel=label(profilePanel,"Загрузка...",38,67,12,C.dim)
local pInfo=panel(settings,112)
label(pInfo,"Настройки без обучения",10,25,14,C.gold,true)
label(pInfo,"Все 4 профиля сохраняются в ZoneHub_profiles_v17.json. Перехват ручной добычи, тестовые кнопки и дрожащая анимация удалены. Если файл пропадёт, четвёртый профиль нужно восстановить из резервной копии.",40,66,11,C.dim)
local intervalPanel=panel(settings,94)
box(intervalPanel,"Интервал между Mine (секунды, не меньше 0.40)",9,cfg.interval,function(t)
    cfg.interval=math.clamp(numeric(t,cfg.interval),.4,5)
    log("Интервал: "..cfg.interval.." с")
end)
local bounds=panel(settings,266)
label(bounds,"Ограничение зоны (X / Z)",9,25,14,C.white,true)
for index,entry in ipairs({{"minX","X минимум"},{"maxX","X максимум"},{"minZ","Z минимум"},{"maxZ","Z максимум"}}) do
    local key=entry[1]
    box(bounds,entry[2],38+(index-1)*55,cfg[key],function(t)
        local v=numeric(t,cfg[key])
        local old=cfg[key]
        cfg[key]=v
        if cfg.minX>=cfg.maxX or cfg.minZ>=cfg.maxZ then
            cfg[key]=old
            log("Min должен быть меньше Max",true)
        else log("Обновлена граница "..key) end
    end)
end
-- Backup controls are not diagnostic tests; keep them for recovering profile 92565120.
local recovery=panel(settings,230)
label(recovery,"Резервная копия",10,24,14,C.white,true)
button(recovery,"Сохранить профили на телефон",42,function()
    local ok,msg=saveProfiles()
    if ok then storageStatus=msg end
    log(msg,not ok)
end,C.blue)
button(recovery,"Скопировать резервную копию JSON",88,function()
    if type(setclipboard)~="function" then log("Буфер обмена недоступен",true) return end
    local ok=pcall(setclipboard,toJson())
    log(ok and "Резервная копия скопирована" or "Не удалось скопировать JSON",not ok)
end)
local jsonInput=box(recovery,"Вставить JSON для восстановления",134,"",function()end)
jsonInput.Text="" jsonInput.PlaceholderText="При необходимости вставь резервную копию"
button(recovery,"Восстановить из JSON",181,function()
    if farming then log("Сначала останови фарм",true) return end
    local ok,n=loadProfiles(jsonInput.Text)
    if not ok then log("Импорт: "..tostring(n),true) return end
    log("Восстановлено профилей: "..n)
    if profileCount()==4 then
        local saved,msg=saveProfiles()
        if saved then storageStatus=msg else log(msg,true) end
    end
    profileLabel.Text="Профилей: "..profileCount().."/4\n"..storageStatus
end,C.panel2)

local lastRefresh=0
local function refresh()
    local options,total=scan()
    coinCount.Text="Монет: "..total.." всего • "..#options.." в зоне"
    eggStatusLabel.Text=(eggRunning and "● РАБОТАЕТ • " or "● ОСТАНОВЛЕНО • ")..eggMessage
    eggCountLabel.Text="Покупок: "..eggAttempts.." • новых питомцев: "..eggOpened.." • инвентарь: "..(eggInventory and (eggInventory.."/"..(eggCapacity or "?")) or "не проверен")
    workLabel.Text=farming and ("● ФАРМ: "..stats.workers.." ПИТОМЦЕВ") or "● ОСТАНОВЛЕН"
    workLabel.TextColor3=farming and C.green or C.red
    startButton.Text=farming and "■  ОСТАНОВИТЬ" or "▶  ЗАПУСТИТЬ АВТОФАРМ"
    startButton.BackgroundColor3=farming and C.red or C.blue
    profileLabel.Text="Готово: "..profileCount().."/4\n"..storageStatus
    if not farming then progressLabel.Text=string.format("Профили: %d/4 | HP за прошлый запуск: %.0f\nMine: %d | Movement: %d | Ошибок: %d",profileCount(),stats.damage,stats.mine,stats.move,stats.clientErrors) end
end
connections[#connections+1]=RunService.Heartbeat:Connect(function()
    if not alive or not gui.Parent then return end
    local n=os.clock()
    if n-lastRefresh>=1.2 then lastRefresh=n refresh() end
end)
local function shutdown()
    stopEggs()
    stopFarm()
    alive=false
    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if type(getgenv)=="function" then getgenv().ZoneHubShutdown=shutdown end
switch("Фарм")
refresh()
log("v1.9: загружено "..profileCount().."/4 профилей. Тесты и дрожащая анимация удалены")
