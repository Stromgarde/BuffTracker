require('logger')
extdata = require('extdata')

equip_slots = {'main','sub','range','ammo','head','neck','left_ear','right_ear','body','hands','left_ring','right_ring','back','waist','legs','feet'}

augment_cache = setmetatable({}, {
    __index = function(t, item)
        return type(item) == 'table' and item.id and item.extdata and rawget(t, item.id .. item.extdata) or rawget(t, item)
    end,
    __newindex = function(t, item, value)
        if not value or not value.type or not value.augments then return end
        if value.type ~= 'Augmented Equipment' then
            rawset(t, item.id .. item.extdata, false)
        else
            local augments = T(extdata_parse.augments):filter(function(a) return a ~= 'none' end)
            rawset(t, item.id .. item.extdata, augments)
        end
    end,
})

cache = {
    get_info
}

function calculate_enhancing_duration(player, spell, target, equipment, buffs)
    --local spell_info, equipment, player, buffs = get_basic_info(spell, equipment)
    if not (player or spell or target or equipment or buffs) then return end

    local composure_modifier = get_base_enhancing_composure_modifier(player, spell, target, buffs)
    local composure_count = 0

    local base_duration = spell.duration or 0
    local duration_modifier = 1
    local duration_bonus = get_enhancing_duration_bonus(spell, player, buffs)

    local augment_duration_modifier = 1
    local perpetuance_modifier = buffs.Perpetuance and 2 or 1
    local embolden_modifier = buffs.Embolden and (target.id == player.id and -0.5) or 1

    for _, slot in ipairs(equip_slots) do
        local item = windower.ffxi.get_items(equipment[slot .. '_bag'], equipment[slot])
        local modifiers = enhancing_modifiers[item.id]

        if modifiers then
            for index, value in pairs(modifiers) do
                if index == 1 then
                    duration_modifier = duration_modifier + value
                elseif index == 'augment' then
                    augment_duration_modifier = augment_duration_modifier + value
                elseif index == 'perpetuance' and buffs.Perpetuance then
                    perpetuance_modifier = perpetuance_modifier + value
                elseif index == 'embolden' and buffs.Embolden then
                    embolden_modifier = embolden_modifier + value
                elseif spell.english:startswith(index) then
                    duration_bonus = duration_bonus + value
                end
            end
        end

        if enhancing_relic_bonus[item.id] then
            duration_bonus = duration_bonus + (player.merits.enhancing_magic_duration and (player.merits.enhancing_magic_duration * 3) or 0)
        end

        if composure_gear[item.id] then
            composure_count = composure_count + 1
        end
    end

    if buffs.Composure and target.id ~= player.id then
        composure_modifier = composure_modifier + (composure_modifiers[composure_count] or 0)
    end

    -- TODO: Implement RUN Embolden. Be sure to account for Evasionist's Cape aug (variable)

    local enhancing_duration = base_duration + duration_bonus

    for _, modifier in ipairs({duration_modifier, augment_duration_modifier, perpetuance_modifier, embolden_modifier}) do
        enhancing_duration = enhancing_duration * modifier
    end

    if enhancing_duration < (60 * 30) then
        enhancing_duration = enhancing_duration * composure_modifier

        if enhancing_duration > (60 * 30) then
            enhancing_duration = 60 * 30
        end
    end

    local modifiers = {
        ["Flat Bonus"] = duration_bonus,
        ["Duration"] = duration_modifier,
        ["Augment"] = augment_duration_modifier,
        ["Composure"] = composure_modifier,
        ["Perpetuance"] = perpetuance_modifier,
        ["Embolden"] = embolden_modifier
    }

    return enhancing_duration, modifiers
end

function calculate_enfeebling_duration(player, spell, target, equipment, buffs)
    if not (player or spell or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    
    local composure_modifier = 1
    local composure_count = 0

    local saboteur_modifier = get_base_saboteur_modifier(spell, target, buffs, mob_data.NMs or L{})

    local duration_modifier = 1
    local augment_duration_modifier = 1

    local base_duration = (spell.duration or 0)

    local duration_bonus = (player.main_job == "RDM" and player.merits.enfeebling_magic_duration and (player.merits.enfeebling_magic_duration * 6) or 0)
    duration_bonus = duration_bonus + (player.job_points[player.main_job:lower()].enfeebling_magic_duration or 0)

    if buffs.Stymie then
        duration_bonus = duration_bonus + (player.job_points[player.main_job:lower()].stymie_effect or 0)
    end


    for _, slot in ipairs(equip_slots) do
        local item = windower.ffxi.get_items(equipment[slot .. '_bag'], equipment[slot])
        local modifiers = enfeebling_modifiers[item.id]

        if modifiers then
            for index, value in pairs(modifiers) do
                if index == 1 then
                    duration_modifier = duration_modifier + value
                elseif index == 'augment' then
                    augment_duration_modifier = augment_duration_modifier + value
                elseif index == 'saboteur' and buffs.saboteur then
                    saboteur_modifier = saboteur_modifier + value
                end
            end
        end

        if enfeebling_relic_bonus[item.id] then
            duration_bonus = duration_bonus + (player.merits.enfeebling_magic_duration and (player.merits.enfeebling_magic_duration * 6) or 0)
        end

        if composure_gear:contains(item.id) then
            composure_count = composure_count + 1
        end
    end
    
    composure_modifier = composure_modifier + (composure_modifiers[composure_count] or 0)
    local duration = (base_duration * saboteur_modifier) + duration_bonus

    for _, modifier in ipairs({duration_modifier, augment_duration_modifier, composure_modifier}) do
        duration = duration * modifier
    end

    duration = math.floor(duration)

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end
    )

    local modifiers = {
        ["Saboteur"] = saboteur_modifier,
        ["Flat Bonus"] = duration_bonus,
        ["Duration"] = duration_modifier,
        ["Augment"] = augment_duration_modifier,
        ["Composure"] = composure_modifier
    }

    return duration_map, modifiers
end

-- Song Calculations
-- Reference page: https://www.bg-wiki.com/ffxi/Category:Song#Song_Effect_Duration
function calculate_song_duration(player, spell, target, equipment, buffs)
    if not (player or spell or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    
    -- Troubadour is applied after all other modifiers

    local duration_bonus = 0
    local duration_modifier = 1
    local augment_duration_modifier = 1
    local troubadour_modifier = 1
    local soul_voice_modifier = 1
    local base_duration = (spell.duration or 0)
    local equipped_items = {}

    local equipped_items = fetch_equipped_items(equipment)

    -- Standard modifiers
    for _, item in ipairs(equipped_items) do
        local modifiers = song_modifiers[item.id]
        if modifiers then
            for song, index in pairs(modifiers) do
                if (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if spell.english:contains(song) then
                        duration_modifier = duration_modifier + index.value
                    elseif index == 'All Songs' or 'Increases song effect duration' then
                        duration_modifier = duration_modifier + index.value
                    end
                end
            end
        end
    end

    --Augments
    -- All Songs
    duration_modifier = duration_modifier + search_augments(equipped_items, 'All Songs'):reduce(function(total, aug) return total + ((not aug.sign or aug.sign=='+') and aug.value or (aug.value * -1)) end, 0) * 0.1

    if buffs.Nightingale and next(search_augments(equipped_items, 'Enhances "Nightingale" effect')) then
        duration_bonus = duration_bonus + (player.merits.nightingale or 0) * 4
    end

    if buffs.Troubadour then
        troubadour_modifier = 2
        duration_bonus = duration_bonus + (player.job_points.brd.troubadour_effect or 0) * 2
        if next(search_augments(equipped_items, 'Enhances "Troubadour" effect')) then
            duration_bonus = duration_bonus + (player.merits.troubadour or 0) * 4
        end
    end

    -- Job point bonus conditions:
    -- clarion_call_effect (2s/per); tenuto_effect (2s/per); lullaby_duration; marcato_effect
    if buffs["Clarion Call"] then
        duration_bonus = duration_bonus + (player.job_points.brd.clarion_call_effect or 0) * 2
    end

    -- TODO: Verify this applies only to self
    if buffs.Tenuto and target.id == player.id then
        duration_bonus = duration_bonus + (player.job_points.brd.tenuto_effect or 0) * 2
    end

    if spell.english:contains("Lullaby") then
        duration_bonus = duration_bonus + (player.job_points.brd.lullaby_duration or 0)
    end

    -- Soul Voice doubles the duration of Hymnus, Mazurka, and Scherzo, but is not compatible with Marcato.
    if spell.english:endswith("Hymnus") or spell.english:endswith("Mazurka") or spell.english:endswith("Scherzo") then
        if buffs["Soul Voice"] then
            soul_voice_modifier = 2
        elseif buffs.Marcato then
            soul_voice_modifier = 1.5
        end
    end

    -- TODO: Test to confirm if both SV and Marcato are in use that the JP duration bonus for Marcato would still apply
    if buffs.Marcato then
        duration_bonus = duration_bonus + (player.job_points.brd.marcato_effect or 0)
    end
    
    -- Flat bonuses and percentage based bonuses are both applied independently, then multiplied by Troubadour's doubling bonus. Soul voice, where applicable is multiplicative with this term.
    local duration = (base_duration * duration_modifier + duration_bonus) * troubadour_modifier * soul_voice_modifier

    duration = math.floor(duration)

    -- Applies to debuff songs, e.g. Elegy
    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    local modifiers = {
        ["Troubadour"] = troubadour_modifier,
        ["Soul Voice"] = soul_voice_modifier,
        ["Flat Bonus"] = duration_bonus,
        ["Duration"] = duration_modifier,
        ["Augment"] = augment_duration_modifier,
    }

    if spell.targets == 32 then
        return duration_map, modifiers
    else
        -- if spell.targets == 1 then
        return duration, modifiers
    end
end

-- Summoner Blood Pacts. This needs to be fired on aftercast of the pact going off!
function calculate_bp_duration(player, pact, target, equipment, buffs)
    if not (player or spell or target or equipment or buffs) then return end
    local current_time = socket.gettime()

    local duration_bonus = 0
    local duration_modifier = 1
    local base_duration = (spell.duration or 0)

    -- We don't actually care about equipment for this one since skill is pulled directly from memory

    --[[ For most abilities the duration is given by:
        base_duration + skill_over_300/100
        Known exceptions: 15 minutes: Aerial Armor, Earthen Ward,
        Perfect Defense, Reraise II, whatever Atomos does ]]
    -- TODO: Perfect Defense does not have a default duration in res/job_abilities.lua
    if (player.skills['???'] >= 300) and (pact.duration >= 60) and (pact.duration <= 180) then
        duration_bonus = duration_bonus + math.floor((player.skills['???'] - 300))
    end

    -- Astral Conduit Job Points
    if player.main_job == "SMN" and buffs['Astral Conduit'] then
        duration_bonus = duration_bonus + ((player.job_points.smn['Astral Conduit'] * 0.01) or 0)
    end

    duration = (base_duration + duration_bonus) * duration_bonus

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    local modifiers = {
        ["Flat Bonus"] = duration_bonus,
        ["Duration"] = duration_modifier,
        ["Augment"] = augment_duration_modifier,
    }

    if spell.targets == 32 then
        return duration_map, modifiers
    else
        -- if spell.targets == 1 then
        return duration, modifiers
    end
end

-- Job Ability Calculations
function calculate_ja_duration(player, ability, target, equipment, buffs)
    if not (player or ability or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    local equipped_items = fetch_equipped_items(equipment)
    local base_duration = (ability.duration or 0)
    local duration_bonus = 0
    local duration_modifier = 1

    -- Special case for Cover's formula, this will be capped in almost all cases over lv75
    -- cover_base_duration = 15 + min(max(floor((user VIT + user MND - target VIT*2)/4),0),15)
    if ability.english == 'Cover' and player.level >= 75 then
        duration_bonus = 15
    end

    -- Merit Points
    job_ability_merit_table = {
        ['Tomahawk'] = {
            trigger='Tomahawk',
            value=15,
            initial=true}, -- This is an indication to use # of points in the category -1 as a multiplier
        ['Cover Effect Length'] = {
            trigger='Cover',
            value=4,
            initial=false
        },
        ['Fealty'] = {
            trigger='Fealty',
            value=5,
            initial=true},
        ['Killer Instinct'] = {
            trigger='Killer Instinct',
            value=10,
            initial=true},
        ['Angon'] = {
            trigger='Angon',
            value=15,
            initial=true
        }
    }

    --[[ Special cases that cannot currently be addressed
    ['Invigorate'] = { -- Maybe special case
        trigger='Chakra',
        value=24
        buff='Regen'},
    ['Penance'] = {
        trigger='Chi Blast',
        value=20,
        buff='Store TP' -- Buff ID 227
        multiplier=-1},
    ]]

    local main_job_merit_pairs = {
        'WAR',S{'Tomahawk'},
        'PLD',S{'Cover','Fealty'},
        'BST',S{'Killer Instinct'},
        'DRG',S{'Angon'}
    }

    local main_job_merit_check = false
    for job, abilities in ipairs(main_job_merit_pairs) do
        if player.main_job == job and abilities:contains(ability.english) then 
            main_job_merit_check = true 
        end
    end

    if main_job_merit_check then
        for merit_title, index in pairs(job_ability_merit_table) do
            if index.trigger == ability.english and player.merits[merit_title:gsub(' ', '_'):lower()] then
                local adjustment = index.initial and 1 or 0
                duration_bonus = duration_bonus + (player.merits[merit_title:gsub(' ', '_'):lower()] - adjustment) * index.value
            end
        end
    end

    -- Thief
    -- Dark Knight
    -- Beastmaster
    -- Ranger
    -- Samurai
    -- Ninja: Keep track of shadows, buff IDs are 66 (1), 444 (2), 445 (3), and 446 (4+)
    -- Puppetmaster: Manoeuvers increase in duration by 1 second for every 3 that the puppet is deployed onto a target.
    --               Might need to just read the value from memory here.
    -- Scholar
    -- Geomancer

    -- Job Points
    job_ability_jp_table = {
        ['Cover Duration'] = {
            trigger='Cover',
            value=1
        },
        ['Sepulcher Duration'] = {
            trigger='Sepulcher  ',
            value=1
        },
        ['Souleater Duration'] = {
            trigger='Souleater',
            value=1
        },
        ['Arcane Crest Duration'] = {
            trigger='Arcane Crest',
            value=1
        },
        ['Scarlet Delirium Duration'] = {
            trigger = 'Scarlet Delirium',
            value=1
        },
        -- Bard abilities are handled in another section
        ['Run Wild Duration'] = {
            trigger='Run Wild',
            value=2
        },
        ['Shadowbind Duration'] = {
            trigger='Shadowbind',
            value=1
        },
        -- Astral Conduit is addressed in another section
        ['Hamanoha Duration'] = {
            trigger='Hamanoha',
            value=1
        },
        -- TODO: Address Ninjutsu duration +10% after 550JP spent in another section
        ['Dragon Breaker Duration'] = {
            trigger='Dragon Breaker',
            value=1
        },
        -- Blue Magic is handled in another section
        -- Bust is strange, so will skip and rely on correction logic
        --[[['Bust Duration'] = {
            trigger='Bust',
            value=10
        }
        ==]]
        -- Scholar is addressed under casting logic
        ['Dematerialize Duration'] = {
            trigger='Dematerialize',
            value=1
        },
        ['One for All Effect Duration'] = {
            trigger='One for All',
            value=1
        }
    }

    local main_job_jp_pairs = {
        'PLD',S{'Cover','Sepulcher'},
        'DRK',S{'Souleater','Arcane Crest','Scarlet Delirium'},
        'BST',S{'Run Wild'},
        'RNG',S{'Shadowbind'},
        'SAM',S{'Hamanoha'},
        'DRG',S{'Dragon Breaker'},
        'GEO',S{'Dematerialize'},
        'RUN',S{'One for All'}
    }

    local main_job_jp_check = false
    for job, abilities in ipairs(main_job_jp_pairs) do
        if player.main_job == job and abilities:contains(ability.english) then 
            main_job_jp_check = true 
        end
    end

    if main_job_jp_check then
        for jp_title, index in pairs(job_ability_jp_table) do
            if index.trigger == ability.english and player.job_points.job:lower()[jp_title:gsub(' ', '_'):lower()] then
                duration_bonus = duration_bonus + (player.job_points.job:lower()[jp_title:gsub(' ', '_'):lower()]) * index.value
            end
        end
    end

    -- Equipment

    for _, item in ipairs(equipped_items) do
        local modifiers = ja_modifiers[item.id]
        if modifiers then
            for key, index in pairs(modifiers) do
                if key:contains(ability.english) and key:contains('duration') and
                (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if index.percent == true then
                        duration_modifier = duration_modifier + index.value
                    else
                        duration_bonus = duration_bonus + index.value
                    end
                end
            end
        end
    end

    local duration = (base_duration * duration_modifier) + duration_bonus

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    if ability.targets == 32 then
        return duration_map, modifiers
    else
        -- if ability.targets == 1 then
        return duration, modifiers
    end
end

-- Corsair Roll Calculations
function calculate_roll_duration(player, ability, target, equipment, buffs)
    if not (player or ability or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    local equipped_items = fetch_equipped_items(equipment)
    local base_duration = (ability.duration or 0)
    local duration_bonus = 0
    local duration_modifier = 1

    -- Merits and Job Points
    -- Corsair
    corsair_merit_modifiers = {
        ['Winning Streak'] = { -- Special case
            trigger='Phantom Roll',
            value=20,
            initial=true}
    }

    if player.main_job == "COR" then
        for merit_title, index in pairs(corsair_merit_modifiers) do
            local adjustment = index.initial and 1 or 0
            duration_bonus = duration_bonus + (player.merits[merit_title:gsub(' ', '_'):lower()] - adjustment) * index.value
        end

        duration_bonus = duration_bonus + (player.job_points.cor.phantom_roll_effect * 2) or 0
    end

    -- Equipment
    -- Only the greatest bonus to duration from equipment is applied; it does not stack.
    local max_bonus = 0
    for _, item in ipairs(equipped_items) do
        local modifiers = ja_modifiers[item.id]
        if modifiers then -- Everything else
            for key, index in pairs(modifiers) do
                if key:contains('Phantom Roll') and key:contains('duration') and
                (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if index.percent == true then
                        duration_modifier = duration_modifier + index.value
                    else
                        if index.value > max_modifier then
                            max_bonus = index.value
                        end
                    end
                end
            end
        end
    end

    duration_bonus = duration_bonus + max_bonus

    local duration = (base_duration + duration_bonus) * duration_modifier

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    if ability.targets == 32 then
        return duration_map, modifiers
    else
        -- if ability.targets == 1 then
        return duration, modifiers
    end
end

-- Dancer
function calculate_dnc_duration(player, ability, target, equipment, buffs)
    if not (player or ability or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    local equipped_items = fetch_equipped_items(equipment)
    local base_duration = (ability.duration or 0)
    local duration_bonus = 0
    local duration_modifier = 1

    -- Merits and Job Points
    if player.main_job == "DNC" then
        if ability.type == 'Jig' then
            duration_bonus = duration_bonus + (player.job_points.dnc['Jig Duration'] or 0) * 1
        elseif ability.type == 'Samba' then
            duration_bonus = duration_bonus + (player.job_points.dnc['Samba Duration'] or 0) * 2
            -- Saber Dance
            if buffs['Saber Dance'] then
                duration_modifier = duration_modifier + (player.merits.saber_dance or 0) * 0.05
            end
        elseif ability.type == 'Step' then
            duration_bonus = duration_bonus + (player.job_points.dnc['Step Duration'] or 0) * 1
        end
    end

    -- Equipment
    for _, item in ipairs(equipped_items) do
        local modifiers = ja_modifiers[item.id]
        if modifiers then
            for key, index in pairs(modifiers) do
                if key:contains('"' .. ability.type .. '" duration') and
                (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if index.percent == true then
                        duration_modifier = duration_modifier + index.value
                    else
                        duration_bonus = duration_bonus + index.value
                    end
                end
            end
        end
    end

    -- Jig modifier cap
    if ability.type == 'Jig' then
        if (duration_modifier > 1.5) then duration_modifier = 1.5 end
    end

    local duration = (base_duration + duration_bonus) * duration_modifier

    -- Step duration cap
    local step_pairs = {
        ['Quickstep'] = 'Lethargic Daze',
        ['Box Step'] = 'Sluggish Daze',
        ['Stutter Step'] = 'Weakened Daze',
        ['Feather Step'] = 'Bewildered Daze'
    }

    if ability.type == 'Step' then
        local mob = tracked_mobs[target.id]
        if mob and mob:has_buffs() then
            for _, buff in pairs(mob.buffs) do
                if buff:get_buff_name():contains(step_pairs[ability.english]) then
                    duration = duration - 30 -- Only initial strike lasts for 60 base seconds
                    if (buff:get_remaining_duration_in_seconds() + duration) > (120 + duration_bonus) then
                        duration = 120 + duration_bonus
                    else
                        duration = buff:get_remaining_duration_in_seconds() + duration
                    end
                end
            end
        end
    end

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    if ability.targets == 32 then
        return duration_map, modifiers
    else
        -- if ability.targets == 1 then
        return duration, modifiers
    end
end

-- Rune Fencer
function calculate_run_duration(player, ability, target, equipment, buffs)
    if not (player or ability or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    local equipped_items = fetch_equipped_items(equipment)
    local base_duration = (ability.duration or 0)
    local duration_bonus = 0
    local duration_modifier = 1
    local player_buffs = nil

    local rune_buff_ids = S{523, 524, 525, 526, 527, 528, 529, 530}
    local current_runes = T(tracked_mobs[player.id].buffs:filter(function(buff) return rune_buff_ids:contains(buff:get_buff_id()) end))

    if player.main_job == 'RUN' then
        -- Merit points
        if ability.english == 'Rayke' then
            duration_bonus = duration_bonus + ((player.merits.rayke -1) * 3)
        -- Job Points
        elseif ability.english == 'Vallation' or ability.english == 'Valiance' then
            duration_bonus = duration_bonus + (player.job_points.run['Vallation Duration'] or 0)
        elseif player.job_points.run[ability.english .. ' Effect Duration'] then
            duration_bonus = (player.job_points.run[ability.english .. ' Effect Duration'] or 0)
        end
    end

    -- Consume all runes with Gambit and Rayke
    if ability.english == 'Gambit' or ability.english == 'Rayke' then
        for _, buff in pairs(current_runes) do
            if(rune_buff_ids:contains(buff:get_buff_id())) then
                tracked_mobs[player.id]:remove_buff(buff:get_buff_id(), buff:get_spell_id())
            end
        end
    end

    -- Equipment
    for _, item in ipairs(equipped_items) do
        local modifiers = run_modifiers[item.id]
        if modifiers then
            for key, index in pairs(modifiers) do
                if key:contains('"' .. ability.english .. '" duration') and
                (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if index.percent == true then
                        duration_modifier = duration_modifier + index.value
                    else
                        duration_bonus = duration_bonus + index.value
                    end
                end
            end
        end
    end


    local duration = (base_duration + duration_bonus) * duration_modifier

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    if ability.targets == 32 then
        return duration_map, modifiers
    else
        -- if ability.targets == 1 then
        return duration, modifiers
    end
end

-- Note: This covers Swipe and Lunge specifically
function effusion(player, ability)
    local rune_buff_ids = S{523, 524, 525, 526, 527, 528, 529, 530}
    local current_runes = T(tracked_mobs[player.id].buffs:filter(function(buff) return rune_buff_ids:contains(buff:get_buff_id()) end))

    if ability.english == 'Swipe' then
        -- TODO: Replace with the 'remove newest' function once implemented
        tracked_mobs[player.id]:subtract_rune_buff()
    else -- Lunge
        for _, buff in pairs(current_runes) do
            if(rune_buff_ids:contains(buff:get_buff_id())) then
                tracked_mobs[player.id]:remove_buff(buff:get_buff_id(), buff:get_spell_id())
            end
        end
    end
end

--[[ Generic stub for future calculators
function calculate_category_duration(player, ability, target, equipment, buffs)
    if not (player or ability or target or equipment or buffs) then return end
    local current_time = socket.gettime()
    local equipped_items = fetch_equipped_items(equipment)
    local base_duration = (ability.duration or 0)
    local duration_bonus = 0
    local duration_modifier = 1

    -- Merits and Job Points
    if player.main_job == "FOO" then
        player.job_points.charlie['bar']
        player.merits.alice_bob
    end

    -- Equipment
    for _, item in ipairs(equipped_items) do
        local modifiers = ja_modifiers[item.id]
        if modifiers then
            for key, index in pairs(modifiers) do
                if key:contains('"' .. ability.type .. '" duration') and
                (not index.condition) or (index.condition and conditions[index.condition](get_world_info(), buffs)) then
                    if index.percent == true then
                        duration_modifier = duration_modifier + index.value
                    else
                        duration_bonus = duration_bonus + index.value
                    end
                end
            end
        end
    end


    local duration = (base_duration + duration_bonus) * duration_modifier

    local duration_map = table.map(resist_state_modifiers,
        function(resist_multiplier)
            return math.floor(duration * resist_multiplier)
        end)

    if ability.targets == 32 then
        return duration_map, modifiers
    else
        -- if ability.targets == 1 then
        return duration, modifiers
    end
end
]]

function get_base_saboteur_modifier(spell, target, buffs, nm_table)
    local saboteur_modifier = 1

    if buffs.Saboteur then
        if nm_table:contains(target:get_name()) then
            saboteur_modifier = 1.25
        else
            saboteur_modifier = 2
        end
    end

    return saboteur_modifier
end

function get_base_enhancing_composure_modifier(player, spell, target, buffs)
    local composure_modifier = 1

    if buffs.Composure and target.id == player.id then
        composure_modifier = 3
    end

    return composure_modifier
end

function get_enhancing_duration_bonus(spell, player, buffs)
    local duration_bonus = 0

    if player.main_job == "RDM" then
        if player.merits.enhancing_magic_duration then
            duration_bonus = duration_bonus + (player.merits.enhancing_magic_duration * 6)
        end

        duration_bonus = duration_bonus + (player.job_points[player.main_job:lower()].enhancing_magic_duration or 0)
    elseif player.main_job == "SCH" then
        if spell.english:startswith("Regen") and (buffs["Light Arts"] or buffs["Addendum: White"]) then
            local light_arts_bonus = math.floor((player.main_job_level - 1) / 4) * 2

            if buffs["Tabula Rasa"] then
                light_arts_bonus = math.floor(light_arts_bonus * 1.5)
            end

            duration_bonus = duration_bonus + light_arts_bonus

            if player.job_points[player.main_job:lower()].light_arts_effect then
                duration_bonus = duration_bonus + (player.job_points[player.main_job:lower()].light_arts_effect * 3)
            end
        end
    elseif player.main_job == "WHM" then
        if spell.english:startswith("Regen") then
            if player.job_points[player.main_job:lower()].regen_duration then
                duration_bonus = duration_bonus + (player.job_points[player.main_job:lower()].regen_duration * 3)
            end
        end
    else

    end

    return duration_bonus
end

function update_gear_map()
    -- TODO: Look at inventory and update augmented gear maps
end

function get_player_buffs(player)
    player = player or windower.ffxi.get_player()
    if not player or not player.buffs then return {} end
    local buffs = T{}
    for _, buff_id in pairs(player.buffs) do
        buffs[buff_id] = (buffs[buff_id] or 0) + 1
        local buff_info = res.buffs[buff_id]
        if buff_info then
            local name = buff_info.english:lower()
            buffs[name] = (buffs[name] or 0) + 1
        end
    end
    setmetatable(buffs, {
        __index = function(t, key)
            if key and type(key) == 'string' then
                key = key:lower()
            end
            return rawget(t, key)
        end
    })
    return buffs
end

function convert_seconds_to_timer(duration)
    local hours, minutes, seconds

    hours = math.floor(duration / 3600)
    minutes = math.floor(duration % 3600 / 60)
    seconds = math.floor(duration % 60)

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)

end

function get_time_utc(time)
    if not time then
        return os.date("'!%Y-%m-%dT%H:%M:%SZ'")
    else
        return os.date("'!%Y-%m-%dT%H:%M:%SZ'", time)
    end
end

function get_time_stamp(time)
    if not time then
        return os.date("%X")
    else
        return os.date("%X", time)
    end
end

function fetch_equipped_items(equipment)
    local equipped_items = {}
    for _, slot in ipairs(equip_slots) do
        local item = item_with_metadata(windower.ffxi.get_items(equipment[slot .. '_bag'], equipment[slot]))
        table.insert(equipped_items, item)
    end
    return equipped_items
end

metadata_definition = {
    __index = function(t, index)
        if index ~= 'augments' then
            return rawget(t, index)
        else
            local augments = augment_cache[t]
            if augments == nil then
                local extdata_parse = extdata.decode(t)
                if extdata_parse and extdata_parse.type == 'Augmented Equipment' then
                    augments = T(extdata_parse.augments):filter(function(a) return a ~= 'none' end)
                end
                augment_cache[t] = augments
                rawset(t, 'augments', augments)
            end
            return augment_cache[t]
        end
    end
}

function item_with_metadata(item)
    return setmetatable(item, metadata_definition)
end

function search_augments(equipped_items, query)
    local found_augments = {}
    for _, item in ipairs(equipped_items) do
        if item.augments then
            
            for _, line in ipairs(item.augments) do
                local match, sign, value, percent = line:match('"?('..query..')"?%s*([+%-]?)([%dVI]*)(%%?)')
                if match then
                    local aug = T{match=match, sign=sign, value=value, percent=percent} --this could probably get cached somewhere too
                    table.insert(found_augments, aug)
                end
            end
        end
    end
    return(T(found_augments))
end

function unpack_equipment_inf0(equipment)
    if not equipment then return end

    local equip_info = T{}

    for _, slot in ipairs(equip_slots) do
        local item = windower.ffxi.get_items(equipment[slot .. "_bag"], equipment[slot])

        if item and item.extdata then
            local extdata_unpacked = extdata.decode(item)
            item.extdata_unpacked = extdata_unpacked.type == "Augmented Equipment" and extdata_unpacked
        end

        if item then
            
            equip_info:append({
                i = item.id,
                a = item.extdata_unpacked and table.filter(item.extdata_unpacked.augments, (function(augment) return augment ~= "none" end)) or nil
            })
        end
    end

    equipment.unpacked = equip_info

    return equipment
end