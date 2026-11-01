-- ZoneHub LevelProbe v1 | Pet Simulator (2018) | standalone
-- Reads server inventory, tests one normal and one increased Mine parameter on a coin.
-- NEVER edits Pets, buys, deletes, fuses, equips, or fires any unverified level-changing remote.
-- IMPORTANT: increased coin damage is NOT proof of changing the stored pet level.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
if not player then return end
local pg=player:WaitForChild('PlayerGui',8)
if not pg then return end
local old=pg:FindFirstChild('ZoneHub_LevelProbe_v1')
if old then old:Destroy() end
local R=workspace:FindFirstChild('__REMOTES')
local core=R and R:FindFirstChild('Core')
local statsRemote=core and core:FindFirstChild('Get Other Stats')
local gameRemotes=R and R:FindFirstChild('Game')
local mine=gameRemotes and gameRemotes:FindFirstChild('Coins')
local move=gameRemotes and gameRemotes:FindFirstChild('Pets')
local coindir=workspace:FindFirstChild('__THINGS') and workspace.__THINGS:FindFirstChild('Coins')
local C={bg=Color3.fromRGB(17,21,34),panel=Color3.fromRGB(28,34,52),accent=Color3.fromRGB(96,86,219),ink=Color3.fromRGB(241,244,255),muted=Color3.fromRGB(177,190,215),green=Color3.fromRGB(75,157,115)}
local function add(class,props,parent)
 local obj=Instance.new(class)
 for k,v in pairs(props) do obj[k]=v end
 obj.Parent=parent
 return obj
end
local function round(x,r) add('UICorner',{CornerRadius=UDim.new(0,r or 8)},x) end
local gui=add('ScreenGui',{Name='ZoneHub_LevelProbe_v1',ResetOnSpawn=false,DisplayOrder=10001,IgnoreGuiInset=true},pg)
local panel=add('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(480,550),BackgroundColor3=C.bg,BorderSizePixel=0},gui)
round(panel,12)
local scale=add('UIScale',{},panel)
local function scaleUI()
 local cam=workspace.CurrentCamera
 local v=cam and cam.ViewportSize or Vector2.new(800,600)
 scale.Scale=math.clamp(math.min((v.X-22)/480,(v.Y-45)/550),.48,1)
end
scaleUI()
local function label(parent,value,x,y,w,h,sz,color)
 return add('TextLabel',{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=sz or 13,TextColor3=color or C.ink,Text=value,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},parent)
end
local function button(txt,x,y,w,h,fn,color)
 local b=add('TextButton',{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),Text=txt,TextColor3=C.ink,Font=Enum.Font.GothamBold,TextSize=12,BackgroundColor3=color or C.accent,BorderSizePixel=0},panel)
 round(b,8)
 b.MouseButton1Click:Connect(fn)
 return b
end
label(panel,'🐾 ZONEHUB · LEVEL PROBE v1',15,8,405,27,17)
label(panel,'Серверный уровень ≠ параметр урона Mine',15,33,410,21,12,C.muted)
local status=label(panel,'Выбери питомца после обновления списка.',14,65,452,40,12,C.muted)
local running=false
local selected=nil
local petList={}
local report='ZONEHUB LEVEL PROBE v1\nТест ещё не запущен.'
local function say(t) status.Text=t print('[ZoneHub LevelProbe] '..t) end
local function readSave()
 if not statsRemote or not statsRemote:IsA('RemoteFunction') then return nil,'Не найден Get Other Stats' end
 local ok,result=pcall(function() return statsRemote:InvokeServer() end)
 if not ok then return nil,'Ошибка чтения: '..tostring(result) end
 local save=type(result)=='table' and type(result[player.Name])=='table' and result[player.Name].Save
 if type(save)~='table' or type(save.Pets)~='table' then return nil,'Нет Save.Pets в ответе сервера' end
 return save
end
local function findPet(save,id)
 for _,p in pairs(save.Pets) do
  if type(p)=='table' and tonumber(p.id)==id then return p end
 end
 return nil
end
local function petName(p)
 return tostring(p.n or p.name or p.t or '?')
end
local function listPets(save)
 local result={}
 for _,p in pairs(save.Pets) do
  local id,l=tonumber(p and p.id),tonumber(p and p.l)
  if id and id>0 and l and l>0 and l==l then
   result[#result+1]={id=id,level=l,name=petName(p),equipped=(p.e==true or p.e==1)}
  end
 end
 table.sort(result,function(a,b)
  if a.level==b.level then return a.id<b.id end
  return a.level>b.level
 end)
 return result
end
local scroll=add('ScrollingFrame',{Position=UDim2.fromOffset(15,143),Size=UDim2.fromOffset(450,127),BackgroundColor3=C.panel,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0)},panel)
round(scroll,8)
local layout=add('UIListLayout',{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)},scroll)
local function renderList()
 for _,ch in ipairs(scroll:GetChildren()) do if ch:IsA('TextButton') then ch:Destroy() end end
 for i,p in ipairs(petList) do
  local b=add('TextButton',{Size=UDim2.new(1,-8,0,32),LayoutOrder=i,BackgroundColor3=selected==p.id and C.accent or Color3.fromRGB(38,47,71),BorderSizePixel=0,TextColor3=C.ink,Font=Enum.Font.Code,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Text='  '..(p.equipped and '●' or '○')..' ID '..p.id..'  ур. '..string.format('%.0f',p.level)..'  '..p.name},scroll)
  round(b,6)
  b.MouseButton1Click:Connect(function()
   selected=p.id
   renderList()
   say('Выбран ID '..p.id..', уровень '..string.format('%.0f',p.level)..'. Тест не изменит питомца.')
  end)
 end
 scroll.CanvasSize=UDim2.fromOffset(0,#petList*35+8)
end
button('1. ОБНОВИТЬ ИНВЕНТАРЬ',15,103,450,35,function()
 if running then return end
 running=true
 task.spawn(function()
  local ok,err=pcall(function()
   local save,e=readSave()
   if not save then say('Ошибка: '..e) return end
   petList=listPets(save)
   if not findPet(save,selected) then selected=petList[1] and petList[1].id or nil end
   renderList()
   say('Сервер: '..#petList..' питомцев. Выбери ID для теста.')
  end)
  if not ok then say('Ошибка интерфейса: '..tostring(err)) end
  running=false
 end)
end)
label(panel,'Желаемый уровень для проверки урона (макс. ×10):',15,274,435,23,12)
local box=add('TextBox',{Position=UDim2.fromOffset(15,300),Size=UDim2.fromOffset(450,35),Text='10000000',PlaceholderText='Например 10000000',ClearTextOnFocus=false,BackgroundColor3=C.panel,TextColor3=C.ink,Font=Enum.Font.Code,TextSize=16,BorderSizePixel=0},panel)
round(box,8)
local function hp(obj)
 if not obj or not obj.Parent then return nil end
 for _,key in ipairs({'Health','HP','Hp','health'}) do
  local val=obj:FindFirstChild(key,true)
  if val and (val:IsA('IntValue') or val:IsA('NumberValue')) then return tonumber(val.Value) end
  local attr=obj:GetAttribute(key)
  if type(attr)=='number' then return attr end
 end
 return nil
end
local function findPart(obj)
 if obj:IsA('BasePart') then return obj end
 if obj:IsA('Model') and obj.PrimaryPart then return obj.PrimaryPart end
 return obj:FindFirstChildWhichIsA('BasePart',true)
end
local function chooseCoin(minHp)
 if not coindir then return nil,'Папка __THINGS.Coins отсутствует' end
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if not root then return nil,'Не найден персонаж' end
 local best,nearest
 for _,obj in ipairs(coindir:GetChildren()) do
  local part=findPart(obj)
  local health=hp(obj)
  if part and health and health>minHp then
   local distance=(part.Position-root.Position).Magnitude
   if distance<350 and (not nearest or distance<nearest) then
    nearest=distance;best={obj=obj,part=part,health=health}
   end
  end
 end
 if not best then return nil,'Нет монеты с HP > '..string.format('%.0f',minHp)..' поблизости (350 studs). Подойди к большой монете.' end
 return best
end
local function pause(t) task.wait(t) end
local function fmt(n) return n and string.format('%.0f',n) or '?' end
local function runTest()
 if not selected then say('Сначала обнови инвентарь и выбери питомца.');return end
 if not mine or not mine:IsA('RemoteEvent') or not move or not move:IsA('RemoteEvent') then
  say('Не найдены Game.Coins или Game.Pets — проверка отменена.');return
 end
 local intended=tonumber(box.Text)
 if not intended or intended~=intended or intended<1 or intended%1~=0 then say('Введи целый положительный уровень.');return end
 if running then return end
 running=true
 task.spawn(function()
  local ok,err=pcall(function()
   local lines={'ZONEHUB LEVEL PROBE v1','Тест: 1 обычный Mine + 1 увеличенный Mine; без изменения инвентаря.'}
   local save,readErr=readSave()
   if not save then say(readErr);return end
   local pet=findPet(save,selected)
   if not pet then say('Питомец с этим ID исчез из серверного инвентаря.');return end
   local beforeLevel=tonumber(pet.l)
   local bonus=0
   if type(save.Hats)=='table' and tonumber(pet.h) then
    for _,hat in pairs(save.Hats) do
     if type(hat)=='table' and tonumber(hat.id)==tonumber(pet.h) then bonus=math.max(tonumber(hat.l) or 0,0);break end
    end
   end
   local effective=beforeLevel+bonus
   local standard=effective*2-1
   -- Hard cap to ×10 and sane integer; never send enormous, negative or invalid numbers.
   local testEffective=math.max(effective,math.min(intended+bonus,effective*10,100000000000))
   local increased=testEffective*2-1
   if increased<=standard then say('Желаемый уровень не выше текущего. Введи больше '..fmt(beforeLevel)) return end
   local coin,coinErr=chooseCoin(increased*4+1000)
   if not coin then say(coinErr);return end
   lines[#lines+1]='Pet ID='..selected..' | питомец='..petName(pet)
   lines[#lines+1]='Серверный уровень ДО='..fmt(beforeLevel)..' | шляпа='..fmt(bonus)
   lines[#lines+1]='Проверяемый желаемый уровень='..fmt(intended)..' | фактически ограничен до='..fmt(testEffective-bonus)
   lines[#lines+1]='Параметры Mine: обычный='..fmt(standard)..' | увеличенный='..fmt(increased)
   lines[#lines+1]='Монета='..coin.obj.Name..' | начальное HP='..fmt(coin.health)
   say('Контроль HP монеты: 1.5 сек. Останови Auto Farm перед тестом.')
   local controlStart=hp(coin.obj)
   pause(1.5)
   local controlEnd=hp(coin.obj)
   if not controlStart or not controlEnd or controlStart~=controlEnd then
    lines[#lines+1]='ОТМЕНЕНО: HP монеты изменялось без теста / монета исчезла.'
    report=table.concat(lines,'\n');say('Монету уже добывают. Найди свободную крупную монету.');return
   end
   -- One pet movement to position; does not equip or modify the pet.
   local pos=coin.part.Position
   local moved,me=pcall(function() move:FireServer({{'PetMovement',player,selected,CFrame.new(pos),false,4.7751576900482178}}) end)
   lines[#lines+1]='PetMovement отправлен='..tostring(moved)
   if not moved then lines[#lines+1]='Ошибка движения='..tostring(me);report=table.concat(lines,'\n');say('Не удалось отправить движение');return end
   pause(.15)
   local h0=hp(coin.obj)
   if not h0 then report=table.concat(lines,'\n');say('Монета исчезла до Mine');return end
   local ok1,err1=pcall(function() mine:FireServer('Mine',coin.obj.Name,standard,selected) end)
   pause(.40)
   local h1=hp(coin.obj)
   lines[#lines+1]='Обычный Mine: pcall='..tostring(ok1)..' | HP '..fmt(h0)..' -> '..fmt(h1)..' | разница='..fmt(h1 and h0-h1)
   if not ok1 then lines[#lines+1]='Ошибка Mine: '..tostring(err1) end
   if not h1 or h1>=h0 then
    lines[#lines+1]='ОТМЕНЕНО: обычный Mine не подтвердил уменьшение HP, тест повышенного параметра пропущен.'
    report=table.concat(lines,'\n');say('Обычный урон не подтверждён. Проверь, есть ли другие скрипты.');return
   end
   local ok2,err2=pcall(function() mine:FireServer('Mine',coin.obj.Name,increased,selected) end)
   pause(.5)
   local h2=hp(coin.obj)
   lines[#lines+1]='Увеличенный Mine: pcall='..tostring(ok2)..' | HP '..fmt(h1)..' -> '..fmt(h2)..' | разница='..fmt(h2 and h1-h2)
   if not ok2 then lines[#lines+1]='Ошибка Mine: '..tostring(err2) end
   local save2,e2=readSave()
   local pet2=save2 and findPet(save2,selected)
   if pet2 then
    lines[#lines+1]='Серверный уровень ПОСЛЕ='..fmt(tonumber(pet2.l))
    lines[#lines+1]=tonumber(pet2.l)==beforeLevel and 'Уровень НЕ изменён. Проверялся только параметр урона.' or 'УРОВЕНЬ ИЗМЕНИЛСЯ! Требуется проверка после перезахода; изменение не обязательно связано с тестом.'
   else
    lines[#lines+1]='Серверный уровень после теста не удалось проверить: '..tostring(e2 or 'ID не найден')
   end
   if h2 and h1 and h2<h1 then
    lines[#lines+1]='Увеличенный Mine уменьшил HP, но это НЕ подтверждает изменение уровня питомца.'
   else
    lines[#lines+1]='Нет подтверждения урона от увеличенного параметра.'
   end
   lines[#lines+1]='Если другие игроки/скрипты били монету, измерения урона недостоверны.'
   report=table.concat(lines,'\n')
   say('Тест завершён. Нажми «Копировать отчёт».')
  end)
  if not ok then
   report='ZONEHUB LEVEL PROBE v1\nОшибка теста: '..tostring(err)
   say('Ошибка: '..tostring(err):sub(1,90))
  end
  running=false
 end)
end
button('2. ПРОБА УРОНА И ПРОВЕРКА УРОВНЯ',15,345,450,42,runTest,C.green)
local info=label(panel,'Тест отправляет ровно 2 команды Mine на одну монету. Он НЕ меняет сохранённый уровень и не трогает питомцев.',15,392,448,65,12,C.muted)
button('3. КОПИРОВАТЬ ОТЧЁТ',15,468,275,43,function()
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,report)
  say(ok and 'Отчёт скопирован — отправь в чат.' or 'Не удалось скопировать. Отчёт в консоли.')
 else say('setclipboard недоступен, отчёт отправлен в консоль.') end
 print(report)
end)
button('ЗАКРЫТЬ ×',302,468,163,43,function() gui:Destroy() end,Color3.fromRGB(105,56,77))
-- Drag by title area only (touch/mouse).
local dragging=false;local origin;local startPos
panel.InputBegan:Connect(function(input)
 if input.Position.Y>panel.AbsolutePosition.Y+59 then return end
 if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
  dragging=true;origin=input.Position;startPos=panel.Position
  local conn
  conn=input.Changed:Connect(function()
   if input.UserInputState==Enum.UserInputState.End then dragging=false;if conn then conn:Disconnect() end end
  end)
 end
end)
UIS.InputChanged:Connect(function(input)
 if not dragging or not origin then return end
 if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then
  local d=input.Position-origin
  panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
 end
end)
say('Загружен. Останови Auto Farm, затем нажми «Обновить инвентарь».')
