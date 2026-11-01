-- ZoneHub | Extra Pet Mine Probe v2.0 | Original Pet Simulator (2018)
-- Read-only inventory and coin HP; sends only PetMovement and Mine for ONE UN-EQUIPPED pet.
-- Does NOT equip, unequip, trade, merge, buy, hook __namecall or change inventory.
-- HP observations are not cryptographic proof of attribution; other players can damage a coin.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local pl=Players.LocalPlayer
local pg=pl:WaitForChild('PlayerGui')
local r=workspace:FindFirstChild('__REMOTES')
local getstats=r and r:FindFirstChild('Core') and r.Core:FindFirstChild('Get Other Stats')
local gr=r and r:FindFirstChild('Game')
local move=gr and gr:FindFirstChild('Pets')
local mine=gr and gr:FindFirstChild('Coins')
local things=workspace:FindFirstChild('__THINGS')
local coins=things and things:FindFirstChild('Coins')
local old=pg:FindFirstChild('ZoneHub_ExtraPetProbeV2')
if old then old:Destroy() end
local running=false
local report='Тест ещё не запущен'
local C={bg=Color3.fromRGB(15,21,34),panel=Color3.fromRGB(27,37,57),text=Color3.fromRGB(239,245,255),muted=Color3.fromRGB(166,185,211),accent=Color3.fromRGB(85,150,250)}
local gui=Instance.new('ScreenGui') gui.Name='ZoneHub_ExtraPetProbeV2' gui.ResetOnSpawn=false gui.DisplayOrder=9999 gui.Parent=pg
local panel=Instance.new('Frame') panel.AnchorPoint=Vector2.new(.5,.5) panel.Position=UDim2.fromScale(.5,.5) panel.Size=UDim2.fromOffset(425,400) panel.BackgroundColor3=C.bg panel.Parent=gui
Instance.new('UICorner',panel).CornerRadius=UDim.new(0,14)
local scale=Instance.new('UIScale',panel)
local cam=workspace.CurrentCamera
local screen=cam and cam.ViewportSize or Vector2.new(850,650)
scale.Scale=math.clamp(math.min(screen.X/455,screen.Y/440),.6,1)
local function label(txt,y,h,size,color)
 local l=Instance.new('TextLabel') l.BackgroundTransparency=1 l.Position=UDim2.fromOffset(15,y) l.Size=UDim2.new(1,-30,0,h) l.Font=Enum.Font.Gotham l.TextSize=size or 13 l.TextColor3=color or C.text l.Text=txt l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left l.TextYAlignment=Enum.TextYAlignment.Center l.Parent=panel return l
end
label('🐾 ZoneHub — Урон без экипировки v2',12,30,17,C.text)
label('Без трейдов, экипировки и перехвата вызовов',44,22,12,C.muted)
local state=label('Готово. Останови Auto Farm, подойди к монетам.',77,67,13,C.text)
local preview=label('Нет снимка инвентаря',148,45,12,C.muted)
local function button(text,x,y,w,callback)
 local b=Instance.new('TextButton') b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,40) b.BackgroundColor3=C.panel b.TextColor3=C.text b.Font=Enum.Font.GothamBold b.TextSize=12 b.Text=text b.Parent=panel Instance.new('UICorner',b).CornerRadius=UDim.new(0,9) b.MouseButton1Click:Connect(callback) return b
end
local logtxt=label('',248,90,11,C.muted)
local function set(s) state.Text=s;print('[ZoneHub ExtraPet] '..s) end
local function petSave()
 if not getstats or not getstats:IsA('RemoteFunction') then return nil,'Нет Get Other Stats' end
 local ok,out=pcall(function() return getstats:InvokeServer() end)
 if not ok then return nil,tostring(out) end
 local save=type(out)=='table' and type(out[pl.Name])=='table' and out[pl.Name].Save
 if type(save)~='table' or type(save.Pets)~='table' then return nil,'Сервер не вернул Save.Pets' end
 return save
end
local function pickPets(save)
 local eq,notEq={},{}
 local hats={}
 if type(save.Hats)=='table' then
  for _,h in pairs(save.Hats) do if type(h)=='table' then hats[tonumber(h.id) or -1]=tonumber(h.l) or 0 end end
 end
 for _,p in pairs(save.Pets) do
  if type(p)=='table' then
   local id,l=tonumber(p.id),tonumber(p.l)
   if id and id>0 and id%1==0 and l and l>0 then
    local bonus=hats[tonumber(p.h) or -1] or 0
    local item={id=id,level=l,hat=bonus,name=tostring(p.n or '?'),power=(l+bonus)*2-1}
    if p.e==true then eq[#eq+1]=item else notEq[#notEq+1]=item end
   end
  end
 end
 table.sort(notEq,function(a,b) return a.level>b.level or (a.level==b.level and a.id<b.id) end)
 return eq,notEq
end
local function hp(o)
 if not o or not o.Parent then return nil end
 for _,s in ipairs({'Health','HP','Hp','health'}) do
  local n=o:FindFirstChild(s,true)
  if n and (n:IsA('NumberValue') or n:IsA('IntValue')) then return n.Value end
  local attr=o:GetAttribute(s)
  if type(attr)=='number' then return attr end
 end
 return nil
end
local function part(o)
 if o:IsA('BasePart') then return o end
 if o:IsA('Model') then return o.PrimaryPart or o:FindFirstChildWhichIsA('BasePart',true) end
 return o:FindFirstChildWhichIsA('BasePart',true)
end
local function pickCoin(minHP)
 if not coins then return nil,'Нет папки монет' end
 local char=pl.Character
 local root=char and char:FindFirstChild('HumanoidRootPart')
 if not root then return nil,'Нет позиции персонажа' end
 local eligible={}
 local found,highest=0,0
 for _,c in ipairs(coins:GetChildren()) do
  local p=part(c)
  local v=hp(c)
  if p and v and v>0 and (p.Position-root.Position).Magnitude<350 then
   found+=1
   highest=math.max(highest,v)
   if v>=minHP then
    eligible[#eligible+1]={obj=c,h=v,d=(p.Position-root.Position).Magnitude,pos=p.Position}
   end
  end
 end
 table.sort(eligible,function(a,b) return a.d<b.d end)
 if #eligible==0 then
  return nil,'Нет монет с HP >= '..string.format('%.0f',minHP)..' в радиусе 350 studs. Найдено '..found..'; максимум HP '..string.format('%.0f',highest)..'. Подойди к более прочной монете.'
 end
 return eligible[1]
end
local function sample(o,duration)
 local first=hp(o)
 if not first then return nil,nil end
 task.wait(duration)
 local last=hp(o)
 return first,last
end
local function fmt(v)
 return v==nil and 'нет' or string.format('%.3f',v)
end
button('1. Обновить',15,204,190,function()
 if running then return end
 local save,err=petSave() if not save then set('Ошибка: '..err);return end
 local eq,ne=pickPets(save)
 preview.Text='Сервер: экипировано '..#eq..' | неэкипировано '..#ne..'\nКандидат: '..(ne[1] and (ne[1].id..', ур. '..ne[1].level) or 'нет')
 set('Список обновлён. Для теста сначала останови фарм и отойди от чужих игроков.')
end)
button('2. Проверить урон',220,204,190,function()
 if running then return end
 running=true
 task.spawn(function()
  local ok,err=pcall(function()
   if not move or not move:IsA('RemoteEvent') or not mine or not mine:IsA('RemoteEvent') then
    set('Не найдены серверные события Pets/Coins');return
   end
   local save,saveErr=petSave() if not save then set('Ошибка инвентаря: '..saveErr);return end
   local eq,ne=pickPets(save)
   if #ne==0 then set('В инвентаре нет неэкипированного питомца');return end
   local p=ne[1]
   -- On a small coin disappearance is inconclusive. Require >= 3 expected Mine arguments.
   local threshold=math.max(1000,p.power*3)
   local coin,coinErr=pickCoin(threshold)
   if not coin then
    report='ZoneHub ExtraPet MineProbe v2 | НЕТ ПОДХОДЯЩЕЙ МОНЕТЫ\n'..coinErr..'\nКандидат ID '..p.id..', мощность '..fmt(p.power)
    set(coinErr);return
   end
   preview.Text='Экипировано: '..#eq..' | свободно: '..#ne..'\nID '..p.id..' | Монета '..coin.obj.Name
   set('Контроль 2 сек. Не бей монету и останови другие скрипты.')
   local baseStart,baseEnd=sample(coin.obj,2)
   if not baseStart or not baseEnd then
    report='ZoneHub ExtraPet MineProbe v2 | КОНТРОЛЬ НЕ ПРОЙДЕН\nМонета исчезла до отправки команд.'
    set('Монета исчезла во время контроля, повтори тест');return
   end
   if baseStart~=baseEnd then
    report='ZoneHub ExtraPet MineProbe v2 | КОНТРОЛЬ НЕ ПРОЙДЕН\nМонета: '..coin.obj.Name..'\nHP: '..fmt(baseStart)..' -> '..fmt(baseEnd)..'\nHP менялся без наших команд.'
    set('HP меняется без теста. Перейди в пустое место.');return
   end
   local initial=hp(coin.obj)
   local moved=pcall(function() move:FireServer({{'PetMovement',pl,p.id,CFrame.new(coin.pos),false,4.7751576900482178}}) end)
   if not moved then set('PetMovement не был отправлен');return end
   task.wait(.10)
   local mineCalls=0
   local readings={}
   local sawDecrease=false
   local disappeared=false
   for i=1,3 do
    if not coin.obj.Parent then disappeared=true;break end
    local before=hp(coin.obj)
    local sent=pcall(function() mine:FireServer('Mine',coin.obj.Name,p.power,p.id) end)
    if sent then mineCalls+=1 end
    task.wait(.30)
    local after=hp(coin.obj)
    readings[#readings+1]='Mine '..i..': '..fmt(before)..' -> '..fmt(after)
    if after and before and after<before then sawDecrease=true;break end
    if not after then disappeared=true;break end
    task.wait(.18)
   end
   local final=hp(coin.obj)
   local saveAfter=petSave()
   local eqAfter=saveAfter and select(1,pickPets(saveAfter)) or nil
   local inEquipped=false
   if eqAfter then for _,e in ipairs(eqAfter) do if e.id==p.id then inEquipped=true;break end end end
   local verdict
   if inEquipped then verdict='НЕКОРРЕКТНО: кандидат стал экипированным'
   elseif sawDecrease then verdict='HP УМЕНЬШИЛСЯ ПОСЛЕ MINE: сильный признак работы неэкипированного питомца (не абсолютное доказательство)'
   elseif disappeared then verdict='Монета исчезла: источник урона не установлен'
   else verdict='HP не уменьшился; урон не подтверждён' end
   report=table.concat({
    'ZoneHub ExtraPet MineProbe v2 | ОТЧЁТ',
    'До: экипировано '..#eq..'; неэкипировано '..#ne,
    'ID кандидата: '..p.id..'; уровень '..p.level..'; шляпа +'..p.hat,
    'Остался неэкипирован: '..tostring(not inEquipped),
    'Монета: '..coin.obj.Name,
    'Требуемый HP >= '..fmt(threshold),
    'Контроль HP: '..fmt(baseStart)..' -> '..fmt(baseEnd),
    'Тест HP: '..fmt(initial)..' -> '..fmt(final),
    table.concat(readings,' | '),
    'Число Mine: '..mineCalls..'/3; аргумент '..fmt(p.power),
    'Результат: '..verdict,
    'FireServer не подтверждает приём команды сервером.'},'\n')
   logtxt.Text='Монета '..coin.obj.Name..'\nHP: '..fmt(initial)..' -> '..fmt(final)..'\nMine: '..mineCalls..'/3'
   set(verdict)
  end)
  if not ok then set('Ошибка теста: '..tostring(err));report='Ошибка: '..tostring(err) end
  running=false
 end)
end)
button('Скопировать отчёт',15,349,395,function()
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,report)
  set(ok and 'Отчёт скопирован. Пришли сюда.' or 'Ошибка копирования. Отчёт в консоли Delta.')
 else
  set('Нет setclipboard. Отчёт напечатан в консоли Delta.')
 end
 print(report)
end)
local dragging,startPos,startInput
panel.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;startPos=panel.Position;startInput=input.Position end
end)
UIS.InputChanged:Connect(function(input)
 if dragging and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
  local d=input.Position-startInput
  panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
 end
end)
UIS.InputEnded:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
print('[ZoneHub ExtraPet] No hooks, equip, trade or inventory writes. Ready.')
