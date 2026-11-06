-- Threat indicator on ALL enemy nameplates (WoW: Forever):  -100% ... 0 ... +100%
--   negative = you do NOT have aggro: -100% = no threat at all, -1% = about to pull
--   positive = you HAVE aggro:        +1% = someone is about to take it, +100% = nobody else has threat
--
-- What the Forever client allows (measured 2026-09-21):
--   * UnitDetailedThreatSituation(unit, "target")     -> readable numbers -> text = ABSOLUTE threat difference (+lead / -deficit)
--   * UnitDetailedThreatSituation(unit, "nameplateN") -> SECRET numbers: no arithmetic, no comparison, no curves for addon
--     code; they may only be handed to display widgets (SetText, StatusBar:SetValue) -> text = my threat as "% of aggro".
-- So the scale is drawn as a centred bar and the game engine does the subtraction graphically:
--   left half : full red, then covered from the far left by a dark StatusBar with value = MY % of aggro
--               -> the red that stays visible next to the centre is (100 - my%) = my deficit
--   right half: full green, then covered from the far right by one dark StatusBar per other group member / pet with
--               value = THEIR % of aggro -> overlapping covers show the maximum, the visible green is my lead
-- When I tank my % is 100 (no red); when someone else tanks their % is 100 (no green). No branching on secret values.

local BAR_WIDTH, BAR_HEIGHT = 84, 9          -- whole bar (both halves), in nameplate pixels
local GAP_TO_PLATE = 6                       -- distance between the bar and the left edge of the health bar
local COVER = { 0.10, 0.10, 0.10, 1 }        -- "empty" colour
local RED, GREEN = { 0.90, 0.15, 0.10, 1 }, { 0.15, 0.85, 0.20, 1 }
local MAX_COVERS = 45                        -- raid members + pets that can be on one threat table

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function has(v) return isSecret(v) or (v ~= nil and v ~= false) end      -- "is there a value", safe for secrets

local widgets = {}                           -- nameplate frame -> widget

-- The -100..+100 bar is optional (default: off, number only). Toggle with /tonp bar; stored in ThreatOnNameplateDB.
local function showBar()
  return type(ThreatOnNameplateDB) == "table" and ThreatOnNameplateDB.showBar == true
end

local function newCover(parent, reverse)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetAllPoints(parent)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar:SetStatusBarColor(COVER[1], COVER[2], COVER[3], COVER[4])
  bar:SetMinMaxValues(0, 100)
  bar:SetReverseFill(reverse)
  bar:SetFrameLevel(parent:GetFrameLevel() + 1)
  return bar
end

local function newHalf(holder, color, point)
  local half = CreateFrame("Frame", nil, holder)
  half:SetSize(BAR_WIDTH / 2, BAR_HEIGHT)
  half:SetPoint(point, holder, "CENTER", 0, 0)
  local fill = half:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(half)
  fill:SetColorTexture(color[1], color[2], color[3], color[4])
  return half
end

local function getWidget(plate, anchor)
  local w = widgets[plate]
  if not w then
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetSize(BAR_WIDTH, BAR_HEIGHT)
    holder:SetFrameLevel(plate:GetFrameLevel() + 20)
    holder:SetIgnoreParentAlpha(true)              -- faded (non-target / distant) plates would let the red shine through the covers
    local bar = CreateFrame("Frame", nil, holder)    -- everything graphical lives here, so the bar can be switched off
    bar:SetAllPoints(holder)
    local border = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    w = { holder = holder, bar = bar, covers = {} }
    w.left = newHalf(bar, RED, "RIGHT")              -- deficit grows from the centre to the left
    w.right = newHalf(bar, GREEN, "LEFT")            -- lead grows from the centre to the right
    w.mine = newCover(w.left, false)                 -- fills from the far left: covers MY % of aggro
    w.noAggro = newCover(w.right, true)              -- hides the whole green half while I do not have aggro
    w.noAggro:SetFrameLevel(w.right:GetFrameLevel() + 3)
    local tickFrame = CreateFrame("Frame", nil, bar)
    tickFrame:SetAllPoints(bar); tickFrame:SetFrameLevel(bar:GetFrameLevel() + 6)
    local tick = tickFrame:CreateTexture(nil, "OVERLAY")
    tick:SetSize(2, BAR_HEIGHT + 4); tick:SetPoint("CENTER"); tick:SetColorTexture(1, 1, 1, 0.9)
    local overlay = CreateFrame("Frame", nil, holder)
    overlay:SetAllPoints(holder); overlay:SetFrameLevel(holder:GetFrameLevel() + 8)
    w.text = overlay:CreateFontString(nil, "OVERLAY")
    w.text:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    widgets[plate] = w
  end
  w.holder:ClearAllPoints()
  w.holder:SetPoint("RIGHT", anchor, "LEFT", -GAP_TO_PLATE, 0)
  local withBar = showBar()
  w.bar:SetShown(withBar)
  w.text:ClearAllPoints()
  if withBar then
    w.text:SetPoint("RIGHT", w.holder, "LEFT", -4, 0)      -- number left of the bar
  else
    w.text:SetPoint("RIGHT", w.holder, "RIGHT", 0, 0)      -- number directly left of the nameplate
  end
  return w
end

local function hide(plate)
  local w = widgets[plate]
  if w then w.holder:Hide() end
end

local function anchorFrameFor(plate, token)
  if type(WeakAuras) == "table" and WeakAuras.GetUnitNameplate then
    local ok, frame = pcall(WeakAuras.GetUnitNameplate, token)      -- health bar of Blizzard / Plater / ElvUI / Kui plates
    if ok and frame then return frame end
  end
  return plate
end

-- everyone except me who can be on a threat table
local others = {}
local function refreshOthers()
  wipe(others)
  others[#others + 1] = "pet"
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do others[#others + 1] = "raid" .. i; others[#others + 1] = "raidpet" .. i end
  else
    for i = 1, GetNumSubgroupMembers() do others[#others + 1] = "party" .. i; others[#others + 1] = "partypet" .. i end
  end
end

local function tokenOf(plate)
  local token = plate.unitToken or plate.namePlateUnitToken or (plate.GetUnit and plate:GetUnit())
  if isSecret(token) or type(token) ~= "string" then return nil end
  return token
end

local function updatePlate(plate, targetPlate)
  if plate.IsForbidden and plate:IsForbidden() then return end
  local token = tokenOf(plate)
  if not token then return hide(plate) end
  -- enemy nameplates only (if the client hides the answer, the threat-table check below decides)
  if not ThreatOnNameplate_TestMode then              -- the /tonp test preview may use any nameplate (e.g. NPCs in town)
    local attackable = UnitCanAttack("player", token)
    if not isSecret(attackable) and not attackable then return hide(plate) end
    local friend = UnitIsFriend("player", token)
    if not isSecret(friend) and friend then return hide(plate) end
  end

  local isTarget = (plate == targetPlate)
  local mob = isTarget and "target" or token          -- "target" gives readable numbers, nameplate tokens give secrets

  local isTanking, _, myPct, myRawPct, myRaw = UnitDetailedThreatSituation("player", mob)
  local testOther
  if ThreatOnNameplate_TestMode then                  -- /tonp test : fake values on every visible nameplate
    local n = tonumber(token:match("%d+")) or 1
    if n % 3 == 0 then isTanking, myPct, testOther = true, 100, (n * 29) % 100          -- "I tank", someone at testOther %
      myRawPct, myRaw = 100, 2400
    elseif n % 2 == 0 then isTanking, myPct = false, UnitPower("player")                -- a SECRET number (mana)
      myRawPct, myRaw = myPct, myPct
    else isTanking, myPct = false, (n * 17) % 100
      myRawPct, myRaw = math.max(myPct, 1), math.max(myPct, 1) * 13 end
  end
  if not has(myPct) then return hide(plate) end       -- not on this unit's threat table (or friendly unit)

  local w = getWidget(plate, anchorFrameFor(plate, token))
  w.mine:SetValue(myPct)                              -- works for readable and secret numbers

  -- The threat STATUS is readable even where the numbers are secret: 2/3 = I have aggro. Without aggro the green half
  -- must stay empty even if nobody of my group is on the threat table (mob fighting someone else).
  local status = UnitThreatSituation("player", mob)
  if ThreatOnNameplate_TestMode then status = isTanking and 3 or 0 end
  if isSecret(status) or status == nil then
    w.noAggro:SetValue(0)                             -- unknown: rely on the covers alone (the tank's cover is 100%)
  else
    w.noAggro:SetValue(status >= 2 and 0 or 100)
  end

  local used, bestOtherRaw = 0, 0
  for _, unit in ipairs(others) do
    if used >= MAX_COVERS then break end
    local exists = UnitExists(unit)
    if isSecret(exists) or exists then
      local selfCheck = UnitIsUnit(unit, "player")    -- raidN can be me
      if isSecret(selfCheck) or not selfCheck then
        local _, _, pct, _, raw = UnitDetailedThreatSituation(unit, mob)
        if has(pct) then
          used = used + 1
          local cover = w.covers[used]
          if not cover then cover = newCover(w.right, true); w.covers[used] = cover end
          cover:SetValue(pct); cover:Show()
          if raw and not isSecret(raw) and raw > bestOtherRaw then bestOtherRaw = raw end
        end
      end
    end
  end
  if testOther then
    used = 1
    if not w.covers[1] then w.covers[1] = newCover(w.right, true) end
    w.covers[1]:SetValue(testOther); w.covers[1]:Show()
    bestOtherRaw = 2400 * testOther / 100
  end
  for i = used + 1, #w.covers do w.covers[i]:Hide() end

  -- TEXT
  -- target: ABSOLUTE threat difference (readable there): + = my lead over the next one, - = what I am missing to the tank.
  --         The percentage is shown by the bar only.
  -- others: my threat as % of aggro (100% = I pull / I have aggro). It is a secret number: it can be printed, but the
  --         client refuses "pct - 100", so a signed percentage is only available graphically (the bar).
  local diff
  if isTarget and myRaw and not isSecret(myRaw) and not isSecret(isTanking) then
    if isTanking then
      diff = myRaw - bestOtherRaw
    elseif myRawPct and not isSecret(myRawPct) and myRawPct > 0 then
      diff = myRaw - myRaw * 100 / myRawPct           -- tank's threat = mine / (my raw % of the tank)
    elseif bestOtherRaw > 0 then
      diff = myRaw - bestOtherRaw
    end
  end
  if diff then
    local rounded = math.floor(math.abs(diff) + 0.5)
    w.text:SetText((diff >= 0 and "+" or "-") .. (AbbreviateNumbers and AbbreviateNumbers(rounded) or tostring(rounded)))
    if isTanking then w.text:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    elseif not isSecret(myPct) and myPct >= 85 then w.text:SetTextColor(1, 0.85, 0.1)        -- close to pulling
    else w.text:SetTextColor(RED[1], RED[2], RED[3]) end
  else
    w.text:SetFormattedText("%.0f%%", myPct)          -- works for readable and secret numbers
    if isSecret(status) or status == nil then w.text:SetTextColor(1, 1, 1)
    elseif status >= 2 then w.text:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    elseif status == 1 then w.text:SetTextColor(1, 0.85, 0.1)
    else w.text:SetTextColor(RED[1], RED[2], RED[3]) end
  end
  w.text:Show()
  w.holder:Show()
end

local function hideAll()
  for _, w in pairs(widgets) do w.holder:Hide() end
end

local function updateAll()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  -- only while I am in combat (the /tonp test preview is the one exception)
  if not ThreatOnNameplate_TestMode and not InCombatLockdown() and not UnitAffectingCombat("player") then
    return hideAll()
  end
  local targetPlate = C_NamePlate.GetNamePlateForUnit("target")
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    local ok, err = pcall(updatePlate, plate, targetPlate)
    if not ok then hide(plate); geterrorhandler()(err) end
  end
end

SLASH_THREATONNAMEPLATE1 = "/tonp"
SlashCmdList["THREATONNAMEPLATE"] = function(msg)
  if (msg or ""):lower():match("test") then
    ThreatOnNameplate_TestMode = not ThreatOnNameplate_TestMode
    local n = C_NamePlate and C_NamePlate.GetNamePlates and #C_NamePlate.GetNamePlates() or 0
    print(("|cff33ff99Threat On Nameplate|r: test mode %s (%d nameplates visible)"):format(ThreatOnNameplate_TestMode and "ON" or "OFF", n))
    updateAll()
  elseif (msg or ""):lower():match("bar") then
    ThreatOnNameplateDB = type(ThreatOnNameplateDB) == "table" and ThreatOnNameplateDB or {}
    ThreatOnNameplateDB.showBar = not showBar()
    print("|cff33ff99Threat On Nameplate|r: bar " .. (ThreatOnNameplateDB.showBar and "ON (-100%..+100%, red = no aggro, green = aggro)" or "OFF (number only)"))
    updateAll()
  else
    print("|cff33ff99Threat On Nameplate|r: number left of each enemy nameplate in combat - target = threat difference in points, others = your % of aggro. /tonp bar = toggle the -100%..+100% bar, /tonp test = preview")
  end
end

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
                      "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
                      "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
  frame:RegisterEvent(ev)
end
local ticker
frame:SetScript("OnEvent", function(_, event, unit)
  if event == "NAME_PLATE_UNIT_REMOVED" then
    if unit and not isSecret(unit) then
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate then hide(plate) end
    end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
    refreshOthers()
  elseif event == "PLAYER_REGEN_DISABLED" then
    refreshOthers()
    if not ticker then ticker = C_Timer.NewTicker(0.2, updateAll) end   -- threat events are sparse; keep it fresh in combat
  elseif event == "PLAYER_REGEN_ENABLED" then
    if ticker then ticker:Cancel(); ticker = nil end
  end
  updateAll()
end)
