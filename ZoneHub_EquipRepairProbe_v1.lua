-- ZoneHub Equip Repair Probe v1 | Original Pet Simulator (2018)
-- CAUTION: One optional state-changing request ONLY after TWO manual taps.
-- Uses the already observed Inventory:InvokeServer("Equip", petID) protocol.
-- Whether "Equip" toggles an equipped pet is UNCONFIRMED. Verification is mandatory.
-- No Delete, Fuse, Shop, Trade, Mine, mass unequip or auto-loops.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return end
local pg = player:WaitForChild("PlayerGui",12)
if not pg then return end
local old = pg:FindFirstChild("ZoneHub_EquipRepairProbe_v1")
if old then old:Destroy() end

local function make(class,props,parent)
    local o = Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local palette={
    bg=Color3.fromRGB(14,21,34),panel=Color3.fromRGB(29,41,62),
    button=Color3.fromRGB(49,91,158),caution=Color3.fromRGB(147,94,27),
    text=Color3.fromRGB(238,245,255),muted=Color3.fromRGB(181,198,221)
}
local function round(o,r)
    make("UICorner",{CornerRadius=UDim.new(0,r or 9)},o)
end
local gui=make("ScreenGui",{Name="ZoneHub_EquipRepairProbe_v1",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=10020},pg)
local frame=make("Frame",{Size=UDim2.fromOffset(466,540),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),BackgroundColor3=palette.bg,BorderSizePixel=0},gui)
round(frame,15)
local scale=make("UIScale",{Scale=1},frame)
local function adapt()
    local camera=workspace.CurrentCamera
    local size=camera and camera.ViewportSize or Vector2.new(800,600)
    scale.Scale=math.clamp(math.min((size.X-20)/466,(size.Y-20)/540),.46,1)
end
adapt()
local function label(parent,value,x,y,w,h,sz,color)
    return make("TextLabel",{BackgroundTransparency=1,Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),Font=Enum.Font.Gotham,
        TextSize=sz or 12,TextWrapped=true,TextColor3=color or palette.text,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},parent)
end
local function button(name,x,y,w,h,color,callback)
    local b=make("TextButton",{Text=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),Font=Enum.Font.GothamBold,TextSize=12,
        TextWrapped=true,TextColor3=palette.text,BackgroundColor3=color or palette.button,BorderSizePixel=0},frame)
    round(b,8)
    b.MouseButton1Click:Connect(callback)
    return b
end
label(frame,"ZONEHUB · EQUIP REPAIR PROBE v1",14,10,410,28,17)
label(frame,"ОСНОВА · один питомец · без массовых операций",14,39,420,20,11,palette.muted)
local status=label(frame,"1. Нажми «Снимок сервера».",14,63,435,58,12,palette.muted)
local idBox=make("TextBox",{Position=UDim2.fromOffset(14,134),Size=UDim2.fromOffset(254,40),Text="",PlaceholderText="ID экипированного питомца",ClearTextOnFocus=false,
    BackgroundColor3=palette.panel,TextColor3=palette.text,PlaceholderColor3=palette.muted,Font=Enum.Font.Code,TextSize=14},frame)
round(idBox,8)
local selected=label(frame,"Кандидат: ещё не выбран",14,177,434,34,12,palette.muted)
local reportBox=make("TextBox",{Position=UDim2.fromOffset(14,324),Size=UDim2.fromOffset(438,158),Text="Отчёт появится после снимка.",
    TextEditable=false,ClearTextOnFocus=false,MultiLine=true,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Code,TextSize=11,BackgroundColor3=palette.panel,
    TextColor3=palette.text},frame)
round(reportBox,8)
local floating=make("TextButton",{Position=UDim2.fromOffset(12,119),Size=UDim2.fromOffset(142,43),Text="🐾 EQUIP PROBE",Visible=false,
    Font=Enum.Font.GothamBold,TextSize=12,TextColor3=palette.text,BackgroundColor3=palette.button,BorderSizePixel=0},gui)
round(floating,10)

local before,after,chosen,armed,used,busy=nil,nil,nil,false,false,false
local confirmedAt=0
local actionRet="НЕ ВЫЗЫВАЛСЯ"
local actionName="Inventory:InvokeServer('Equip',ID)"
local lastError="нет"
local reports={}
local function log(s)
    reports[#reports+1]=s
    reportBox.Text=table.concat(reports,"\n")
    print("[ZoneHub Equip Repair] "..s)
end
local function msg(s)
    status.Text=s
    print("[ZoneHub Equip Repair] "..s)
end
local function toId(v)
    local n=tonumber(v)
    if n and n>0 and n<1e12 and n%1==0 then return n end
end
local function readServer()
    local root=workspace:FindFirstChild("__REMOTES")
    local core=root and root:FindFirstChild("Core")
    local rf=core and core:FindFirstChild("Get Other Stats")
    if not rf or not rf:IsA("RemoteFunction") then return nil,"Get Other Stats не найден" end
    local ok,data=pcall(function() return rf:InvokeServer() end)
    if not ok then return nil,"Ошибка Get Other Stats: "..tostring(data) end
    local mine=type(data)=="table" and data[player.Name]
    local save=type(mine)=="table" and mine.Save
    if type(save)~="table" or type(save.Pets)~="table" then return nil,"Нет Save.Pets" end
    local s={pets={},list={},equip={},num=0,count=0,slots=save.PetSlots,max=save.MaxPets,duplicates=0}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=toId(p.id)
            if id then
                if s.pets[id] then
                    s.duplicates=s.duplicates+1
                else
                    local pet={id=id,n=tostring(p.n or "?"),level=tonumber(p.l) or -1,e=(p.e==true),gold=(p.g==true),rainbow=(p.r==true),dark=(p.dm==true)}
                    s.pets[id]=pet
                    s.list[#s.list+1]=pet
                    s.count=s.count+1
                    if pet.e then s.num=s.num+1;s.equip[#s.equip+1]=pet end
                end
            end
        end
    end
    table.sort(s.equip,function(a,b)
        if a.level~=b.level then return a.level<b.level end
        return a.id<b.id
    end)
    return s
end
local function inspectChoice(s,raw)
    local id=toId(raw)
    if not id then return nil,"Введи числовой ID" end
    local p=s.pets[id]
    if not p then return nil,"Такого ID нет в серверном инвентаре" end
    if not p.e then return nil,"Этот питомец уже НЕ экипирован — запрос запрещён" end
    return p
end
local function setChoice(s)
    local pet,err=inspectChoice(s,idBox.Text)
    if not pet then selected.Text=err;return nil,err end
    chosen=pet.id
    selected.Text="ID "..pet.id.." | тип "..pet.n.." | lvl "..pet.level.." | e=true"
    return pet
end
local function summary(tag,s)
    if not s then return end
    log(tag..": "..s.count.."/"..tostring(s.slots).." | экипировано="..s.num.."/"..tostring(s.max).." | дубликатов="..s.duplicates)
end
local function chooseDefault(s)
    if #s.equip>0 then
        idBox.Text=tostring(s.equip[1].id)
        setChoice(s)
    else
        selected.Text="В серверном Save нет экипированных питомцев"
    end
end
local function resetConfirmation()
    armed=false
    confirmedAt=0
end
button("1. Снимок сервера",14,218,213,40,nil,function()
    if busy then return end
    busy=true
    resetConfirmation()
    before=nil
    after=nil
    chosen=nil
    reports={}
    actionRet="НЕ ВЫЗЫВАЛСЯ"
    local snap,err=readServer()
    if not snap then
        lastError=err
        msg(err)
        log("ОШИБКА: "..err)
    else
        before=snap
        lastError="нет"
        log("ZONEHUB EQUIP REPAIR PROBE v1")
        log("Тест: один запрос ТОЛЬКО после двойного подтверждения.")
        summary("ДО",before)
        chooseDefault(before)
        log("Кандидат автоматически: "..tostring(chosen or "нет"))
        msg("Снимок готов. Проверь ID. Нажми «2. Проверить ID», затем «3. Один запрос» дважды.")
    end
    used=false
    busy=false
end)
button("2. Проверить ID",239,218,213,40,nil,function()
    resetConfirmation()
    if not before then msg("Сначала снимок сервера") return end
    local pet,err=setChoice(before)
    if not pet then msg(err);return end
    msg("ID="..pet.id.." действительно e=true. Один запрос может изменить экипировку, но ещё не отправлен.")
end)
button("3. Один запрос (дважды)",14,267,275,42,palette.caution,function()
    if busy or used then msg("Один запрос уже выполнен или идёт проверка. Перезайди в игру для нового опыта.");return end
    if not before then msg("Нужен исходный снимок") return end
    local pet,err=inspectChoice(before,idBox.Text)
    if not pet then msg(err);resetConfirmation();return end
    if chosen~=pet.id then msg("Сначала нажми «2. Проверить ID»") resetConfirmation();return end
    if not armed or os.clock()-confirmedAt>20 then
        armed=true
        confirmedAt=os.clock()
        msg("ПОДТВЕРЖДЕНИЕ: повтори нажатие в течение 20 секунд. Возможна смена экипировки ОДНОГО питомца "..pet.id..".")
        return
    end
    resetConfirmation()
    busy=true
    used=true
    msg("Проверяю сервер перед отправкой...")
    local fresh,ferr=readServer()
    if not fresh then lastError=ferr;log("Отмена: "..ferr);msg("Отмена: "..ferr);busy=false;return end
    if fresh.count~=before.count or fresh.num~=before.num or not fresh.pets[pet.id] or not fresh.pets[pet.id].e then
        log("ОТМЕНА: состояние сервера поменялось до действия")
        msg("Состояние сервера изменилось. Новый снимок обязателен.")
        busy=false
        return
    end
    local remoteRoot=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remoteRoot and remoteRoot:FindFirstChild("Game")
    local inv=gameRemotes and gameRemotes:FindFirstChild("Inventory")
    if not inv or not inv:IsA("RemoteFunction") then
        msg("Inventory RemoteFunction не найден. Ничего не отправлено.")
        log("ОТМЕНА: Inventory RF не найден")
        busy=false
        return
    end
    local ok,result=pcall(function() return inv:InvokeServer("Equip",pet.id) end)
    actionRet=ok and tostring(result) or ("ОШИБКА: "..tostring(result))
    log("ID попытки="..pet.id.." | действие="..actionName)
    log("pcall="..tostring(ok).." | ответ="..actionRet)
    if not ok then lastError=tostring(result) end
    task.wait(1.5)
    local snap,serr=readServer()
    if not snap then
        lastError=serr
        log("ПОСЛЕ: нет снимка ("..serr..")")
        msg("Ответ получен, но повторный снимок не удался. Отчёт сохранить.")
        busy=false
        return
    end
    after=snap
    summary("ПОСЛЕ",after)
    local p=after.pets[pet.id]
    log("ID после: существует="..tostring(p~=nil).." | e="..tostring(p and p.e))
    local gained,lost={},{}
    for id in pairs(before.pets) do if not after.pets[id] then lost[#lost+1]=id end end
    for id in pairs(after.pets) do if not before.pets[id] then gained[#gained+1]=id end end
    log("Исчезнувших ID="..#lost.." | новых ID="..#gained)
    if #lost>0 then log("ВНИМАНИЕ: исчезнувшие ID: "..table.concat(lost,",")) end
    if p and p.e==false and after.num<before.num then
        log("РЕЗУЛЬТАТ: сервер подтвердил снятие ОДНОГО питомца.")
        msg("УСПЕХ: один питомец снят. Проверь игровой инвентарь и повтори после перезахода.")
    elseif p and p.e==true then
        log("РЕЗУЛЬТАТ: e остался true; команда не сняла питомца.")
        msg("Не снялся: e=true. Других команд скрипт не отправляет. Отправь отчёт.")
    else
        log("РЕЗУЛЬТАТ: неоднозначно; изменения требуют анализа.")
        msg("Неоднозначный результат. Не повторяй запрос, отправь отчёт.")
    end
    busy=false
end)
button("4. Перепроверить",303,267,149,42,nil,function()
    if busy then return end
    busy=true
    local s,err=readServer()
    if s then
        summary("ПОВТОР",s)
        local id=toId(idBox.Text)
        log("Выбранный ID теперь e="..tostring(id and s.pets[id] and s.pets[id].e))
        msg("Проверка завершена, скопируй отчёт.")
    else
        log("ПОВТОР: "..err)
        msg(err)
    end
    busy=false
end)
button("Копировать отчёт",14,491,213,38,nil,function()
    local r=reportBox.Text.."\nОшибки="..lastError
    if type(setclipboard)=="function" then
        local ok=pcall(function() setclipboard(r) end)
        msg(ok and "Отчёт скопирован" or "Копирование не удалось; отчёт в консоли")
    else
        print(r)
        msg("Отчёт в консоли; setclipboard недоступен")
    end
end)
button("Скрыть / показать",239,491,213,38,nil,function()
    frame.Visible=false
    floating.Visible=true
end)
floating.MouseButton1Click:Connect(function() frame.Visible=true;floating.Visible=false end)
msg("Только ОСНОВА. Не запускай другой ZoneHub. Сначала сделай серверный снимок.")
print("[ZoneHub Equip Repair] Готово. Никаких серверных изменений при запуске.")
