-- ZoneHub v5.5 LITE FUSION FIX | FARM LOCK | 3 EGGS | SETTINGS
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local priorErrorHint = workspace:FindFirstChild("ZoneHub_StartError")
if priorErrorHint then priorErrorHint:Destroy() end

if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubShutdown)=="function" then pcall(env.ZoneHubShutdown) end
    if type(env.ZoneHubAlphaShutdown)=="function" then pcall(env.ZoneHubAlphaShutdown) end
    if type(env.__ZoneHubManualCapture)=="table" then
        env.__ZoneHubManualCapture.recording=false
    end
end
local priorOverlay=pg:FindFirstChild("ZoneHub_40_Zoni")
if priorOverlay then priorOverlay:Destroy() end
local old = pg:FindFirstChild("ZoneHub_PetSim")
if old then old:Destroy() end

local alive, farming, session = true, false, 0
local eggRunning, eggEpoch = false, 0
local Z25={}
Z25.farmWorld="Earth"
Z25.currency={}
Z25.currencyStart={}
Z25.paused=false
Z25.area="world"
Z25.radius=420
Z25.sleighCache={coin=nil,at=-1e9}
Z25.sleighState={coin=nil,hp=nil,killed=false}
Z25.coverageVisits={}
Z25.coverageSectors=0
function Z25.areaDescription()
    local names={Earth="Земля — все зоны",Moon="Луна — все зоны",Winter="Зима — все зоны",Sleigh="Сани — одна общая цель"}
    return names[Z25.farmWorld] or "Выбери мир"
end
local EGG_WORLDS={Moon={prefix="Tier "},Winter={prefix="Christmas Tier "}}
local function eggKey(world,tier)
    return EGG_WORLDS[world].prefix..tostring(tier)
end
local eggOpened, eggAttempts, eggInventory, eggCapacity = 0, 0, nil, nil
local eggConfirmed, eggRejected, eggBatches, eggStarted = 0, 0, 0, 0
local eggAdditionalPets, eggConfirmedMultiplier = 0, nil -- read-only server observations
local eggPerfMode="fast" -- faster default; adaptive backoff on slow responses/rejections. Never modifies server odds.
local eggActiveBatch=0
local eggWaveSeconds=0
local fpsValue=0 -- populated by read-only FPS monitor below
local eggPerfButton
local eggMessage = "Открытие трёх яиц не запущено"
-- Три фиксированных яйца используют общую очередь запросов и один проверяемый инвентарь.
local dualEggMode=false
local dualEgg={
    winter3={["78005"]=true},winter4={["78005"]=true,["79003"]=true},moon={["17009"]=true},
    merged={},fuseEnabled=false,fuseType=nil,
    winter3Sent=0,winter4Sent=0,moonSent=0,confirmationUntil=0,
    savedFusionType=nil,message="Выбирай питомцев для сохранения. Рандольф защищён в T3/T4."
}

Z25.PET_TYPE_NAMES={
    [78001]='Festive Ame Damnee',
    [78002]='Gingerbread',
    [78003]='Reindeer',
    [78004]='Festive Dominus',
    [78005]='Randolph',
    [79001]='Festive Immortuos',
    [79002]='Festive C0RE',
    [79003]='Giant Penguin',
    [17001]='Dominus Pumpkin',
    [17002]='Dominus Cherry',
    [17003]='Dominus Noob',
    [17004]='Dominus Wavy',
    [17005]='Dominus HeadStack',
    [17006]='Dominus Damnee',
    [17007]='Dominus Rainbow',
    [17008]='Dominus Electric',
    [17009]='Dominus Huge',
}
Z25.EGG_CONTENTS={
    Winter={
        [3]={78001,78002,78003,78004,78005},
        [4]={79001,79002,79003,78005},
    },
    Moon={
        [17]={17001,17002,17003,17004,17005,17006,17007,17008,17009},
    },
}
-- Safety-first: never auto-delete these rare new pets even if omitted from keep list.
-- p.n is the PET TYPE code. p.id is a unique inventory ID, do not confuse them.
Z25.protectedEggTypes={['78005']='Randolph',['79003']='Giant Penguin',['17009']='Dominus Huge'}
Z25.eggFilter={mode="off",keep={},kept=0,deleted=0,rainbowDeleted=0,goldDeleted=0,protected=0,preview=0,
    rareDrops={},limit=30,last="Фильтр выключен. Сначала выбери нужного питомца.",pendingAt=0}
function Z25.dualKeepRebuild()
    local merged={}
    for code,enabled in pairs(dualEgg.winter3) do if enabled then merged[code]=true end end
    for code,enabled in pairs(dualEgg.winter4) do if enabled then merged[code]=true end end
    for code,enabled in pairs(dualEgg.moon) do if enabled then merged[code]=true end end
    dualEgg.merged=merged
end
function Z25.activeEggKeep()
    return dualEgg.merged
end
-- Старых питомцев скрещиваем по запросу пользователя; по умолчанию защищены
-- редкие типы, заблокированные и экипированные питомцы.
Z25.eggFusion={tracked={},limit=math.huge,done=0,last="Автоскрещивание не запускалось",blocked=0,
    fuseType=nil,allowExisting=true,fuseAllTypes=true}
local manualFusionRunning=false
local manualFusionEpoch=0
local manualFusionConfirmUntil=0
function Z25.petNameForType(typeCode)
    return Z25.PET_TYPE_NAMES[tonumber(typeCode)]
end
Z25.inventory={count=nil,capacity=nil,normal=0,gold=0,rainbow=0,dark=0,equipped=0,updated="не проверен",lines=""}
Z25.inventoryLabel=nil
function Z25.trueFlag(value)
    return value~=nil and value~=false and value~=0
end
function Z25.classify(p)
    if Z25.trueFlag(p.dm) then return "dark" end
    if Z25.trueFlag(p.r) then return "rainbow" end
    if Z25.trueFlag(p.g) then return "gold" end
    return "normal"
end
function Z25.updateInventory(save, context)
    if type(save)~="table" or type(save.Pets)~="table" then return end
    local snap={count=0,capacity=save.PetSlots,normal=0,gold=0,rainbow=0,dark=0,equipped=0,updated=os.date("%H:%M:%S"),lines=""}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            snap.count+=1
            local stage=Z25.classify(p)
            snap[stage]+=1
            if Z25.trueFlag(p.e) then snap.equipped+=1 end
        end
    end
    local currencies={Coins="Земля",MoonCoins="Луна",SnowCoins="Зима"}
    for key,_ in pairs(currencies) do
        if type(save[key])=="number" then
            Z25.currency[key]=save[key]
            if type(Z25.currencyStart[key])~="number" then Z25.currencyStart[key]=save[key] end
        end
    end
    Z25.inventory=snap
    if Z25.inventoryLabel then
        Z25.inventoryLabel.Text=string.format("Сервер: %d/%s • экипировано: %d\nОбычных: %d | золотых: %d | радужных: %d | Dark: %d",snap.count,tostring(snap.capacity or "?"),snap.equipped,snap.normal,snap.gold,snap.rainbow,snap.dark)
    end
end
local connections, reserved = {}, {}
local lockedTargets={}
local logLines = {}
local cfg = {
    minX=-3218.733,maxX=-2832.849,minZ=-1747.956,maxZ=-1468.381,
    groundY=144.810,interval=.42,mode="Near"
}
local stats = {mine=0, move=0, clientErrors=0, damage=0, gone=0, noProgress=0, workers=0,
    targetReused=0,targetChanged=0,started=0,perPet={},peakWorkers=0}
Z25.autoPets={mode="all",total=0,equipped=0,ready=0,rotated=0,
    last="Не проверен",rejected={},success={},activeCount=165,lockedIDs=nil,lockedCount=0}
local lastInventorySignature=nil
Z25.dynamicPoolCursor=0
local function timestamp() return os.date("%H:%M:%S") end
local statusLabel
local showErrorToast
local function log(msg, bad)
    table.insert(logLines, 1, (bad and "! " or "• ")..timestamp().." "..tostring(msg))
    while #logLines>5 do table.remove(logLines) end
    if bad then
        stats.clientErrors+=1
        if showErrorToast then showErrorToast(tostring(msg)) end
    end
    if statusLabel then statusLabel.Text=logLines[1] or "Готово" end
end
-- Cache parts across hits/scans; keep weak keys so destroyed coins are not retained.
local partCache=setmetatable({},{__mode="kv"})
local function partOf(o)
    if not o then return nil end
    if o:IsA("BasePart") then return o end
    local cached=partCache[o]
    if cached and cached.Parent and cached:IsDescendantOf(o) then return cached end
    local part=(o:IsA("Model") and o.PrimaryPart) or o:FindFirstChildWhichIsA("BasePart",true)
    if part then partCache[o]=part else partCache[o]=nil end
    return part
end
local function root()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local cachedNodes={coins=nil,mine=nil,pets=nil}
local function nodes()
    local cached=cachedNodes
    if cached.coins and cached.coins.Parent and cached.mine and cached.mine.Parent
        and cached.pets and cached.pets.Parent then
        return cached.coins,cached.mine,cached.pets
    end
    local things=workspace:FindFirstChild("__THINGS")
    local coins=things and things:FindFirstChild("Coins")
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    local mine=gameRemotes and gameRemotes:FindFirstChild("Coins")
    local pets=gameRemotes and gameRemotes:FindFirstChild("Pets")
    if mine and not mine:IsA("RemoteEvent") then mine=nil end
    if pets and not pets:IsA("RemoteEvent") then pets=nil end
    cached.coins,cached.mine,cached.pets=coins,mine,pets
    return coins,mine,pets
end
Z25.coinWorldCache=setmetatable({},{__mode="k"})
Z25.coinWorldMissingAt=setmetatable({},{__mode="k"})
local function coinWorld(coin)
    if not coin then return nil end
    local cached=Z25.coinWorldCache[coin]
    if cached~=nil then return cached~=false and cached or nil end
    local lastMiss=Z25.coinWorldMissingAt[coin]
    if lastMiss and os.clock()-lastMiss<4 then return nil end
    local marker=coin:FindFirstChild("CoinName",true)
    local coinName=nil
    if marker and marker:IsA("StringValue") then coinName=marker.Value end
    if not coinName then coinName=coin:GetAttribute("CoinName") end
    if type(coinName)~="string" then
        local raw=string.lower(tostring(coin.Name))
        if raw:find("sleigh",1,true) then return "Sleigh" end
        Z25.coinWorldMissingAt[coin]=os.clock()
        return nil
    end
    local world=nil
    local directory=Z25.coinDirectory
    local record=directory and directory[coinName]
    if type(record)=="table" then
        local t=record.Type
        if t=="Coins" then world="Earth"
        elseif t=="MoonCoins" then world="Moon"
        elseif t=="SnowCoins" then world="Winter" end
    end
    if not world then
        local lower=string.lower(coinName)
        if lower:find("sleigh",1,true) then world="Sleigh"
        elseif lower:find("christmas",1,true) then world="Winter"
        elseif lower=="dominus chest" or lower=="grim chest" then world="Moon"
        elseif lower=="super chest" or lower=="omega chest" then world="Earth"
        else
            local zone=tonumber(coinName:match("^(%d+)%s"))
            if zone and zone>=1 and zone<=6 then world="Earth"
            elseif zone and zone>=7 and zone<=10 then world="Moon" end
        end
    end
    if string.lower(coinName):find("sleigh",1,true) then world="Sleigh" end
    if world then Z25.coinWorldCache[coin]=world
    else Z25.coinWorldMissingAt[coin]=os.clock() end
    return world
end
local function inside(p,coin)
    if Z25.area=="world" then
        local world=coinWorld(coin)
        if Z25.farmWorld=="Winter" then return world=="Winter" or world=="Sleigh" end
        return world==Z25.farmWorld
    end
    return false
end
function Z25.loadCoinDirectory()
    if Z25.coinDirectoryChecked then return end
    Z25.coinDirectoryChecked=true
    local rem=workspace:FindFirstChild("__REMOTES")
    local core=rem and rem:FindFirstChild("Core")
    local getDir=core and core:FindFirstChild("Get Directory")
    if getDir and getDir:IsA("RemoteFunction") then
        local ok,result=pcall(function() return getDir:InvokeServer() end)
        if ok and type(result)=="table" then
            local coins=result.Coins or (result.Directory and result.Directory.Coins)
            if type(coins)=="table" then Z25.coinDirectory=coins end
        end
    end
end
function Z25.coverageCell(pos)
    return tostring(math.floor(pos.X/290))..":"..tostring(math.floor(pos.Z/290))
end
local healthValues=setmetatable({},{__mode="k"})
local HEALTH_NAMES={"Health","HP","Hp","health"}
local function health(o)
    if not o then return nil end
    local ref=healthValues[o]
    if ref and ref.Parent then return ref.Value end
    for _,name in ipairs(HEALTH_NAMES) do
        local v=o:FindFirstChild(name,true)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
            healthValues[o]=v
            return v.Value
        end
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
        if part and inside(part.Position,coin) then
            local hp=health(coin)
            if type(hp)=="number" and hp>0 then
                result[#result+1]={object=coin,pos=part.Position,hp=hp}
            end
        end
    end
    return result,total
end
function Z25.findSleigh()
    local now=os.clock()
    local cached=Z25.sleighCache
    if cached.coin and cached.coin.Parent and (health(cached.coin) or 0)>0 and
        coinWorld(cached.coin)=="Sleigh" then
        return cached.coin
    end
    if now-cached.at<2.0 then return nil end
    cached.at=now
    cached.coin=nil
    local coins=nodes()
    if not coins then return nil end
    local best,bestHP=nil,-1
    for _,coin in ipairs(coins:GetChildren()) do
        if coinWorld(coin)=="Sleigh" then
            local hp=health(coin)
            if type(hp)=="number" and hp>0 and partOf(coin) and hp>bestHP then
                best,bestHP=coin,hp
            end
        end
    end
    if not best then
        local things=workspace:FindFirstChild("__THINGS")
        local spawns=things and things:FindFirstChild("Coin Spawns")
        local anchor=spawns and spawns:FindFirstChild("Sleigh")
        local anchorPart=partOf(anchor)
        if anchorPart then
            local pos=anchorPart.Position
            local closest=100
            for _,coin in ipairs(coins:GetChildren()) do
                local hp=health(coin)
                local world=coinWorld(coin)
                if type(hp)=="number" and hp>0 and (world=="Winter" or world==nil) then
                    local part=partOf(coin)
                    if part then
                        local distance=(part.Position-pos).Magnitude
                        local limit=world=="Winter" and 65 or 35
                        if distance<math.min(closest,limit) and (world=="Winter" or hp>=1e9) then
                            best=coin
                            closest=distance
                        end
                    end
                end
            end
        end
    end
    if best then Z25.coinWorldCache[best]="Sleigh" end
    cached.coin=best
    return best
end
local function orderCoins(items)
    local r=root()
    local o=r and r.Position or Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY,(cfg.minZ+cfg.maxZ)/2)
    for _,item in ipairs(items) do
        local delta=item.pos-o
        item.sortDistance=delta:Dot(delta) -- squared distance; no sqrt per sort comparison
    end
    local mode=cfg.mode
    if mode=="LowHP" then
        table.sort(items,function(a,b)
            return a.hp==b.hp and a.sortDistance<b.sortDistance or a.hp<b.hp
        end)
    elseif mode=="HighHP" then
        table.sort(items,function(a,b)
            return a.hp==b.hp and a.sortDistance<b.sortDistance or a.hp>b.hp
        end)
    else
        table.sort(items,function(a,b) return a.sortDistance<b.sortDistance end)
    end
end
local function validCoin(o)
    if not o or not o.Parent then return false end
    local part=partOf(o)
    local hp=health(o)
    return part~=nil and inside(part.Position,o) and type(hp)=="number" and hp>0
end
local function stopEggs(reason)
    local wasRunning=eggRunning
    eggRunning=false
    eggEpoch+=1
    Z25.eggFusion.collecting=false
    if dualEggMode then
        dualEggMode=false
        Z25.eggFusion.fuseType=dualEgg.savedFusionType
        if reason then dualEgg.message=reason end
    end
    if reason then
        eggMessage=reason..(wasRunning and " • уже отправленные покупки могут завершиться" or "")
    end
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
    local count=0
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" then count+=1 end
    end
    if not Z25.inventory or not Z25.lastEggInventoryUi or os.clock()-Z25.lastEggInventoryUi>=1.5 then
        Z25.updateInventory(save,"яйца")
        Z25.lastEggInventoryUi=os.clock()
    end
    return count,save.PetSlots,nil,save
end
local function eggSessionActive(epoch)
    return alive and eggRunning and eggEpoch==epoch
end

local function indexedPets(save)
    local byId={}
    if type(save)~="table" or type(save.Pets)~="table" then return byId end
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=tonumber(p.id)
            if id and id>0 and id%1==0 then byId[id]=p end
        end
    end
    return byId
end
local function hatchResultPet(info)
    if type(info)~="table" then return nil end
    local candidate=info[1]
    if type(candidate)=="table" then candidate=candidate[1] end
    if type(candidate)~="table" then return nil end
    local id=tonumber(candidate.id)
    if not id or id<=0 or id%1~=0 then return nil end
    return {id=id,kind=tostring(candidate.n or "")}
end
local function filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
    local keep=Z25.activeEggKeep()
    if not next(keep) then return false,false,"Не выбран ни один питомец для сохранения" end
    local prior=indexedPets(beforeSave)
    local after=indexedPets(afterSave)
    local newPets,unexpected={},0
    local allowed={}
    for _,code in ipairs(Z25.EGG_CONTENTS.Winter[3]) do allowed[tostring(code)]=true end
    for _,code in ipairs(Z25.EGG_CONTENTS.Winter[4]) do allowed[tostring(code)]=true end
    for _,code in ipairs(Z25.EGG_CONTENTS.Moon[17]) do allowed[tostring(code)]=true end
    local knownCodes=next(allowed)~=nil
    for id,p in pairs(after) do
        if not prior[id] then
            local kind=tostring(p.n or "")
            local stage=Z25.classify(p)
            if knownCodes and allowed[kind] and
                (stage=="normal" or stage=="gold" or stage=="rainbow") and
                not Z25.trueFlag(p.e) then
                newPets[#newPets+1]={id=id,data=p,kind=kind,stage=stage}
            else
                unexpected+=1 -- unknown type, equipped or Dark Matter: protect
            end
        end
    end
    -- Count newly observed rare pets before considering deletion. This is a server-ID
    -- observation, not a probability claim; reset when each opening session begins.
    for _,item in ipairs(newPets) do
        if Z25.protectedEggTypes[item.kind] then
            Z25.eggFilter.rareDrops[item.kind]=(Z25.eggFilter.rareDrops[item.kind] or 0)+1
        end
    end
    if #newPets+unexpected<confirmed or #newPets+unexpected>confirmed*3 then
        return false,false,"Число новых ID не соответствует подтверждённым покупкам; очистка остановлена"
    end
    if unexpected>0 then
        return false,false,"Найдены "..unexpected.." неожиданных ID/вариантов; очистка не будет удалять неизвестное"
    end
    local extraIds=0 -- all verified newly created IDs are in newPets; no ambiguous extras
    local wanted,removable,unknown=0,{},0
    local variantById={}
    local huntedRare=false
    for _,item in ipairs(newPets) do
        local p=item.data
        local name=Z25.petNameForType(item.kind)
        if keep[item.kind] or Z25.protectedEggTypes[item.kind] then
            wanted+=1
            huntedRare=true
        elseif not name or Z25.trueFlag(p.e) or
            (item.stage~="normal" and item.stage~="gold" and item.stage~="rainbow") then
            unknown+=1 -- unknown/equipped/Dark Matter: never delete
        else
            removable[#removable+1]=item.id
            variantById[item.id]=item.stage
        end
    end
    if Z25.eggFusion.collecting then
        for _,item in ipairs(newPets) do
            if (Z25.eggFusion.fuseAllTypes or Z25.eggFusion.fuseType==item.kind) and
                keep[item.kind] and not Z25.protectedEggTypes[item.kind] then
                Z25.eggFusion.tracked[item.id]=true
            end
        end
    end
    Z25.eggFilter.kept+=wanted
    Z25.eggFilter.protected+=unknown+extraIds
    if #removable==0 then
        return true,huntedRare,string.format("Оставлено %d, защищено %d, доп. ID %d не трогаю",wanted,unknown,extraIds),0
    end
    if not eggSessionActive(epoch) then return false,wanted>0,"Покупки остановлены до удаления" end
    local gameRemotes=workspace:FindFirstChild("__REMOTES")
    gameRemotes=gameRemotes and gameRemotes:FindFirstChild("Game")
    local inv=gameRemotes and gameRemotes:FindFirstChild("Inventory")
    if not inv or not inv:IsA("RemoteFunction") then
        return false,wanted>0,"Нет Game.Inventory: серверное удаление недоступно"
    end
    local _,_,err,fresh=getEggInventory()
    if err or not fresh then return false,wanted>0,"Ошибка контрольного чтения: "..tostring(err) end
    local current=indexedPets(fresh)
    for _,id in ipairs(removable) do
        local orig=after[id]
        local now=current[id]
        if not now or prior[id] or tonumber(now.id)~=id or tostring(now.n)~=tostring(orig.n)
            or keep[tostring(now.n)] or Z25.protectedEggTypes[tostring(now.n)] or Z25.trueFlag(now.e) or
            Z25.classify(now)~=Z25.classify(orig) or
            (Z25.classify(now)~="normal" and Z25.classify(now)~="gold" and Z25.classify(now)~="rainbow") or
            Z25.trueFlag(now.lock) or Z25.trueFlag(now.locked) or
            Z25.trueFlag(now.lk) or Z25.trueFlag(now.fav) then
            return false,wanted>0,"Контроль удаления не пройден. Питомцы сохранены."
        end
    end
    local removed=0
    local batchSize=6 -- fewer server snapshot round-trips; each ID remains verified
    for first=1,#removable,batchSize do
        if not eggSessionActive(epoch) then
            return false,wanted>0,"Остановлено перед следующей группой удаления"
        end
        local _,_,verifyErr,nowSave=getEggInventory()
        if verifyErr or not nowSave then
            return false,wanted>0,"Нет свежего инвентаря перед удалением: "..tostring(verifyErr)
        end
        local latest=indexedPets(nowSave)
        local batch={}
        for i=first,math.min(#removable,first+batchSize-1) do
            local id=removable[i]
            local orig=after[id]
            local now=latest[id]
            if not now or not orig or prior[id] or tonumber(now.id)~=id or
                tostring(now.n)~=tostring(orig.n) or keep[tostring(now.n)] or
                Z25.protectedEggTypes[tostring(now.n)] or Z25.trueFlag(now.e) or Z25.classify(now)~=Z25.classify(orig) or
                (Z25.classify(now)~="normal" and Z25.classify(now)~="gold" and Z25.classify(now)~="rainbow") or
                Z25.trueFlag(now.lock) or Z25.trueFlag(now.locked) or
                Z25.trueFlag(now.lk) or Z25.trueFlag(now.fav) then
                return false,wanted>0,"Защита: состояние ID "..id.." изменилось, удаление отменено"
            end
            batch[#batch+1]=id
        end
        local completed,failures=0,{}
        for _,id in ipairs(batch) do
            task.spawn(function()
                local ok,response=pcall(function() return inv:InvokeServer("Delete",id) end)
                if not ok or response==false then
                    failures[#failures+1]=tostring(id)..": "..tostring(response):sub(1,45)
                end
                completed+=1
            end)
            task.wait(.014)
        end
        local deadline=os.clock()+12
        while eggSessionActive(epoch) and completed<#batch and os.clock()<deadline do
            task.wait(.06)
        end
        if not eggSessionActive(epoch) then
            return false,wanted>0,"Удаление остановлено; часть отправленных команд может завершиться"
        end
        if completed<#batch then
            return false,wanted>0,"Тайм-аут удаления; повторов не будет"
        end
        local post,postErr
        local missing={}
        for retry=1,5 do
            task.wait(retry==1 and .08 or .20)
            local _,_,err,snapshot=getEggInventory()
            post=snapshot postErr=err
            if err or not snapshot then break end
            local map=indexedPets(snapshot)
            missing={}
            for _,id in ipairs(batch) do
                if not map[id] then missing[#missing+1]=id end
            end
            if #missing==#batch then break end
        end
        if postErr or not post then
            return false,wanted>0,"Не удалось проверить результат удаления: "..tostring(postErr)
        end
        removed+=#missing
        Z25.eggFilter.deleted+=#missing
        for _,removedId in ipairs(missing) do
            if variantById[removedId]=="rainbow" then Z25.eggFilter.rainbowDeleted+=1 end
            if variantById[removedId]=="gold" then Z25.eggFilter.goldDeleted+=1 end
        end
        if #failures>0 or #missing~=#batch then
            return false,wanted>0,"Удалено "..#missing.."/"..#batch.." в группе; остановлено без повторов. "..table.concat(failures,"; ")
        end
    end
    return true,huntedRare,string.format("Оставлено %d, удалено %d (включая невыбранные Rainbow/Gold), защищено %d, доп. ID %d не трогаю",wanted,removed,unknown,extraIds),removed
end

local fuseNewEggPets
-- Проверяем количество реально доступных к скрещиванию питомцев.
-- Если сервер выбирает группу по одному ID, нельзя безопасно смешивать обычных
-- с избранными/экипированными одного и того же типа и стадии.
local function isFusionProtected(p)
    return Z25.trueFlag(p.e) or Z25.trueFlag(p.lock) or
        Z25.trueFlag(p.locked) or Z25.trueFlag(p.lk) or Z25.trueFlag(p.fav)
end
local FUSION_RULES={
    {from="normal",to="gold",need=10,remote="Golden Pets",title="Gold"},
    {from="gold",to="rainbow",need=7,remote="Rainbow Pets",title="Rainbow"},
    {from="rainbow",to="dark",need=5,remote="Dark Matter Pets",title="Dark Matter"}
}
local function fusionEligibleTypes(save)
    local kinds={}
    if type(save)~="table" or type(save.Pets)~="table" then return kinds end
    if Z25.eggFusion.fuseAllTypes then
        for _,p in pairs(save.Pets) do
            if type(p)=="table" and p.n~=nil then
                local kind=tostring(p.n)
                -- Никогда автоматически не расходуем редкие виды.
                if not Z25.protectedEggTypes[kind] then kinds[kind]=true end
            end
        end
    else
        local kind=Z25.eggFusion.fuseType
        if kind and Z25.activeEggKeep()[kind] and not Z25.protectedEggTypes[kind] then
            kinds[kind]=true
        end
    end
    return kinds
end
function Z25.eggFusionProgress(save)
    if type(save)~="table" or type(save.Pets)~="table" then
        return false,"Не удалось прочитать инвентарь"
    end
    local kinds=fusionEligibleTypes(save)
    if not next(kinds) then return false,"Нет выбранных для скрещивания видов (редкие защищены)" end
    local groups={}
    for kind in pairs(kinds) do groups[kind]={} end
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local kind=tostring(p.n or "")
            local record=groups[kind]
            if record then
                local stage=Z25.classify(p)
                if stage~="dark" then
                    local bucket=record[stage] or {eligible=0,old=0,unsafe=0}
                    record[stage]=bucket
                    local id=tonumber(p.id)
                    if isFusionProtected(p) then bucket.unsafe+=1
                    elseif Z25.eggFusion.allowExisting or (id and Z25.eggFusion.tracked[id]) then
                        bucket.eligible+=1
                    else bucket.old+=1 end
                end
            end
        end
    end
    local ready=0
    local protected=0
    for _,rule in ipairs(FUSION_RULES) do
        for _,record in pairs(groups) do
            local group=record[rule.from]
            if group then
                if group.unsafe>0 or group.old>0 then protected+=1
                else ready+=math.floor(group.eligible/rule.need) end
            end
        end
    end
    return ready>0,string.format("Групп: %d (10 normal / 7 gold / 5 rainbow); заблокированных сочетаний: %d; старые: %s; виды: %s",
        ready,protected,Z25.eggFusion.allowExisting and "ДА" or "НЕТ",
        Z25.eggFusion.fuseAllTypes and "все, кроме редких" or "один выбранный")
end

local function startEggs()
    Z25.dualKeepRebuild()
    if not next(dualEgg.winter3) or not next(dualEgg.winter4) or not next(dualEgg.moon) then
        dualEgg.message="Отметь хотя бы один вид для сохранения в каждом яйце"
        return
    end
    if dualEgg.fuseEnabled and not Z25.eggFusion.fuseAllTypes and
        (not dualEgg.fuseType or not dualEgg.merged[dualEgg.fuseType]) then
        dualEgg.message="Выбери вид для скрещивания или выключи его"
        return
    end
    if eggRunning then dualEgg.message="Яйца уже покупаются; нажми СТОП" return end
    if manualFusionRunning then dualEgg.message="Дождись окончания ручного скрещивания" return end
    local _,shop=eggRemotes()
    if not shop then
        dualEgg.message="Не найден Game.Shop (RemoteFunction)"
        log(dualEgg.message,true)
        return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local key="Christmas Tier 3 + Christmas Tier 4 + Tier 17"
    local fuseEnabled=dualEgg.fuseEnabled
    dualEgg.winter3Sent,dualEgg.winter4Sent,dualEgg.moonSent=0,0,0
    dualEgg.savedFusionType=Z25.eggFusion.fuseType
    Z25.eggFusion.fuseType=dualEgg.fuseEnabled and dualEgg.fuseType or nil
    dualEggMode=true
    local maxWave=eggPerfMode=="turbo" and 36 or eggPerfMode=="fast" and 24 or 12
    local waveLimit=maxWave
    local adaptiveWave=eggPerfMode=="turbo" and 16 or eggPerfMode=="fast" and 14 or 8
    local responsiveWaves=0
    Z25.eggFusion.collecting=fuseEnabled
    Z25.eggFusion.tracked={}
    Z25.eggFusion.done=0
    Z25.eggFusion.blocked=0
    Z25.eggFusion.last=fuseEnabled and
        (Z25.eggFusion.fuseAllTypes and "Все обычные виды: 10/7/5; старые разрешены, редкие защищены" or
            "Выбранный вид: 10/7/5; старые разрешены") or "Автоскрещивание выключено"
    eggRunning=true
    Z25.eggFilter.kept,Z25.eggFilter.deleted,Z25.eggFilter.protected,Z25.eggFilter.preview=0,0,0,0
    Z25.eggFilter.rainbowDeleted,Z25.eggFilter.goldDeleted=0,0
    Z25.eggFilter.rareDrops={}
    eggAttempts,eggOpened,eggConfirmed,eggRejected,eggBatches=0,0,0,0,0
    eggAdditionalPets,eggConfirmedMultiplier=0,nil
    local expectedPetsPerBuy=3
    eggInventory,eggCapacity=nil,nil
    eggStarted=os.clock()
    eggMessage="Подготовка • "..key.." • три яйца по очереди"
    log("Три яйца: "..key)
    if farming then
        log("Яйца и фарм работают одновременно: скорость зависит от сервера и FPS")
    end
    task.spawn(function()
        local ok,err=pcall(function()
            local cachedBefore=nil
            local batchNumber=0
            while eggSessionActive(epoch) do
                batchNumber+=1
                local count,capacity,errorText,beforeSave
                if cachedBefore and os.clock()-cachedBefore.at<1.25 and batchNumber%4~=0 then
                    count,capacity,beforeSave=cachedBefore.count,cachedBefore.capacity,cachedBefore.save
                    errorText=nil
                else
                    count,capacity,errorText,beforeSave=getEggInventory()
                end
                cachedBefore=nil
                if errorText then
                    for retry=1,2 do
                        if not eggSessionActive(epoch) then break end
                        task.wait(.3*retry)
                        count,capacity,errorText,beforeSave=getEggInventory()
                        if not errorText then break end
                    end
                end
                if not eggSessionActive(epoch) then break end
                if errorText then eggMessage="Ошибка чтения инвентаря (после повторов): "..tostring(errorText).." • остановлено" break end
                eggInventory,eggCapacity=count,capacity
                local free=math.max(0,math.floor(capacity-count))
                if free<=0 then
                    if fuseEnabled and type(fuseNewEggPets)=="function" then
                        local ready,progress=Z25.eggFusionProgress(beforeSave)
                        Z25.eggFusion.last=progress
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if not good or converted==0 then
                                eggMessage="Инвентарь полон: "..detail.." • остановлено"
                                break
                            end
                            eggMessage="Скрещено "..converted.." групп; продолжаю покупки"
                            task.wait(.12)
                            continue
                        end
                        eggMessage="Инвентарь полон: "..progress..". Подходящих групп для скрещивания нет."
                        break
                    end
                    eggMessage="Инвентарь заполнен ("..count.."/"..capacity..")"
                    break
                end
                local left=free
                if left<=0 then
                    eggMessage="Покупка завершена: "..eggOpened.." питомцев"
                    break
                end
                local safeRequests=math.floor(free/expectedPetsPerBuy)
                if safeRequests<1 then
                    if fuseEnabled and type(fuseNewEggPets)=="function" then
                        local ready,progress=Z25.eggFusionProgress(beforeSave)
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if good and converted>0 then
                                cachedBefore=nil
                                task.wait(.12)
                                continue -- fusion freed slots; refresh inventory next cycle
                            end
                        end
                    end
                    eggMessage="Осталось "..free.." мест; недостаточно для безопасной серии (до "..expectedPetsPerBuy.." питомцев). Сохранён инвентарь."
                    break
                end
                local n=math.min(adaptiveWave,safeRequests,left)
                if n<=0 then break end
                eggActiveBatch=n
                eggBatches+=1
                eggMessage=string.format("%s • группа %d: запросов %d (1/3), свободно %d",key,eggBatches,n,free)
                local completed,confirmed,rejected,errors=0,0,0,0
                local waveStarted=os.clock()
                local buyResults={}
                local reason=""
                for i=1,n do
                    if not eggSessionActive(epoch) then break end
                    eggAttempts+=1
                    -- Раунд-робин: T3 -> T4 -> Moon17, затем повторить.
                    local seq=(eggAttempts-1)%3
                    local purchaseKey
                    if seq==0 then
                        purchaseKey=eggKey("Winter",3) dualEgg.winter3Sent+=1
                    elseif seq==1 then
                        purchaseKey=eggKey("Winter",4) dualEgg.winter4Sent+=1
                    else
                        purchaseKey=eggKey("Moon",17) dualEgg.moonSent+=1
                    end
                    task.spawn(function()
                        local invoked,accepted,details=pcall(function()
                            return shop:InvokeServer("Buy","Eggs",purchaseKey)
                        end)
                        if invoked and accepted==true then
                            confirmed+=1
                            buyResults[i]={accepted=true,pet=hatchResultPet(details)}
                        else
                            rejected+=1
                            if not invoked then errors+=1 end
                            if reason=="" then reason=tostring(accepted):sub(1,70) end
                        end
                        completed+=1
                    end)
                    if i<n then task.wait(.012) end
                end
                local sent=n
                local waitStarted=os.clock()
                while eggSessionActive(epoch) and completed<sent and os.clock()-waitStarted<22 do
                    task.wait(.045)
                end
                if not eggSessionActive(epoch) then break end
                if completed<sent then
                    eggMessage="Тайм-аут ответов сервера ("..completed.."/"..sent.."); остановлено. Ожидающие покупки ещё могут завершиться"
                    break
                end
                eggConfirmed+=confirmed
                eggRejected+=rejected
                eggWaveSeconds=os.clock()-waveStarted
                if waveLimit>1 then
                    local slowResponse=eggWaveSeconds>2.3
                    local fpsLow=fpsValue>0 and fpsValue<33
                    if slowResponse or fpsLow or rejected>0 then
                        adaptiveWave=math.max(2,math.min(waveLimit,adaptiveWave-1))
                        responsiveWaves=0
                    elseif eggWaveSeconds<1.1 and (fpsValue==0 or fpsValue>=43) then
                        responsiveWaves+=1
                        if responsiveWaves>=2 then
                            adaptiveWave=math.min(waveLimit,adaptiveWave+1)
                            responsiveWaves=0
                        end
                    else
                        responsiveWaves=0
                    end
                end
                local latest,cap,readErr,afterSave
                for tries=1,9 do
                    if not eggSessionActive(epoch) then break end
                    task.wait(tries==1 and .10 or .30)
                    latest,cap,readErr,afterSave=getEggInventory()
                    if readErr then break end
                    if latest and latest>=count+confirmed then break end
                    if confirmed==0 and latest then break end
                end
                if not eggSessionActive(epoch) then break end
                if readErr or not latest then
                    eggMessage="Не удалось подтвердить инвентарь: "..tostring(readErr)
                    break
                end
                eggInventory,eggCapacity=latest,cap
                local gained=math.max(0,latest-count)
                eggOpened+=gained
                eggMessage=string.format("%s • +%d питомцев • %d/%d • подтверждено: %d/%d",key,gained,latest,cap,confirmed,sent)
                if gained<confirmed or gained>confirmed*3 then
                    eggMessage=eggMessage.." • изменение инвентаря не соответствует 1–3 питомцам на подтверждённую покупку; остановлено без повторов"
                    break
                end
                if confirmed>0 then
                    eggAdditionalPets+=math.max(0,gained-confirmed)
                    if gained==confirmed*3 then
                        expectedPetsPerBuy=3
                        eggConfirmedMultiplier=3
                    elseif gained==confirmed then
                        expectedPetsPerBuy=1
                        eggConfirmedMultiplier=1
                    else
                        expectedPetsPerBuy=3
                        eggConfirmedMultiplier=nil
                    end
                    if gained>confirmed then
                        eggMessage=eggMessage.." • доп. питомцы +"..(gained-confirmed).." (возможен Pet Cloner)"
                    end
                end
                if rejected>0 then
                    eggMessage=eggMessage.." • отказов: "..rejected.." ("..reason.."); остановлено"
                    break
                end
                if gained==0 then
                    eggMessage="Сервер подтвердил запросы, но не добавил ID: возможно, лимит, задержка или нехватка валюты. Остановлено без повторов"
                    break
                end
                local verifiedNextCount,verifiedNextCapacity,verifiedNextSave=latest,cap,afterSave
                if afterSave then
                    local good,found,detail,deletedCount=filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
                    Z25.eggFilter.last=detail
                    eggMessage=eggMessage.." • "..detail
                    if not good then break end
                    -- When no pets were deleted, afterSave is already server-verified.
                    -- If removal happened, always re-read to protect subsequent fusion.
                    local postCount,postCap,postErr,postSave=latest,cap,nil,afterSave
                    if deletedCount~=0 then
                        postCount,postCap,postErr,postSave=getEggInventory()
                        if postErr then eggMessage="Ошибка инвентаря после фильтра: "..postErr break end
                        eggInventory,eggCapacity=postCount,postCap
                        verifiedNextCount,verifiedNextCapacity,verifiedNextSave=postCount,postCap,postSave
                    end
                    if fuseEnabled then
                        local ready,progress=Z25.eggFusionProgress(postSave)
                        Z25.eggFusion.last=progress
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if not good then
                                eggMessage=eggMessage.." • АВТОСКРЕЩИВАНИЕ ОСТАНОВЛЕНО: "..detail
                                break
                            end
                            eggMessage=eggMessage.." • скрещено "..converted.." групп"
                            if converted>0 then
                                local refreshed,refCap,refError,refSave=getEggInventory()
                                if refError then
                                    eggMessage="Скрещивание завершилось, но не удалось обновить инвентарь: "..tostring(refError)
                                    break
                                end
                                eggInventory,eggCapacity=refreshed,refCap
                                verifiedNextCount,verifiedNextCapacity,verifiedNextSave=refreshed,refCap,refSave
                            end
                        end
                    end
                end
                if verifiedNextSave then
                    cachedBefore={count=verifiedNextCount,capacity=verifiedNextCapacity,
                        save=verifiedNextSave,at=os.clock()}
                end
                task.wait(.025)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            eggActiveBatch=0
            Z25.eggFusion.collecting=false
            dualEggMode=false
            Z25.eggFusion.fuseType=dualEgg.savedFusionType
            dualEgg.message=eggMessage
                    if not ok then
                eggMessage="Ошибка покупки яиц: "..tostring(err):sub(1,100)
                log(eggMessage,true)
            else
                log("Яйца: "..eggMessage)
            end
        end
    end)
end

local stopFarm
local lastSaveUiRefresh=0
local function readPetSave()
    local statsRemote=eggRemotes()
    if not statsRemote then return nil,"Не найден Get Other Stats" end
    local ok,data=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,"Ошибка данных: "..tostring(data):sub(1,80) end
    local own=type(data)=="table" and data[player.Name]
    local save=type(own)=="table" and own.Save
    if type(save)~="table" or type(save.Pets)~="table" then
        return nil,"Сервер не вернул Save.Pets"
    end
    local now=os.clock()
    if now-lastSaveUiRefresh>=1.5 then
        Z25.updateInventory(save,"инвентарь")
        lastSaveUiRefresh=now
    end
    return save
end
Z25.readCurrentPetSave=readPetSave
function Z25.numberId(v)
    local n=tonumber(v)
    if not n or n~=n or n<1 or n%1~=0 then return nil end
    return n
end
function Z25.numericPetLevel(p)
    local level=tonumber(p.l)
    if not level or level~=level or level<0 then return nil end
    return level
end
function Z25.inventoryProfile(id,p)
    local level=Z25.numericPetLevel(p)
    if not level then return nil,false end
    local damageArgument=math.max(1,2*level-1)
    if damageArgument~=damageArgument then return nil,false end
    return {samples={damageArgument,damageArgument,damageArgument},
            movement={speed=4.7751576900482178},derived=true},false
end
function Z25.inventorySnapshot()
    local save,err=readPetSave()
    if not save then return nil,err end
    local result,seen={},{}
    local count,eq=0,0
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=Z25.numberId(p.id)
            if id and not seen[id] then
                seen[id]=true
                count+=1
                local equipped=p.e==true
                if equipped then eq+=1 end
                local level=tonumber(p.l)
                if level and level>=0 and (not Z25.autoPets.lockedIDs or Z25.autoPets.lockedIDs[id]) then
                    local profile=Z25.inventoryProfile(id,p)
                    if profile then
                        result[#result+1]={id=id,profile=profile,equipped=equipped,level=level}
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b)
        local aa=tonumber(a.profile.samples[1]) or 0
        local bb=tonumber(b.profile.samples[1]) or 0
        if aa~=bb then return aa>bb end
        return a.id<b.id
    end)
    local ids={}
    for _,v in ipairs(result) do ids[#ids+1]=tostring(v.id) end
    table.sort(ids)
    local signature=table.concat(ids,",")
    if signature~=lastInventorySignature then
        lastInventorySignature=signature
        Z25.autoPets.rejected={}
        Z25.dynamicPoolCursor=0
    end
    Z25.autoPets.total=count Z25.autoPets.equipped=eq Z25.autoPets.ready=#result
    Z25.autoPets.last="Инвентарь: "..count.." • экипировано: "..eq.." • в фарме: "..#result.." • лимит: "..math.min(165,Z25.autoPets.activeCount)
    if Z25.autoPets.lockedIDs then
        Z25.autoPets.last=Z25.autoPets.last.." • 🔒 исходно: "..Z25.autoPets.lockedCount.." • исчезли/недоступны: "..math.max(0,Z25.autoPets.lockedCount-#result)
    end
    if Z25.farmLockLabel then
        Z25.farmLockLabel.Text=Z25.autoPets.lockedIDs and ("🔒 В фарме: "..#result.." / "..Z25.autoPets.lockedCount.." • новые ID игнорируются") or "Список создаётся при первом запуске"
    end
    return result,nil
end
-- Один и тот же обработчик для автояиц и отдельного ручного скрещивания.
local function fusionSessionActive(epoch,manual)
    if manual then
        return alive and manualFusionRunning and manualFusionEpoch==epoch and not eggRunning
    end
    return eggSessionActive(epoch)
end
-- Запросы инвентаря выполняем лишь после реального скрещивания, а не
-- по одному разу для каждого (неподходящего) вида и стадии.
fuseNewEggPets=function(epoch,manual)
    if not fusionSessionActive(epoch,manual) or not Z25.eggFusion.collecting then
        return false,0,"Скрещивание остановлено"
    end
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    if not gameRemotes then return false,0,"Не найден Game Remotes" end
    local _,_,initialError,currentSave=getEggInventory()
    if initialError or not currentSave then
        return false,0,"Инвентарь недоступен: "..tostring(initialError)
    end
    local kinds=fusionEligibleTypes(currentSave)
    if not next(kinds) then return true,0,"Нет безопасных видов для скрещивания" end
    local kindNames={}
    for kind in pairs(kinds) do kindNames[#kindNames+1]=kind end
    table.sort(kindNames)
    local completed,skipped=0,0
    local maxOperations=70
    local function pickOne(save)
        local byId=indexedPets(save)
        -- Все группы собираем за один проход Save.Pets.
        local groups={}
        for id,p in pairs(byId) do
            local kind=tostring(p.n or "")
            if kinds[kind] then
                local stage=Z25.classify(p)
                if stage~="dark" then
                    local key=kind..":"..stage
                    if not groups[key] then
                        groups[key]={eligible={},danger=0,old=0}
                    end
                    local group=groups[key]
                    if isFusionProtected(p) then group.danger+=1
                    elseif Z25.eggFusion.tracked[id] or Z25.eggFusion.allowExisting then
                        group.eligible[#group.eligible+1]=id
                    else group.old+=1 end
                end
            end
        end
        local blocked=0
        for _,rule in ipairs(FUSION_RULES) do
            for _,kind in ipairs(kindNames) do
                local group=groups[kind..":"..rule.from]
                if group and #group.eligible>=rule.need then
                    if group.danger==0 and group.old==0 then
                        table.sort(group.eligible)
                        return rule,kind,group.eligible,byId,blocked
                    else blocked+=1 end
                end
            end
        end
        return nil,nil,nil,byId,blocked
    end
    for _=1,maxOperations do
        if not fusionSessionActive(epoch,manual) then
            return false,completed,"Скрещивание остановлено"
        end
        local rule,kind,stageIds,before,blocked=pickOne(currentSave)
        skipped=math.max(skipped,blocked or 0)
        if not rule then break end
        local remote=gameRemotes:FindFirstChild(rule.remote)
        if not remote or not remote:IsA("RemoteFunction") then
            return false,completed,"Недоступен "..rule.remote
        end
        local beforeMaterial={}
        for _,id in ipairs(stageIds) do beforeMaterial[id]=true end
        local oldDest={}
        for id,p in pairs(before) do
            if tostring(p.n)==kind and Z25.classify(p)==rule.to then oldDest[id]=true end
        end
        -- Сервер сам выбирает группу по одному ID. Поэтому выше проверяем
        -- ВСЕХ питомцев соответствующего вида/стадии, а не только 10/7/5.
        local invoked,response=pcall(function()
            return remote:InvokeServer(stageIds[1])
        end)
        if not invoked or response==false then
            return false,completed,"Сервер отклонил "..kind.." → "..rule.title..": "..tostring(response):sub(1,65)
        end
        local newSave=nil
        local afterMap=nil
        local outputIds={}
        local changed=false
        for verify=1,6 do
            if not fusionSessionActive(epoch,manual) then
                return false,completed,"Остановлено при проверке результата"
            end
            task.wait(verify==1 and .20 or .28)
            local _,_,verifyErr,after=getEggInventory()
            if verifyErr or not after then
                return false,completed,"Нет подтверждения инвентаря после скрещивания"
            end
            local afterNow=indexedPets(after)
            local lost=0
            local otherLost=false
            local produced={}
            for id in pairs(before) do
                if not afterNow[id] then
                    if beforeMaterial[id] then lost+=1
                    elseif not Z25.eggFusion.tracked[id] then otherLost=true end
                end
            end
            for id,p in pairs(afterNow) do
                if tostring(p.n)==kind and Z25.classify(p)==rule.to and not oldDest[id] then
                    produced[#produced+1]=id
                end
            end
            if otherLost then
                return false,completed,"Неожиданно исчез другой питомец; автоулучшение остановлено"
            end
            if lost>0 and #produced>0 then
                changed=true
                outputIds=produced
                afterMap=afterNow
                newSave=after
                break
            end
        end
        if not changed or not afterMap or not newSave then
            return false,completed,"Нет подтверждения "..kind.." → "..rule.title.."; повтор не отправлен"
        end
        local farmLocked=Z25.autoPets.lockedIDs
        local consumedFarm=0
        for id in pairs(before) do
            if not afterMap[id] then
                Z25.eggFusion.tracked[id]=nil
                if farmLocked and farmLocked[id] then
                    farmLocked[id]=nil
                    consumedFarm+=1
                end
            end
        end
        if consumedFarm>0 and farmLocked then
            -- Только результат скрещивания старых фермеров наследует фарм.
            -- ID новых питомцев, вылупившихся из яиц, не добавляем.
            for _,newId in ipairs(outputIds) do farmLocked[newId]=true end
            Z25.autoPets.lockedCount=math.max(0,Z25.autoPets.lockedCount-consumedFarm+#outputIds)
        end
        for _,id in ipairs(outputIds) do Z25.eggFusion.tracked[id]=true end
        currentSave=newSave
        Z25.autoPets.refreshAt=os.clock()
        completed+=1
        Z25.eggFusion.done+=1
        Z25.eggFusion.last="♻ "..(Z25.petNameForType(kind) or kind).." → "..rule.title..
            " • групп: "..Z25.eggFusion.done
        task.wait(.06)
    end
    return true,completed,string.format("Скрещено %d групп (лимит за проход %d). Пропущено защищённых групп: %d. Старые: %s",
        completed,maxOperations,skipped,Z25.eggFusion.allowExisting and "ДА" or "НЕТ")
end

stopFarm=function()
    farming=false
    Z25.paused=false
    session+=1
    stats.workers=0
    table.clear(reserved)
    table.clear(lockedTargets)
end
local function releaseLockedTarget(id,epoch)
    if epoch~=session then return end
    local lock=lockedTargets[id]
    if lock then
        if reserved[lock.coin]==id then reserved[lock.coin]=nil end
        lockedTargets[id]=nil
    end
end
Z25.coinCache={list={},at=-1e9,zone=nil,cursor=0}
local function claimCoin(id,minHP)
    local zoneKey=tostring(Z25.area)..":"..tostring(Z25.farmWorld)..":"..tostring(cfg.mode)
    local cache=Z25.coinCache
    local now=os.clock()
    if now-cache.at>2.0 or cache.zone~=zoneKey then
        local fresh=scan()
        orderCoins(fresh)
        cache={list=fresh,at=now,zone=zoneKey,cursor=cache.cursor or 0}
        Z25.coinCache=cache
    end
    local list=cache.list
    local n=#list
    if n==0 then return nil end
    local start=cache.cursor%n+1
    local function choose(requireStrong)
        for offset=0,n-1 do
            local index=(start+offset-1)%n+1
            local info=list[index]
            local coin=info.object
            if not reserved[coin] and (not requireStrong or info.hp>=minHP) and validCoin(coin) then
                cache.cursor=index
                reserved[coin]=id
                local cell=Z25.coverageCell(info.pos)
                if Z25.coverageVisits[cell]==nil then Z25.coverageSectors+=1 end
                Z25.coverageVisits[cell]=(Z25.coverageVisits[cell] or 0)+1
                return coin
            end
        end
        return nil
    end
    if minHP then return choose(true) or choose(false) end
    return choose(false)
end
function Z25.mineForOne(epoch,id,profile,oneCoin)
    if not Z25.waitWhilePaused(epoch) then return nil,"Фарм уже остановлен" end
    local sleighMode=Z25.farmWorld=="Sleigh"
    local lock=not sleighMode and lockedTargets[id] or nil
    local coin
    if sleighMode then
        coin=Z25.findSleigh()
    elseif oneCoin then
        coin=oneCoin
    elseif lock and validCoin(lock.coin) and reserved[lock.coin]==id then
        coin=lock.coin
        stats.targetReused+=1
    else
        if lock then
            stats.gone+=1
            releaseLockedTarget(id,epoch)
        end
        coin=claimCoin(id,Z25.autoPets.mode=="all" and profile.samples[1]*2 or nil)
        if coin then
            lockedTargets[id]={coin=coin,misses=0}
            stats.targetChanged+=1
        end
    end
    if not coin then
        return nil,sleighMode and "Сани не найдены в загруженных монетах — ожидаю появления" or "Нет свободных монет в зоне"
    end
    local p=partOf(coin)
    local before=health(coin)
    if not p or type(before)~="number" or before<=0 then
        if not sleighMode then releaseLockedTarget(id,epoch) end
        return nil,"Нет доступного HP"
    end
    if sleighMode then
        local shared=Z25.sleighState
        if shared.coin~=coin then
            shared.coin=coin
            shared.hp=before
            shared.killed=false
        elseif type(shared.hp)=="number" and before<shared.hp then
            stats.damage+=shared.hp-before
            shared.hp=before
        end
    end
    local _,mineRemote,petRemote=nodes()
    if not mineRemote or not petRemote then
        releaseLockedTarget(id,epoch)
        return nil,"Серверные события недоступны"
    end
    if not Z25.waitWhilePaused(epoch) then return nil,"Фарм остановлен" end
    local ok,err=pcall(function()
        petRemote:FireServer({{"PetMovement",player,id,CFrame.new(p.Position),false,profile.movement.speed}})
    end)
    if not ok then
        releaseLockedTarget(id,epoch)
        return nil,"Movement: "..tostring(err):sub(1,75)
    end
    stats.move+=1
    task.wait(.06)
    for i=1,math.min(#profile.samples,5) do
        if not Z25.waitWhilePaused(epoch) or not validCoin(coin) then break end
        local arg=profile.samples[i]
        local sent,problem=pcall(function() mineRemote:FireServer("Mine",coin.Name,arg,id) end)
        if not sent then
            releaseLockedTarget(id,epoch)
            return nil,"Mine: "..tostring(problem):sub(1,75)
        end
        stats.mine+=1
        local petStats=stats.perPet[id]
        if not petStats then
            petStats={mine=0,damage=0,batches=0}
            stats.perPet[id]=petStats
        end
        petStats.mine+=1
        task.wait(cfg.interval)
    end
    task.wait(.35)
    if epoch~=session or not farming then return nil,"Фарм остановлен" end
    local after=health(coin)
    local delta=type(after)=="number" and math.max(0,before-after) or 0
    local vanished=not validCoin(coin)
    if sleighMode then
        local shared=Z25.sleighState
        if shared.coin==coin then
            if not vanished and type(after)=="number" and type(shared.hp)=="number" and after<shared.hp then
                stats.damage+=shared.hp-after
                shared.hp=after
            elseif vanished and not shared.killed then
                shared.killed=true
                stats.gone+=1
                Z25.sleighCache.coin=nil
                Z25.sleighCache.at=os.clock()-2.1
            end
        end
        if vanished then return nil,"Сани исчезли — ищу появление новых" end
        if delta>0 then return true,delta end
        return nil,"Общий HP саней пока не изменился"
    end
    local petStats=stats.perPet[id]
    if delta>0 then
        stats.damage+=delta
        if petStats then
            petStats.damage+=delta
            petStats.batches+=1
        end
    end
    if vanished then
        stats.gone+=1
        releaseLockedTarget(id,epoch)
        if delta>0 then return true,delta end
        return nil,"Цель исчезла: HP за удар не подтверждён"
    end
    if delta>0 then
        if lockedTargets[id] then lockedTargets[id].misses=0 end
        return true,delta
    end
    if lockedTargets[id] then
        lockedTargets[id].misses+=1
        if lockedTargets[id].misses>=2 then
            releaseLockedTarget(id,epoch)
            return false,"HP не уменьшился два цикла — меняю недоступную цель"
        end
    end
    return nil,"HP пока не изменился — сохраняю текущую цель"
end

local function active(epoch)
    return alive and farming and epoch==session
end
function Z25.waitWhilePaused(epoch)
    while active(epoch) and Z25.paused do task.wait(.12) end
    return active(epoch)
end
-- Continuous fair dispatch. A completed request frees its slot immediately;
-- remaining pets do not wait for the slowest pet in a batch.
function Z25.dynamicFarm(epoch)
    local pool={}
    local busy={}
    local cooldown={}
    local inFlight=0
    local nextRefresh=0
    local lastSeenTrigger=0
    local nextWarning=0
    local cursor=Z25.dynamicPoolCursor or 0
    local function capacity()
        if fpsValue>0 and fpsValue<32 then return 4 end
        if fpsValue>0 and fpsValue<40 then return 7 end
        if fpsValue>0 and fpsValue<50 then return 12 end
        return 24
    end
    local function obtain(now)
        local total=math.min(165,Z25.autoPets.activeCount,#pool)
        if total==0 then return nil end
        for _=1,total do
            cursor=cursor%total+1
            local item=pool[cursor]
            if item and not busy[item.id] and (cooldown[item.id] or 0)<=now then
                Z25.dynamicPoolCursor=cursor
                return item
            end
        end
        return nil
    end
    local function dispatch(item)
        busy[item.id]=true
        inFlight+=1
        stats.workers=inFlight
        stats.peakWorkers=math.max(stats.peakWorkers,inFlight)
        task.spawn(function()
            local executed,success,detail=pcall(Z25.mineForOne,epoch,item.id,item.profile,nil)
            busy[item.id]=nil
            inFlight=math.max(0,inFlight-1)
            if not active(epoch) then return end
            stats.workers=inFlight
            if executed and success==true then
                if not Z25.autoPets.success[item.id] then Z25.autoPets.rotated+=1 end
                Z25.autoPets.success[item.id]=(Z25.autoPets.success[item.id] or 0)+1
                Z25.autoPets.rejected[item.id]=0
                cooldown[item.id]=0
            elseif executed and success==false then
                local failures=math.min(5,(Z25.autoPets.rejected[item.id] or 0)+1)
                Z25.autoPets.rejected[item.id]=failures
                stats.noProgress+=1
                cooldown[item.id]=os.clock()+math.min(12,2*failures)
                releaseLockedTarget(item.id,epoch)
            elseif executed then
                -- Missing targets, shared HP contention, temporary errors:
                -- retry fairly without blacklisting the pet.
                cooldown[item.id]=os.clock()+(Z25.farmWorld=="Sleigh" and .50 or 1.2)
            else
                Z25.autoPets.rejected[item.id]=(Z25.autoPets.rejected[item.id] or 0)+1
                cooldown[item.id]=os.clock()+5
                releaseLockedTarget(item.id,epoch)
                if os.clock()>=nextWarning then
                    nextWarning=os.clock()+8
                    log("Фарм ID "..tostring(item.id)..": "..tostring(success):sub(1,90),true)
                end
            end
        end)
    end
    while active(epoch) do
        if not Z25.waitWhilePaused(epoch) then break end
        local now=os.clock()
        if now>=nextRefresh or (Z25.autoPets.refreshAt and Z25.autoPets.refreshAt>lastSeenTrigger) then
            local newPool,err=Z25.inventorySnapshot()
            nextRefresh=now+(eggRunning and 4 or 10) -- быстро убираем скрещённые и удалённые ID
            lastSeenTrigger=Z25.autoPets.refreshAt or 0
            if newPool then
                pool=newPool
                cursor=math.min(cursor,#pool)
                local present={}
                for _,item in ipairs(pool) do present[item.id]=true end
                for id,_ in pairs(lockedTargets) do
                    if not present[id] and not busy[id] then releaseLockedTarget(id,epoch) end
                end
                for id,_ in pairs(cooldown) do
                    if not present[id] then cooldown[id]=nil end
                end
            elseif now>=nextWarning then
                nextWarning=now+8
                log("Не удалось обновить питомцев: "..tostring(err):sub(1,75),true)
            end
        end
        if #pool==0 then
            stats.workers=inFlight
            task.wait(1.5)
            continue
        end
        if Z25.farmWorld=="Sleigh" and not Z25.findSleigh() then
            -- One shared target; wait for its respawn without switching worlds.
            stats.workers=inFlight
            task.wait(1)
            continue
        end
        local limit=capacity()
        while active(epoch) and inFlight<limit do
            local item=obtain(os.clock())
            if not item then break end
            dispatch(item)
        end
        stats.workers=inFlight
        task.wait(inFlight==0 and .22 or .085)
    end
    if epoch==session then
        stats.workers=0
        farming=false
    end
end
local function startFarm()
    if not alive or farming then return end
    if manualFusionRunning then
        log("Дождись завершения ручного скрещивания перед запуском фарма",true)
        return
    end
    Z25.loadCoinDirectory()
    Z25.autoPets.mode="all"
    local list,err=Z25.inventorySnapshot()
    if not list or #list==0 then
        log("Автофарм: "..tostring(err or (Z25.autoPets.lockedIDs and "рабочих старых питомцев больше нет; обнови состав" or "в инвентаре нет доступных питомцев")),true)
        return
    end
    if not Z25.autoPets.lockedIDs then
        local locked={}
        for _,pet in ipairs(list) do locked[pet.id]=true end
        Z25.autoPets.lockedIDs=locked
        Z25.autoPets.lockedCount=#list
        log("🔒 Зафиксированы "..#list.." ID • новые питомцы не участвуют")
        if Z25.farmLockLabel then
            Z25.farmLockLabel.Text="🔒 Работают "..#list.." / "..#list.." • новые игнорируются"
        end
    end
    local coins,mine,pets=nodes()
    if not coins or not mine or not pets then log("Монеты или серверные события не найдены",true) return end
    local found=scan()
    if #found==0 then log("В выбранном мире нет монет — ждём появления") end
    session+=1
    local epoch=session
    farming=true
    Z25.paused=false
    table.clear(reserved)
    table.clear(lockedTargets)
    table.clear(Z25.coverageVisits)
    Z25.coverageSectors=0
    Z25.sleighState={coin=nil,hp=nil,killed=false}
    Z25.sleighCache={coin=nil,at=-1e9}
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.targetReused=0 stats.targetChanged=0 stats.perPet={} stats.peakWorkers=0 stats.started=os.clock()
    for key,current in pairs(Z25.currency) do
        if type(current)=="number" then Z25.currencyStart[key]=current end
    end
    Z25.autoPets.rejected={} Z25.autoPets.success={} Z25.autoPets.rotated=0
    stats.workers=0
    log("Фарм: "..#list.." питомцев в ротации • не больше 24 одновременных запросов")
    task.spawn(function()
        while alive and farming and epoch==session do
            local ok,fault=pcall(Z25.dynamicFarm,epoch)
            if ok then break end
            log("Ошибка фарма, повтор через 5 с: "..tostring(fault):sub(1,80),true)
            task.wait(5)
        end
    end)
end

local function createZoneHubUI()
local shutdown
local C={
    bg=Color3.fromRGB(11,14,20), panel=Color3.fromRGB(23,28,36), panel2=Color3.fromRGB(37,44,55),
    inset=Color3.fromRGB(17,21,28), line=Color3.fromRGB(52,62,76), white=Color3.fromRGB(245,247,250),
    dim=Color3.fromRGB(161,170,184),blue=Color3.fromRGB(91,139,220), green=Color3.fromRGB(75,180,143),
    red=Color3.fromRGB(213,105,116),gold=Color3.fromRGB(209,174,107), purple=Color3.fromRGB(149,124,190),
    cyan=Color3.fromRGB(111,178,207)
}
local function tween(obj,props,duration,style)
    local tw=TweenService:Create(obj,TweenInfo.new(duration or .20,style or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),props)
    tw:Play()
    return tw
end
local function corner(o,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=o return c
end
local function label(p,text,y,h,size,col,bold)
    local l=Instance.new("TextLabel") l.Name="Label"
    l.BackgroundTransparency=1 l.Position=UDim2.fromOffset(14,y) l.Size=UDim2.new(1,-28,0,h)
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.Text=text l.TextSize=size or 12 l.TextColor3=col or C.white
    l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left l.TextYAlignment=Enum.TextYAlignment.Center
    l.Parent=p return l
end
local orderCounts={}
local function card(p,h,highlight)
    local f=Instance.new("Frame") f.BackgroundColor3=C.panel f.BorderSizePixel=0
    f.Size=UDim2.new(1,0,0,h)
    orderCounts[p]=(orderCounts[p] or 0)+1
    f.LayoutOrder=orderCounts[p]
    f.Parent=p corner(f,10)
    return f
end
local function button(p,txt,y,fn,bg)
    local b=Instance.new("TextButton") b.Text=txt b.Font=Enum.Font.GothamSemibold b.TextSize=12
    b.TextColor3=C.white b.BackgroundColor3=bg or C.panel2 b.BorderSizePixel=0
    b.Size=UDim2.new(1,-28,0,42) b.Position=UDim2.fromOffset(14,y)
    b.AutoButtonColor=true b.Parent=p corner(b,8)
    connections[#connections+1]=b.MouseButton1Click:Connect(function()
        if not alive then return end
        local ok,err=pcall(fn)
        if not ok then log("Кнопка: "..tostring(err):sub(1,85),true) end
    end)
    return b
end
local gui=Instance.new("ScreenGui") gui.Name="ZoneHub_PetSim" gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true gui.DisplayOrder=260 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=pg
local toast=Instance.new("TextLabel")
toast.Name="ErrorToast" toast.Visible=false
toast.AnchorPoint=Vector2.new(.5,0)
toast.Position=UDim2.new(.5,0,0,12)
toast.Size=UDim2.new(.85,0,0,45)
toast.BackgroundColor3=Color3.fromRGB(85,41,51)
toast.BackgroundTransparency=.08 toast.BorderSizePixel=0
toast.TextColor3=Color3.fromRGB(255,242,245)
toast.Font=Enum.Font.GothamSemibold toast.TextSize=12
toast.TextWrapped=true toast.ZIndex=80 toast.Parent=gui corner(toast,12)
local lastToastAt=-1e9
local toastVersion=0
showErrorToast=function(message)
    if not alive or not gui.Parent then return end
    local now=os.clock()
    if now-lastToastAt<4 then return end
    lastToastAt=now toastVersion+=1
    local token=toastVersion
    toast.Text="⚠ "..message:sub(1,145)
    toast.Visible=true toast.TextTransparency=0
    task.delay(3.6,function()
        if not alive or token~=toastVersion or not toast.Parent then return end
        tween(toast,{TextTransparency=1,BackgroundTransparency=1},.28)
        task.delay(.31,function()
            if alive and token==toastVersion and toast.Parent then
                toast.Visible=false toast.BackgroundTransparency=.08
            end
        end)
    end)
end
local shadow=Instance.new("Frame") shadow.BackgroundColor3=Color3.fromRGB(3,6,14)
shadow.BackgroundTransparency=.80 shadow.BorderSizePixel=0 shadow.AnchorPoint=Vector2.new(.5,.5)
shadow.Position=UDim2.fromScale(.5,.505) shadow.Size=UDim2.fromOffset(408,588) shadow.Parent=gui corner(shadow,24)
local main=Instance.new("Frame") main.Name="Window" main.BackgroundColor3=C.bg main.BorderSizePixel=0
main.AnchorPoint=Vector2.new(.5,.5) main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromOffset(396,576) main.Parent=gui corner(main,14)
local scale=Instance.new("UIScale") scale.Scale=.92 scale.Parent=main
local shadowScale=Instance.new("UIScale") shadowScale.Parent=shadow
local folded, inTransition, transitionId, baseScale = false, false, 0, 1
local openPosition=main.Position
local openShadowPosition=shadow.Position
local function fit()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=camera.ViewportSize
    baseScale=math.clamp(math.min((v.X-24)/405,(v.Y-24)/592),.45,1)
    if not folded and not inTransition then tween(scale,{Scale=baseScale},.25) end
    shadowScale.Scale=baseScale
end
fit()
connections[#connections+1]=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
local top=Instance.new("Frame") top.BackgroundColor3=C.panel
top.BorderSizePixel=0 top.Size=UDim2.new(1,0,0,90) top.Parent=main corner(top,14)
local headSeparator=Instance.new("Frame") headSeparator.BorderSizePixel=0 headSeparator.BackgroundColor3=C.line
headSeparator.BackgroundTransparency=.55 headSeparator.Position=UDim2.new(0,16,1,-1) headSeparator.Size=UDim2.new(1,-32,0,1) headSeparator.Parent=top
label(top,"ZONEHUB",13,32,19,C.white,true)
label(top,"5.4 LITE • PET SIMULATOR 2018",49,20,10,C.dim,true)
local livePill=Instance.new("TextLabel") livePill.Size=UDim2.fromOffset(65,24)
livePill.Position=UDim2.new(1,-173,0,21) livePill.Text="● IDLE"
livePill.Font=Enum.Font.GothamBold livePill.TextSize=10 livePill.TextColor3=C.dim
livePill.BackgroundColor3=C.inset livePill.Parent=top corner(livePill,13)
local collapse=Instance.new("TextButton") collapse.Name="Collapse"
collapse.Size=UDim2.fromOffset(37,37) collapse.Position=UDim2.new(1,-48,0,14)
collapse.Text="−" collapse.Font=Enum.Font.GothamBold collapse.TextSize=20
collapse.TextColor3=C.white collapse.BackgroundColor3=C.panel2 collapse.AutoButtonColor=false
collapse.Parent=top corner(collapse,12)
local gameIcon="rbxthumb://type=GameIcon&id="..tostring(game.GameId).."&w=150&h=150"
local float=Instance.new("TextButton") float.Name="FloatingButton" float.Visible=false
float.Size=UDim2.fromOffset(70,70) float.AnchorPoint=Vector2.new(1,.5)
float.Position=UDim2.new(1,-10,.5,0) float.Text="" float.AutoButtonColor=false
float.BackgroundColor3=C.panel2 float.Parent=gui corner(float,20)

local floatScale=Instance.new("UIScale") floatScale.Scale=.7 floatScale.Parent=float
local paw=Instance.new("TextLabel") paw.BackgroundTransparency=1 paw.Size=UDim2.new(1,0,1,-4)
paw.Position=UDim2.fromOffset(0,0) paw.Text="🐾" paw.TextSize=32 paw.TextColor3=C.white
paw.Font=Enum.Font.GothamBold paw.Parent=float
local iconArt=Instance.new("ImageLabel") iconArt.Name="OfficialPetSimulatorIcon"
iconArt.BackgroundTransparency=1 iconArt.Size=UDim2.fromOffset(54,54)
iconArt.Position=UDim2.fromOffset(8,5) iconArt.Image=gameIcon
iconArt.ScaleType=Enum.ScaleType.Crop iconArt.Parent=float corner(iconArt,15)
local iconCaption=Instance.new("TextLabel") iconCaption.BackgroundColor3=C.inset
iconCaption.Size=UDim2.new(1,-10,0,14) iconCaption.Position=UDim2.new(0,5,1,-17)
iconCaption.Text="ZONEHUB" iconCaption.TextSize=8 iconCaption.TextColor3=C.white
iconCaption.Font=Enum.Font.GothamBold iconCaption.Parent=float corner(iconCaption,7)
local function moveToFloat()
    return UDim2.new(1,-45,.5,0)
end
local keepOnScreen -- forward declaration for completion callback
local function setCollapsed(state)
    if folded==state or not alive then return end
    folded=state
    inTransition=false
    main.Visible=not state
    shadow.Visible=not state
    float.Visible=state
    if not state then
        main.Position=openPosition
        shadow.Position=openShadowPosition
        keepOnScreen()
    else
        openPosition=main.Position
        openShadowPosition=shadow.Position
    end
end
connections[#connections+1]=collapse.MouseButton1Click:Connect(function() setCollapsed(true) end)
connections[#connections+1]=float.MouseButton1Click:Connect(function() setCollapsed(false) end)
local function viewportSize()
    local cam=workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280,720)
end
local function clampWindowCenter(x,y)
    local screen=viewportSize()
    local halfWidth=main.Size.X.Offset*baseScale/2
    local halfHeight=main.Size.Y.Offset*baseScale/2
    local margin=5
    local minX,maxX=halfWidth+margin,screen.X-halfWidth-margin
    local minY,maxY=halfHeight+margin,screen.Y-halfHeight-margin
    if maxX<minX then minX,maxX=screen.X/2,screen.X/2 end
    if maxY<minY then minY,maxY=screen.Y/2,screen.Y/2 end
    return math.clamp(x,minX,maxX),math.clamp(y,minY,maxY)
end
local function repositionWindow(x,y)
    x,y=clampWindowCenter(x,y)
    main.Position=UDim2.fromOffset(x,y)
    shadow.Position=UDim2.fromOffset(x,y+5)
end
local function currentWindowCenter()
    local v=viewportSize()
    local p=main.Position
    return v.X*p.X.Scale+p.X.Offset,v.Y*p.Y.Scale+p.Y.Offset
end
local grip=Instance.new("TextButton")
grip.Name="MoveGrip" grip.Size=UDim2.fromOffset(56,45)
grip.Position=UDim2.new(1,-59,1,-50)
grip.Text="⇲" grip.TextSize=26 grip.Font=Enum.Font.GothamBold
grip.TextColor3=C.cyan grip.BackgroundColor3=C.panel2 grip.BorderSizePixel=0
 grip.AutoButtonColor=false grip.ZIndex=8 grip.Parent=main corner(grip,12)
local gripHint=Instance.new("TextLabel")
gripHint.Size=UDim2.new(1,0,0,13) gripHint.Position=UDim2.new(0,0,1,-14)
gripHint.BackgroundTransparency=1 gripHint.Text="ТЯНИ" gripHint.Font=Enum.Font.GothamBold
 gripHint.TextColor3=C.dim gripHint.TextSize=9 gripHint.ZIndex=9 gripHint.Parent=grip
local dragging,dragInput,dragStart,dragCenter=false,nil,nil,nil
local function startDrag(input)
    if folded or inTransition or not alive then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    dragging=true dragInput=input dragStart=input.Position
    local x,y=currentWindowCenter()
    dragCenter=Vector2.new(x,y)
end
connections[#connections+1]=top.InputBegan:Connect(function(input)
    if input.Position.X>=top.AbsolutePosition.X+top.AbsoluteSize.X-58*baseScale then return end
    startDrag(input)
end)
connections[#connections+1]=grip.InputBegan:Connect(startDrag)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragCenter or not dragStart then return end
    if input~=dragInput and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=input.Position-dragStart
    repositionWindow(dragCenter.X+delta.X,dragCenter.Y+delta.Y)
end)
connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==dragInput then
        dragging=false dragInput=nil dragStart=nil dragCenter=nil
    end
end)
keepOnScreen=function()
    if not alive or folded or inTransition then return end
    local x,y=currentWindowCenter()
    local cx,cy=clampWindowCenter(x,y)
    if math.abs(cx-x)>.5 or math.abs(cy-y)>.5 then repositionWindow(cx,cy) end
end
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        task.defer(keepOnScreen)
    end)
end
local tabBar=Instance.new("Frame") tabBar.BackgroundColor3=C.inset tabBar.BorderSizePixel=0
tabBar.Size=UDim2.new(1,-24,0,43) tabBar.Position=UDim2.fromOffset(12,100) tabBar.Parent=main corner(tabBar,12)
local tabs,pages={},{}
local names={"Фарм","3 яйца","Настройки"}
local pill=Instance.new("Frame")
pill.BackgroundColor3=C.panel2 pill.BorderSizePixel=0
pill.Position=UDim2.new(0,3,0,3) pill.Size=UDim2.new(1/#names,-6,1,-6)
pill.Parent=tabBar corner(pill,8)
for i,name in ipairs(names) do
    local b=Instance.new("TextButton")
    b.Name=name b.Text=name b.TextSize=10 b.TextScaled=true
    b.Font=Enum.Font.GothamSemibold b.TextColor3=C.dim
    b.BackgroundTransparency=1 b.BorderSizePixel=0 b.AutoButtonColor=false b.ZIndex=2
    b.Position=UDim2.new((i-1)/#names,2,0,3)
    b.Size=UDim2.new(1/#names,-4,1,-6)
    b.Parent=tabBar tabs[name]=b
    local sc=Instance.new("ScrollingFrame") sc.Name=name sc.Visible=false
    sc.Position=UDim2.fromOffset(12,151)
    sc.Size=UDim2.new(1,-24,1,-219)
    sc.BackgroundTransparency=1 sc.BorderSizePixel=0
    sc.CanvasSize=UDim2.new() sc.AutomaticCanvasSize=Enum.AutomaticSize.Y
    sc.ScrollBarThickness=3 sc.ScrollBarImageColor3=C.blue
    sc.ScrollingDirection=Enum.ScrollingDirection.Y sc.Parent=main
    local pad=Instance.new("UIPadding")
    pad.PaddingTop=UDim.new(0,2) pad.PaddingBottom=UDim.new(0,8) pad.Parent=sc
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,8)
    layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Parent=sc
    pages[name]=sc
end
local activePage=nil
local function switch(name)
    if not pages[name] or activePage==name then return end
    activePage=name
    for i,n in ipairs(names) do
        pages[n].Visible=(n==name)
        tabs[n].TextColor3=n==name and C.white or C.dim
        if n==name then pill.Position=UDim2.new((i-1)/#names,3,0,3) end
    end
end
for name,b in pairs(tabs) do
    connections[#connections+1]=b.MouseButton1Click:Connect(function() switch(name,false) end)
end
local footer=card(main,54)
footer.Position=UDim2.new(0,12,1,-62) footer.Size=UDim2.new(1,-24,0,53)
statusLabel=label(footer,"Готово",6,41,10,C.dim)
statusLabel.TextYAlignment=Enum.TextYAlignment.Top
statusLabel.Size=UDim2.new(1,-84,0,41)

do
local farm=pages["Фарм"]
local hero=card(farm,88,C.blue)
label(hero,"Автофарм",9,25,16,C.white,true)
Z25.coinCount=label(hero,"Готов к запуску",34,21,11,C.dim)
Z25.workLabel=label(hero,"● ОСТАНОВЛЕН",60,19,11,C.dim,true)
local controls=card(farm,70,C.green)
Z25.startButton=button(controls,"▶ ЗАПУСТИТЬ ФАРМ",13,function()
    if farming then stopFarm() log("Фарм остановлен") else startFarm() end
end,C.green)
local worldCard=card(farm,200,C.blue)
label(worldCard,"Мир · все зоны / сани",8,27,13,C.white,true)
local worldChoices={{"ЗЕМЛЯ","Earth",C.blue},{"ЛУНА","Moon",C.purple},{"ЗИМА","Winter",C.cyan},{"🛷 САНИ","Sleigh",C.gold}}
local worldButtons={}
local function syncWorlds()
    for _,v in ipairs(worldButtons) do
        v.b.BackgroundColor3=Z25.farmWorld==v.world and v.color or C.panel2
    end
    if Z25.areaLabel then Z25.areaLabel.Text=Z25.areaDescription() end
end
for i,choice in ipairs(worldChoices) do
    local w=choice[2]
    local b=button(worldCard,choice[1],43,function()
        if farming then log("Останови фарм для переключения мира",true) return end
        Z25.farmWorld=w
        Z25.area="world"
        Z25.coinCache={list={},at=-1e9,zone=nil,cursor=0}
        Z25.sleighCache={coin=nil,at=-1e9}
        syncWorlds()
        log(w=="Sleigh" and "Выбраны САНИ: все зафиксированные питомцы атакуют одну цель, без деления на разные монеты" or
            "Выбран мир: "..Z25.areaDescription()..". Монеты определяются по игровому типу.")
    end,C.panel2)
    b.Position=UDim2.new((i-1)%2/2,5,0,42+math.floor((i-1)/2)*43)
    b.Size=UDim2.new(.5,-8,0,37)
    worldButtons[#worldButtons+1]={b=b,world=w,color=choice[3]}
end
button(worldCard,"🔎 ПРОВЕРИТЬ ЦЕЛИ",141,function()
    Z25.loadCoinDirectory()
    if Z25.farmWorld=="Sleigh" then
        local sleigh=Z25.findSleigh()
        log(sleigh and ("Сани: CoinID="..sleigh.Name.." • HP="..tostring(health(sleigh))) or
            "Сани не найдены в __THINGS.Coins: возможно, зимний мир ещё не загрузился",not sleigh)
    else
        local found,total=scan()
        log(Z25.areaDescription()..": доступно "..#found.." из "..total.." загруженных монет")
    end
end,C.panel2)
syncWorlds()
local selection=card(farm,107)
label(selection,"Приоритет",9,24,13,C.white,true)
local modes={{"Ближайшие","Near"},{"Меньше HP","LowHP"},{"Больше HP","HighHP"}}
local priButtons={}
for i,item in ipairs(modes) do
    local mode=item[2]
    local b=button(selection,item[1],45,function()
        cfg.mode=mode
        for _,row in ipairs(priButtons) do tween(row.b,{BackgroundColor3=row.mode==mode and C.blue or C.panel2},.15) end
    end,mode==cfg.mode and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)/3,5,0,45) b.Size=UDim2.new(1/3,-8,0,38) b.TextSize=10
    priButtons[#priButtons+1]={b=b,mode=mode}
end
local jobs=card(farm,138,C.green)
label(jobs,"Питомцы · любой уровень",9,27,14,C.white,true)
local values={8,32,64,128,165}
local jobButtons={}
for i,n in ipairs(values) do
    local b=button(jobs,tostring(n),49,function()
        Z25.autoPets.activeCount=n
        for _,row in ipairs(jobButtons) do tween(row.b,{BackgroundColor3=row.n==n and C.blue or C.panel2},.16) end
        log("Питомцев в ротации за круг: до "..n)
    end,n==165 and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)%3/3,5,0,49+math.floor((i-1)/3)*42)
    b.Size=UDim2.new(1/3,-8,0,36)
    jobButtons[#jobButtons+1]={b=b,n=n}
end
local lockCard=card(farm,113,C.green)
label(lockCard,"🔒 Состав автофарма",8,26,13,C.white,true)
Z25.farmLockLabel=label(lockCard,"Фиксация при первом запуске",35,22,11,C.dim)
button(lockCard,"↻ ОБНОВИТЬ СОСТАВ (ПОСЛЕ СТОП)",62,function()
    if farming then log("Сначала останови фарм",true) return end
    Z25.autoPets.lockedIDs=nil
    Z25.autoPets.lockedCount=0
    Z25.autoPets.success={} Z25.autoPets.rejected={} Z25.autoPets.rotated=0
    Z25.dynamicPoolCursor=0 lastInventorySignature=nil
    Z25.farmLockLabel.Text="Список сброшен: новый состав при запуске"
    log("🔓 Состав сброшен. Следующий запуск захватит всех текущих питомцев")
end,C.blue)
end

do
local dualPage=pages["3 яйца"]
local lead=card(dualPage,91)
label(lead,"ТРИ ЯЙЦА · Winter T3/T4 + Moon T17",8,28,15,C.white,true)
label(lead,"Открытие по очереди: Winter Tier 3 (Рандольф), Winter Tier 4, Moon Tier 17. Редкие питомцы защищены.",36,44,11,C.dim)
local dualRows={}
local updateDualUI
local function buildDualCard(title,world,tier,color)
    local codes=Z25.EGG_CONTENTS[world][tier]
    local height=64+math.ceil(#codes/2)*45
    local panel=card(dualPage,height,color)
    if tier==3 then Z25.triEggTier3Card=panel end
    label(panel,title,8,28,14,C.white,true)
    label(panel,"Оставить до 6 видов • остальные новые удаляются",34,24,10,C.dim)
    for i,code in ipairs(codes) do
        local key=tostring(code)
        local b=button(panel,"",62+math.floor((i-1)/2)*45,function()
            if eggRunning then dualEgg.message="Останови открытие перед изменением выбора" return end
            local keep=(world=="Moon") and dualEgg.moon or tier==3 and dualEgg.winter3 or dualEgg.winter4
            local amount=0
            for _,yes in pairs(keep) do if yes then amount+=1 end end
            if not keep[key] and amount>=6 then dualEgg.message="Можно выбрать максимум 6 видов для этого яйца" return end
            keep[key]=not keep[key] or nil
            Z25.dualKeepRebuild()
            if dualEgg.fuseType and not dualEgg.merged[dualEgg.fuseType] then dualEgg.fuseType=nil dualEgg.fuseEnabled=false end
            dualEgg.confirmationUntil=0
            updateDualUI()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%2/2,5,0,62+math.floor((i-1)/2)*45)
        b.Size=UDim2.new(.5,-8,0,39) b.TextSize=10
        dualRows[#dualRows+1]={button=b,code=key,world=world,tier=tier}
    end
end
buildDualCard("❄ ЗИМА · CHRISTMAS TIER 3","Winter",3,C.cyan)
buildDualCard("❄ ЗИМА · CHRISTMAS TIER 4","Winter",4,C.cyan)
buildDualCard("🌙 ЛУНА · TIER 17","Moon",17,C.purple)
local fcard=card(dualPage,329)
label(fcard,"♻ Скрещивание (по желанию)",8,28,14,C.white,true)
local fuseToggle=button(fcard,"СКРЕЩИВАНИЕ: ВЫКЛ",40,function()
    if eggRunning then dualEgg.message="Сначала останови открытие" return end
    if not dualEgg.fuseEnabled and not Z25.eggFusion.fuseAllTypes and not dualEgg.fuseType then
        dualEgg.message="Сначала выбери вид для скрещивания"
        return
    end
    dualEgg.fuseEnabled=not dualEgg.fuseEnabled
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.panel2)
local fuseChoose=button(fcard,"Вид: не выбран (нажми для выбора)",88,function()
    if eggRunning then dualEgg.message="Сначала останови открытие" return end
    local options={}
    local used={}
    for _,code in ipairs(Z25.EGG_CONTENTS.Winter[3]) do
        local k=tostring(code)
        if dualEgg.winter3[k] then options[#options+1]=k used[k]=true end
    end
    for _,code in ipairs(Z25.EGG_CONTENTS.Winter[4]) do
        local k=tostring(code)
        if dualEgg.winter4[k] and not used[k] then options[#options+1]=k used[k]=true end
    end
    for _,code in ipairs(Z25.EGG_CONTENTS.Moon[17]) do
        if dualEgg.moon[tostring(code)] then options[#options+1]=tostring(code) end
    end
    if #options==0 then dualEgg.message="Сначала отметь питомцев для сохранения" return end
    local pos=0
    for i,k in ipairs(options) do if dualEgg.fuseType==k then pos=i end end
    dualEgg.fuseType=options[pos%#options+1]
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.panel2)
local fuseExisting=button(fcard,"",135,function()
    if eggRunning or manualFusionRunning then
        dualEgg.message="Сначала останови скрещивание или покупку" return
    end
    Z25.eggFusion.allowExisting=not Z25.eggFusion.allowExisting
    updateDualUI()
end,C.panel2)
local fuseScope=button(fcard,"",181,function()
    if eggRunning or manualFusionRunning then
        dualEgg.message="Сначала останови скрещивание или покупку" return
    end
    Z25.eggFusion.fuseAllTypes=not Z25.eggFusion.fuseAllTypes
    updateDualUI()
end,C.panel2)
local manualFuse=button(fcard,"♻ СКРЕСТИТЬ СТАРЫХ СЕЙЧАС",228,function()
    if eggRunning then dualEgg.message="Останови открытие яиц" return end
    if manualFusionRunning then
        manualFusionRunning=false
        manualFusionEpoch+=1
        Z25.eggFusion.collecting=false
        dualEgg.message="Ручное скрещивание остановлено"
        return
    end
    Z25.dualKeepRebuild()
    if not Z25.eggFusion.fuseAllTypes and
        (not dualEgg.fuseType or not dualEgg.merged[dualEgg.fuseType]) then
        dualEgg.message="Выбери вид либо включи ВСЕ ВИДЫ" return
    end
    local now=os.clock()
    if manualFusionConfirmUntil<now then
        manualFusionConfirmUntil=now+10
        dualEgg.message="ПОДТВЕРДИ: старые питомцы будут необратимо скрещены. Нажми кнопку повторно."
        if Z25.dualUiUpdate then Z25.dualUiUpdate() end
        return
    end
    manualFusionConfirmUntil=0
    manualFusionEpoch+=1
    local epoch=manualFusionEpoch
    manualFusionRunning=true
    Z25.eggFusion.collecting=true
    Z25.eggFusion.fuseType=dualEgg.fuseType
    dualEgg.message="Проверяю старых и новых питомцев на допустимые группы..."
    task.spawn(function()
        local ok,good,count,detail=pcall(fuseNewEggPets,epoch,true)
        if manualFusionEpoch~=epoch then return end
        manualFusionRunning=false
        Z25.eggFusion.collecting=false
        if ok then
            dualEgg.message=detail or "Ручное скрещивание завершено"
            Z25.eggFusion.last=dualEgg.message
            if not good then log(dualEgg.message,true) end
        else
            dualEgg.message="Ошибка скрещивания: "..tostring(good):sub(1,90)
            Z25.eggFusion.last=dualEgg.message
            log(dualEgg.message,true)
        end
        if Z25.dualUiUpdate then Z25.dualUiUpdate() end
    end)
end,C.blue)
label(fcard,"ВНИМАНИЕ: старые питомцы расходуются. Экипированные, заблокированные и редкие виды защищены. Результаты старого фарма возвращаются в фарм.",279,43,10,C.dim)
local run=card(dualPage,166)
label(run,"⚡ Открытие трёх яиц",8,29,14,C.white,true)
local startDual=button(run,"▶ ЗАПУСТИТЬ 3 ЯЙЦА",40,function()
    if eggRunning then dualEgg.message="Яйца уже открываются. Сначала СТОП" return end
    local now=os.clock()
    if dualEgg.confirmationUntil<now then
        dualEgg.confirmationUntil=now+9
        dualEgg.message="Подтверди удаление невыбранных новых питомцев: нажми ЗАПУСТИТЬ ещё раз"
        updateDualUI()
        return
    end
    dualEgg.confirmationUntil=0
    startEggs()
    updateDualUI()
end,C.green)
button(run,"■ СТОП ПОКУПОК",89,function()
    if dualEggMode then stopEggs("Покупки остановлены") else dualEgg.message="Открытие не запущено" end
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.red)
local report=card(dualPage,202)
label(report,"Состояние",9,26,14,C.white,true)
local dualStatus=label(report,"Не запущено",37,150,10,C.dim)
updateDualUI=function()
    for _,item in ipairs(dualRows) do
        local keep=(item.world=="Moon") and dualEgg.moon or item.tier==3 and dualEgg.winter3 or dualEgg.winter4
        local selected=keep[item.code]==true
        item.button.Text=(selected and "✓ " or "○ ")..(Z25.PET_TYPE_NAMES[tonumber(item.code)] or item.code)
        item.button.BackgroundColor3=selected and C.green or C.panel2
    end
    local chosen=dualEgg.fuseType and (Z25.petNameForType(dualEgg.fuseType) or dualEgg.fuseType) or "не выбран"
    fuseToggle.Text="СКРЕЩИВАНИЕ: "..(dualEgg.fuseEnabled and "ВКЛ" or "ВЫКЛ")
    fuseToggle.BackgroundColor3=dualEgg.fuseEnabled and C.green or C.panel2
    fuseChoose.Text="Выбрать вид: "..chosen
    fuseExisting.Text=Z25.eggFusion.allowExisting and
        "⚠ СТАРЫЕ ПИТОМЦЫ: СКРЕЩИВАТЬ" or "🛡 СТАРЫЕ ПИТОМЦЫ: НЕ ТРОГАТЬ"
    fuseExisting.BackgroundColor3=Z25.eggFusion.allowExisting and C.gold or C.panel2
    fuseScope.Text=Z25.eggFusion.fuseAllTypes and
        "ВСЕ ВИДЫ: ВКЛ (кроме редких)" or "ТОЛЬКО ВЫБРАННЫЙ ВИД"
    fuseScope.BackgroundColor3=Z25.eggFusion.fuseAllTypes and C.blue or C.panel2
    manualFuse.Text=manualFusionRunning and "■ СТОП СКРЕЩИВАНИЯ" or
        manualFusionConfirmUntil>os.clock() and "⚠ ПОДТВЕРДИТЬ СКРЕЩИВАНИЕ" or
        "♻ СКРЕСТИТЬ СЕЙЧАС"
    if dualEgg.confirmationUntil>os.clock() then
        startDual.Text="ПОДТВЕРДИТЬ ОТКРЫТИЕ И ФИЛЬТР"
    else
        startDual.Text="▶ ЗАПУСТИТЬ 3 ЯЙЦА"
    end
end
Z25.dualUiUpdate=updateDualUI
Z25.dualUiStatus=dualStatus
Z25.dualUiStart=startDual
updateDualUI()
end

local settings=pages["Настройки"]
local speedCard=card(settings,130,C.purple)
label(speedCard,"Скорость трёх яиц",9,26,15,C.white,true)
eggPerfButton=button(speedCard,"",43,function()
    if eggRunning then log("Останови открытие, чтобы изменить скорость",true) return end
    eggPerfMode=eggPerfMode=="auto" and "fast" or eggPerfMode=="fast" and "turbo" or "auto"
end,C.blue)
label(speedCard,"АВТО: до 12 • БЫСТРО: до 24 • ТУРБО: до 36 запросов за серию. Сервер может ограничить скорость.",90,34,10,C.dim)

local inventoryCard=card(settings,160,C.cyan)
label(inventoryCard,"Инвентарь",9,27,15,C.white,true)
Z25.inventoryLabel=label(inventoryCard,"Не проверен",39,54,12,C.dim)
button(inventoryCard,"ОБНОВИТЬ",102,function()
    local save,err=readPetSave()
    if not save then log("Инвентарь: "..tostring(err),true) return end
    Z25.updateInventory(save,"ручная проверка")
end,C.blue)

local fpsFrames=0
local fpsDuration=0
connections[#connections+1]=RunService.RenderStepped:Connect(function(dt)
    if not alive then return end
    fpsFrames+=1
    fpsDuration+=dt
    if fpsDuration>=1 then
        fpsValue=math.floor(fpsFrames/math.max(.01,fpsDuration)+.5)
        fpsFrames=0
        fpsDuration=0
    end
end)
local diagnostics=card(settings,125,C.blue)
label(diagnostics,"Состояние",9,27,15,C.white,true)
Z25.healthLabel=label(diagnostics,"FPS: —",38,25,12,C.dim)
button(diagnostics,"КОПИРОВАТЬ ОШИБКИ",75,function()
    if type(setclipboard)~="function" then log("Буфер обмена Delta недоступен",true) return end
    local lines={"ZoneHub 5.5 LITE", "FPS: "..tostring(fpsValue),
        "Фарм: "..tostring(farming),"Яйца: "..tostring(eggRunning),
        "Зона: "..Z25.areaDescription(),"Ошибки: "..stats.clientErrors}
    for _,line in ipairs(logLines) do lines[#lines+1]=line end
    local ok=pcall(setclipboard,table.concat(lines,"\n"))
    log(ok and "Журнал скопирован" or "Не удалось скопировать журнал",not ok)
end,C.blue)

local exitCard=card(settings,67)
button(exitCard,"✕ ЗАКРЫТЬ ZONEHUB",12,function()
    if shutdown then shutdown() end
end,C.red)

local function uiText(obj,value)
    if obj and obj.Text~=value then obj.Text=value end
end
local function uiColor(obj,value)
    if obj and obj.TextColor3~=value then obj.TextColor3=value end
end
local function uiBackground(obj,value)
    if obj and obj.BackgroundColor3~=value then obj.BackgroundColor3=value end
end
local function refresh()
    if not main.Visible then return end
    local currentState=farming and "● FARM" or eggRunning and "● EGGS" or "● IDLE"
    uiText(livePill,currentState)
    uiColor(livePill,(farming or eggRunning) and C.green or C.dim)
    if activePage=="Фарм" then
        uiText(Z25.coinCount,farming and (Z25.farmWorld=="Sleigh" and "Сани · общая цель" or "Все зоны выбранного мира") or Z25.areaDescription())
        uiText(Z25.workLabel,farming and ("● ФАРМ · "..stats.workers.." задач") or "● ОСТАНОВЛЕН")
        uiColor(Z25.workLabel,farming and C.green or C.dim)
        uiText(Z25.startButton,farming and "■ ОСТАНОВИТЬ" or "▶ ЗАПУСТИТЬ ФАРМ")
        uiBackground(Z25.startButton,farming and C.red or C.blue)
    elseif activePage=="3 яйца" then
        if Z25.dualUiStatus then
            local rares=Z25.eggFilter.rareDrops or {}
            uiText(Z25.dualUiStatus,(dualEggMode and "● РАБОТАЕТ" or "○ ОЖИДАНИЕ")..
                " • T3: "..dualEgg.winter3Sent.." / T4: "..dualEgg.winter4Sent.." / Moon 17: "..dualEgg.moonSent..
                "\nОставлено: "..Z25.eggFilter.kept.." • удалено: "..Z25.eggFilter.deleted..
                "\nРедкие за запуск: Рандольф "..(rares['78005'] or 0).." • пингвин "..(rares['79003'] or 0).." • Huge "..(rares['17009'] or 0)..
                "\n♻ "..Z25.eggFusion.last.."\n"..(dualEggMode and eggMessage or dualEgg.message))
            uiColor(Z25.dualUiStatus,dualEggMode and C.green or C.dim)
        end
        if Z25.dualUiStart then
            local caption=dualEgg.confirmationUntil>os.clock() and "ПОДТВЕРДИТЬ ОТКРЫТИЕ И ФИЛЬТР" or "▶ ЗАПУСТИТЬ 3 ЯЙЦА"
            uiText(Z25.dualUiStart,caption)
        end
    elseif activePage=="Настройки" then
        if Z25.healthLabel then uiText(Z25.healthLabel,"FPS: "..fpsValue.." • ошибок: "..stats.clientErrors) end
        if eggPerfButton then
            local mode={auto="АВТО • 12",fast="БЫСТРО • 24",turbo="ТУРБО • 36"}
            uiText(eggPerfButton,"СКОРОСТЬ: "..(mode[eggPerfMode] or "АВТО • 12"))
        end
    end
end
task.spawn(function()
    while alive and gui.Parent do
        task.wait(1.5)
        if alive and gui.Parent then refresh() end
    end
end)
shutdown=function()
    manualFusionRunning=false
    manualFusionEpoch+=1
    stopEggs()
    stopFarm()
    alive=false
    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if type(getgenv)=="function" then getgenv().ZoneHubShutdown=shutdown end
switch("Фарм",true)
refresh()
log("ZoneHub 5.5 LITE: фарм • 3 яйца • настройки")

end -- createZoneHubUI

local uiOk, uiErr = pcall(createZoneHubUI)
if not uiOk then
    warn("ZoneHub 5.5 LITE | UI startup error: "..tostring(uiErr))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="ZoneHub 5.5 LITE: ошибка запуска",
            Text=tostring(uiErr):sub(1,115),Duration=7
        })
    end)
end
