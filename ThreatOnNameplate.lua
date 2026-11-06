-- ThreatOnNameplate draws its own indicator (Nameplates.lua). Older versions of this package installed the WeakAura
-- "Threat Differential on Nameplates" for the target's nameplate; it would now show a second number there, so it is
-- switched to "never load" once (nothing is deleted - re-enable it in /wa -> Load -> Never if you prefer it).
local AURA_ID = "Threat Differential on Nameplates"

local function retireOldAura()
  if type(WeakAuras) ~= "table" or not WeakAuras.GetData or not WeakAuras.Add then return end
  ThreatOnNameplateDB = type(ThreatOnNameplateDB) == "table" and ThreatOnNameplateDB or {}
  if ThreatOnNameplateDB.auraRetired then return end                 -- only once; respect a later manual re-enable
  local data = WeakAuras.GetData(AURA_ID)
  if data and not (data.load and data.load.use_never) then
    local copy = CopyTable(data)
    copy.load = copy.load or {}
    copy.load.use_never = true
    WeakAuras.Add(copy)
    print("|cff33ff99Threat On Nameplate|r: the WeakAura '" .. AURA_ID .. "' was set to 'never load' - the new -100%..+100% indicator replaces it.")
  end
  ThreatOnNameplateDB.auraRetired = true
end

local tries = 0
local function waitForWeakAuras()
  tries = tries + 1
  if type(WeakAuras) ~= "table" then return end                       -- WeakAuras not installed: nothing to do
  if WeakAuras.IsLoginFinished and WeakAuras.IsLoginFinished() then
    local ok, err = pcall(retireOldAura)
    if not ok then geterrorhandler()(err) end
  elseif tries < 120 then
    C_Timer.After(1, waitForWeakAuras)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  C_Timer.After(2, waitForWeakAuras)
end)
