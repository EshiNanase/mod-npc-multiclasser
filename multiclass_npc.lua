-- ============================================================
--  МУЛЬТИКЛАСС НПС — универсальный скрипт
--  Eluna / AzerothCore / TrinityCore
-- ============================================================

local NPC_ENTRY  = 9000000
local CLASS_COST = 10000   -- 1 золото за мультикласс
local SPELL_COST = 10000   -- 1 золото за спелл
local PAGE_SIZE  = 20      -- макс спеллов на странице

-- ====== GOSSIP SENDER-КОДЫ ======
local S_MAIN = 0
-- Меню уровней:        100 + classIndex
-- Меню спеллов:        200 + classIndex
-- Кнопка "Назад":      300 + classIndex
-- Пагинация спеллов:   400 + classIndex

-- ====== КОНФИГ КЛАССОВ ======
local CLASS_CONFIG = {
    { index = 1, classId = 4, name = "Воин" },
    { index = 2, classId = 3, name = "Маг"  },
    -- { index = 3, classId = 6, name = "Жрец" },
}

-- Уровневые ступени — спеллы группируются по ближайшей ступени снизу
local LEVEL_STEPS = { 10, 20, 30, 40, 50, 60, 70, 80 }

-- ====== ЗАГРУЗКА ДАННЫХ ======

local CLASSES        = {}
local CLASS_BY_INDEX = {}

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
            print(string.format("[MulticlassNPC] ОШИБКА: не удалось загрузить %s.lua", moduleName))
            print("[MulticlassNPC] Запусти: python dbc_to_lua.py --dbc ./data/dbc/Spell.dbc --out ./lua_scripts/")
            goto continue
        end

        local spellsByLevel = {}
        local total = 0

        for _, s in ipairs(spellData.spells) do
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

        package.loaded[moduleName] = nil
        spellData = nil

        print(string.format("[MulticlassNPC] Загружено %d спеллов для класса %s", total, cfg.name))

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

-- ====== ХРАНИЛИЩЕ МУЛЬТИКЛАССОВ ======
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

-- ====== ВСПОМОГАТЕЛЬНЫЕ ======

local function SpellLink(spellId, spellName)
    return string.format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", spellId, spellName)
end

local function SpellLabel(sd, playerLevel)
    local rankSuffix = ""
    if sd.rank and sd.rank > 0 then
        rankSuffix = string.format(" (Ранг %d)", sd.rank)
    end
    local levelSuffix = ""
    if sd.reqLevel and playerLevel < sd.reqLevel then
        levelSuffix = string.format(" [требует %d ур.]", sd.reqLevel)
    end
    return string.format("%s%s%s", sd.name, rankSuffix, levelSuffix)
end

-- action = level * 100 + spellIndex  (макс 80*100+99 = 8099)
local function EncodeSpellAction(level, spellIndex)
    return level * 100 + spellIndex
end

local function DecodeSpellAction(action)
    local level      = math.floor(action / 100)
    local spellIndex = action % 100
    return level, spellIndex
end

-- action для пагинации = level * 100 + page
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

-- ====== МЕНЮ ======

local function OpenMainMenu(player, creature)
    player:GossipClearMenu()

    for _, cls in ipairs(CLASSES) do
        if not HasMulticlass(player, cls.index) then
            player:GossipMenuAddItem(
                0,
                string.format("Я хочу стать %sом", cls.name),
                S_MAIN, cls.index * 10 + 1,
                false,
                string.format("Ты получишь доступ к заклинаниям %sа", cls.name),
                CLASS_COST
            )
        else
            player:GossipMenuAddItem(
                0,
                string.format("Купить заклинания %sа", cls.name),
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
            string.format("Уровень %d", lvl),
            LevelMenuSender(cls.index), lvl,
            false, "", 0
        )
    end

    player:GossipMenuAddItem(0, "Назад", S_MAIN, 0, false, "", 0)
    player:GossipSendMenu(1, creature)
end

local function OpenSpellMenu(player, creature, cls, level, page, sendLinks)
    local spells = cls.spells[level]
    if not spells or #spells == 0 then
        player:GossipClearMenu()
        player:GossipMenuAddItem(0, "На этом уровне нет заклинаний.", LevelMenuSender(cls.index), 0, false, "", 0)
        player:GossipSendMenu(1, creature)
        return
    end

    page = page or 1
    local totalPages = math.ceil(#spells / PAGE_SIZE)
    local fromIdx    = (page - 1) * PAGE_SIZE + 1
    local toIdx      = math.min(page * PAGE_SIZE, #spells)

    if sendLinks then
        for j = fromIdx, toIdx do
            player:SendBroadcastMessage(SpellLink(spells[j].id, spells[j].name))
        end
    end

    local playerLevel = player:GetLevel()
    player:GossipClearMenu()

    for i = fromIdx, toIdx do
        local sd     = spells[i]
        local label  = SpellLabel(sd, playerLevel)
        local known  = player:HasSpell(sd.id)
        local tooLow = sd.reqLevel and (playerLevel < sd.reqLevel)
        local action = EncodeSpellAction(level, i)

        if known then
            player:GossipMenuAddItem(0, "[известно] " .. label, SpellMenuSender(cls.index), action, false, "", 0)
        elseif tooLow then
            player:GossipMenuAddItem(3, label, SpellMenuSender(cls.index), action, false, "", 0)
        else
            player:GossipMenuAddItem(
                3, label,
                SpellMenuSender(cls.index), action,
                false,
                string.format("Купить %s (Ранг %d)?", sd.name, sd.rank or 1),
                SPELL_COST
            )
        end
    end

    if page > 1 then
        player:GossipMenuAddItem(0, string.format("<< Предыдущая (%s/%d)", page, totalPages), PagingSender(cls.index), EncodePagingAction(level, page - 1), false, "", 0)
    end
    if page < totalPages then
        player:GossipMenuAddItem(0, string.format(">> Следующая (%s/%d)", page, totalPages), PagingSender(cls.index), EncodePagingAction(level, page + 1), false, "", 0)
    end

    player:GossipMenuAddItem(0, "Назад к уровням", BackToLevelsSender(cls.index), cls.index, false, "", 0)
    player:GossipSendMenu(1, creature)
end

-- ====== ОБРАБОТЧИК ВЫБОРА ======

local function OnGossipSelect(event, player, creature, sender, action)

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
            if HasMulticlass(player, cls.index) then
                player:SendBroadcastMessage("У тебя уже есть мультикласс " .. cls.name .. "а.")
                OpenMainMenu(player, creature)
                return
            end
            if (player:GetCoinage() or 0) < CLASS_COST then
                player:SendBroadcastMessage("Не хватает золота!")
                OpenMainMenu(player, creature)
                return
            end
            player:ModifyMoney(-CLASS_COST)
            SetMulticlass(player, cls.index, true)
            player:SendBroadcastMessage("Ты получил мультикласс " .. cls.name .. "а!")
            OpenMainMenu(player, creature)

        elseif subAction == 2 then
            if not HasMulticlass(player, cls.index) then
                player:SendBroadcastMessage("Сначала купи мультикласс " .. cls.name .. "а.")
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
            player:SendBroadcastMessage("Ошибка: заклинание не найдено.")
            OpenLevelMenu(player, creature, cls)
            return
        end

        if player:HasSpell(spellData.id) then
            player:SendBroadcastMessage("Ты уже знаешь " .. spellData.name .. ".")
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        local playerLevel = player:GetLevel()
        if spellData.reqLevel and playerLevel < spellData.reqLevel then
            player:SendBroadcastMessage(
                string.format("Нужно минимум %d уровня для %s.", spellData.reqLevel, spellData.name)
            )
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        if (player:GetCoinage() or 0) < SPELL_COST then
            player:SendBroadcastMessage("Не хватает золота!")
            OpenSpellMenu(player, creature, cls, level, 1, false)
            return
        end

        player:ModifyMoney(-SPELL_COST)
        player:LearnSpell(spellData.id)
        OpenSpellMenu(player, creature, cls, level, 1, false)
    end
end

-- ====== РЕГИСТРАЦИЯ ======

local _initialized = false

local function EnsureInit()
    if not _initialized then
        InitClasses()
        _initialized = true
    end
end

RegisterServerEvent(3, function()
    EnsureInit()
end)

EnsureInit()

RegisterCreatureGossipEvent(NPC_ENTRY, 1, function(event, player, creature)
    OpenMainMenu(player, creature)
end)

RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)