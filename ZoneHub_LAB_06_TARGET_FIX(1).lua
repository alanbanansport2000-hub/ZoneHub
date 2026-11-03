--[[
 ZoneHub LAB 0.6 TARGET FIX | Original Pet Simulator (2018) | Android/Delta
 Standalone diagnostic laboratory. UI HOTFIX: manual content layout. DOES NOT execute or modify ZoneHub 3.7/4.0.
 Read-only by default. Only explicit, double-confirmed tests send PetMovement and Mine events.
 The 3-ID sequence sends at most THREE Mine calls, one per unique unequipped pet.
 LAB 0.6: fixes duplicate baseline fetch + weakest-coin selection for x2/x4.
 No gamepass bypass, duping, trading, egg buying, deletion, fusion, remote hooks,
 executor bypasses, external code, web traffic, or auto-equip.
 Historic comparison: retpirato/Roblox-Scripts Pet_Simulator.lua (2018) and
 Pet Simulator GUI.lua (2019); nullhubexe/ps1-branch listing not verified.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return warn("ZoneHub LAB: LocalPlayer unavailable") end

local parent = player:WaitForChild("PlayerGui",10)
if not parent then return warn("ZoneHub LAB: PlayerGui unavailable") end
local guiName = "ZoneHub_LAB_01"
local old = parent:FindFirstChild(guiName)
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100102
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local live = true
local connections = {}
local log = {}
local evidence = {}
local tests = {}
local metrics = {fps = 0,frames = 0,seconds = 0,lastSnapshot = 0,scanMs = 0,scanCount = 0}
local state = {parallelRuns={},seriesCancel=false,seriesDone=0,seriesGoal=3,seriesActive=false,save = nil,pets = {},byId = {},counts = {},coins = {},baseline = nil,lastError = nil,fetchBusy = false,scanBusy = false,petTrialAt = 0,trialBusy=false,trialMode=nil,trialCooldownUntil=0,oneEggTest=false,hatchHistory={}}
local PALETTE = {bg=Color3.fromRGB(9,14,26),panel=Color3.fromRGB(18,27,46),card=Color3.fromRGB(25,38,63),border=Color3.fromRGB(52,71,103),blue=Color3.fromRGB(88,139,255),purple=Color3.fromRGB(144,113,255),green=Color3.fromRGB(87,210,159),yellow=Color3.fromRGB(250,193,94),red=Color3.fromRGB(249,116,125),white=Color3.fromRGB(233,241,255),muted=Color3.fromRGB(151,167,193)}
local C = PALETTE
local function clock() return os.clock() end
local function tstamp() local ok,x=pcall(os.date,"%H:%M:%S"); return ok and x or "--:--:--" end
local function shorten(v,lim) local s=tostring(v); return #s>(lim or 300) and string.sub(s,1,lim or 300).."…" or s end
local function fmt(n)
    if type(n)~="number" then return tostring(n or "?") end
    if n ~= n or n==math.huge or n==-math.huge then return "?" end
    local abs=math.abs(n)
    if abs>=1e15 then return string.format("%.2fQ",n/1e15) end
    if abs>=1e12 then return string.format("%.2fT",n/1e12) end
    if abs>=1e9 then return string.format("%.2fB",n/1e9) end
    if abs>=1e6 then return string.format("%.2fM",n/1e6) end
    if abs>=1e4 then return string.format("%.1fK",n/1e3) end
    return string.format("%.0f",n)
end
local function addLog(s)
    table.insert(log,1,"["..tstamp().."] "..shorten(s,420))
    if #log>100 then table.remove(log) end
end
local function emit(key,title,status,detail)
    tests[key]={title=title,status=status,detail=detail,at=tstamp()}
    evidence[#evidence+1]={key=key,status=status,detail=detail,at=tstamp()}
    if #evidence>150 then table.remove(evidence,1) end
    addLog(status.." | "..title..": "..detail)
end
local function sortedKeys(tab)
    local arr={}
    for k in pairs(tab) do arr[#arr+1]=tostring(k) end
    table.sort(arr)
    return arr
end
local function findPath(root,parts)
    local x=root
    for _,name in ipairs(parts) do x=x and x:FindFirstChild(name) end
    return x
end
local function remote(kind,group,name)
    local r=findPath(workspace,{"__REMOTES",group,name})
    return (r and r:IsA(kind)) and r or nil
end
local function coinsFolder()
    for _,n in ipairs({"__THINGS","_THINGS"}) do
        local f=findPath(workspace,{n,"Coins"})
        if f then return f,n end
    end
    return nil,nil
end
local function rootPart()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function partOf(o)
    if not o then return nil end
    if o:IsA("BasePart") then return o end
    if o:IsA("Model") and o.PrimaryPart then return o.PrimaryPart end
    return o:FindFirstChildWhichIsA("BasePart",true)
end
local function health(o)
    if not o then return nil end
    for _,n in ipairs({"Health","HP","Hp","health"}) do
        local a=o:GetAttribute(n)
        if type(a)=="number" then return a end
        local c=o:FindFirstChild(n,true)
        if c and (c:IsA("NumberValue") or c:IsA("IntValue")) then return c.Value end
    end
    return nil
end
local function numberId(n)
    n=tonumber(n)
    return n and n==n and n>=1 and n<1e17 and n%1==0 and n or nil
end
local function ownSave(payload)
    if type(payload)~="table" then return nil end
    local rec=payload[player.Name]
    if type(rec)=="table" and type(rec.Save)=="table" then return rec.Save end
    if type(payload.Save)=="table" then return payload.Save end
    return nil
end
-- A single in-flight Read-Only RemoteFunction, timed out in the UI after 9s.
-- Roblox cannot cancel an InvokeServer that never returns. Never schedule another
-- Get Other Stats while a previous request is in-flight.
local function fetchSave()
    local r=remote("RemoteFunction","Core","Get Other Stats")
    if not r then return nil,"Core/Get Other Stats отсутствует" end
    if state.fetchBusy then return nil,"Предыдущая серверная проверка ещё выполняется" end
    state.fetchBusy=true
    local result={finished=false,ok=false,value=nil}
    task.spawn(function()
        local success,val=pcall(function() return r:InvokeServer() end)
        result.ok=success;result.value=val;result.finished=true
        state.fetchBusy=false
    end)
    local started=clock()
    while live and not result.finished and clock()-started<9 do task.wait(.08) end
    if not live then return nil,"Окно закрыто" end
    if not result.finished then return nil,"Тайм-аут 9 секунд (зависший запрос не дублируем)" end
    if not result.ok then return nil,"Ошибка получения: "..shorten(result.value,130) end
    local save=ownSave(result.value)
    if type(save)~="table" or type(save.Pets)~="table" then return nil,"Нет Save/Pets в ответе" end
    return save
end
local function normalizedSave(save)
    local pets,byId,counts = {},{}, {all=0,equipped=0,normal=0,gold=0,rainbow=0,dark=0,noID=0,duplicates=0}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            counts.all=counts.all+1
            local id=numberId(p.id)
            if not id then counts.noID=counts.noID+1
            elseif byId[id] then counts.duplicates=counts.duplicates+1
            else byId[id]=p end
            local v={id=id,equipped=p.e==true,level=tonumber(p.l),type=tostring(p.t or "?"),name=tostring(p.n or "?"),gold=p.g~=nil and p.g~=false and p.g~=0,rainbow=p.r~=nil and p.r~=false and p.r~=0,dark=p.dm~=nil and p.dm~=false and p.dm~=0,raw=p}
            if v.equipped then counts.equipped=counts.equipped+1 end
            local kind=v.dark and "dark" or v.rainbow and "rainbow" or v.gold and "gold" or "normal"
            counts[kind]=counts[kind]+1
            pets[#pets+1]=v
        end
    end
    table.sort(pets,function(a,b)
        local x,y=a.level or 0,b.level or 0
        if x==y then return (a.id or 0)<(b.id or 0) end
        return x>y
    end)
    return pets,byId,counts
end
local function snapshot()
    local save,err=fetchSave()
    if not save then
        emit("save","Серверный инвентарь","ERROR",err)
        state.lastError=err
        return false
    end
    state.save=save
    state.pets,state.byId,state.counts=normalizedSave(save)
    metrics.lastSnapshot=clock()
    emit("save","Серверный инвентарь","OK",tostring(state.counts.all).." питомцев / лимит "..tostring(save.PetSlots or "?"))
    return true
end
local function scanCoins()
    if state.scanBusy then return false,"Сканирование уже выполняется" end
    local folder,which=coinsFolder()
    if not folder then return false,"Не найдена папка __THINGS/_THINGS.Coins" end
    state.scanBusy=true
    local items={}
    local roots=rootPart()
    local pos=roots and roots.Position
    local started=clock()
    local total=0;local withHP=0;local nearby=0
    local children=folder:GetChildren()
    for i,coin in ipairs(children) do
        if not live then break end
        total=total+1
        local part=partOf(coin)
        if part then
            local hp=health(coin)
            local distance=pos and (part.Position-pos).Magnitude or nil
            if type(hp)=="number" and hp>0 then withHP=withHP+1 end
            if distance and distance<=500 then nearby=nearby+1 end
            if hp and hp>0 then
                items[#items+1]={obj=coin,name=coin.Name,hp=hp,distance=distance,pos=part.Position}
            end
        end
        if i%125==0 then task.wait() end -- cooperative; avoids mobile frame spikes
    end
    table.sort(items,function(a,b)
        if a.hp==b.hp then return (a.distance or math.huge)<(b.distance or math.huge) end
        return a.hp>b.hp
    end)
    metrics.scanMs=(clock()-started)*1000
    metrics.scanCount=total
    state.coins=items
    state.scanBusy=false
    return true,string.format("%s.Coins: %d объектов; HP доступны: %d; до 500 studs: %d; %.1f мс",which,total,withHP,nearby,metrics.scanMs)
end
local function runAudit(includeNetwork)
    if not live then return end
    local f,folderName=coinsFolder()
    local core=remote("RemoteFunction","Core","Get Other Stats")
    local mine=remote("RemoteEvent","Game","Coins")
    local move=remote("RemoteEvent","Game","Pets")
    local shop=remote("RemoteFunction","Game","Shop")
    local inventory=remote("RemoteFunction","Game","Inventory")
    local trading=remote("RemoteFunction","Game","Trading")
    local hasModules = core and mine and move and f
    emit("protocol","Протокол игры",hasModules and "OK" or "WARN","Save="..tostring(core~=nil)..", Coins:Mine="..tostring(mine~=nil)..", Pets:Movement="..tostring(move~=nil)..", Coins="..tostring(folderName or "нет"))
    local tradeFields={}
    if state.save and type(state.save.Pets)=="table" then
        for _,p in pairs(state.save.Pets) do
            if type(p)=="table" then
                for k in pairs(p) do
                    local low=string.lower(tostring(k))
                    if low:find("trade",1,true) or low:find("lock",1,true) then tradeFields[tostring(k)]=true end
                end
                break
            end
        end
    end
    emit("trading","Обмены","INFO","Game.Trading="..tostring(trading~=nil).."; поля питомца о торговле="..table.concat(sortedKeys(tradeFields),",")..". Обмены не выполняются")
    emit("autonomy","Автономная система","INFO","Датчики: save="..tostring(core~=nil)..", farm="..tostring(mine~=nil)..", яйца="..tostring(shop~=nil)..", инвентарь="..tostring(inventory~=nil)..". Выполнение действий НЕ включено")
    emit("teleport","Телепорт","INFO","Наличие PlayerGui.Teleport: "..tostring(parent:FindFirstChild("Teleport",true)~=nil).."; доступность интерфейса не доказывает покупку Game Pass")
    emit("performance","Производительность","INFO","FPS="..tostring(metrics.fps).."; скан="..string.format("%.1f",metrics.scanMs).." мс / "..metrics.scanCount.." монет; LAB не запускает автодействия")
    if not includeNetwork then return end
    if not snapshot() then return end
    local save=state.save;local n=state.counts
    emit("slots","Вместимость",type(save.PetSlots)=="number" and "OK" or "UNKNOWN","Сервер: "..tostring(n.all).."/"..tostring(save.PetSlots or "?").."; MaxPets="..tostring(save.MaxPets or "?").."; HatSlots="..tostring(save.HatSlots or "?"))
    local free=math.max(0,(tonumber(save.PetSlots) or 0)-n.all)
    emit("army","Pet Army",n.all>n.equipped and "READY" or "WARN",n.equipped.." экипировано / "..n.all.." всего; свободных ID: "..(n.all-n.equipped)..". Для проверки урона нужен отдельный подтверждаемый тест")
    local valid=0
    for _,p in ipairs(state.pets) do if p.id and p.level and p.level>0 then valid=valid+1 end end
    emit("equip","Экипировка",n.equipped <= (tonumber(save.MaxPets) or math.huge) and "INFO" or "WARN","Экипировано "..n.equipped.."/"..tostring(save.MaxPets or "?").."; питомцев с числовыми ID и уровнем "..valid..". Изменений не выполняю")
    emit("turbo","Turbo Farm","INFO","Возможна адаптивная очередь по измеренному FPS/ответам; предельную скорость без отдельного теста подтвердить нельзя")
    local withLevel=0
    for _,p in ipairs(state.pets) do if p.id and p.level then withLevel=withLevel+1 end end
    emit("exp","Прокачка EXP",withLevel>0 and "READY" or "UNKNOWN","Читаются уровни: "..withLevel.." питомцев; изменение EXP можно измерить после обычного фарма")
    local passFields={}
    for _,k in ipairs(sortedKeys(save)) do
        if string.find(string.lower(k),"pass",1,true) or string.find(string.lower(k),"slot",1,true) or string.find(string.lower(k),"luck",1,true) or string.find(string.lower(k),"clone",1,true) then
            passFields[#passFields+1]=k.."="..shorten(save[k],32)
        end
    end
    emit("passes","Game Pass / улучшения","INFO","Найденные поля: "..(#passFields>0 and table.concat(passFields,"; ") or "нет явных")..". Право собственности на Game Pass не проверялось")
    emit("cloner","Pet Cloner ×3","UNVERIFIED","Пока нет парных снимков ДО/ПОСЛЕ одиночной ручной покупки; без покупки Cloner дополнительные копии не подтверждены")
    emit("rarity","Шансы редких питомцев","UNVERIFIED","Инвентарь читается, но официальные вероятности по нему не вычисляются. Возможен учёт фактических выпадений при выключенном автоудалении")
    emit("capacity","Слоты > лимита","UNVERIFIED","Свободных мест "..free..". Увеличение числа на экране не создаёт серверные слоты")
    emit("fusion","Золото/Rainbow/Dark Matter","INFO","Нормальных "..n.normal..", Gold "..n.gold..", Rainbow "..n.rainbow..", Dark "..n.dark..". Изменения запрещены")
    emit("protection","Защита от дублей ID",n.duplicates==0 and "OK" or "WARN","Повторяющихся уникальных ID: "..n.duplicates.."; питомцев без числового ID: "..n.noID)
end
local function runWorld()
    local ok,msg=scanCoins()
    emit("world","Глобальный сбор монет",ok and "INFO" or "WARN",msg)
    if not ok then return end
    local top={}
    for i=1,math.min(6,#state.coins) do
        local c=state.coins[i]
        top[#top+1]=c.name.." HP="..fmt(c.hp).." dist="..(c.distance and fmt(c.distance) or "?")
    end
    emit("radar","Радар монет","OK",#state.coins.." подходящих объектов по HP; топ: "..(#top>0 and table.concat(top," | ") or "нет"))
    emit("optimization","Оптимизация фарма","INFO","Монеты загружены, можно тестировать стратегию выбора. Никаких запросов Mine при сканировании нет")
end
local function saveBaseline()
    if not state.save then emit("baseline","Снимок для сравнения","WARN","Сначала получи серверный инвентарь") return end
    local copy={ids={},counts={},levels={},types={},currencies={},at=tstamp(),time=clock()}
    for _,p in ipairs(state.pets) do
        if p.id then
            copy.ids[p.id]=true
            copy.levels[p.id]=p.level
            copy.types[p.id]=p.type
        end
    end
    for _,key in ipairs({"Coins","MoonCoins","SnowCoins"}) do
        if type(state.save[key])=="number" then copy.currencies[key]=state.save[key] end
    end
    copy.counts={all=state.counts.all,equipped=state.counts.equipped,petSlots=state.save.PetSlots}
    state.baseline=copy
    emit("baseline","Снимок ДО","OK",copy.at..": "..copy.counts.all.." питомцев; затем вручную выполни действие и нажми «Сравнить»")
end
local function compareBaseline()
    local base=state.baseline
    if not base then emit("compare","Сравнение","WARN","Сначала нажми «Снимок ДО»") return end
    if not state.save then return end
    local newer,missing={},{ }
    for _,p in ipairs(state.pets) do if p.id and not base.ids[p.id] then newer[#newer+1]=p end end
    for id in pairs(base.ids) do if not state.byId[id] then missing[#missing+1]=id end end
    local levels={}
    for _,p in ipairs(state.pets) do
        if p.id and base.levels[p.id] and p.level and p.level~=base.levels[p.id] then
            levels[#levels+1]=tostring(p.id).." "..fmt(base.levels[p.id]).."→"..fmt(p.level)
        end
    end
    local wallet={}
    for key,oldval in pairs(base.currencies) do
        local curr=state.save[key]
        if type(curr)=="number" then wallet[#wallet+1]=key.." "..fmt(curr-oldval) end
    end
    local grouped={}
    for _,p in ipairs(newer) do
        local k=p.name.." (t="..p.type..")"
        grouped[k]=(grouped[k] or 0)+1
    end
    local groups={}
    for k,n in pairs(grouped) do groups[#groups+1]=k.." ×"..n end
    table.sort(groups)
    local timeSpan=math.max(1,clock()-base.time)
    local description=string.format("за %.0f с: +%d ID, -%d ID, уровней изменено %d; валюты: %s",timeSpan,#newer,#missing,#levels,table.concat(wallet,"; "))
    emit("compare","Сравнение ДО/ПОСЛЕ","OK",description)
    emit("hatching","Новые питомцы",#newer>0 and "OBSERVED" or "INFO",#newer.." новых уникальных ID: "..(#groups>0 and table.concat(groups,"; ") or "нет")..". Без автоудаления результаты точнее")
    emit("levelDelta","Изменения EXP/уровней",#levels>0 and "OBSERVED" or "INFO",#levels>0 and table.concat(levels,"; ") or "Изменений уровня нет; скрытый прогресс EXP не определён")
    if #newer>0 then
        for _,p in ipairs(newer) do
            state.hatchHistory[#state.hatchHistory+1]={name=p.name,type=p.type,id=p.id,at=tstamp()}
            if #state.hatchHistory>250 then table.remove(state.hatchHistory,1) end
        end
    end
    if state.oneEggTest then
        local sameType=true
        for i=2,#newer do
            if newer[i].type~=newer[1].type then sameType=false break end
        end
        if #newer==3 and sameType and #missing==0 then
            emit("cloner","Pet Cloner ×3","INCONCLUSIVE","Получено 3 ID одного типа, но LAB НЕ считает число покупок. При открытии ×3 это три обычных питомца, а не подтверждение Pet Cloner; проверь списание валюты и режим открытия")
        elseif #newer==1 and #missing==0 then
            emit("cloner","Pet Cloner ×3","INFO","После заявленного одного открытия: 1 новый ID, множитель ×1. Дополнительные копии не наблюдались")
        else
            emit("cloner","Pet Cloner ×3","INCONCLUSIVE","Новых ID "..#newer..", исчезло "..#missing.."; эксперимент неоднозначен. Убедись, что автоудаление и параллельный фарм/яйца отключены")
        end
        state.oneEggTest=false
    elseif #newer>0 then
        emit("cloner","Pet Cloner ×3","INFO","Новых ID: "..#newer.."; число открытых яиц неизвестно. Для проверки используй снимок ровно одного яйца")
    end
    if #missing>0 then emit("removed","Исчезнувшие питомцы","WARN",#missing.." ID отсутствуют; проверь автоудаление, скрещивание или обмен") end
    if #newer>0 then
        emit("observedOdds","Наблюдаемые выпадения","INFO","За период получено "..#newer.."; без подтверждённого числа открытых яиц не вычисляю проценты")
    end
end
local function activeArmyTrial(mode)
    local finish = mode == "finish"
    local label = finish and "Pet Army — награда за монету" or "Pet Army — 1 удар"
    if not state.save or not state.pets then emit("armyTrial",label,"WARN","Сначала выполни обзор") return end
    if state.trialBusy then return end
    local coinEvent=remote("RemoteEvent","Game","Coins")
    local moveEvent=remote("RemoteEvent","Game","Pets")
    if not coinEvent or not moveEvent then emit("armyTrial",label,"WARN","Нет Coins/Pets RemoteEvent") return end
    local options={}
    for _,p in ipairs(state.pets) do
        if not p.equipped and p.id and p.level and p.level>0 and p.level < 1e13 then
            options[#options+1]=p
        end
    end
    table.sort(options,function(a,b) return a.level<b.level end)
    if #options==0 then emit("armyTrial",label,"WARN","Нет неэкипированных питомцев с валидными ID и уровнями") return end
    local chosen=options[1]
    local damage=2*chosen.level-1
    if type(state.save.Hats)=="table" and numberId(chosen.raw.h) then
        for _,hat in pairs(state.save.Hats) do
            if type(hat)=="table" and numberId(hat.id)==numberId(chosen.raw.h) and tonumber(hat.l) then
                damage=damage+tonumber(hat.l)*2; break
            end
        end
    end
    if damage<=0 then emit("armyTrial",label,"WARN","Уровень даёт некорректный расчёт урона") return end
    state.trialBusy=true
    local ok,msg=scanCoins()
    if not ok then state.trialBusy=false;emit("armyTrial",label,"WARN",msg) return end
    local candidate=nil
    for _,coin in ipairs(state.coins) do
        if coin.distance and coin.distance<420 then
            local suitable = finish and (coin.hp>0 and coin.hp <= damage*0.95)
                or ((not finish) and coin.hp >= math.max(1000,damage*1.2))
            if suitable then
                -- Normal test: smallest durable coin. Finish test: nearest killable coin.
                if not candidate or (finish and coin.distance<candidate.distance)
                    or ((not finish) and coin.hp<candidate.hp) then candidate=coin end
            end
        end
    end
    if not candidate then
        state.trialBusy=false
        local minHP=math.max(1000,damage*1.2)
        local detail=finish and ("Нет монеты до 420 studs с 0 < HP ≤ "..fmt(damage*0.95).." (урон выбранного питомца "..fmt(damage).."). Подойди к слабой монете")
            or ("Нет стабильной монеты до 420 studs с HP ≥ "..fmt(minHP).." (раньше порог был ×4). Подойди к более прочной монете")
        emit("armyTrial",label,"WARN",detail)
        return
    end
    local beforeSave=nil
    if finish then
        local err
        beforeSave,err=fetchSave()
        if not beforeSave then
            state.trialBusy=false
            emit("armyTrial",label,"WARN","Не удалось получить баланс ДО удара: "..tostring(err))
            return
        end
    end
    local startHP=health(candidate.obj)
    task.wait(.65)
    if not live or not candidate.obj.Parent or health(candidate.obj)~=startHP then
        state.trialBusy=false
        emit("armyTrial",label,"INCONCLUSIVE","Монета изменилась до теста. Останови обычный фарм и повтори")
        return
    end
    local before=health(candidate.obj)
    local sentMove,moveErr=pcall(function()
        moveEvent:FireServer({{"PetMovement",player,chosen.id,CFrame.new(candidate.pos),false,4.7751576900482178}})
    end)
    if not sentMove then
        state.trialBusy=false
        emit("armyTrial",label,"ERROR","PetMovement: "..shorten(moveErr,160))
        return
    end
    task.wait(.10)
    local sentMine,mineErr=pcall(function() coinEvent:FireServer("Mine",candidate.name,damage,chosen.id) end)
    if not sentMine then
        state.trialBusy=false
        emit("armyTrial",label,"ERROR","Mine: "..shorten(mineErr,160))
        return
    end
    task.wait(finish and 1.5 or .65)
    local after=health(candidate.obj)
    if finish then
        local afterSave,err=fetchSave()
        state.trialBusy=false
        if not afterSave then
            emit("armyReward",label,"INCONCLUSIVE","Удар отправлен, но не удалось прочитать баланс ПОСЛЕ: "..tostring(err))
            return
        end
        local gains={};local any=false
        for _,wallet in ipairs({"Coins","MoonCoins","SnowCoins"}) do
            local a,b=beforeSave[wallet],afterSave[wallet]
            if type(a)=="number" and type(b)=="number" then
                local d=b-a
                if d~=0 then gains[#gains+1]=wallet.." "..(d>0 and "+" or "")..fmt(d) end
                if d>0 then any=true end
            end
        end
        local gone = (not candidate.obj.Parent) or type(after)~="number" or after<=0
        local result=any and "OBSERVED" or "INCONCLUSIVE"
        emit("armyReward",label,result,string.format("Неэкип. ID %s, цель %s, HP до %.0f, после %s, монета исчезла=%s; валюта: %s. Начисление подтверждается только при выключенном другом фарме",tostring(chosen.id),candidate.name,before,type(after)=="number" and fmt(after) or "недоступно",tostring(gone),#gains>0 and table.concat(gains,"; ") or "нет изменений"))
        return
    end
    state.trialBusy=false
    if type(before)~="number" or type(after)~="number" then
        emit("armyTrial",label,"INCONCLUSIVE","Монета исчезла / HP недоступен после теста; не считаю успехом")
        return
    end
    local delta=before-after
    if delta>0 and math.abs(delta-damage)<math.max(2,damage*.001) then
        emit("armyTrial",label,"OBSERVED",string.format("Неэкипированный ID %s: HP %.0f → %.0f (−%.0f), совпало с аргументом Mine %.0f. Отдельный тест награды теперь доступен",tostring(chosen.id),before,after,delta,damage))
    elseif delta>0 then
        emit("armyTrial",label,"INCONCLUSIVE",string.format("HP %.0f → %.0f (−%.0f), ожидалось −%.0f; возможны параллельные действия. Успех не подтверждён",before,after,delta,damage))
    else
        emit("armyTrial",label,"UNVERIFIED","Не обнаружено уменьшения HP от неэкипированного ID "..tostring(chosen.id).."; аргумент "..fmt(damage))
    end
end


-- LAB 0.4: bounded multi-ID verification, at most 3 unique unequipped pet IDs.
-- Unlike an infinite farm, it never automatically restarts or repeats an ID.
-- Each attempt takes its own wallet snapshot and only counts a reward if the
-- selected coin was destroyed AND a supported server balance increased.
local function multiArmyTrial()
    if state.trialBusy then emit("multiArmy","Pet Army — 3 разных ID","WARN","Другая проверка ещё выполняется") return end
    state.trialBusy=true
    state.seriesActive=true
    state.seriesCancel=false
    state.seriesDone=0
    local function runSequence()
        if not snapshot() then return end
        local mine=remote("RemoteEvent","Game","Coins")
        local movement=remote("RemoteEvent","Game","Pets")
        if not mine or not movement then
            emit("multiArmy","Pet Army — 3 разных ID","ERROR","Отсутствует Coins/Pets RemoteEvent")
            return
        end
        local choices={}
        for _,p in ipairs(state.pets) do
            if not p.equipped and p.id and p.level and p.level>0 and p.level<1e13 then
                choices[#choices+1]=p
            end
        end
        table.sort(choices,function(a,b) return a.level>b.level end)
        if #choices<3 then
            emit("multiArmy","Pet Army — 3 разных ID","WARN","Нужно минимум 3 неэкипированных питомца с числовыми ID")
            return
        end
        local selected={choices[1],choices[2],choices[3]}
        local usedCoins={}
        local attempts,damageObserved,rewardsObserved=0,0,0
        local details={}
        for index,p in ipairs(selected) do
            if not live or state.seriesCancel then
                details[#details+1]="Остановлено перед питомцем "..index
                break
            end
            if metrics.fps>0 and metrics.fps<25 then
                details[#details+1]="Остановка: FPS ниже 25"
                break
            end
            local damage=2*p.level-1
            if type(state.save.Hats)=="table" and numberId(p.raw.h) then
                for _,hat in pairs(state.save.Hats) do
                    if type(hat)=="table" and numberId(hat.id)==numberId(p.raw.h) and tonumber(hat.l) then
                        damage=damage+tonumber(hat.l)*2
                        break
                    end
                end
            end
            if damage<=0 or damage~=damage then
                details[#details+1]="ID "..p.id..": некорректный урон"
                break
            end
            local scanOk,err=scanCoins()
            if not scanOk then
                details[#details+1]="ID "..p.id..": скан не удался: "..tostring(err)
                break
            end
            local candidate=nil
            for _,coin in ipairs(state.coins) do
                if coin.distance and coin.distance<=420 and coin.hp>0 and coin.hp<=damage*.95
                    and not usedCoins[coin.name] then
                    if not candidate or coin.distance<candidate.distance then candidate=coin end
                end
            end
            if not candidate then
                details[#details+1]="ID "..p.id..": нет рядом монеты, которую можно добить одним ударом (урон "..fmt(damage)..")"
                break
            end
            usedCoins[candidate.name]=true
            local beforeSave,saveErr=fetchSave()
            if not beforeSave then
                details[#details+1]="ID "..p.id..": баланс до удара недоступен: "..tostring(saveErr)
                break
            end
            local hpBefore=health(candidate.obj)
            task.wait(.5)
            if not live or state.seriesCancel then
                details[#details+1]="Прервано до удара ID "..p.id
                break
            end
            if not candidate.obj.Parent or health(candidate.obj)~=hpBefore then
                details[#details+1]="ID "..p.id..": монета изменена сторонним действием, серия остановлена"
                break
            end
            local okMove,moveErr=pcall(function()
                movement:FireServer({{"PetMovement",player,p.id,CFrame.new(candidate.pos),false,4.7751576900482178}})
            end)
            if not okMove then
                details[#details+1]="ID "..p.id..": PetMovement error "..shorten(moveErr,90)
                break
            end
            task.wait(.12)
            if not live or state.seriesCancel then
                details[#details+1]="Отменено до Mine для ID "..p.id
                break
            end
            local okMine,mineErr=pcall(function()
                mine:FireServer("Mine",candidate.name,damage,p.id)
            end)
            if not okMine then
                details[#details+1]="ID "..p.id..": Mine error "..shorten(mineErr,90)
                break
            end
            attempts=attempts+1
            state.seriesDone=attempts
            task.wait(1.65)
            local hpAfter=health(candidate.obj)
            local destroyed=(not candidate.obj.Parent) or (type(hpAfter)=="number" and hpAfter<=0)
            if destroyed then damageObserved=damageObserved+1 end
            local afterSave,afterErr=fetchSave()
            if not afterSave then
                details[#details+1]="ID "..p.id..": баланс после удара недоступен: "..tostring(afterErr)
                break
            end
            local gainParts={}
            local gainPositive=false
            for _,key in ipairs({"Coins","MoonCoins","SnowCoins"}) do
                local old,new=beforeSave[key],afterSave[key]
                if type(old)=="number" and type(new)=="number" and new-old~=0 then
                    local change=new-old
                    gainParts[#gainParts+1]=key.." "..(change>0 and "+" or "")..fmt(change)
                    if change>0 then gainPositive=true end
                end
            end
            local rewarded=destroyed and gainPositive
            if rewarded then rewardsObserved=rewardsObserved+1 end
            local status=rewarded and "OBSERVED" or "INCONCLUSIVE"
            local message="ID "..p.id.." / "..candidate.name.." HP "..fmt(hpBefore).." → "..
                (type(hpAfter)=="number" and fmt(hpAfter) or "недоступно")..
                "; уничтожена="..tostring(destroyed).."; баланс "..
                (#gainParts>0 and table.concat(gainParts,", ") or "без изменений")
            details[#details+1]=message
            emit("multiPet"..index,"Pet Army — питомец "..index,status,message)
            if not rewarded then
                details[#details+1]="Серия остановлена: результат не подтверждён"
                break
            end
            task.wait(1.25)
        end
        local status=(rewardsObserved==3 and attempts==3) and "OBSERVED" or "INCONCLUSIVE"
        emit("multiArmy","Pet Army — 3 разных ID",status,
            "Отправлено ударов "..attempts.."/3; монет уничтожено "..damageObserved.."; наград за монеты "..rewardsObserved.."/3. "..
            table.concat(details," | ")..". Не подтверждает работу 119 питомцев одновременно; при другом активном фарме результат неоднозначен")
    end
    local ok,err=pcall(runSequence)
    if not ok then emit("multiArmy","Pet Army — 3 разных ID","ERROR",shorten(err,200)) end
    state.trialBusy=false
    state.seriesActive=false
    state.seriesCancel=false
end


-- LAB 0.6: bounded near-simultaneous test for 2 or 4 DIFFERENT unequipped IDs.
-- At most one hit per selected ID; distinct nearby targets, never loops.
-- The total wallet gain cannot be attributed to each concurrent pet individually.
local function parallelArmyTrial(requested)
    local label="Pet Army — параллельно ×"..tostring(requested)
    local key="parallel"..tostring(requested)
    if requested~=2 and requested~=4 then return end
    if state.trialBusy or state.seriesActive then
        emit(key,label,"WARN","Другая проверка ещё выполняется") return
    end
    if state.parallelRuns[requested] then
        emit(key,label,"WARN","Этот пакет из "..requested.." ударов уже выполнялся в текущем запуске LAB. Для повторения перезапусти LAB") return
    end
    state.trialBusy=true;state.seriesActive=true;state.seriesCancel=false
    state.seriesDone=0;state.seriesGoal=requested
    local ok,err=pcall(function()
        if not live then return end
        if not snapshot() then emit(key,label,"WARN","Не удалось прочитать свежий серверный инвентарь") return end
        local mine=remote("RemoteEvent","Game","Coins")
        local movement=remote("RemoteEvent","Game","Pets")
        if not mine or not movement then emit(key,label,"ERROR","Нет необходимых RemoteEvent") return end
        local fpsBefore=metrics.fps
        if fpsBefore>0 and fpsBefore<35 then emit(key,label,"WARN","FPS ниже 35 до эксперимента; остановлено") return end
        local choices={}
        for _,p in ipairs(state.pets) do
            if not p.equipped and p.id and p.level and p.level>0 and p.level<1e13 then choices[#choices+1]=p end
        end
        table.sort(choices,function(a,b) if a.level==b.level then return a.id<b.id end return a.level>b.level end)
        if #choices<requested then
            emit(key,label,"WARN","Недостаточно неэкипированных питомцев: "..#choices.." из "..requested) return
        end
        local scanOK,scanError=scanCoins()
        if not scanOK then emit(key,label,"WARN",tostring(scanError)) return end
        local used,prepared={},{}
        for i=1,requested do
            local p=choices[i]
            local damage=2*p.level-1
            if type(state.save.Hats)=="table" and numberId(p.raw.h) then
                for _,hat in pairs(state.save.Hats) do
                    if type(hat)=="table" and numberId(hat.id)==numberId(p.raw.h) and tonumber(hat.l) then
                        damage=damage+2*tonumber(hat.l);break
                    end
                end
            end
            if damage<=0 or damage~=damage or damage==math.huge then
                emit(key,label,"WARN","Недопустимый расчёт урона ID "..p.id) return
            end
            local best=nil
            for _,coin in ipairs(state.coins) do
                -- Only targets that can be defeated in ONE calculated hit.
                -- Prefer the weakest target, not the nearest high-HP chest.
                if coin.obj and coin.obj.Parent and coin.distance and coin.distance<=420
                  and coin.hp>0 and coin.hp<=damage*.9 and not used[coin.name] then
                    if not best or coin.hp<best.hp or (coin.hp==best.hp and coin.distance<best.distance) then best=coin end
                end
            end
            if not best then
                emit(key,label,"WARN","Нет "..requested.." монет с HP ≤ 90% урона в радиусе 420 studs. Для ID "..p.id.." урон "..fmt(damage)..". Подойди к обычным слабым монетам")
                return
            end
            used[best.name]=true
            prepared[#prepared+1]={pet=p,coin=best,damage=damage,hpBefore=health(best.obj)}
        end
        -- Snapshot already fetched the authoritative Save once at the start of this test.
        -- Do NOT call Get Other Stats a second time for the same baseline (0.5 timed out here).
        -- Copy scalar balances immediately; never retain a mutable save table as our baseline.
        local beforeSave=state.save
        if type(beforeSave)~="table" then emit(key,label,"ERROR","Нет снимка баланса после инвентаризации") return end
        local prevWallet={}
        for _,name in ipairs({"Coins","MoonCoins","SnowCoins"}) do
            if type(beforeSave[name])=="number" then prevWallet[name]=beforeSave[name] end
        end
        if next(prevWallet)==nil then emit(key,label,"ERROR","Не найдено числовых полей валюты") return end
        task.wait(.35)
        if state.seriesCancel or not live then emit(key,label,"INFO","Отменено до действий") return end
        for _,unit in ipairs(prepared) do
            if not unit.coin.obj.Parent or health(unit.coin.obj)~=unit.hpBefore then
                emit(key,label,"INCONCLUSIVE","Цель "..unit.coin.name.." изменилась до начала; другой фарм должен быть выключен")
                return
            end
        end
        local moved=0
        for _,unit in ipairs(prepared) do
            if state.seriesCancel or not live then emit(key,label,"INFO","Остановлено до действий") return end
            local movedOK,movedErr=pcall(function()
                movement:FireServer({{"PetMovement",player,unit.pet.id,CFrame.new(unit.coin.pos),false,4.7751576900482178}})
            end)
            if not movedOK then emit(key,label,"ERROR","PetMovement ID "..unit.pet.id..": "..shorten(movedErr,120)) return end
            moved=moved+1
        end
        task.wait(.12)
        if state.seriesCancel or not live then emit(key,label,"INFO","Отменено до Mine") return end
        for _,unit in ipairs(prepared) do
            if not unit.coin.obj.Parent or health(unit.coin.obj)~=unit.hpBefore then
                emit(key,label,"INCONCLUSIVE","Цель "..unit.coin.name.." изменилась до отправки Mine") return
            end
        end
        state.parallelRuns[requested]=true -- only one packet of this size per launch
        local started=clock()
        local sent=0
        local failure=nil
        for _,unit in ipairs(prepared) do
            if state.seriesCancel or not live then failure="Остановлено после "..sent.." отправок";break end
            local callOK,callErr=pcall(function()
                mine:FireServer("Mine",unit.coin.name,unit.damage,unit.pet.id)
            end)
            if not callOK then failure="Mine: "..shorten(callErr,120);break end
            sent=sent+1;state.seriesDone=sent
            -- 0.5 sent all packets in ~0.1 ms; a small gap makes any server throttling observable.
            -- This remains a short overlapping group, NOT a sustained automatic farm.
            if sent<requested then task.wait(.20) end
        end
        local spreadMs=(clock()-started)*1000
        -- Wait briefly for coin replication; stop when every target visibly changed.
        -- Waiting does not mean we keep attacking: each pet gets ONE Mine call only.
        local deadline=clock()+3.5
        while live and not state.seriesCancel and clock()<deadline do
            local pending=0
            for _,unit in ipairs(prepared) do
                if unit.coin.obj.Parent and health(unit.coin.obj)==unit.hpBefore then pending=pending+1 end
            end
            if pending==0 then break end
            task.wait(.20)
        end
        local vanished,changed,results=0,0,{}
        for _,unit in ipairs(prepared) do
            local post=health(unit.coin.obj)
            local gone=(not unit.coin.obj.Parent) or (type(post)=="number" and post<=0)
            local changedHP=gone or (type(post)=="number" and post<unit.hpBefore)
            if gone then vanished=vanished+1 end
            if changedHP then changed=changed+1 end
            results[#results+1]="ID "..unit.pet.id.."/"..unit.coin.name.." "..fmt(unit.hpBefore).."→"..(type(post)=="number" and fmt(post) or "недоступно").." ("..(gone and "исчезла" or changedHP and "HP уменьшился" or "HP НЕ изменился")..")"
        end
        local afterSave,afterError=fetchSave()
        if not afterSave then
            emit(key,label,"INCONCLUSIVE","Mine "..sent.."/"..requested..", изменён HP "..changed.."/"..requested..", уничтожено "..vanished.."/"..requested.."; баланс ПОСЛЕ недоступен: "..tostring(afterError).."; "..table.concat(results," | ")) return
        end
        local balances={};local gain=false
        for _,name in ipairs({"Coins","MoonCoins","SnowCoins"}) do
            if prevWallet[name] and type(afterSave[name])=="number" then
                local delta=afterSave[name]-prevWallet[name]
                if delta~=0 then
                    balances[#balances+1]=name.." "..(delta>0 and "+" or "")..fmt(delta)
                    if delta>0 then gain=true end
                end
            end
        end
        local status=(sent==requested and vanished==requested and gain and not failure) and "OBSERVED" or "INCONCLUSIVE"
        local detail="Mine "..sent.."/"..requested..", изменён HP "..changed.."/"..requested..", уничтожено "..vanished.."/"..requested..
            "; общий баланс "..(#balances>0 and table.concat(balances,", ") or "без изменений")..
            "; длительность пакета "..string.format("%.0f",spreadMs).." мс; FPS до/после "..fpsBefore.."/"..metrics.fps..
            "; "..table.concat(results," | ")..
            (failure and "; "..failure or "")..
            ". Общая награда не доказывает индивидуальное начисление каждым питомцем, но последовательный тест 0.4 это проверял"
        emit(key,label,status,detail)
    end)
    if not ok then emit(key,label,"ERROR",shorten(err,230)) end
    state.trialBusy=false;state.seriesActive=false;state.seriesCancel=false
end

local function report()
    local output={"ZoneHub LAB 0.6 TARGET FIX | Pet Simulator (2018)","Дата: "..tstamp(),"PlaceId: "..tostring(game.PlaceId),"Игрок: [скрыто]","FPS: "..tostring(metrics.fps),"Примечание: read-only по умолчанию; платные бонусы не разблокируются",""}
    local keys=sortedKeys(tests)
    for _,k in ipairs(keys) do
        local v=tests[k]
        output[#output+1]=v.title.." ["..v.status.."]"
        output[#output+1]="  "..v.detail
    end
    output[#output+1]=""
    output[#output+1]="История (последние 25):"
    for i=1,math.min(25,#log) do output[#output+1]=log[i] end
    return table.concat(output,"\n")
end

-- === Android UI ===
local function create(kind,properties,parentInstance)
    local o=Instance.new(kind)
    for k,v in pairs(properties or {}) do o[k]=v end
    o.Parent=parentInstance
    return o
end
local function round(o,r) create("UICorner",{CornerRadius=UDim.new(0,r or 12)},o) return o end
local function stroke(o) create("UIStroke",{Color=C.border,Thickness=1,Transparency=.32},o) end
local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(400,740)
local W=math.min(450,math.max(290,view.X-18))
local H=math.min(565,math.max(335,view.Y-75))
local main=round(create("Frame",{Name="Panel",Size=UDim2.fromOffset(W,H),Position=UDim2.new(.5,-W/2,.5,-H/2),BackgroundColor3=C.bg,BorderSizePixel=0,Active=true},gui),16)
stroke(main)
local header=round(create("Frame",{Size=UDim2.new(1,-12,0,52),Position=UDim2.fromOffset(6,6),BackgroundColor3=C.panel,BorderSizePixel=0,Active=true},main),12)
local title=create("TextLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(14,6),Size=UDim2.new(1,-115,0,23),Font=Enum.Font.GothamBold,TextSize=17,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.white,Text="◈ ZONEHUB LAB 0.6"},header)
create("TextLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(14,30),Size=UDim2.new(1,-115,0,16),Font=Enum.Font.Gotham,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.muted,Text="PS1 • DIAGNOSTIC • OPT-IN TESTS"},header)
local function smallButton(parentInstance,text,x,w,color)
    local b=round(create("TextButton",{Size=UDim2.fromOffset(w,34),Position=UDim2.new(1,x,0,9),Text=text,TextSize=15,Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundColor3=color or C.card,AutoButtonColor=true,BorderSizePixel=0},parentInstance),9)
    return b
end
local close=smallButton(header,"×",-41,33,C.card)
local minimize=smallButton(header,"−",-79,33,C.card)
local mini=round(create("TextButton",{Name="FloatingLAB",Size=UDim2.fromOffset(61,61),Position=UDim2.new(1,-73,.48,0),Text="🔬\nLAB",TextSize=15,Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundColor3=C.blue,BorderSizePixel=0,Visible=false},gui),18)
local tabBar=create("ScrollingFrame",{Name="Tabs",Size=UDim2.new(1,-12,0,42),Position=UDim2.fromOffset(6,66),BackgroundTransparency=1,ScrollBarThickness=0,ScrollingDirection=Enum.ScrollingDirection.X,AutomaticCanvasSize=Enum.AutomaticSize.X,CanvasSize=UDim2.fromOffset(0,0)},main)
create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder},tabBar)
-- UI FIX: NO AutomaticCanvasSize/UIListLayout for content. Explicit pixel heights
-- and offsets avoid invisible pages on some Android/Delta clients.
local body=create("ScrollingFrame",{Name="Body",Size=UDim2.new(1,-12,1,-163),Position=UDim2.fromOffset(6,113),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.blue,ScrollingEnabled=true,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.None,CanvasSize=UDim2.fromOffset(0,0)},main)
local bodyCursor=8
local function putInBody(obj,height)
    height=math.max(1,math.ceil(height))
    obj.Position=UDim2.fromOffset(4,bodyCursor)
    obj.Size=UDim2.new(1,-8,0,height)
    bodyCursor=bodyCursor+height+8
    body.CanvasSize=UDim2.fromOffset(0,math.max(bodyCursor+12, H-155))
    return obj
end
local function textHeight(value,size,font,width,minHeight)
    value=tostring(value or "")
    local success,bounds=pcall(function()
        return TextService:GetTextSize(value,size,font,Vector2.new(math.max(80,width),10000))
    end)
    if success and bounds and type(bounds.Y)=="number" and bounds.Y>0 then
        return math.max(minHeight or size+6,math.ceil(bounds.Y)+6)
    end
    -- Fallback if TextService unavailable. utf8.len avoids Cyrillic bytes overcount.
    local ok,count=pcall(function() return utf8.len(value) end)
    if not ok or not count then count=#value end
    local charsPerLine=math.max(14,math.floor(math.max(90,width)/(size*0.58)))
    local newlines=1
    for _ in string.gmatch(value,"\n") do newlines=newlines+1 end
    return math.max(minHeight or size+6, math.ceil(count/charsPerLine+newlines-1)*(size+5)+6)
end
local footer=round(create("Frame",{Size=UDim2.new(1,-12,0,39),Position=UDim2.new(0,6,1,-45),BackgroundColor3=C.panel,BorderSizePixel=0},main),10)
local footerLabel=create("TextLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(11,0),Size=UDim2.new(1,-22,1,0),Font=Enum.Font.Gotham,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.muted,Text="Готово • по умолчанию ничего не меняем"},footer)
local current="Обзор";local activeButtons={}
local pageConnections={}
local draw
local function setBusy(s) if live then footerLabel.Text=s end end
local function run(label,fn)
    if state.uiBusy then setBusy("⏳ Завершите текущую операцию") return end
    state.uiBusy=true
    setBusy("⏳ "..label)
    task.spawn(function()
        local ok,err=pcall(fn)
        if not ok then emit("uierror","Ошибка LAB","ERROR",shorten(err,300)) end
        state.uiBusy=false
        if live then setBusy(ok and "✓ "..label.." завершено" or "! Ошибка, см. журнал");draw() end
    end)
end
local function labelText(text,color,isHeader)
    local font=isHeader and Enum.Font.GothamBold or Enum.Font.Gotham
    local sz=isHeader and 15 or 12
    local h=textHeight(text,sz,font,W-42,isHeader and 27 or 24)
    local lb=create("TextLabel",{BackgroundTransparency=1,Font=font,TextSize=sz,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextColor3=color or C.white,Text=tostring(text)},body)
    return putInBody(lb,h)
end
local function tile(heading,desc,status)
    heading=tostring(heading or "")
    desc=tostring(desc or "")
    local hd=23
    local dh=textHeight(desc,11,Enum.Font.Gotham,W-56,22)
    local h=11+hd+dh+15
    local frame=round(create("Frame",{BackgroundColor3=C.panel,BorderSizePixel=0},body),11)
    putInBody(frame,h)
    local color=status=="OK" and C.green or status=="OBSERVED" and C.green or status=="ERROR" and C.red or status=="WARN" and C.yellow or C.blue
    create("TextLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(11,8),Size=UDim2.new(1,-22,0,hd),Text=heading..(status and "  ["..status.."]" or ""),Font=Enum.Font.GothamBold,TextSize=12,TextColor3=color,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},frame)
    create("TextLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(11,8+hd),Size=UDim2.new(1,-22,0,dh),Text=desc,TextWrapped=true,Font=Enum.Font.Gotham,TextSize=11,TextYAlignment=Enum.TextYAlignment.Top,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.muted},frame)
    return frame
end
local function actionButton(name,callback,tint)
    local button=round(create("TextButton",{Text=name,Font=Enum.Font.GothamBold,TextSize=12,TextWrapped=true,TextColor3=C.white,BackgroundColor3=tint or C.card,BorderSizePixel=0,AutoButtonColor=true},body),10)
    putInBody(button,46)
    pageConnections[#pageConnections+1]=button.MouseButton1Click:Connect(callback)
    return button
end
local function allTests()
    local a={}
    for _,t in pairs(tests) do a[#a+1]=t end
    table.sort(a,function(x,y) return x.title<y.title end)
    return a
end
local function textList(t,empty)
    if #t==0 then labelText(empty or "Пока данных нет",C.muted) return end
    for _,item in ipairs(t) do tile(item.title,item.detail,item.status) end
end
local tabs={"Обзор","Монеты","Питомцы","Эксперименты","Журнал"}
for i,name in ipairs(tabs) do
    local b=round(create("TextButton",{LayoutOrder=i,Size=UDim2.fromOffset(name=="Эксперименты" and 136 or 90,36),BackgroundColor3=C.panel,TextColor3=C.muted,Font=Enum.Font.GothamBold,TextSize=11,Text=name,BorderSizePixel=0,AutoButtonColor=true},tabBar),9)
    activeButtons[name]=b
    connections[#connections+1]=b.MouseButton1Click:Connect(function() current=name;draw() end)
end
local function showReport()
    local txt=report()
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,txt)
        setBusy(ok and "✓ Отчёт скопирован" or "! Ошибка копирования")
        if ok then return end
    end
    local existing=gui:FindFirstChild("ReportOverlay")
    if existing then existing:Destroy() end
    local mask=round(create("Frame",{Name="ReportOverlay",Size=UDim2.new(1,-20,1,-20),Position=UDim2.fromOffset(10,10),BackgroundColor3=C.bg,ZIndex=50,BorderSizePixel=0},gui),12)
    create("TextLabel",{Text="ОТЧЁТ • выдели текст и скопируй",TextSize=13,Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,30),Position=UDim2.fromOffset(10,8),ZIndex=51},mask)
    create("TextBox",{Text=txt,TextSize=12,Font=Enum.Font.Code,TextColor3=C.white,BackgroundColor3=C.card,Size=UDim2.new(1,-20,1,-95),Position=UDim2.fromOffset(10,43),MultiLine=true,ClearTextOnFocus=false,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=51},mask)
    local done=round(create("TextButton",{Text="Закрыть",TextSize=14,Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundColor3=C.blue,Size=UDim2.new(1,-20,0,38),Position=UDim2.new(0,10,1,-43),ZIndex=51},mask),9)
    done.MouseButton1Click:Connect(function() mask:Destroy() end)
end
local function renderPage()
    if not live then return end
    bodyCursor=8
    body.CanvasSize=UDim2.fromOffset(0,H-155)
    for _,name in ipairs(tabs) do
        activeButtons[name].BackgroundColor3=(name==current) and C.blue or C.panel
        activeButtons[name].TextColor3=(name==current) and C.white or C.muted
    end
    for _,connection in ipairs(pageConnections) do pcall(function() connection:Disconnect() end) end
    pageConnections={}
    for _,it in ipairs(body:GetChildren()) do
        if it:IsA("GuiObject") then it:Destroy() end
    end
    body.CanvasPosition=Vector2.new(0,0)
    if current=="Обзор" then
        labelText("12 направлений исследования • без изменений аккаунта",C.white,true)
        tile("Правила LAB","Весь аудит — чтение. Никаких покупок, торговли, удаления, изменения Game Pass. Единственный активный эксперимент запускается вручную, двойным подтверждением, ручные удары только после подтверждения.")
        actionButton("🔬 ПРОВЕРИТЬ ВСЕ СИСТЕМЫ",function() run("Полный аудит",function() runAudit(true) end) end,C.blue)
        actionButton("🗺 ПРОСКАНИРОВАТЬ МОНЕТЫ",function() run("Радар монет",runWorld) end)
        actionButton("📋 СКОПИРОВАТЬ ПОЛНЫЙ ОТЧЁТ",showReport,C.purple)
        tile("Сводка",(state.save and ("Питомцев: "..state.counts.all.."/"..tostring(state.save.PetSlots or "?")..", экипировано "..state.counts.equipped) or "Инвентарь не читался").." | FPS "..metrics.fps.." | монет с HP "..#state.coins)
        textList(allTests(),"Нажми «Проверить все системы», чтобы заполнить отчёт")
    elseif current=="Монеты" then
        labelText("GLOBAL FARM ENGINE • RADAR • TURBO",C.white,true)
        actionButton("СКАНИРОВАТЬ ВЕСЬ ЗАГРУЖЕННЫЙ МИР",function() run("Сканирование",runWorld) end,C.blue)
        tile("Производительность",string.format("FPS: %s | Последний скан %.1f мс | Изучено %d объектов",metrics.fps,metrics.scanMs,metrics.scanCount))
        for i=1,math.min(12,#state.coins) do
            local x=state.coins[i]
            tile(x.name,"HP: "..fmt(x.hp).." | расстояние "..(x.distance and fmt(x.distance) or "?").." studs")
        end
        if #state.coins==0 then labelText("Скан пока не запускался или монеты недоступны",C.muted) end
        tile("Что тестируем","Наличие целей, HP, расстояние, возможности ранжирования и стоимость сканирования. Не запускает Mine и не обходит ограничения миров")
    elseif current=="Питомцы" then
        labelText("PET ARMY • INVENTORY • EXP • CLONER",C.white,true)
        actionButton("ОБНОВИТЬ СЕРВЕРНЫЙ ИНВЕНТАРЬ",function() run("Инвентарь",function()runAudit(true)end)end,C.blue)
        actionButton("📸 СНИМОК ДО (ПОТОМ ОТКРОЙ ЯЙЦО/ПОФАРМИ)",function() run("Снимок",function() if not snapshot() then return end state.oneEggTest=false saveBaseline() end) end)
        actionButton("🥚 СНИМОК ДЛЯ ОДНОГО ЯЙЦА / ×3",function() run("Тест одного яйца",function()
            if not snapshot() then return end
            saveBaseline()
            state.oneEggTest=true
            emit("singleEgg","Подготовка проверки ×3","READY","Открой ровно 1 яйцо вручную с выключенным автоудалением, затем нажми СРАВНИТЬ")
        end) end)
        actionButton("📊 СРАВНИТЬ СНИМОК ПОСЛЕ ДЕЙСТВИЯ",function() run("Сравнение",function() if snapshot() then compareBaseline() end end) end,C.purple)
        if #state.hatchHistory>0 then
            local tallies={}
            for _,h in ipairs(state.hatchHistory) do
                local key=h.name.." ("..h.type..")"
                tallies[key]=(tallies[key] or 0)+1
            end
            local names={}
            for name,count in pairs(tallies) do names[#names+1]=name.." ×"..count end
            table.sort(names)
            tile("Наблюдаемые выпадения",table.concat(names,"; ")..". Без точного числа яиц это не вероятность")
        end
        if state.save then
            local n=state.counts
            tile("Серверные слоты",n.all.." / "..tostring(state.save.PetSlots or "?").."; экипировано "..n.equipped.." / "..tostring(state.save.MaxPets or "?").."; Gold "..n.gold..", Rainbow "..n.rainbow..", Dark "..n.dark)
            for i=1,math.min(10,#state.pets) do
                local p=state.pets[i]
                tile(p.name.."  #"..tostring(p.id or "?"),"Уровень: "..fmt(p.level).." | тип "..p.type.." | "..(p.equipped and "ЭКИПИРОВАН" or "не экипирован"))
            end
        else
            labelText("Инвентарь ещё не загружен",C.muted)
        end
    elseif current=="Эксперименты" then
        labelText("ПРОВЕРКИ СЕРВЕРА • РУЧНОЕ ПОДТВЕРЖДЕНИЕ",C.white,true)
        tile("Pet Army — одиночные и серия ×3","Обычный удар: монета должна иметь минимум ×1.2 HP от урона питомца. Тест награды: ищет монету, которую питомец может добить, и сравнивает валюту ДО/ПОСЛЕ. В одиночном тесте одна команда Mine. В серии максимум три последовательных команды Mine. Выключи другой фарм; лучше проверять на твинке.")
        local function confirmArmy(mode,runLabel)
            if not state.save then setBusy("Сначала обнови инвентарь") return end
            if state.uiBusy or state.trialBusy then setBusy("Текущий эксперимент выполняется") return end
            local now=clock()
            if now<(state.trialCooldownUntil or 0) then
                setBusy("⏳ Между опытами пауза "..math.ceil(state.trialCooldownUntil-now).." с")
                return
            end
            if (state.trialMode~=mode) or (now-state.petTrialAt > 10) then
                state.petTrialAt=now;state.trialMode=mode
                setBusy("⚠️ Повтори эту же кнопку в течение 10 секунд")
            else
                state.petTrialAt=0;state.trialMode=nil
                state.trialCooldownUntil=now+6
                run(runLabel,function() if mode=="multi" then multiArmyTrial() elseif mode=="parallel2" then parallelArmyTrial(2) elseif mode=="parallel4" then parallelArmyTrial(4) else activeArmyTrial(mode) end end)
            end
        end
        actionButton("🧪 1 УДАР НЕЭКИПИРОВАННЫМ",function() confirmArmy("hit","Один удар неэкипированным") end,C.purple)
        actionButton("🪙 ДОБИТЬ МОНЕТУ И ПРОВЕРИТЬ ВАЛЮТУ",function() confirmArmy("finish","Проверка награды за монету") end,C.green)
        tile("Новая проверка: 3 разных ID","Три сильнейших неэкипированных питомца по очереди (не одновременно), до трёх атак. Каждому нужна отдельная монета до 420 studs, которую он может уничтожить одним ударом. Проверяем серверный баланс после каждой атаки. Если награды нет — автоматическая остановка. Без другого фарма и яиц.")
        actionButton("🐾 СЕРИЯ: 3 РАЗНЫХ ПИТОМЦА + НАГРАДА",function() confirmArmy("multi","Серия трёх разных ID") end,C.purple)
        tile("LAB 0.6 • контроль целей","При запуске снимок Save делается один раз: не будет повторного чтения баланса ДО. До 420 studs выбираются самые слабые монеты с HP ≤ 90% урона питомца, без огромных сундуков. Пакеты ×2/×4 с небольшой паузой 0.2 с. HP каждой цели проверяется отдельно. До одного Mine на питомца, без постоянного фарма. Выключи все другие скрипты фарма и яйца")
        actionButton("🐾 ПАРАЛЛЕЛЬНО: 2 ПИТОМЦА",function() confirmArmy("parallel2","Параллельно два питомца") end,C.green)
        actionButton("🐾 ПАРАЛЛЕЛЬНО: 4 ПИТОМЦА",function() confirmArmy("parallel4","Параллельно четыре питомца") end,C.purple)
        actionButton("🛑 ОСТАНОВИТЬ СЕРИЮ",function()
            if state.seriesActive then state.seriesCancel=true;setBusy("Запрошена остановка после текущей проверки")
            else setBusy("Активной серии нет") end
        end,C.red)
        tile("Состояние серии","Отправлено: "..tostring(state.seriesDone or 0).."/"..tostring(state.seriesGoal or 3).."; активна="..tostring(state.seriesActive)..". В LAB 0.6 тесты ×2 и ×4 по одному разу за запуск; остановка запрещает новые запросы")
        tile("Game Pass / бесплатные слоты","Пассивный тест читает лимиты и видимые флаги. Проверка успешности платного серверного действия без права покупки не выполняется. UI не доказывает разблокировку")
        tile("Обмены и неторгуемые питомцы","Проверяем наличие RemoteFunction и известные данные питомцев. Автоматическая передача и изменение флагов торговли исключены")
        tile("Ручной тест Pet Cloner","LAB не отслеживает число купленных яиц. +3 питомца может означать 3 обычных открытия. Перед оценкой ×3 обязательно убедись, что открывалось именно одно яйцо, а не кнопка ×3")
        tile("Автономный аккаунт","Проверяем готовность датчиков, валюты, инвентаря и механизмов. Сама автоматизация отсутствует: без подтверждения датчиков она небезопасна")
    else
        labelText("ЖУРНАЛ И ЭКСПОРТ",C.white,true)
        actionButton("СКОПИРОВАТЬ ОТЧЁТ",showReport,C.blue)
        for i=1,math.min(#log,45) do tile("Запись "..i,log[i]) end
        if #log==0 then labelText("Журнал пуст",C.muted) end
    end
end
-- Never allow a failed render to leave a silently empty window.
draw=function()
    if not live then return end
    local ok,err=pcall(renderPage)
    if ok then return end
    local message="Ошибка построения вкладки "..tostring(current)..": "..shorten(err,220)
    addLog(message)
    pcall(function()
        for _,node in ipairs(body:GetChildren()) do
            if node:IsA("GuiObject") then node:Destroy() end
        end
        bodyCursor=8
        local errorTitle=create("TextLabel",{BackgroundTransparency=1,Text="⚠️ LAB: ошибка интерфейса",TextColor3=C.red,Font=Enum.Font.GothamBold,TextSize=16,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},body)
        putInBody(errorTitle,32)
        local detail=create("TextLabel",{BackgroundTransparency=1,Text=message,TextColor3=C.white,Font=Enum.Font.Gotham,TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},body)
        putInBody(detail,110)
        setBusy("! Ошибка UI. Сделай скриншот текста")
    end)
end
local isDragging=false;local dragStart,frameStart
local function enableDrag(object,frame)
    connections[#connections+1]=object.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            isDragging=true;dragStart=input.Position;frameStart=frame.Position
        end
    end)
    connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
        if not isDragging then return end
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then
            local delta=input.Position-dragStart
            frame.Position=UDim2.new(frameStart.X.Scale,frameStart.X.Offset+delta.X,frameStart.Y.Scale,frameStart.Y.Offset+delta.Y)
        end
    end)
    connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then isDragging=false end
    end)
end
enableDrag(header,main)
local function shutdown()
    if not live then return end
    live=false
    state.seriesCancel=true
    for _,c in ipairs(pageConnections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui.Parent then gui:Destroy() end
end
connections[#connections+1]=gui.Destroying:Connect(shutdown)
connections[#connections+1]=close.MouseButton1Click:Connect(shutdown)
connections[#connections+1]=minimize.MouseButton1Click:Connect(function() main.Visible=false;mini.Visible=true end)
connections[#connections+1]=mini.MouseButton1Click:Connect(function() mini.Visible=false;main.Visible=true end)
connections[#connections+1]=RunService.RenderStepped:Connect(function(dt)
    if not live then return end
    metrics.frames=metrics.frames+1; metrics.seconds=metrics.seconds+dt
    if metrics.seconds>=1 then metrics.fps=math.floor(metrics.frames/metrics.seconds+0.5);metrics.seconds=0;metrics.frames=0 end
end)
addLog("LAB загружен. На запуске не отправлено ни одного игрового Remote")
runAudit(false)
draw()
