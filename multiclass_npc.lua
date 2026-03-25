local DEBUG = true
local ENABLE = true

local INITIALIZED = false

local NPC_ENTRY  = 133337
local CLASS_COST = 100000
local SPELL_COST = 10000
local PAGE_SIZE  = 20

local S_MAIN = 0
local CLASS_CONFIG = {
    -- { index = 1, classId = 4, name = "Warrior" },
    { index = 2, classId = 10, name = "Paladin" },
    { index = 3, classId = 9, name = "Hunter" },
    -- { index = 4, classId = 8, name = "Rogue" },
    { index = 5, classId = 6, name = "Priest" },
    { index = 6, classId = 7, name = "Druid" },
    { index = 7, classId = 11, name = "Shaman" },
    { index = 8, classId = 3, name = "Mage" },
    { index = 9, classId = 5, name = "Warlock" },
    -- { index = 10, classId = 15, name = "Death Knight" }
}
UNSUPPORTED_CLASSES = { "Warrior", "Rogue", "Death Knight" }

local LOCALE = {
    [0] = { -- enUS
        CLASS_BUY       = "I want to become a %s",
        CLASS_DESC      = "You will get access to %s spells",
        BUY_SPELLS      = "Buy %s spells",
        LEVEL           = "Level %d",
        BACK            = "Back",
        NO_SPELLS       = "No spells at this level.",
        BACK_TO_LEVELS  = "Back to levels",
        PREV_PAGE       = "<< Previous (%d/%d)",
        NEXT_PAGE       = ">> Next (%d/%d)",
        KNOWN           = "[known] %s",
        BUY_SPELL       = "Buy %s (Rank %d)?",
        NO_MONEY        = "Not enough gold!",
        ALREADY_MULTI   = "You already have multiclass %s!",
        NATIVE_CLASS    = "Can't choose your native class!",
        BUY_MULTI_FIRST = "First buy multiclass %s!",
        GOT_MULTICLASS  = "You got multiclass %s!",
        ALREADY_KNOW    = "You already know %s.",
        NEED_LEVEL      = "Need at least %d level for %s.",
        SPELL_NOT_FOUND = "Error: spell not found.",
        LEVEL_SPELLS    = "%s class spells, level %d",
        RANK_SUFFIX     = "(Rank %d)",
        LEVEL_SUFFIX    = "[requires %d level]",
        UNSUPPORTED_CLASS = "I'm not master of your class yet...",
    },
    [8] = { -- ruRU
        CLASS_BUY       = "Я хочу стать %sом",
        CLASS_DESC      = "Ты получишь доступ к заклинаниям %sа",
        BUY_SPELLS      = "Купить заклинания %sа",
        LEVEL           = "Уровень %d",
        BACK            = "Назад",
        NO_SPELLS       = "На этом уровне нет заклинаний.",
        BACK_TO_LEVELS  = "Назад к уровням",
        PREV_PAGE       = "<< Предыдущая (%d/%d)",
        NEXT_PAGE       = ">> Следующая (%d/%d)",
        KNOWN           = "[известно] %s",
        BUY_SPELL       = "Купить %s (Ранг %d)?",
        NO_MONEY        = "Не хватает золота!",
        ALREADY_MULTI   = "У тебя уже есть мультикласс %sа!",
        NATIVE_CLASS    = "Нельзя выбрать свой родной класс!",
        BUY_MULTI_FIRST = "Сначала купи мультикласс %sа!",
        GOT_MULTICLASS  = "Ты получил мультикласс %sа!",
        ALREADY_KNOW    = "Ты уже знаешь %s.",
        NEED_LEVEL      = "Нужно минимум %d уровня для %s.",
        SPELL_NOT_FOUND = "Ошибка: заклинание не найдено.",
        LEVEL_SPELLS    = "Заклинания класса %s, %d уровень",
        RANK_SUFFIX     = "(Ранг %d)",
        LEVEL_SUFFIX    = "[требует %d ур.]",
        UNSUPPORTED_CLASS = "Твой класс я пока не освоил...",   
        Warrior = "Воин",
        Paladin = "Паладин",
        Hunter = "Охотник",
        Rogue = "Разбойник",
        Priest = "Жрец",
        Druid = "Друид",
        Shaman = "Шаман",
        Mage = "Маг",
        Warlock = "Чернокнижник",
        DeathKnight = "Рыцарь смерти",
    }
}

local LEVEL_STEPS = { 10, 20, 30, 40, 50, 60, 70, 80 }

local CLASSES        = {}
local CLASS_BY_INDEX = {}

local function translate(player, key, ...)
    if DEBUG then
        print(player)
        print(key)
        print(...)
    end
    local localeId = player:GetDbLocaleIndex() or 0
    local loc = LOCALE[localeId] or LOCALE[0]
    local str = loc[key] or string.gsub(key, " ", "") or key
    return string.format(str, ...)
end

local function RoundDownToStep(lvl)
    local result = LEVEL_STEPS[1]
    for _, step in ipairs(LEVEL_STEPS) do
        if lvl >= step then result = step else break end
    end
    return result
end

local function InitClasses()
    CLASSES        = {}
    CLASS_BY_INDEX = {}

    for _, cfg in ipairs(CLASS_CONFIG) do
        local moduleName = string.format("spell_data_%d", cfg.classId)

        package.loaded[moduleName] = nil
        local ok, spellData = pcall(require, moduleName)
        if not ok or not spellData then
            goto continue
        end

        local spellsByLevel = {}
        local total = 0

        for _, s in ipairs(spellData.spells) do
            local spellInfo = GetSpellInfo(s.id)
            if spellInfo and not spellInfo:IsPassive() then
                local nameLower = string.lower(s.name)
                if not string.find(nameLower, "test") then
                    local step = RoundDownToStep(s.reqLevel)
                    if not spellsByLevel[step] then spellsByLevel[step] = {} end
                    table.insert(spellsByLevel[step], {
                        id       = s.id,
                        name     = s.name,
                        rank     = s.rank,
                        reqLevel = s.reqLevel,
                    })
                    total = total + 1
                end
            end
        end

        package.loaded[moduleName] = nil
        spellData = nil

        local cls = {
            index  = cfg.index,
            name   = cfg.name,
            spells = spellsByLevel,
        }
        table.insert(CLASSES, cls)
        CLASS_BY_INDEX[cls.index] = cls

        ::continue::
    end
end

local multiclassData = {}

local function HasMulticlass(player, classIndex)
    local g = player:GetGUIDLow()
    return multiclassData[g] and multiclassData[g][classIndex] == true
end

local function SetMulticlass(player, classIndex, value)
    local g = player:GetGUIDLow()
    if not multiclassData[g] then multiclassData[g] = {} end
    multiclassData[g][classIndex] = value and true or nil
end

local function SpellLink(player, spellId, spellName, spellRank)
    local rankMes = translate(player, "RANK_SUFFIX", spellRank)
    local spellName = string.format("%s %s", spellName, rankMes)
    return string.format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", spellId, spellName)
end

local function SpellLabel(player, spell, playerLevel)
    local rankSuffix = ""
    if spell.rank and spell.rank > 0 then
        rankSuffix = translate(player, "RANK_SUFFIX", spell.rank)
    end
    local levelSuffix = ""
    if spell.reqLevel and playerLevel < spell.reqLevel then
        levelSuffix = translate(player, "LEVEL_SUFFIX", spell.reqLevel)
    end
    return string.format("%s %s %s", spell.name, rankSuffix, levelSuffix)
end

local function EncodeSpellAction(level, spellIndex)
    return level * 100 + spellIndex
end

local function DecodeSpellAction(action)
    local level      = math.floor(action / 100)
    local spellIndex = action % 100
    return level, spellIndex
end

local function EncodePagingAction(level, page)
    return level * 100 + page
end

local function DecodePagingAction(action)
    local level = math.floor(action / 100)
    local page  = action % 100
    return level, page
end

local function LevelMenuSender(classIndex)    return 100 + classIndex end
local function SpellMenuSender(classIndex)    return 200 + classIndex end
local function BackToLevelsSender(classIndex) return 300 + classIndex end
local function PagingSender(classIndex)       return 400 + classIndex end

local function OpenMainMenu(player, creature)
    player:GossipClearMenu()

    local playerClassName = player:GetClassAsString()

    for _, cls in ipairs(CLASSES) do
        if cls.name ~= playerClassName and not HasMulticlass(player, cls.index) then
            player:GossipMenuAddItem(
                0,
                translate(player, "CLASS_BUY", translate(player, cls.name)),
                S_MAIN, cls.index * 10 + 1,
                false,
                translate(player, "CLASS_DESC", translate(player, cls.name)),
                CLASS_COST
            )
        elseif cls.name ~= playerClassName then
            player:GossipMenuAddItem(
                0,
                translate(player, "BUY_SPELLS", translate(player, cls.name)),
                S_MAIN, cls.index * 10 + 2,
                false, "", 0
            )
        end
    end

    player:GossipSendMenu(1, creature)
end

local function OpenLevelMenu(player, creature, cls)
    player:GossipClearMenu()

    local levels = {}
    for lvl, _ in pairs(cls.spells) do
        table.insert(levels, lvl)
    end
    table.sort(levels)

    for _, lvl in ipairs(levels) do
        player:GossipMenuAddItem(
            0,
            translate(player, "LEVEL", lvl),
            LevelMenuSender(cls.index), lvl,
            false, "", 0
        )
    end

    player:GossipMenuAddItem(0, translate(player, "BACK"), S_MAIN, 0, false, "", 0)
    player:GossipSendMenu(1, creature)
end

local function OpenSpellMenu(player, creature, cls, level, page, sendLinks)
    local spells = cls.spells[level]
    if not spells or #spells == 0 then
        player:GossipClearMenu()
        player:GossipMenuAddItem(0, translate(player, "NO_SPELLS"), LevelMenuSender(cls.index), 0, false, "", 0)
        player:GossipSendMenu(1, creature)
        return
    end

    page = page or 1
    local totalPages = math.ceil(#spells / PAGE_SIZE)
    local fromIdx    = (page - 1) * PAGE_SIZE + 1
    local toIdx      = math.min(page * PAGE_SIZE, #spells)

    if sendLinks then
        player:SendBroadcastMessage(translate(player, "LEVEL_SPELLS", translate(player, cls.name), level))
        for _, spell in ipairs(spells) do
            player:SendBroadcastMessage(SpellLink(player, spell.id, spell.name, spell.rank))
        end
    end

    local playerLevel = player:GetLevel()
    player:GossipClearMenu()

    for i = fromIdx, toIdx do
        local spell  = spells[i]
        local label  = SpellLabel(player, spell, playerLevel)
        local known  = player:HasSpell(spell.id)
        local tooLow = spell.reqLevel and (playerLevel < spell.reqLevel)
        local action = EncodeSpellAction(level, i)

        if known then
            player:GossipMenuAddItem(0, translate(player, "KNOWN", label), SpellMenuSender(cls.index), action, false, "", 0)
        elseif tooLow then
            player:GossipMenuAddItem(3, label, SpellMenuSender(cls.index), action, false, "", 0)
        else
            player:GossipMenuAddItem(
                3, label,
                SpellMenuSender(cls.index), action,
                false,
                translate(player, "BUY_SPELL", spell.name, spell.rank or 1),
                SPELL_COST
            )
        end
    end

    if page > 1 then
        player:GossipMenuAddItem(0, translate(player, "PREV_PAGE", page, totalPages), PagingSender(cls.index), EncodePagingAction(level, page - 1), false, "", 0)
    end
    if page < totalPages then
        player:GossipMenuAddItem(0, translate(player, "NEXT_PAGE", page, totalPages), PagingSender(cls.index), EncodePagingAction(level, page + 1), false, "", 0)
    end

    player:GossipMenuAddItem(0, translate(player, "BACK_TO_LEVELS"), BackToLevelsSender(cls.index), cls.index, false, "", 0)
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, action)

    local playerClass = player:GetClass()
    for _, class in ipairs(UNSUPPORTED_CLASSES) do
        if playerClass == class then
            player:SendBroadcastMessage(translate(player, "UNSUPPORTED_CLASS"))
            return
        end
    end


    if sender == S_MAIN then
        if action == 0 then
            OpenMainMenu(player, creature)
            return
        end

        local classIndex = math.floor(action / 10)
        local subAction  = action % 10
        local cls        = CLASS_BY_INDEX[classIndex]

        if not cls then OpenMainMenu(player, creature) return end

        if subAction == 1 then
            if cls.classId == playerClass then
                OpenMainMenu(player, creature)
                return
            end
            if HasMulticlass(player, cls.index) then
                OpenMainMenu(player, creature)
                return
            end
            if (player:GetCoinage() or 0) < CLASS_COST then
                OpenMainMenu(player, creature)
                return
            end
            player:ModifyMoney(-CLASS_COST)
            SetMulticlass(player, cls.index, true)
            player:SendBroadcastMessage(translate(player, "GOT_MULTICLASS", translate(player, cls.name)))
            OpenMainMenu(player, creature)

        elseif subAction == 2 then
            if not HasMulticlass(player, cls.index) then
                OpenMainMenu(player, creature)
                return
            end
            OpenLevelMenu(player, creature, cls)
        end

    elseif sender >= 101 and sender <= 199 then
        local cls = CLASS_BY_INDEX[sender - 100]
        if not cls then return end
        if action == 0 then
            OpenLevelMenu(player, creature, cls)
        else
            OpenSpellMenu(player, creature, cls, action, 1, true)
        end

    elseif sender >= 301 and sender <= 399 then
        local cls = CLASS_BY_INDEX[sender - 300]
        if not cls then return end
        OpenLevelMenu(player, creature, cls)

    elseif sender >= 401 and sender <= 499 then
        local cls = CLASS_BY_INDEX[sender - 400]
        if not cls then return end
        local level, page = DecodePagingAction(action)
        OpenSpellMenu(player, creature, cls, level, page, false)

    elseif sender >= 201 and sender <= 299 then
        if action == 0 then return end

        local classIndex = sender - 200
        local level, spellIndex = DecodeSpellAction(action)
        local cls = CLASS_BY_INDEX[classIndex]
        if not cls then return end

        local spells    = cls.spells[level]
        local spellData = spells and spells[spellIndex]

        if not spellData then
            OpenLevelMenu(player, creature, cls)
            return
        end

        if player:HasSpell(spellData.id) then
            player:SendBroadcastMessage(translate(player, "ALREADY_KNOW", spellData.name))
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        local playerLevel = player:GetLevel()   
        if spellData.reqLevel and playerLevel < spellData.reqLevel then
            player:SendBroadcastMessage(
                translate(player, "NEED_LEVEL", spellData.reqLevel, spellData.name)
            )
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        if (player:GetCoinage() or 0) < SPELL_COST then
            player:SendBroadcastMessage(translate(player, "NO_MONEY"))
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        player:ModifyMoney(-SPELL_COST)
        player:LearnSpell(spellData.id)
        OpenSpellMenu(player, creature, cls, level, 1, false)
    end
end

local function EnsureInit()
    if not INITIALIZED then
        InitClasses()
        INITIALIZED = true
    end
end

if ENABLE then

    RegisterServerEvent(3, function()
        EnsureInit()
    end)

    EnsureInit()

    RegisterCreatureGossipEvent(NPC_ENTRY, 1, function(event, player, creature)
        EnsureInit()
        OpenMainMenu(player, creature)
    end)

    RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)
end