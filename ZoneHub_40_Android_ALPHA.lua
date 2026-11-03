--[[
 ZoneHub 4.0 ALPHA / Zoni Companion v0.1
 Based on the UNMODIFIED ZoneHub 3.7.0 script by the same repository owner.
 Platform: Roblox Android / executor with game:HttpGet and loadstring.
 Features: independent companion, code search, manual server snapshot, diagnostic UI.
 Zoni is a local rules-based assistant, NOT a remote LLM or autonomous code repairer.
 NEVER auto-runs purchase/fusion/delete/equip commands. No remote calls at startup.
]]
local BASE_URL = "https://raw.githubusercontent.com/alanbanansport2000-hub/ZoneHub/main/ZoneHub_37_Android_FRESH.lua"
local VERSION = "4.0.0-alpha.1"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local environment = (type(getgenv)=="function" and getgenv()) or _G
if type(environment.ZoneHubAlphaShutdown)=="function" then
    pcall(environment.ZoneHubAlphaShutdown)
end

-- The base is loaded as an independent execution, preserving its private locals.
-- No game changes take place until this validation passes.
local fetched, source = pcall(function() return game:HttpGet(BASE_URL) end)
if not fetched or type(source)~="string" then
    warn("[ZoneHub Alpha] Cannot fetch v3.7: "..tostring(source))
    return
end
if #source < 90000 or not source:find("ZoneHub 3.7.0",1,true)
    or not source:find("ZoneHubShutdown",1,true) then
    warn("[ZoneHub Alpha] Base does not look like trusted ZoneHub 3.7. Nothing executed.")
    return
end
if type(loadstring)~="function" then
    warn("[ZoneHub Alpha] Executor does not offer loadstring")
    return
end
local compiled, compileError = loadstring(source)
if not compiled then warn("[ZoneHub Alpha] Compile error: "..tostring(compileError)) return end
local baseOK, baseErr = pcall(compiled)
if not baseOK then warn("[ZoneHub Alpha] Original 3.7 failed: "..tostring(baseErr)) return end
local baseGui = playerGui:FindFirstChild("ZoneHub_PetSim")
if not baseGui then warn("[ZoneHub Alpha] Original window not found; stopping companion") return end

local active = true
local connections = {}
local runningTweens = {}
local logs = {}
local samples = {}
local lastScan = "Загрузка 3.7 выполнена. Проверка ещё не запускалась."
local lastError = nil
local lastSnapshot = nil
local busySnapshot = false
local manualRequestedAt = -1e9
local frames, frameSeconds, fps = 0, 0, 0
local startedAt = os.clock()
local guiName = "ZoneHub_40_Zoni"
local configPath = "ZoneHub4_Zoni_Config.json"
local config = {sound=true, theme="Ocean", animate=true, originalVisible=true}
local supportedThemes = {
    Ocean = {background=Color3.fromRGB(10,15,29), card=Color3.fromRGB(21,31,52),
       accent=Color3.fromRGB(89,142,255), text=Color3.fromRGB(241,246,255)},
    AMOLED = {background=Color3.fromRGB(1,1,3), card=Color3.fromRGB(13,15,22),
       accent=Color3.fromRGB(102,230,198), text=Color3.fromRGB(248,249,255)},
    Violet = {background=Color3.fromRGB(19,13,36), card=Color3.fromRGB(36,26,61),
       accent=Color3.fromRGB(191,125,255), text=Color3.fromRGB(249,245,255)}
}
local function saveConfig()
    if type(writefile)~="function" then return false end
    local ok = pcall(function() writefile(configPath,HttpService:JSONEncode(config)) end)
    return ok
end
if type(readfile)=="function" and type(isfile)=="function" then
    pcall(function()
        if isfile(configPath) then
            local data = HttpService:JSONDecode(readfile(configPath))
            if type(data)=="table" then
                if type(data.sound)=="boolean" then config.sound=data.sound end
                if type(data.animate)=="boolean" then config.animate=data.animate end
                if supportedThemes[data.theme] then config.theme=data.theme end
                if type(data.originalVisible)=="boolean" then config.originalVisible=data.originalVisible end
            end
        end
    end)
end
local function palette() return supportedThemes[config.theme] or supportedThemes.Ocean end
local function track(c) connections[#connections+1]=c return c end
local function log(message,isError)
    local m = string.format("[%s] %s",os.date("%H:%M:%S"),tostring(message))
    logs[#logs+1]=m
    if #logs>32 then table.remove(logs,1) end
    if isError then lastError=m end
    if isError then warn("[Zoni] "..m) end
end
local function corner(parent,r)
    local u = Instance.new("UICorner") u.CornerRadius=UDim.new(0,r or 12) u.Parent=parent return u
end
local function outline(parent,color,thickness)
    local u = Instance.new("UIStroke") u.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    u.Color=color or palette().accent u.Thickness=thickness or 1.1 u.Transparency=.40 u.Parent=parent
    return u
end
local function element(class,name,parent)
    local x=Instance.new(class) x.Name=name
    if x:IsA("GuiObject") then x.BorderSizePixel=0 end
    x.Parent=parent return x
end
local function textLabel(name,parent,value,size,color)
    local x=element("TextLabel",name,parent)
    x.BackgroundTransparency=1 x.Font=Enum.Font.Gotham
    x.Text=tostring(value or "") x.TextSize=size or 14
    x.TextColor3=color or palette().text x.TextXAlignment=Enum.TextXAlignment.Left
    x.TextYAlignment=Enum.TextYAlignment.Center
    return x
end
local function tween(obj,goals,duration)
    if not active or not config.animate then
        for k,v in pairs(goals) do pcall(function() obj[k]=v end) end
        return nil
    end
    local ok,anim=pcall(function()
        return TweenService:Create(obj,TweenInfo.new(duration or .22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goals)
    end)
    if ok and anim then
        anim:Play() runningTweens[#runningTweens+1]=anim
        if #runningTweens>100 then table.remove(runningTweens,1) end
        return anim
    end
end
local existing=playerGui:FindFirstChild(guiName)
if existing then existing:Destroy() end
local gui=element("ScreenGui",guiName,playerGui)
gui.IgnoreGuiInset=true gui.ResetOnSpawn=false gui.DisplayOrder=420
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local sound=element("Sound","ZoniSound",gui)
sound.SoundId="rbxassetid://12221990" sound.Volume=.22
local function ping()
    if not config.sound then return end
    pcall(function() sound:Stop() sound:Play() end)
end

-- Animated floating pet: native shapes only, no untrusted images/assets.
local pet=element("TextButton","ZoniPet",gui)
pet.Text="" pet.AutoButtonColor=false pet.BackgroundTransparency=1
pet.Size=UDim2.fromOffset(84,91) pet.AnchorPoint=Vector2.new(.5,.5)
pet.Position=UDim2.new(1,-57,.70,0)
local glow=element("Frame","Aura",pet)
glow.BackgroundColor3=palette().accent glow.BackgroundTransparency=.80
 glow.AnchorPoint=Vector2.new(.5,.5) glow.Position=UDim2.fromScale(.5,.51)
glow.Size=UDim2.fromOffset(76,76) corner(glow,40)
local leftEar=element("Frame","EarL",pet)
leftEar.BackgroundColor3=Color3.fromRGB(121,155,246)
leftEar.Position=UDim2.fromOffset(15,11) leftEar.Size=UDim2.fromOffset(19,28)
leftEar.Rotation=-21 corner(leftEar,12)
local rightEar=element("Frame","EarR",pet)
rightEar.BackgroundColor3=Color3.fromRGB(121,155,246)
rightEar.Position=UDim2.fromOffset(50,11) rightEar.Size=UDim2.fromOffset(19,28)
rightEar.Rotation=21 corner(rightEar,12)
local head=element("Frame","Head",pet)
head.BackgroundColor3=Color3.fromRGB(102,133,240)
head.Size=UDim2.fromOffset(60,57) head.Position=UDim2.fromOffset(12,25)
corner(head,29) outline(head,Color3.fromRGB(178,203,255),1.5)
local eyeL=element("Frame","EyeL",head)
eyeL.BackgroundColor3=Color3.fromRGB(11,28,63)
eyeL.Size=UDim2.fromOffset(7,10) eyeL.Position=UDim2.fromOffset(16,22) corner(eyeL,8)
local eyeR=element("Frame","EyeR",head)
eyeR.BackgroundColor3=Color3.fromRGB(11,28,63)
eyeR.Size=UDim2.fromOffset(7,10) eyeR.Position=UDim2.fromOffset(39,22) corner(eyeR,8)
local mouth=textLabel("Mouth",head,"ᴗ",17,Color3.fromRGB(15,38,91))
mouth.Size=UDim2.fromOffset(22,16) mouth.Position=UDim2.fromOffset(24,34)
local petTag=textLabel("PetTag",pet,"ZONI",10,Color3.fromRGB(234,246,255))
petTag.TextXAlignment=Enum.TextXAlignment.Center petTag.Font=Enum.Font.GothamBold
petTag.Position=UDim2.fromOffset(19,71) petTag.Size=UDim2.fromOffset(48,15)
local speech=textLabel("Speech",gui,"Привет! Я Zoni 🐾",12,Color3.fromRGB(245,247,255))
speech.TextWrapped=true speech.BackgroundTransparency=.13
speech.BackgroundColor3=palette().card speech.TextXAlignment=Enum.TextXAlignment.Center
speech.Size=UDim2.fromOffset(172,44) speech.AnchorPoint=Vector2.new(1,.5)
speech.Position=UDim2.new(1,-101,.70,0) corner(speech,12)
local speechEpoch=0
local function say(s)
    if not active then return end
    speechEpoch=speechEpoch+1
    local current=speechEpoch
    speech.Text=tostring(s):sub(1,105)
    speech.Visible=true
    task.delay(4.5,function()
        if active and speechEpoch==current and speech.Parent then speech.Visible=false end
    end)
end

local panel=element("Frame","Panel",gui)
panel.BackgroundColor3=palette().background
panel.Size=UDim2.fromOffset(370,505) panel.AnchorPoint=Vector2.new(1,.5)
panel.Position=UDim2.new(1,-99,.47,0) panel.Visible=false
corner(panel,18) local panelOutline=outline(panel,palette().accent,1.2)
local panelScale=element("UIScale","MobileScale",panel)
local header=element("Frame","DragHeader",panel)
header.BackgroundTransparency=1 header.Size=UDim2.new(1,0,0,61)
local title=textLabel("Title",header,"ZONI / ZoneHub 4.0",17,palette().text)
title.Font=Enum.Font.GothamBold title.Position=UDim2.fromOffset(16,8)
title.Size=UDim2.new(1,-80,0,25)
local subtitle=textLabel("Subtitle",header,"Локальный помощник • ALPHA 1",11,Color3.fromRGB(155,174,207))
subtitle.Position=UDim2.fromOffset(16,34) subtitle.Size=UDim2.new(1,-80,0,18)
local function createButton(parent,name,label,size,pos,callback)
    local b=element("TextButton",name,parent)
    b.Text=label b.Font=Enum.Font.GothamSemibold b.TextSize=13
    b.TextColor3=Color3.fromRGB(240,246,255)
    b.BackgroundColor3=palette().card
    b.AutoButtonColor=false
    b.Size=size b.Position=pos corner(b,10)
    track(b.MouseButton1Click:Connect(function()
        if not active then return end
        ping()
        local ok,err=pcall(callback)
        if not ok then log(name..": "..tostring(err),true) say("Ошибка кнопки. Смотри логи.") end
    end))
    return b
end
local close=createButton(header,"Close","×",UDim2.fromOffset(37,35),UDim2.new(1,-45,0,12),function()
    panel.Visible=false
end)
local divider=element("Frame","Divider",panel)
divider.BackgroundColor3=Color3.fromRGB(54,68,99)
divider.Size=UDim2.new(1,-28,0,1) divider.Position=UDim2.fromOffset(14,64)
local tabs=element("Frame","Tabs",panel)
tabs.BackgroundTransparency=1 tabs.Position=UDim2.fromOffset(10,74)
tabs.Size=UDim2.new(1,-20,0,38)
local tabPages={}
local tabButtons={}
local activeTab="Чат"
local content=element("Frame","Content",panel)
content.BackgroundTransparency=1 content.Position=UDim2.fromOffset(12,121)
content.Size=UDim2.new(1,-24,1,-134)
local function page(name)
    local p=element("Frame","Page_"..name,content)
    p.Size=UDim2.fromScale(1,1) p.BackgroundTransparency=1 p.Visible=false
    tabPages[name]=p
    return p
end
local chatPage=page("Чат")
local diagPage=page("Монитор")
local codePage=page("Код")
local settingsPage=page("Опции")
local function selectTab(name)
    activeTab=name
    for k,p in pairs(tabPages) do p.Visible=(k==name) end
    for k,b in pairs(tabButtons) do
        tween(b,{BackgroundColor3=k==name and palette().accent or palette().card},.14)
    end
end
for i,name in ipairs({"Чат","Монитор","Код","Опции"}) do
    local width=84
    local b=createButton(tabs,"Tab_"..name,name,UDim2.fromOffset(width,36),UDim2.fromOffset((i-1)*88,0),function() selectTab(name) end)
    tabButtons[name]=b
end

local history=element("ScrollingFrame","ChatHistory",chatPage)
history.BackgroundColor3=palette().card history.BackgroundTransparency=.12
history.Size=UDim2.new(1,0,1,-92) history.ScrollBarThickness=3
history.AutomaticCanvasSize=Enum.AutomaticSize.Y
history.CanvasSize=UDim2.new(0,0,0,0) corner(history,12)
local historyLayout=element("UIListLayout","ChatLayout",history)
historyLayout.Padding=UDim.new(0,7) historyLayout.SortOrder=Enum.SortOrder.LayoutOrder
local chatPadding=element("UIPadding","ChatPadding",history)
chatPadding.PaddingTop=UDim.new(0,10) chatPadding.PaddingLeft=UDim.new(0,9)
chatPadding.PaddingRight=UDim.new(0,9) chatPadding.PaddingBottom=UDim.new(0,10)
local chatCount=0
local function addMessage(by,message)
    chatCount=chatCount+1
    local text=tostring(message):sub(1,1500)
    local l=textLabel("Message_"..chatCount,history,(by=="Zoni" and "🐾 Zoni: " or "Вы: ")..text,13)
    l.TextWrapped=true l.TextYAlignment=Enum.TextYAlignment.Top
    l.Size=UDim2.new(1,-8,0,0) l.AutomaticSize=Enum.AutomaticSize.Y
    l.BackgroundTransparency=1
    l.LayoutOrder=chatCount
    if by=="Zoni" then l.TextColor3=Color3.fromRGB(165,200,255) end
    if chatCount>38 then
        for _,it in ipairs(history:GetChildren()) do
            if it:IsA("TextLabel") and it.LayoutOrder <= chatCount-38 then it:Destroy() end
        end
    end
    task.defer(function()
        if active and history.Parent then history.CanvasPosition=Vector2.new(0,history.AbsoluteCanvasSize.Y) end
    end)
end
local input=element("TextBox","MessageInput",chatPage)
input.Size=UDim2.new(1,-86,0,40) input.Position=UDim2.new(0,0,1,-82)
input.BackgroundColor3=palette().card input.TextColor3=palette().text
input.PlaceholderColor3=Color3.fromRGB(150,165,190)
input.PlaceholderText="Спроси про фарм, код, FPS..." input.Text=""
input.Font=Enum.Font.Gotham input.TextSize=12 input.ClearTextOnFocus=false
input.TextXAlignment=Enum.TextXAlignment.Left corner(input,10)
local sendButton

local function compact(v)
    if type(v)~="number" then return "н/д" end
    local n=math.abs(v)
    if n>=1e12 then return string.format("%.2fT",v/1e12) end
    if n>=1e9 then return string.format("%.2fB",v/1e9) end
    if n>=1e6 then return string.format("%.2fM",v/1e6) end
    if n>=1e3 then return string.format("%.1fK",v/1e3) end
    return tostring(math.floor(v))
end
local function russianLower(s)
    local result={}
    local ok=pcall(function()
        for _,cp in utf8.codes(tostring(s)) do
            if cp>=1040 and cp<=1071 then cp=cp+32
            elseif cp==1025 then cp=1105
            elseif cp>=65 and cp<=90 then cp=cp+32 end
            result[#result+1]=utf8.char(cp)
        end
    end)
    return ok and table.concat(result) or tostring(s):lower()
end
local lines=string.split(source,"\n")
local normalizedLines={}
for i,line in ipairs(lines) do normalizedLines[i]=russianLower(line) end
local function searchSource(phrase)
    local needle=russianLower(tostring(phrase or "")):sub(1,65)
    if #needle<2 then return "После «код:» напиши минимум 2 символа." end
    local results={}
    for n,s in ipairs(lines) do
        if normalizedLines[n]:find(needle,1,true) then
            results[#results+1]=string.format("%d: %s",n,s:gsub("^%s+", ""):sub(1,118))
            if #results>=6 then break end
        end
    end
    if #results==0 then return "В загруженном исходнике нет совпадений «"..needle.."»." end
    return "Найдено в 3.7:\n"..table.concat(results,"\n").."\nПоказаны первые 6 совпадений."
end
local diagList={}
local function monitorBase()
    if not baseGui or not baseGui.Parent then
        lastScan="Исходный интерфейс 3.7 отсутствует. Возможно, другой скрипт его закрыл."
        return
    end
    local pieces={}
    local ok=pcall(function()
        for _,d in ipairs(baseGui:GetDescendants()) do
            if d:IsA("TextLabel") then
                local s=d.Text or ""
                if (#s>10 and #s<380) and
                   (s:find("HP:",1,true) or s:find("питомцев в очереди",1,true)
                    or s:find("Питомцев в очереди",1,true)
                    or s:find("Mine:",1,true)) then
                    pieces[#pieces+1]=s:sub(1,270)
                    if #pieces>=3 then break end
                end
            end
        end
    end)
    if ok and #pieces>0 then lastScan=table.concat(pieces,"\n")
    else lastScan="Окно 3.7 найдено. Активные счётчики пока не обнаружены." end
end
local snapshotLines=function()
    if not lastSnapshot then return "Снимок инвентаря не запрашивался. Нажми «Инвентарь»." end
    local s=lastSnapshot
    local line="Питомцев: "..tostring(s.count).." / "..tostring(s.slots)
           .."\nЭкипировано: "..tostring(s.equipped).." / "..tostring(s.maxPets)
    if s.coins then line=line.."\nМонеты: "..compact(s.coins) end
    if s.error then line=line.."\nОшибка: "..s.error end
    return line
end
local function remoteInventory()
    if busySnapshot then return "Чтение уже запущено, дождись результата." end
    if os.clock()-manualRequestedAt<12 then return "Не чаще одного запроса за 12 секунд." end
    manualRequestedAt=os.clock()
    local r=workspace:FindFirstChild("__REMOTES")
    local core=r and r:FindFirstChild("Core")
    local remote=core and core:FindFirstChild("Get Other Stats")
    if not remote or not remote:IsA("RemoteFunction") then
        return "Серверный Core/Get Other Stats не обнаружен."
    end
    busySnapshot=true
    task.spawn(function()
        local began=os.clock()
        local ok,data=pcall(function() return remote:InvokeServer() end)
        if not active then return end
        busySnapshot=false
        if not ok then
            local err=tostring(data):sub(1,140)
            log("Inventory: "..err,true) say("Не удалось обновить инвентарь")
            return
        end
        local own=type(data)=="table" and data[player.Name]
        local save=type(own)=="table" and own.Save
        if type(save)~="table" or type(save.Pets)~="table" then
            log("Ответ сервера не содержит Save.Pets",true) return
        end
        local count,equipped=0,0
        for _,p in pairs(save.Pets) do
            if type(p)=="table" and tonumber(p.id) then
                count=count+1
                if p.e==true or p.e==1 or p.e=="true" then equipped=equipped+1 end
            end
        end
        lastSnapshot={count=count,equipped=equipped,
            slots=tonumber(save.PetSlots) or "?", maxPets=tonumber(save.MaxPets) or "?",
            coins=tonumber(save.Coins),duration=os.clock()-began,at=os.clock()}
        if type(lastSnapshot.maxPets)=="number" and equipped>lastSnapshot.maxPets then
            log("Экипировка требует проверки: "..equipped.."/"..lastSnapshot.maxPets,true)
        else log("Серверный снимок: "..count.." питомцев") end
        say("Инвентарь обновлён: "..count.." питомцев")
    end)
    task.delay(12,function()
        if active and busySnapshot then log("Get Other Stats отвечает более 12 секунд; новые запросы заблокированы",true) end
    end)
    return "Запрос отправлен. Чтение выполняется отдельно от интерфейса."
end
local function statusText()
    local rem=workspace:FindFirstChild("__REMOTES")
    local core=rem and rem:FindFirstChild("Core")
    local g=rem and rem:FindFirstChild("Game")
    local mine=g and g:FindFirstChild("Coins")
    return string.format("FPS: %d\n3.7: %s\nGame Remotes: %s\nCoins Remote: %s\nВремя: %d сек\n%s",fps,
      baseGui and baseGui.Parent and "загружен" or "не найден",core and "есть" or "нет",
      mine and "есть" or "нет",math.floor(os.clock()-startedAt),snapshotLines())
end
local function answer(question)
    local q=russianLower(tostring(question or ""))
    if q:find("код:",1,true) then
        return searchSource(q:match("код:%s*(.+)") or "")
    end
    if q:find("code:",1,true) then
        return searchSource(q:match("code:%s*(.+)") or "")
    end
    local line=q:match("строк[а-я]*%s+(%d+)")
    if line then
        local n=tonumber(line)
        if n and lines[n] then return "Строка "..n..":\n"..lines[n]:sub(1,550) end
        return "Нет такой строки в загруженной 3.7."
    end
    if q:find("помощ",1,true) or q:find("умеешь",1,true) or q:find("команд",1,true) then
        return "Могу объяснить фарм, яйца и питомцев; показать FPS и состояние игры; вручную прочитать инвентарь; искать в Lua-коде (код: dynamicFarm), показывать строки (строка 1759), объяснять ошибки. Не редактирую код на лету."
    end
    if q:find("инвентар",1,true) or q:find("сколько питом",1,true) or q:find("экипир",1,true) then
        return snapshotLines().."\nДля актуализации используй «Инвентарь» на вкладке «Монитор»."
    end
    if q:find("fps",1,true) or q:find("фпс",1,true) or q:find("производ",1,true) or q:find("лага",1,true) then
        return "Текущий FPS: "..fps..". Монитор считает локальные кадры, но не определяет причину каждого падения. Отключи анимации, если они мешают."
    end
    if q:find("ошиб",1,true) or q:find("баг",1,true) or q:find("завис",1,true) then
        return lastError and ("Последняя зарегистрированная проблема:\n"..lastError.."\nПопробуй перезапуск игры при зависшем Remote.") or "Ошибок Zoni пока не зарегистрировано. Ошибки внутри закрытых локальных функций 3.7 не всегда видны помощнику."
    end
    if q:find("яйц",1,true) or q:find("хэтч",1,true) then
        return "3.7 открывает яйца через Game.Shop и проверяет результат через Core/Get Other Stats. Сезонные яйца могут быть недоступны. Покупки Zoni не запускает. Для фрагмента реализации: код: getEggInventory"
    end
    if q:find("скрещ",1,true) or q:find("золот",1,true) or q:find("радуж",1,true) then
        return "В 3.7 правила преобразования: 10 обычных → золотой, 7 золотых → радужный, 5 радужных → Dark Matter. Результат нужно подтверждать через текущий инвентарь. Для кода: код: UPGRADE"
    end
    if q:find("фарм",1,true) or q:find("монет",1,true) or q:find("mine",1,true) then
        return "В 3.7 уже есть планировщик dynamicFarm, удержание целей, приоритет сильных питомцев и контроль HP монет. Состояние текста 3.7:\n"..lastScan:sub(1,480).."\nДля кода: код: dynamicFarm"
    end
    if q:find("статус",1,true) or q:find("провер",1,true) then return statusText() end
    if q:find("привет",1,true) or q:find("зони",1,true) or q:find("кто ты",1,true) then
        return "Я Zoni 🐾, локальный помощник ZoneHub Alpha. Исходник 3.7 загружен, могу искать конкретные места в коде и объяснять известные механики. Спроси «помощь»."
    end
    return "Я пока работаю по проверенным правилам и поиску по исходнику, поэтому не могу достоверно ответить на произвольный вопрос. Попробуй «помощь», «статус» или «код: <слово>»."
end
local function send()
    local q=input.Text
    if #q==0 then return end
    input.Text=""
    addMessage("You",q)
    local ok,r=pcall(answer,q)
    addMessage("Zoni",ok and r or "Не смог разобрать вопрос. Подробности в журнале.")
    if not ok then log(r,true) end
    if ok then say("Ответ готов! 🐾") end
    ping()
end
sendButton=createButton(chatPage,"Send","➤",UDim2.fromOffset(76,40),UDim2.new(1,-76,1,-82),send)
track(input.FocusLost:Connect(function(enter)
    if enter and active then send() end
end))
local quick=createButton(chatPage,"Help","? Возможности",UDim2.fromOffset(120,30),UDim2.new(0,0,1,-32),function()
    input.Text="помощь" send()
end)
local quick2=createButton(chatPage,"Status","Статус",UDim2.fromOffset(91,30),UDim2.new(0,130,1,-32),function()
    input.Text="статус" send()
end)

-- Monitor page.
local statusBox=textLabel("Status",diagPage,"Сбор состояния...",14)
statusBox.TextWrapped=true statusBox.TextYAlignment=Enum.TextYAlignment.Top
statusBox.Position=UDim2.fromOffset(5,3) statusBox.Size=UDim2.new(1,-10,0,155)
local baseBox=textLabel("BaseDetails",diagPage,"",12,Color3.fromRGB(177,196,231))
baseBox.TextWrapped=true baseBox.TextYAlignment=Enum.TextYAlignment.Top
baseBox.Position=UDim2.fromOffset(5,190) baseBox.Size=UDim2.new(1,-10,0,112)
local invButton=createButton(diagPage,"Inventory","Инвентарь",UDim2.fromOffset(117,38),UDim2.fromOffset(0,148),function()
    local m=remoteInventory() say(m) log(m)
end)
local statButton=createButton(diagPage,"Check","Проверка",UDim2.fromOffset(111,38),UDim2.fromOffset(125,148),function()
    monitorBase() say("Проверка завершена")
end)
local copyButton=createButton(diagPage,"Copy","Копировать",UDim2.fromOffset(105,38),UDim2.fromOffset(244,148),function()
    if type(setclipboard)~="function" then say("Буфер обмена недоступен") return end
    local report="ZoneHub "..VERSION.." / Original 3.7\n"..statusText().."\n3.7 UI:\n"..lastScan.."\nErrors:\n"..table.concat(logs,"\n")
    local ok=pcall(setclipboard,report:sub(1,4500))
    say(ok and "Диагностика скопирована" or "Копирование не удалось")
end)
local bars={}
local barHolder=element("Frame","FPSChart",diagPage)
barHolder.BackgroundColor3=palette().card
barHolder.Position=UDim2.fromOffset(0,308) barHolder.Size=UDim2.new(1,0,0,58)
corner(barHolder,9)
for i=1,24 do
    local bar=element("Frame","Bar"..i,barHolder)
    bar.BackgroundColor3=palette().accent
    bar.AnchorPoint=Vector2.new(0,1) bar.Position=UDim2.new((i-1)/24,3,1,-4)
    bar.Size=UDim2.new(0,8,0,5)
    bars[i]=bar
end

-- Code page.
local codeInfo=textLabel("CodeInfo",codePage,"",13)
codeInfo.TextWrapped=true codeInfo.TextYAlignment=Enum.TextYAlignment.Top
codeInfo.Position=UDim2.fromOffset(3,3) codeInfo.Size=UDim2.new(1,-6,0,62)
local codeInput=element("TextBox","CodeSearch",codePage)
codeInput.Position=UDim2.fromOffset(0,68) codeInput.Size=UDim2.new(1,-94,0,39)
codeInput.Text="" codeInput.PlaceholderText="function, Mine, Get Other Stats..."
codeInput.Font=Enum.Font.Gotham codeInput.TextSize=12
codeInput.BackgroundColor3=palette().card codeInput.TextColor3=palette().text
codeInput.PlaceholderColor3=Color3.fromRGB(140,160,185)
codeInput.ClearTextOnFocus=false corner(codeInput,10)
local codeResult=textLabel("CodeResult",codePage,"Напиши запрос и нажми «Найти».\nНапример: dynamicFarm",12,Color3.fromRGB(184,206,246))
codeResult.TextWrapped=true codeResult.TextYAlignment=Enum.TextYAlignment.Top
codeResult.Position=UDim2.fromOffset(4,116) codeResult.Size=UDim2.new(1,-8,1,-121)
local findButton=createButton(codePage,"Find","Найти",UDim2.fromOffset(86,39),UDim2.new(1,-86,0,68),function()
    codeResult.Text=searchSource(codeInput.Text)
end)
track(codeInput.FocusLost:Connect(function(enter)
    if enter then codeResult.Text=searchSource(codeInput.Text) end
end))

-- Settings page.
local settingInfo=textLabel("SettingInfo",settingsPage,"Здесь меняется только Zoni. Механики 3.7 не затрагиваются.",13)
settingInfo.TextWrapped=true settingInfo.Size=UDim2.new(1,-10,0,54)
local soundButton,animationButton,themeButton,originalButton
soundButton=createButton(settingsPage,"SoundToggle","Звук: "..(config.sound and "ВКЛ" or "ВЫКЛ"),UDim2.new(1,-12,0,40),UDim2.fromOffset(6,61),function()
    config.sound=not config.sound soundButton.Text="Звук: "..(config.sound and "ВКЛ" or "ВЫКЛ") saveConfig()
end)
animationButton=createButton(settingsPage,"AnimToggle","Анимации: "..(config.animate and "ВКЛ" or "ВЫКЛ"),UDim2.new(1,-12,0,40),UDim2.fromOffset(6,111),function()
    config.animate=not config.animate animationButton.Text="Анимации: "..(config.animate and "ВКЛ" or "ВЫКЛ") saveConfig()
end)
themeButton=createButton(settingsPage,"ThemeToggle","Тема: "..config.theme,UDim2.new(1,-12,0,40),UDim2.fromOffset(6,161),function()
    config.theme=config.theme=="Ocean" and "AMOLED" or (config.theme=="AMOLED" and "Violet" or "Ocean")
    themeButton.Text="Тема: "..config.theme
    local c=palette()
    panel.BackgroundColor3=c.background panelOutline.Color=c.accent
    title.TextColor3=c.text glow.BackgroundColor3=c.accent
    for i,b in ipairs(bars) do b.BackgroundColor3=c.accent end
    for k,b in pairs(tabButtons) do b.BackgroundColor3=(activeTab==k) and c.accent or c.card end
    saveConfig()
end)
originalButton=createButton(settingsPage,"OriginalToggle","Окно 3.7: "..(config.originalVisible and "ПОКАЗАНО" or "СКРЫТО"),UDim2.new(1,-12,0,40),UDim2.fromOffset(6,211),function()
    if baseGui and baseGui.Parent then
        baseGui.Enabled=not baseGui.Enabled
        config.originalVisible=baseGui.Enabled
        originalButton.Text="Окно 3.7: "..(baseGui.Enabled and "ПОКАЗАНО" or "СКРЫТО")
        saveConfig()
    else say("Окно 3.7 не найдено") end
end)
local stopConfirmUntil=0
local stopBase
stopBase=createButton(settingsPage,"StopBoth","Остановить всё (подтверждение)",UDim2.new(1,-12,0,40),UDim2.fromOffset(6,269),function()
    if os.clock() > stopConfirmUntil then
        stopConfirmUntil=os.clock()+5
        stopBase.Text="Нажми ещё раз: остановить"
        say("Подтверди остановку в течение 5 секунд")
    else
        stopConfirmUntil=0
        local shut=environment.ZoneHubShutdown
        if type(shut)=="function" then pcall(shut) end
        local ownShut=environment.ZoneHubAlphaShutdown
        if type(ownShut)=="function" then ownShut() end
    end
end)

-- Drag panel only from the header (not the input box).
local dragStart=nil
local startPosition=nil
track(header.InputBegan:Connect(function(t)
    if t.UserInputType==Enum.UserInputType.Touch or t.UserInputType==Enum.UserInputType.MouseButton1 then
        dragStart=t.Position startPosition=panel.Position
    end
end))
track(UserInputService.InputChanged:Connect(function(t)
    if not dragStart or not active or not panel.Visible then return end
    if t.UserInputType~=Enum.UserInputType.Touch and t.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=t.Position-dragStart
    panel.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,
                             startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
end))
track(UserInputService.InputEnded:Connect(function(t)
    if t.UserInputType==Enum.UserInputType.Touch or t.UserInputType==Enum.UserInputType.MouseButton1 then dragStart=nil end
end))
local function fitUI()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    panelScale.Scale=math.clamp(math.min((v.X-22)/375,(v.Y-22)/510),.50,1)
end
fitUI()
local panelOpened=false
track(pet.MouseButton1Click:Connect(function()
    if not active then return end
    panelOpened=not panelOpened
    panel.Visible=panelOpened
    ping()
    if panelOpened then say("Можешь задать мне вопрос!") end
end))

-- Live telemetry. No Heartbeat workspace scans or server Remote calls.
track(RunService.RenderStepped:Connect(function(dt)
    frames=frames+1
    frameSeconds=frameSeconds+dt
    if frameSeconds>=1.0 then
        fps=math.max(0,math.floor(frames/frameSeconds+.5))
        frameSeconds=0 frames=0
    end
end))
local previousFpsSample=0
local previousPoll=0
local floatEpoch=0
local function petAnimation()
    floatEpoch=floatEpoch+1
    local epoch=floatEpoch
    task.spawn(function()
        while active and epoch==floatEpoch do
            if config.animate then
                tween(head,{Position=UDim2.fromOffset(12,21)},.75)
                tween(glow,{BackgroundTransparency=.92},.75)
                task.wait(.82)
                if not active then break end
                tween(head,{Position=UDim2.fromOffset(12,25)},.75)
                tween(glow,{BackgroundTransparency=.78},.75)
                task.wait(.82)
                if math.random(1,4)==1 then
                    eyeL.Size=UDim2.fromOffset(7,2) eyeR.Size=UDim2.fromOffset(7,2)
                    task.wait(.13)
                    if active then eyeL.Size=UDim2.fromOffset(7,10) eyeR.Size=UDim2.fromOffset(7,10) end
                end
            else task.wait(1.3) end
        end
    end)
end
petAnimation()
track(RunService.Heartbeat:Connect(function()
    local now=os.clock()
    if now-previousPoll>=3 then
        previousPoll=now
        fitUI()
        if baseGui and baseGui.Parent then monitorBase() end
        if diagPage.Visible then
            statusBox.Text=statusText()
            baseBox.Text=lastScan:sub(1,560)
        end
        if codePage.Visible then
            codeInfo.Text=string.format("Источник: ZoneHub 3.7.0\n%d строк; исходник прочитан при запуске.\nПоиск локальный, без отправки кода.",#lines)
        end
    end
    if now-previousFpsSample>=5 then
        previousFpsSample=now
        samples[#samples+1]=fps
        if #samples>24 then table.remove(samples,1) end
        for i,b in ipairs(bars) do
            local f=samples[i] or 0
            b.Size=UDim2.new(0,8,0,math.clamp(f/90*48,3,49))
        end
    end
end))

-- Exit releases all owned signals and UI. Base 3.7 remains untouched on Zoni-only exit.
local shutdownCalled=false
local function shutdownAlpha()
    if shutdownCalled then return end
    shutdownCalled=true
    active=false
    floatEpoch=floatEpoch+1
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _,tw in ipairs(runningTweens) do pcall(function() tw:Cancel() end) end
    pcall(function() gui:Destroy() end)
    if environment.ZoneHubAlphaShutdown==shutdownAlpha then environment.ZoneHubAlphaShutdown=nil end
end
environment.ZoneHubAlphaShutdown=shutdownAlpha
if baseGui and baseGui.Parent then baseGui.Enabled=config.originalVisible end
selectTab("Чат")
addMessage("Zoni","Привет! Я Zoni 🐾. Сохранил логику 3.7 без изменений. Напиши «помощь», «статус» или «код: dynamicFarm». Для получения инвентаря нажми «Инвентарь» на вкладке «Монитор».")
log("Alpha loaded. Base v3.7 started, source lines: "..#lines)
say("Zoni готов помочь! 🐾")
