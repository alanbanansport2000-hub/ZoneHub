-- ZoneHub DeepDiagnostic v4.0 (Pet Simulator original 2018)
-- Read-only 90-second battery: 16 checks in one launch.
-- Reads ONLY workspace.__REMOTES.Core["Get Other Stats"] and local PlayerGui/LogService.
-- NEVER invokes Game.Inventory, Trade, Shop, Pets, Fuse, Delete, Equip or any mutations.
-- Run alone on your own account. Original Roblox cannot execute this external script.

local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local player = Players.LocalPlayer
if not player then return end
local pg = player:WaitForChild("PlayerGui", 12)
if not pg then return end
local GAME_NAME = "ZoneHub_DeepDiagnostic_v4"
local oldUI = pg:FindFirstChild(GAME_NAME)
if oldUI then oldUI:Destroy() end
local ENV = type(getgenv)=="function" and getgenv() or _G
if type(ENV.__ZoneDeepDiagV4)=="table" then
    ENV.__ZoneDeepDiagV4.cancelled = true
    if ENV.__ZoneDeepDiagV4.logConn then
        pcall(function() ENV.__ZoneDeepDiagV4.logConn:Disconnect() end)
    end
end
local session = {cancelled=false, logConn=nil}
ENV.__ZoneDeepDiagV4=session

local function addObj(class, props, parent)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function corner(obj, n) addObj("UICorner",{CornerRadius=UDim.new(0,n or 9)},obj) end
local C={bg=Color3.fromRGB(15,19,32),panel=Color3.fromRGB(27,36,55),blue=Color3.fromRGB(65,104,189),green=Color3.fromRGB(40,130,108),muted=Color3.fromRGB(177,192,216),white=Color3.fromRGB(237,244,255),orange=Color3.fromRGB(156,102,59)}
local gui=addObj("ScreenGui",{Name=GAME_NAME,ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=10020},pg)
local panel=addObj("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(455,500),BackgroundColor3=C.bg,BorderSizePixel=0,Active=true},gui)
corner(panel,14)
local uiScale=addObj("UIScale",{},panel)
local function resize()
    local camera=workspace.CurrentCamera
    local size=camera and camera.ViewportSize or Vector2.new(800,600)
    uiScale.Scale=math.clamp(math.min((size.X-20)/455,(size.Y-20)/500),.46,1)
end
resize()
local header=addObj("TextLabel",{Text="ZoneHub • DEEP DIAGNOSTIC v4",Position=UDim2.fromOffset(14,8),Size=UDim2.fromOffset(405,29),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.white,Font=Enum.Font.GothamBold,TextSize=17},panel)
local subtitle=addObj("TextLabel",{Text="16 проверок • только чтение • 90 секунд",Position=UDim2.fromOffset(14,37),Size=UDim2.fromOffset(425,20),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C.muted,Font=Enum.Font.Gotham,TextSize=12},panel)
local status=addObj("TextLabel",{Text="Готово. Запусти тест, открой питомцев и Trading.",Position=UDim2.fromOffset(14,65),Size=UDim2.fromOffset(425,39),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true,TextColor3=C.white,Font=Enum.Font.Gotham,TextSize=12},panel)
local function btn(text,x,y,w,h,color)
    local o=addObj("TextButton",{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color or C.blue,TextColor3=C.white,BorderSizePixel=0,Font=Enum.Font.GothamBold,TextWrapped=true,TextSize=12},panel)
    corner(o,8)
    return o
end
local startBtn=btn("1. СТАРТ / 90 сек",14,111,205,42,C.green)
local snapBtn=btn("2. СНИМОК СЕЙЧАС",229,111,212,42,C.blue)
local stopBtn=btn("3. СТОП + ОТЧЁТ",14,160,205,42,C.orange)
local copyBtn=btn("4. КОПИРОВАТЬ",229,160,212,42,C.blue)
local out=addObj("TextBox",{Position=UDim2.fromOffset(14,212),Size=UDim2.fromOffset(427,241),BackgroundColor3=C.panel,BorderSizePixel=0,TextColor3=C.white,Font=Enum.Font.Code,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=false,TextEditable=false,MultiLine=true,ClearTextOnFocus=false,Text="Отчёт появится после запуска."},panel)
corner(out,8)
local hideBtn=btn("СВЕРНУТЬ • открывай игровые окна",14,461,427,28,C.panel)
local bubble=addObj("TextButton",{Text="🔎 V4",Position=UDim2.new(1,-100,.27,0),Size=UDim2.fromOffset(82,43),BackgroundColor3=C.blue,TextColor3=C.white,Font=Enum.Font.GothamBold,TextSize=14,BorderSizePixel=0,Visible=false},gui)
corner(bubble,11)
hideBtn.MouseButton1Click:Connect(function() panel.Visible=false bubble.Visible=true end)
bubble.MouseButton1Click:Connect(function() panel.Visible=true bubble.Visible=false end)
-- Small drag handler for mobile.
local UIS=game:GetService("UserInputService")
local dragging=false
local dragStart=nil
local origin=nil
header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true; dragStart=input.Position; origin=panel.Position
        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
header.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) and dragStart then
        local d=input.Position-dragStart
        panel.Position=UDim2.new(origin.X.Scale,origin.X.Offset+d.X,origin.Y.Scale,origin.Y.Offset+d.Y)
    end
end)

local function str(v)
    if v==nil then return "nil" end
    if type(v)=="number" then
        if v~=v then return "NaN" end
        if v==math.huge then return "+Inf" end
        if v==-math.huge then return "-Inf" end
        if v==math.floor(v) and math.abs(v)<1e20 then return string.format("%.0f",v) end
        return string.format("%.17g",v)
    end
    return tostring(v)
end
local function clip(s,n)
    s=tostring(s or ""):gsub("[\r\n\t]"," ")
    if #s>(n or 120) then return s:sub(1,(n or 120)).."..." end
    return s
end
local function sortedKeys(map)
    local a={}
    for k in pairs(map or {}) do a[#a+1]=k end
    table.sort(a,function(x,y)return tostring(x)<tostring(y) end)
    return a
end
local function inc(t,k)
    local key=str(k)
    t[key]=(t[key] or 0)+1
end
local function topCounts(tab,limit)
    local items={}
    for k,v in pairs(tab) do items[#items+1]={name=k,count=v} end
    table.sort(items,function(a,b)if a.count~=b.count then return a.count>b.count end return a.name<b.name end)
    local out={}
    for i=1,math.min(limit or 8,#items) do out[#out+1]=items[i].name.."="..items[i].count end
    return table.concat(out,", ")
end
local data={started=false,running=false,stopped=false,at=0,serverBefore=nil,serverAfter=nil,serverError=nil,uiBase=nil,uiPets=nil,uiTrade=nil,uiManual={},errors={},latestUI=nil,uiSamples=0,serverChanges=nil,logsReadable="не проверено"}
local function appendLog(kind, message)
    local msg=clip(message,450)
    if #data.errors>=40 then return end
    for _,v in ipairs(data.errors) do if v.kind==kind and v.msg==msg then v.count+=1 return end end
    data.errors[#data.errors+1]={kind=kind,msg=msg,count=1}
end
local function pullHistory()
    local ok,history=pcall(function() return LogService:GetLogHistory() end)
    if not ok or type(history)~="table" then data.logsReadable="нет доступа";return end
    data.logsReadable="да ("..#history.." сообщений)"
    local start=math.max(1,#history-180)
    for i=start,#history do
        local m=history[i]
        if type(m)=="table" then
            local k=tostring(m.messageType or m.MessageType)
            if k:find("Error") or k:find("Warning") then appendLog(k,m.message or m.Message or "") end
        end
    end
end
local function readSave()
    local rr=workspace:FindFirstChild("__REMOTES")
    local core=rr and rr:FindFirstChild("Core")
    local remote=core and core:FindFirstChild("Get Other Stats")
    if not remote or not remote:IsA("RemoteFunction") then return nil,"нет Core/Get Other Stats" end
    local ok,res=pcall(function() return remote:InvokeServer() end)
    if not ok then return nil,"InvokeServer: "..clip(res,250) end
    local user=type(res)=="table" and res[player.Name]
    local save=type(user)=="table" and user.Save
    if type(save)~="table" or type(save.Pets)~="table" then return nil,"Save.Pets недоступен" end
    return save
end
local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function inspectSave(save)
    local s={slots=save.PetSlots,max=save.MaxPets,total=0,valid=0,bad=0,equip=0,duplicates=0,
        ipairs=0,arrayLength=0,maxNumericKey=0,numericKeys=0,stringKeys=0,otherKeys=0,
        idMap={},equippedIds={},issues={}, xpRisk={},xpBad={},levelBad={},
        xpMin=nil,xpMax=nil,levelMin=nil,levelMax=nil,levels={},typeHistogram={},
        fields={},eTypes={},pTypes={},keysSummary={},saveSummary={}, badFieldTypes=0}
    for k,v in pairs(save) do inc(s.saveSummary,tostring(k)..":"..type(v)) end
    for _idx, _pet in ipairs(save.Pets) do s.ipairs+=1 end
    s.arrayLength=#save.Pets
    for key, p in pairs(save.Pets) do
        s.total+=1
        if type(key)=="number" and finite(key) and key>=1 and key==math.floor(key) then
            s.numericKeys+=1
            if key>s.maxNumericKey then s.maxNumericKey=key end
        elseif type(key)=="string" then s.stringKeys+=1
        else s.otherKeys+=1 end
        if type(p)~="table" then
            s.bad+=1
            if #s.issues<60 then s.issues[#s.issues+1]="key="..str(key).." имеет тип "..type(p) end
        else
            local id=tonumber(p.id)
            local validId=finite(id) and id>0 and id==math.floor(id)
            if not validId then
                s.bad+=1
                if #s.issues<60 then s.issues[#s.issues+1]="key="..str(key).." ID некорректен: "..str(p.id) end
            else
                s.valid+=1
                local idstr=str(id)
                if s.idMap[idstr] then
                    s.duplicates+=1
                    if #s.issues<60 then s.issues[#s.issues+1]="Дублируется ID "..idstr end
                end
                s.idMap[idstr]={e=p.e==true,l=p.l,xp=p.xp,n=p.n}
                if p.e==true then s.equippedIds[#s.equippedIds+1]=idstr end
            end
            inc(s.eTypes,type(p.e))
            inc(s.pTypes,type(p.n))
            for field,val in pairs(p) do
                local entry=s.fields[tostring(field)]
                if not entry then entry={count=0,types={}};s.fields[tostring(field)]=entry end
                entry.count+=1;inc(entry.types,type(val))
            end
            if p.e==true then s.equip+=1 end
            local level=tonumber(p.l)
            if not finite(level) or level<0 then
                s.levelBad[#s.levelBad+1]=str(p.id)..":"..str(p.l)
            else
                if not s.levelMin or level<s.levelMin then s.levelMin=level end
                if not s.levelMax or level>s.levelMax then s.levelMax=level end
                s.levels[#s.levels+1]={id=str(p.id),level=level,n=str(p.n)}
            end
            local xp=tonumber(p.xp)
            if not finite(xp) or xp<0 then
                s.xpBad[#s.xpBad+1]=str(p.id)..":"..str(p.xp)
            else
                if not s.xpMin or xp<s.xpMin then s.xpMin=xp end
                if not s.xpMax or xp>s.xpMax then s.xpMax=xp end
                if xp>9007199254740992 then
                    s.xpRisk[#s.xpRisk+1]={id=str(p.id),xp=xp,n=str(p.n)}
                end
            end
            inc(s.typeHistogram,p.n)
        end
    end
    table.sort(s.levels,function(a,b) return a.level>b.level end)
    table.sort(s.xpRisk,function(a,b) return a.xp>b.xp end)
    table.sort(s.equippedIds)
    return s
end
local function serverSnap()
    local save,err=readSave()
    if not save then data.serverError=err;return nil end
    return inspectSave(save)
end

local function isShown(obj)
    local node=obj
    while node and node~=pg do
        if node:IsA("GuiObject") and (not node.Visible or node.AbsoluteSize.X==0 or node.AbsoluteSize.Y==0) then return false end
        if node:IsA("LayerCollector") and not node.Enabled then return false end
        node=node.Parent
    end
    return true
end
local function shortPath(obj)
    local steps={}
    local node=obj
    for _=1,7 do
        if not node or node==pg then break end
        table.insert(steps,1,clip(node.Name,28))
        node=node.Parent
    end
    return table.concat(steps,"/")
end
local function uiSnap()
    local s={screenCount=0,activeScreens=0,guiCount=0,visibleCount=0,
        images=0,buttons=0,scrolls=0,visibleScrolls=0,
        roots={},matches={},emptyScrolls={},counters={},detectedPets=false,detectedTrade=false,changes=""}
    local all=pg:GetDescendants()
    for i=1,math.min(#all,12500) do
        local v=all[i]
        local name=v.Name
        if v:IsA("ScreenGui") and v~=gui then
            s.screenCount+=1
            if v.Enabled then s.activeScreens+=1 end
            if #s.roots<25 and not name:find("ZoneHub",1,true) then
                s.roots[#s.roots+1]=clip(name,58).."["..(v.Enabled and "ON" or "OFF").."]"
            end
        end
        if v:IsA("GuiObject") and v~=gui and not v:IsDescendantOf(gui) and not name:find("ZoneHub",1,true) then
            s.guiCount+=1
            local visible=isShown(v)
            if visible then
                s.visibleCount+=1
                if v:IsA("ImageLabel") or v:IsA("ImageButton") then s.images+=1 end
                if v:IsA("TextButton") or v:IsA("ImageButton") then s.buttons+=1 end
            end
            local lower=string.lower(name)
            local txt=""
            if v:IsA("TextLabel") or v:IsA("TextButton") or v:IsA("TextBox") then
                txt=tostring(v.Text or "")
            end
            local ltxt=string.lower(txt)
            local pets=(lower:find("invent",1,true) or lower:find("pet",1,true) or lower:find("pocket",1,true)
                 or ltxt:find("your pets",1,true) or ltxt:find("your pet",1,true))
            local trade=(lower:find("trad",1,true) or ltxt:find("trading",1,true) or ltxt:find("trade",1,true))
            -- Distinguish an actual open panel from the always-visible Pets/Trade toolbar buttons.
            if visible and (ltxt:find("your pets",1,true) or ltxt:find("your pet",1,true)) then s.detectedPets=true end
            if visible and (ltxt:find("trading",1,true) or (ltxt=="trade" and v.AbsoluteSize.X>140)) then s.detectedTrade=true end
            if (pets or trade) and #s.matches<42 then
                local count=0
                for _,c in ipairs(v:GetChildren()) do if c:IsA("GuiObject") then count+=1 end end
                s.matches[#s.matches+1]=(visible and "+ " or "- ")..clip(shortPath(v),115).." / "..v.ClassName.." / children="..count.." / size="..str(v.AbsoluteSize.X).."x"..str(v.AbsoluteSize.Y)..(txt~="" and (" / text="..clip(txt,78)) or "")
            end
            if visible and txt:match("^%s*%d+%s*/%s*%d+%s*$") and #s.counters<18 then
                s.counters[#s.counters+1]=clip(shortPath(v),83).." => "..clip(txt,45)
            end
            if v:IsA("ScrollingFrame") then
                s.scrolls+=1
                if visible then
                    s.visibleScrolls+=1
                    local guiChildren=0
                    for _,c in ipairs(v:GetChildren()) do if c:IsA("GuiObject") then guiChildren+=1 end end
                    if #s.emptyScrolls<18 then
                        local ch=v.AbsoluteCanvasSize
                        s.emptyScrolls[#s.emptyScrolls+1]=clip(shortPath(v),105).." | прямых GUI="..guiChildren.." | canvas="..str(ch.X).."x"..str(ch.Y)
                    end
                end
            end
        end
    end
    return s
end
local function compareServers(a,b)
    if not a or not b then return "нет двух снимков" end
    local removed,added,eqChanged,levelChanged,xpChanged=0,0,0,0,0
    for id,p in pairs(a.idMap) do
        local q=b.idMap[id]
        if not q then removed+=1
        else
            if p.e~=q.e then eqChanged+=1 end
            if p.l~=q.l then levelChanged+=1 end
            if p.xp~=q.xp then xpChanged+=1 end
        end
    end
    for id in pairs(b.idMap) do if not a.idMap[id] then added+=1 end end
    return "Изменения: добавлено="..added..", пропало="..removed..", экипировка="..eqChanged..", уровни="..levelChanged..", XP="..xpChanged
end
local function report()
    local L={}
    local function ln(t) L[#L+1]=t end
    ln("ZONEHUB DEEP DIAGNOSTIC v4.0 | ИТОГ")
    ln("Только чтение: Get Other Stats / PlayerGui / LogService")
    ln("Никаких Equip, Unequip, Delete, Fuse, Shop, Trade, Mine")
    ln("Проверок: 16; UI снимков: "..data.uiSamples.."; секунд с запуска: "..(data.started and str(math.floor(os.clock()-data.at)) or "0"))
    ln("")
    local a=data.serverBefore
    local b=data.serverAfter
    ln("01 СЕРВЕР: "..(a and ("записей="..a.total.." ID="..a.valid.." слотов="..str(a.slots).." экипировано="..a.equip.."/"..str(a.max)) or ("ОШИБКА "..str(data.serverError))))
    if a then
        ln("02 ИД: дубликаты="..a.duplicates.." плохие="..a.bad.." типы ключей num/str/other="..a.numericKeys.."/"..a.stringKeys.."/"..a.otherKeys)
        ln("03 ТАБЛИЦА PETS: pairs="..a.total.." ipairs="..a.ipairs.." #Pets="..a.arrayLength.." maxNumericKey="..a.maxNumericKey)
        ln("    ВАЖНО: ipairs=0 может быть нормой при словаре, а не ошибкой.")
        ln("04 ЭКИПИРОВКА: "..a.equip.."/"..str(a.max).." | флаги e типы: "..topCounts(a.eTypes,8))
        ln("    ID экипированных: "..table.concat(a.equippedIds,", "))
        ln("05 УРОВНИ: диапазон "..str(a.levelMin).." ... "..str(a.levelMax)..", ошибочных="..#a.levelBad)
        ln("06 XP: диапазон "..str(a.xpMin).." ... "..str(a.xpMax)..", ошибочных="..#a.xpBad)
        ln("07 XP > 2^53: "..#a.xpRisk.." питомцев (РИСК точности чисел, НЕ доказанная причина поломки)")
        for i=1,math.min(#a.xpRisk,45) do
            local p=a.xpRisk[i]
            ln("    XP_RISK ID="..p.id.." xp="..str(p.xp).." type="..p.n)
        end
        ln("08 ЗАПОЛНЕННОСТЬ: "..a.total.."/"..str(a.slots).."; сверх слотов="..tostring(type(a.slots)=="number" and a.total>a.slots))
        ln("09 ТИПЫ n: "..topCounts(a.typeHistogram,16).." | типы поля n: "..topCounts(a.pTypes,8))
        ln("10 СХЕМА ПОЛЕЙ PETS:")
        for _,k in ipairs(sortedKeys(a.fields)) do
            local v=a.fields[k]
            ln("    "..clip(k,45)..": "..v.count.." / "..topCounts(v.types,4))
        end
        ln("11 SAVE ROOT КЛЮЧИ (только имена/типы, без личных значений):")
        for _,k in ipairs(sortedKeys(a.saveSummary)) do ln("    "..clip(k,100)) end
        if #a.issues>0 or #a.xpBad>0 or #a.levelBad>0 then
            ln("    НЕКОРРЕКТНЫЕ ДАННЫЕ:")
            for i=1,math.min(30,#a.issues) do ln("    ! "..a.issues[i]) end
            for i=1,math.min(20,#a.xpBad) do ln("    ! BAD_XP "..a.xpBad[i]) end
            for i=1,math.min(20,#a.levelBad) do ln("    ! BAD_L "..a.levelBad[i]) end
        end
        ln("    TOP-8 уровней:")
        for i=1,math.min(8,#a.levels) do
            local p=a.levels[i]
            ln("    "..p.id.." lvl="..str(p.level).." type="..p.n)
        end
    end
    ln("")
    local function uiBlock(num,title,s)
        if not s then ln(num.." UI "..title..": не обнаружен (открой окно во время теста)");return end
        ln(num.." UI "..title..": ScreenGui "..s.activeScreens.."/"..s.screenCount.."; GUI "..s.visibleCount.."/"..s.guiCount.."; Images="..s.images.." Buttons="..s.buttons)
        ln("    pets="..tostring(s.detectedPets).." trade="..tostring(s.detectedTrade).." Scroll="..s.visibleScrolls.."/"..s.scrolls)
        ln("    GUI roots: "..table.concat(s.roots,", "))
        for _,x in ipairs(s.counters) do ln("    COUNTER "..x) end
        for _,x in ipairs(s.emptyScrolls) do ln("    SCROLL "..x) end
        for _,x in ipairs(s.matches) do ln("    NODE "..x) end
    end
    uiBlock("12","НАЧАЛО",data.uiBase)
    uiBlock("13","PETS",data.uiPets)
    uiBlock("14","TRADING",data.uiTrade)
    if #data.uiManual>0 then
        ln("    РУЧНЫЕ СНИМКИ (последние до 4):")
        for i=math.max(1,#data.uiManual-3),#data.uiManual do
            local m=data.uiManual[i]
            uiBlock("14."..i,"РУЧНОЙ-"..m.tag,m.s)
        end
    end
    ln("15 КЛИЕНТСКИЕ ОШИБКИ: LogHistory="..data.logsReadable.."; ошибок/предупреждений="..#data.errors)
    for _,it in ipairs(data.errors) do ln("    ["..it.kind.."] x"..it.count.." "..it.msg) end
    ln("16 СЕРВЕР ПОВТОР: "..(b and ("записей="..b.total.." экипировано="..b.equip.."/"..str(b.max).." XP>2^53="..#b.xpRisk) or "не выполнен"))
    ln("    "..compareServers(a,b))
    ln("")
    ln("ИНТЕРПРЕТАЦИЯ: 120 записей на сервере не гарантируют, что GUI умеет их рисовать.")
    ln("Логи/структура помогают найти место сбоя; XP>2^53 — гипотеза, а не диагноз.")
    ln("В Delta нельзя исключить влияние стороннего клиента. Проверяй обычный Roblox отдельно.")
    return table.concat(L,"\n")
end
local function show(txt) out.Text=txt end
local function statusText(txt) status.Text=txt end
local function liveSnap(mark)
    local ok,s=pcall(uiSnap)
    if not ok then appendLog("ProbeError","GUI: "..str(s));return end
    data.uiSamples+=1
    data.latestUI=s
    if not data.uiBase then data.uiBase=s end
    if s.detectedPets then data.uiPets=s end
    if s.detectedTrade then data.uiTrade=s end
    if mark then
        data.uiManual[#data.uiManual+1]={tag=mark,s=s}
        if #data.uiManual>8 then table.remove(data.uiManual,1) end
    end
end
local function finalize()
    if data.stopped then return end
    data.running=false
    data.stopped=true
    local ok,res=pcall(serverSnap)
    if ok then data.serverAfter=res else appendLog("ProbeError","Повтор сервера: "..str(res)) end
    show(report())
    statusText("Готово. Нажми КОПИРОВАТЬ и отправь весь отчёт в чат.")
end
local function run()
    if data.started then statusText("Тест уже запускался. Снимок доступен по кнопке 2.");return end
    data.started=true;data.running=true;data.at=os.clock()
    statusText("Снимаю сервер. Затем открой Pets, закрой, открой Trading.")
    pullHistory()
    local ok,err=pcall(function() session.logConn=LogService.MessageOut:Connect(function(message,kind)
        local k=tostring(kind)
        if k:find("Error") or k:find("Warning") then appendLog(k,message) end
    end) end)
    if not ok then appendLog("ProbeError","LogService.MessageOut: "..str(err)) end
    local worked,s=pcall(serverSnap)
    if worked then data.serverBefore=s else appendLog("ProbeError","Начальный сервер: "..str(s)) end
    liveSnap("BASE")
    show(report())
    task.spawn(function()
        while data.running and not session.cancelled and os.clock()-data.at<90 do
            local tm=math.floor(90-(os.clock()-data.at))
            statusText("Осталось ~"..tm.."с. Pets="..tostring(data.uiPets~=nil).." | Trading="..tostring(data.uiTrade~=nil)..". Сверни панель.")
            liveSnap()
            task.wait(1.5)
        end
        if not data.stopped and not session.cancelled then finalize() end
    end)
end
startBtn.MouseButton1Click:Connect(run)
snapBtn.MouseButton1Click:Connect(function()
    if not data.started then statusText("Сначала нажми СТАРТ.");return end
    liveSnap("USER")
    show(report())
    statusText("Снимок записан. Продолжай открывать меню. Сохрани отчёт позже.")
end)
stopBtn.MouseButton1Click:Connect(function()
    if not data.started then statusText("Тест ещё не запущен.");return end
    data.running=false
    task.spawn(finalize)
end)
copyBtn.MouseButton1Click:Connect(function()
    if not data.started then statusText("Сначала запусти тест.");return end
    local txt=report()
    show(txt)
    if type(setclipboard)=="function" then
        local ok=pcall(function() setclipboard(txt) end)
        statusText(ok and "Отчёт скопирован в буфер. Отправь его в чат." or "Буфер недоступен; выдели текст отчёта.")
    else
        statusText("setclipboard отсутствует. Выдели текст вручную.")
    end
end)
statusText("Готово. Запусти 1 раз. В течение 90с открой Pets и Trading.")
