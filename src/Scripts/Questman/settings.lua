-- questman: settings page (MENU context — I.Settings registration must live here).
-- Registers the Options page, a custom "press a key" renderer, and the open-key + window-size settings.

local core = require('openmw.core')
local ui = require('openmw.ui')
local input = require('openmw.input')
local async = require('openmw.async')
local storage = require('openmw.storage')
local I = require('openmw.interfaces')

local l10n = core.l10n('Questman')

I.Settings.registerPage {
    key = 'Questman',
    l10n = 'Questman',
    name = l10n('settings_page_title'),
    description = l10n('settings_page_desc'),
}

-- Custom renderer: shows the current key and rebinds on the next key press.
I.Settings.registerRenderer('Questman/keyBinding', function(value, set)
    local name = value and input.getKeyName(value) or l10n('settings_no_key')
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textEditLine,
                        props = { text = name },
                        events = {
                            keyPress = async:callback(function(e)
                                if e.code == input.KEY.Escape then return end
                                set(e.code)
                            end),
                        },
                    },
                },
            },
        },
    }
end)

-- Reset button: clears the remembered window position so the window re-centres next time it opens.
-- (Size is the Width/Height settings; this only affects position.)
I.Settings.registerRenderer('Questman/resetWindow', function(value, set)
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = { text = l10n('settings_window_position_btn') },
                    },
                },
            },
        },
        events = {
            mouseClick = async:callback(function()
                storage.playerSection('Questman/Window'):set('pos', false)
            end),
        },
    }
end)

-- Display names for the controller-binding renderer below.
local CONTROLLER_BUTTON_NAMES = {
    [input.CONTROLLER_BUTTON.A] = 'A',   [input.CONTROLLER_BUTTON.B] = 'B',
    [input.CONTROLLER_BUTTON.X] = 'X',   [input.CONTROLLER_BUTTON.Y] = 'Y',
    [input.CONTROLLER_BUTTON.Back] = 'Back', [input.CONTROLLER_BUTTON.Start] = 'Start',
    [input.CONTROLLER_BUTTON.Guide] = 'Guide',
    [input.CONTROLLER_BUTTON.LeftShoulder] = 'LB', [input.CONTROLLER_BUTTON.RightShoulder] = 'RB',
    [input.CONTROLLER_BUTTON.LeftStick] = 'L3',     [input.CONTROLLER_BUTTON.RightStick] = 'R3',
    [input.CONTROLLER_BUTTON.DPadUp] = 'D-pad Up',     [input.CONTROLLER_BUTTON.DPadDown] = 'D-pad Down',
    [input.CONTROLLER_BUTTON.DPadLeft] = 'D-pad Left', [input.CONTROLLER_BUTTON.DPadRight] = 'D-pad Right',
}

-- "Recording" state for the controller-binding field. Controller buttons are NOT delivered to widgets
-- (no widget event like keyPress), so -- unlike the keyboard picker -- we can't capture the press inside
-- the widget. Instead, clicking the field arms `recordingButton`, and the onControllerButtonPress engine
-- handler (bottom of this file) captures the next press. Pattern studied from Diject's binding library in
-- quest-guider-lite (not copied).
local recordingButton = false
local recordingSet             -- the setting's `set` callback, captured when recording starts

-- Custom renderer: the CONTROLLER button that opens the menu -- a boxed clickable label matching the
-- keyboard picker above. Left-click arms recording; right-click clears. Unset value is -1 (button ids >= 0).
I.Settings.registerRenderer('Questman/controllerBinding', function(value, set)
    local label
    if recordingButton then
        label = l10n('settings_press_button')
    elseif type(value) == 'number' and value >= 0 then
        label = CONTROLLER_BUTTON_NAMES[value] or ('#' .. value)
    else
        label = l10n('settings_no_button')
    end
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = { text = label },
                        events = {
                            mouseRelease = async:callback(function(e)
                                if recordingButton then           -- click again to cancel a pending record
                                    recordingButton = false
                                    set(value)
                                elseif e.button == 1 then          -- left: start recording
                                    recordingButton = true
                                    recordingSet = set
                                    set(value)                     -- refresh -> shows "press a button"
                                elseif e.button == 3 then          -- right: clear the binding
                                    set(-1)
                                end
                            end),
                        },
                    },
                },
            },
        },
    }
end)

I.Settings.registerGroup {
    key = 'Settings/Questman/Options',
    page = 'Questman',
    l10n = 'Questman',
    name = l10n('settings_group_options'),
    permanentStorage = true,
    settings = {
        {
            key = 'OpenMenuKey',
            renderer = 'Questman/keyBinding',
            name = l10n('settings_open_key'),
            description = l10n('settings_open_key_desc'),
            default = input.KEY.X,
        },
        {
            key = 'OpenMenuButton',
            renderer = 'Questman/controllerBinding',
            name = l10n('settings_open_button'),
            description = l10n('settings_open_button_desc'),
            default = -1,   -- -1 = unset (controller button ids are >= 0)
        },
        {
            key = 'OverrideJournal',
            renderer = 'checkbox',
            name = l10n('settings_override_journal'),
            description = l10n('settings_override_journal_desc'),
            default = false,   -- read once at load in ui.lua (registerWindow) -> needs a restart to apply
        },
        {
            -- Quest-list icon set: Questman's bundled icons, or the SSQN mod's (read live via its
            -- I.SSQN.getQIcon interface -- no SSQN mapping is duplicated here). SSQN requires that mod
            -- installed; 'ssqn_plus' additionally asks SSQN by real id for non-vanilla add-ons, for players
            -- with SSQN's extension icon packs (see questProvider.ssqnIcon). The item values
            -- ('builtin'/'ssqn'/'ssqn_plus') are l10n keys for the select renderer's label.
            key = 'IconPack',
            renderer = 'select',
            argument = { l10n = 'Questman', items = { 'builtin', 'ssqn', 'ssqn_plus' } },
            name = l10n('settings_icon_pack'),
            description = l10n('settings_icon_pack_desc'),
            default = 'builtin',
        },
        {
            -- Off = the vanilla journal's Topics order (case-sensitive: capitalized names first). Read by
            -- questProvider.getTopics, which is rebuilt per open -> applies the next time the menu opens.
            key = 'TopicSortIgnoreCase',
            renderer = 'checkbox',
            name = l10n('settings_topic_sort_ignore_case'),
            description = l10n('settings_topic_sort_ignore_case_desc'),
            default = false,
        },
        {
            key = 'ShowTechnicalInfo',
            renderer = 'checkbox',
            name = l10n('settings_tech_info'),
            description = l10n('settings_tech_info_desc'),
            default = false,
        },
        {
            key = 'Debug',
            renderer = 'checkbox',
            name = l10n('settings_debug'),
            description = l10n('settings_debug_desc'),
            default = false,  -- off by default; flip on to print [questman] traces to the log
        },
        -- Window group (kept together): default size, the list/detail split percentages, and reset-position.
        {
            key = 'WindowWidth',
            renderer = 'number',
            name = l10n('settings_window_width'),
            description = l10n('settings_window_width_desc'),
            default = 900,
        },
        {
            key = 'WindowHeight',
            renderer = 'number',
            name = l10n('settings_window_height'),
            description = l10n('settings_window_height_desc'),
            default = 600,
        },
        {
            key = 'QuestListWidthPercent',
            renderer = 'number',
            name = l10n('settings_quest_list_width'),
            description = l10n('settings_quest_list_width_desc'),
            default = 40,   -- % of the window width used by the Quests list pane (drag the divider to change)
        },
        {
            key = 'TopicListWidthPercent',
            renderer = 'number',
            name = l10n('settings_topic_list_width'),
            description = l10n('settings_topic_list_width_desc'),
            default = 30,   -- % of the window width used by the Topics list pane
        },
        {
            key = 'ResetWindow',
            renderer = 'Questman/resetWindow',
            name = l10n('settings_window_position'),
            description = l10n('settings_window_position_desc'),
            default = false,
        },
    },
}

-- Capture a controller button for the binding field above -- only while it's recording (a field was
-- clicked). Fires in the settings (menu) context; stores the pressed button id into that setting.
return {
    engineHandlers = {
        onControllerButtonPress = function(id)
            if not recordingButton then return end
            recordingButton = false
            local s = recordingSet
            recordingSet = nil
            if s then s(id) end   -- write the button id + refresh the row
        end,
    },
}
