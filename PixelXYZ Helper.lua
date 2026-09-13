script_name('Pixel XYZ Helper')
script_author('Nikita Valeyev')
script_version('1.0.0')

-- =========================
-- Подключаемые библиотеки
-- =========================
local imgui = require 'mimgui'
local encoding = require 'encoding'
local json = require 'dkjson'
local render = require 'lib.render'
local inicfg = require 'inicfg'
local lfs = require 'lfs'
local ffi = require "ffi"

-- Для воспроизведения звуков, аудио
ffi.cdef[[
    int PlaySoundA(const char *pszSound, void* hmod, unsigned int fdwSound);
]]

local winmm = ffi.load("winmm")
local SND_ASYNC = 0x0001
local SND_FILENAME = 0x00020000

require 'lib.moonloader'
require 'lib.sampfuncs'
require 'vkeys'
local sampev = require 'lib.samp.events'

encoding.default = 'CP1251'
u8 = encoding.UTF8

-- Переменные автора и даты
local authorName = "Nikita Valeyev"
local lastdateUpdate = "13.09.2026"
local nickname = "Unknown"

-- Окна и состояния
local window = {
    mainMenu = imgui.new.bool(false),
	catSettings = imgui.new.bool(false),
	lastXyz = imgui.new.bool(false)
}

-- Анимации
local Animation = {
    alphas = {},
    speed = 1.5
}

function Animation.getAlpha(windowName, isVisible)
    if Animation.alphas[windowName] == nil then
        Animation.alphas[windowName] = 0.0
    end

    local currentAlpha = Animation.alphas[windowName]
    local deltaTime = imgui.GetIO().DeltaTime

    if isVisible then
        if currentAlpha < 1.0 then
            currentAlpha = math.min(currentAlpha + deltaTime * Animation.speed, 1.0)
        end
    else
        currentAlpha = 0.0
    end
    
    Animation.alphas[windowName] = currentAlpha
    return currentAlpha
end

-- Иконки
local Icons = {
    logo = nil,
    notfound = nil,
	settings = nil,
	copy = nil,
    delete = nil
}

-- Переменные функций окна
local current_tab = 1 -- 1: Список, 2: Сохранить, 3: Настройки, 4: Поддержка
local selected_category_idx = imgui.new.int(0)
local input_coord_name = imgui.new.char[128]("")
local categories = {"Основной"}
local input_new_category = imgui.new.char[128]("")
local saved_coordinates = {} -- Хранилище загруженных данных

-- Хранилище сессионных координат и состояние разблокировки
local last_coordinates = {}
local is_unlocked = imgui.new.bool(false)

-- Переменные оверлея уведомлений
local ovlPushM = {
    -- Состояние и данные
    active = false,
    text = "",
    timer = 0,
    duration = 9999,
    alpha = 0,
	
	queue = {}, -- Очередь уведомлений
	
	-- Шрифты, размеры и цвета
    fontSize = 14,
    font = renderCreateFont('Arial', 14, 5),
    
    colors = {
        default = 0xFFFFFFFF,
        yellow  = 0xFFFFD200
    },
	
	-- Конфигурация типов (звуки, акцентные цвета и т.д.)
    types = {
        success = {
            sound = getWorkingDirectory() .. "\\config\\pixel_xyzhelper\\sound\\success.wav",
            accentColor = 0xFF2ECC71 -- Зеленый
        },
        warning = {
            sound = getWorkingDirectory() .. "\\config\\pixel_xyzhelper\\sound\\warning.wav",
            accentColor = 0xFFF1C40F -- Желтый
        },
        error = {
            sound = getWorkingDirectory() .. "\\config\\pixel_xyzhelper\\sound\\error.wav",
            accentColor = 0xE74C3C -- Красный
        },
        info = {
            sound = nil,
            accentColor = 0xFF3498DB -- Синий
        }
    },
	
    -- Режим редактирования позиции
    editPos = false,
    isDragging = false,
    dragOffset = { x = 0, y = 0 },
	
	-- Расположение и размеры
    pos = { x = 20, y = 20 },
    padding = 10,
    radius = 12
}

-- Переменные оверлея координат (/currentxyz)
local ovlXyz = {
    -- Текстовые наименования и соответствие размерам шрифта
    fontSizes = { "Маленький", "Средний", "Большой" },
    fontSizeValues = { 9, 11, 14 }, -- Пиксельные размеры под каждые типы
    fontSizeIndex = imgui.new.int(1), -- Индекс по умолчанию (1 = "Средний", 0-индексация)

    font = renderCreateFont('Arial', 11, 5),

    -- Режим редактирования позиции
    editPos = false,
    isDragging = false,
    dragOffset = { x = 0, y = 0 },

    -- Цветовая палитра
    colors = {
        bgDefault  = 0x99000000, -- Тёмный полупрозрачный фон
        title      = 0xFFFFD200, -- Золотистый заголовок "XYZ:"
        coords     = 0xFFFFFFFF, -- Белый цвет самих координат
        editBorder = 0xAAFF4444  -- Красная рамка при редактировании
    }
}

-- Переменные настроек
local settings = {
    hotkeys = {
        mainMenu = 0x71, -- F2 по умолчанию
    },
	overlayPushM = true,
	overlayPushMSound = true,
	overlayPushMPos = { x = 20, y = 20 },
	overlayXyz = true,
    overlayXyzBackground = false,
    overlayXyzPos = { x = 20, y = 400 },
    overlayXyzFontSize = 11
}

-- Пустышки для настроек в imgui оверлеи
local overlayPushM = imgui.new.bool()
local overlayPushMSound = imgui.new.bool()
local overlayXyz = imgui.new.bool()
local overlayXyzBackground = imgui.new.bool()

-- =========================
-- UI стили
-- =========================
imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    
    style.WindowRounding    = 12.0
    style.FrameRounding     = 10.0
    style.ChildRounding     = 10.0
    style.GrabRounding      = 10.0
    style.PopupRounding     = 10.0
    style.ScrollbarRounding = 8.0
    style.WindowPadding     = imgui.ImVec2(12, 12)
    style.ItemSpacing       = imgui.ImVec2(8, 6)
    style.FramePadding      = imgui.ImVec2(10, 8)
    
    local titleBgColor = imgui.ImVec4(0.07, 0.07, 0.08, 0.96) -- цвет шапки
    
	-- Иконки, изображения
    Icons.logo = imgui.CreateTextureFromFile("moonloader\\config\\pixel_xyzhelper\\img\\pxyz_logo.png")
    Icons.notfound = imgui.CreateTextureFromFile("moonloader\\config\\pixel_xyzhelper\\img\\notfound.png")
	Icons.settings = imgui.CreateTextureFromFile("moonloader\\config\\pixel_xyzhelper\\img\\settings.png")
	Icons.copy = imgui.CreateTextureFromFile("moonloader\\config\\pixel_xyzhelper\\img\\copy.png")
    Icons.delete = imgui.CreateTextureFromFile("moonloader\\config\\pixel_xyzhelper\\img\\delete.png")

    style.Colors[imgui.Col.WindowBg]           = titleBgColor
    style.Colors[imgui.Col.TitleBg]            = titleBgColor
    style.Colors[imgui.Col.TitleBgActive]      = titleBgColor
    style.Colors[imgui.Col.TitleBgCollapsed]   = titleBgColor
end)

-- ===================================
-- Функция ввода и форматирования
-- ===================================

-- UI стили для текста
local textColor = imgui.ImVec4(1, 1, 1, 1)
local gray1 = imgui.ImVec4(0.75, 0.75, 0.75, 1.0)
local green1 = imgui.ImVec4(0.35, 1.0, 0.35, 1.0)
local red1 = imgui.ImVec4(1.0, 0.35, 0.35, 1.0)
local yellow1 = imgui.ImVec4(1.0, 0.85, 0.25, 1.0)
local pink1 = imgui.ImVec4(1.0, 0.41, 0.71, 1.0)
local cyan1     = imgui.ImVec4(0.35, 0.75, 1.00, 1.0)
local purple1   = imgui.ImVec4(0.70, 0.40, 0.95, 1.0)

-- Преобразование кода клавиши в понятное название
local function keyToName(key)
    if not key or type(key) ~= "number" or key == 0 then return "Не выбрано" end
    
    local names = {
        [0x01] = "LMB", [0x02] = "RMB", [0x04] = "MMB",
        [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter",
        [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt",
        [0x13] = "Pause", [0x14] = "CapsLock", [0x1B] = "Esc", [0x20] = "Space",
        [0x21] = "PageUp", [0x22] = "PageDown", [0x23] = "End", [0x24] = "Home",
        [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
        [0x2C] = "PrintScreen", [0x2D] = "Insert", [0x2E] = "Delete", [0x91] = "ScrollLock",
        [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5",
        [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
    }

    if key >= 0x41 and key <= 0x5A then return string.char(key) end -- A-Z
    if key >= 0x30 and key <= 0x39 then return string.char(key) end -- 0-9
    if key >= 0x60 and key <= 0x69 then return "Num " .. tostring(key - 0x60) end -- NumPad

    if names[key] then return names[key] end
    return "VK_" .. tostring(key)
end

-- Кнопки
local function ButtonWithStyle(label, width, height, colorNormal, colorHovered, colorActive)
    imgui.PushStyleColor(imgui.Col.Button, colorNormal)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, colorHovered)
    imgui.PushStyleColor(imgui.Col.ButtonActive, colorActive)

    local clicked = imgui.Button(label, imgui.ImVec2(width, height))

    imgui.PopStyleColor(3)
    return clicked
end

-- Выпадающий список
local dropdownState = {}
function StyledDropdown(id, label, items, currentIndex, width)
    if not items or #items == 0 then return false end
    
    width = width or 140
    dropdownState[id] = dropdownState[id] or false
    local opened = dropdownState[id]

    local changed = false
    local buttonHeight = 26
    local io = imgui.GetIO()
    local mouseX, mouseY = io.MousePos.x, io.MousePos.y

    if label ~= "" then
        imgui.TextColored(textColor, label)
        imgui.SameLine()
    end

    local min = imgui.GetCursorScreenPos()
    local max = imgui.ImVec2(min.x + width, min.y + buttonHeight)
    imgui.Dummy(imgui.ImVec2(width, buttonHeight))
    
    local hovered = mouseX >= min.x and mouseX <= max.x and mouseY >= min.y and mouseY <= max.y
    local draw = imgui.GetWindowDrawList()
    local bgColor = hovered and imgui.ImVec4(0.15, 0.15, 0.16, 1.0) or imgui.ImVec4(0.10, 0.10, 0.12, 1.0)

    draw:AddRectFilled(min, max, imgui.ColorConvertFloat4ToU32(bgColor), 6)
    
    local currentText = u8(tostring(items[currentIndex[0] + 1] or "Выберите..."))
    local textPos = imgui.ImVec2(min.x + 8, min.y + (buttonHeight - imgui.GetTextLineHeight()) / 2)
    draw:AddText(textPos, imgui.ColorConvertFloat4ToU32(textColor), currentText)

    local arrowSize = 6
    local arrowCenterX = max.x - 15
    local arrowCenterY = min.y + buttonHeight / 2
    local arrowColor = imgui.ColorConvertFloat4ToU32(gray1)

    if opened then
        draw:AddTriangleFilled(
            imgui.ImVec2(arrowCenterX - arrowSize, arrowCenterY + arrowSize/2),
            imgui.ImVec2(arrowCenterX + arrowSize, arrowCenterY + arrowSize/2),
            imgui.ImVec2(arrowCenterX, arrowCenterY - arrowSize/2),
            arrowColor
        )
    else
        draw:AddTriangleFilled(
            imgui.ImVec2(arrowCenterX - arrowSize, arrowCenterY - arrowSize/2),
            imgui.ImVec2(arrowCenterX + arrowSize, arrowCenterY - arrowSize/2),
            imgui.ImVec2(arrowCenterX, arrowCenterY + arrowSize/2),
            arrowColor
        )
    end

    if hovered and imgui.IsMouseClicked(0) then
        dropdownState[id] = not opened
    end

    if opened then
        local foreDraw = imgui.GetForegroundDrawList()
        local listMin = imgui.ImVec2(min.x, max.y + 2)
        local listMax = imgui.ImVec2(min.x + width, max.y + 2 + #items * 24)
        
        foreDraw:AddRectFilled(listMin, listMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.07, 0.07, 0.08, 0.98)), 8)
        foreDraw:AddRect(listMin, listMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.20, 0.20, 0.22, 1.0)), 8)

        for i, value in ipairs(items) do
            local itemMin = imgui.ImVec2(listMin.x + 2, listMin.y + (i-1)*24 + 2)
            local itemMax = imgui.ImVec2(listMax.x - 2, listMin.y + i*24)
            local itemHovered = mouseX >= itemMin.x and mouseX <= itemMax.x and mouseY >= itemMin.y and mouseY <= itemMax.y
            
            local valText = u8(tostring(value or ""))

            if itemHovered then
                foreDraw:AddRectFilled(itemMin, itemMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.88, 0.11, 0.28, 0.8)), 6)
                if imgui.IsMouseClicked(0) then
                    currentIndex[0] = i - 1
                    dropdownState[id] = false
                    changed = true
                end
            end
            foreDraw:AddText(imgui.ImVec2(itemMin.x + 8, itemMin.y + 4), imgui.ColorConvertFloat4ToU32(textColor), valText)
        end

        if imgui.IsMouseClicked(0) and not hovered and not (mouseX >= listMin.x and mouseX <= listMax.x and mouseY >= listMin.y and mouseY <= listMax.y) then
            dropdownState[id] = false
        end
    end

    return changed
end

-- Переключатель / Тоггл / Чекбокс (Кастомный стиль)
-- Хранение состояния анимации кружка для каждого тоггла (относительная позиция: 0 = выключено, 1 = включено)
local toggleAnimationProgress = {}
function ToggleSwitch(id, state)
    local drawList = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()

    local height = 22
    local width = height * 1.8
    local radius = height * 0.5

    -- Цвет фона
    local bgColor = state[0]
        and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.2, 0.4, 1.0, 1.0))
        or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.2, 0.2, 1.0))

    local knobColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 1))

    -- Инициализация анимации
    if toggleAnimationProgress[id] == nil then
        toggleAnimationProgress[id] = state[0] and 1 or 0
    end

    -- Анимация
    local target = state[0] and 1 or 0
    toggleAnimationProgress[id] =
        toggleAnimationProgress[id] + (target - toggleAnimationProgress[id]) * 0.2

    -- Рисование
    drawList:AddRectFilled(pos, imgui.ImVec2(pos.x + width, pos.y + height), bgColor, radius)

    local knobX = pos.x + radius + toggleAnimationProgress[id] * (width - 2 * radius)
    drawList:AddCircleFilled(imgui.ImVec2(knobX, pos.y + radius), radius - 1, knobColor)

    -- КНОПКА (ID - КРИТИЧЕСКИ ВАЖНО)
    imgui.InvisibleButton("##" .. id, imgui.ImVec2(width, height))

    if imgui.IsItemClicked() then
        state[0] = not state[0]
        return true
    end

    return false
end

-- Поле для ввода
function InputCustom(width, drawFunc, isError)
    local col_normal   = imgui.ImVec4(0.10, 0.10, 0.12, 1.0)
    local col_hovered  = imgui.ImVec4(0.15, 0.15, 0.16, 1.0)
    local col_active   = imgui.ImVec4(0.18, 0.18, 0.20, 1.0)
    local col_border   = imgui.ImVec4(0.25, 0.25, 0.28, 1.0)

    local err_bg      = imgui.ImVec4(70/255, 20/255, 20/255, 1.0)
    local err_hover   = imgui.ImVec4(100/255, 30/255, 30/255, 1.0)
    local err_active  = imgui.ImVec4(85/255, 25/255, 25/255, 1.0)
    local err_border  = imgui.ImVec4(160/255, 60/255, 60/255, 1.0)

    if isError then
        imgui.PushStyleColor(imgui.Col.FrameBg, err_bg)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, err_hover)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, err_active)
        imgui.PushStyleColor(imgui.Col.Border, err_border)
    else
        imgui.PushStyleColor(imgui.Col.FrameBg, col_normal)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, col_hovered)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, col_active)
        imgui.PushStyleColor(imgui.Col.Border, col_border)
    end

    if width then
        imgui.SetNextItemWidth(width)
    end

    drawFunc()

    imgui.PopStyleColor(4)
end

-- Поле ввода 2: для буфера последних координат
function InputLastXYZ(width, height, drawFunc, isLocked)
    local col_lock_bg     = imgui.ImVec4(0.12, 0.12, 0.14, 1.0)
    local col_lock_border = imgui.ImVec4(0.20, 0.20, 0.24, 1.0)
    local col_normal   = imgui.ImVec4(0.08, 0.08, 0.10, 1.0)
    local col_hovered  = imgui.ImVec4(0.12, 0.12, 0.14, 1.0)
    local col_active   = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
    local col_border   = imgui.ImVec4(0.88, 0.11, 0.28, 0.6)

    if isLocked then
        imgui.PushStyleColor(imgui.Col.FrameBg, col_lock_bg)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, col_lock_bg)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, col_lock_bg)
        imgui.PushStyleColor(imgui.Col.Border, col_lock_border)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.6, 0.6, 0.65, 1.0))
    else
        imgui.PushStyleColor(imgui.Col.FrameBg, col_normal)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, col_hovered)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, col_active)
        imgui.PushStyleColor(imgui.Col.Border, col_border)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
    end

    if width then
        imgui.SetNextItemWidth(width)
    end

    local startPos = imgui.GetCursorScreenPos()

    -- 1. Если заблокировано, сначала ставим прозрачный щит
    if isLocked then
        imgui.InvisibleButton("##lock_shield", imgui.ImVec2(width or 404, height or 150))
        imgui.SetCursorScreenPos(startPos)
    end

    -- 2. Отрисовываем само поле
    drawFunc()

    imgui.PopStyleColor(5)
end

-- Кнопка для назначения/перезначения клавиш
local function drawKeyInput(target, tooltip)
    tooltip = tooltip or "Нажмите для смены клавиши"
    local BTN_WIDTH  = 110
    local BTN_HEIGHT = 26
    
    local currentKey = settings.hotkeys[target] or 0
    local keyName = keyToName(currentKey)
    
    local names = {
        mainMenu = "Главное окно",
    }
    local displayName = names[target] or target

    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.88, 0.11, 0.28, 0.8))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.24, 0.36, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.74, 0.07, 0.23, 1.0))

    if imgui.Button(u8(keyName .. "##" .. target), imgui.ImVec2(BTN_WIDTH, BTN_HEIGHT)) then
        waitingKeyInputType = target
        ovlPushM.show("Назначить клавишу для: " .. displayName, 60)
    end

    imgui.PopStyleColor(3)
    if imgui.IsItemHovered() then 
        imgui.SetTooltip(u8(tooltip)) 
    end
end

-- Тоггл для переключения состояния актив/неактив
function CustomToggle(str_id, bool_ptr)
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    
    local height = 18.0
    local width = 34.0
    local radius = height * 0.5
    
    imgui.InvisibleButton(str_id, imgui.ImVec2(width, height))
    local clicked = imgui.IsItemClicked()
    if clicked then
        bool_ptr[0] = not bool_ptr[0]
    end

    local t = bool_ptr[0] and 1.0 or 0.0
    
    -- Цвета состояния (Активный / Неактивный)
    local col_bg_border = bool_ptr[0] and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.88, 0.11, 0.28, 1.0)) or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.35, 0.20, 0.40, 0.6))
    local col_bg_fill   = bool_ptr[0] and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.40, 0.10, 0.25, 0.8)) or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.12, 0.10, 0.15, 1.0))
    local col_circle    = bool_ptr[0] and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.00, 0.41, 0.71, 1.0)) or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.45, 0.40, 0.50, 1.0))

    -- Отрисовка рамки и фона
    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + width, p.y + height), col_bg_fill, radius)
    draw_list:AddRect(p, imgui.ImVec2(p.x + width, p.y + height), col_bg_border, radius, 0, 1.5)

    -- Отрисовка ползунка (шарика)
    local circle_x = p.x + radius + t * (width - radius * 2.0)
    draw_list:AddCircleFilled(imgui.ImVec2(circle_x, p.y + radius), radius - 2.5, col_circle)

    return clicked
end

-- =========================
-- Функции работы с файлами
-- =========================

-- Создание папки
local function getFolderPCH()
    local folder = "moonloader/config/pixel_xyzhelper"
    if not lfs.attributes(folder) then
        lfs.mkdir(folder)
    end
    return folder
end

local function getSettingsPath()
    return getFolderPCH() .. "/" .. nickname .. "_settings.json"
end

-- Создание файла координат
local function getCoordinatPath()
    return getFolderPCH().."/"..nickname.."_coordinates.json"
end

-- Сохранение настроек
local function saveSettings()
    local path = getSettingsPath()
    local file = io.open(path, "w")
    if file then
        file:write(json.encode(settings, { indent = true }))
        file:close()
    end
end

-- Загрузка настроек
local function loadSettings()
    local path = getSettingsPath()
    local file = io.open(path, "r")

    if file then
        local content = file:read("*a")
        file:close()

        local data = json.decode(content)
        if type(data) == "table" then
            settings = data
        end
    else
        saveSettings()
    end
    
    settings.hotkeys = settings.hotkeys or {}
    settings.hotkeys.mainMenu = settings.hotkeys.mainMenu or 0x71
	
	overlayPushM[0] = (settings.overlayPushM ~= false)
	overlayPushMSound[0] = (settings.overlayPushMSound ~= false)
	settings.overlayPushMPos = settings.overlayPushMPos or { x = 20, y = 20 }
	
	overlayXyz[0] = (settings.overlayXyz ~= false)
	overlayXyzBackground[0] = (settings.overlayXyzBackground == true)

	settings.overlayXyzPos = settings.overlayXyzPos or { x = 20, y = 400 }
	settings.overlayXyzFontSize = settings.overlayXyzFontSize or 11
	
	-- Выставляем правильный индекс для Dropdown (Маленький / Средний / Большой)
	for i, v in ipairs(ovlXyz.fontSizeValues) do
		if v == settings.overlayXyzFontSize then
			ovlXyz.fontSizeIndex[0] = i - 1
			break
		end
	end
	ovlXyz.font = renderCreateFont('Arial', settings.overlayXyzFontSize, 5)
end

-- Сброс настроек
local function resetSettings()
    settings = {
		-- Все горячие клавиши
        hotkeys = {
            mainMenu = 0x71,
        },
		overlayPushM = true,
		overlayPushMSound = true,
		overlayPushMPos = { x = 20, y = 20 },
		overlayXyz = true,
		overlayXyzBackground = false,
		overlayXyzFontSize = 11,
		overlayXyzPos = { x = 20, y = 400 },
    }
	-- синхронизация imgui-переменных
	overlayPushM[0] = true
	overlayPushM[0] = true
	overlayXyz[0] = true
	overlayXyzBackground[0] = false
	
	-- пересоздаём шрифты оверлеев
	ovlXyz.fontSizeIndex[0] = 1 -- Средний
	ovlXyz.font = renderCreateFont('Arial', 11, 5)

	-- Режим редактирования (перемещения оверлеев)
	ovlPushM.editPos = false
	ovlPushM.isDragging = false
	
	ovlXyz.editPos = false
	ovlXyz.isDragging = false
	
	showCursor(false)
	
    saveSettings()
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Настройки сброшены к дефолтным значениям.", -1)
end

-- Функция сохранения координат
function SaveCoordinatesData()
    local path = getCoordinatPath()
    local file = io.open(path, "w+")
    if file then
        local str = json.encode(saved_coordinates, { indent = true })
        file:write(str)
        file:close()
    end
end

-- Функция загрузки координат
function loadCoordinatesData()
    local path = getCoordinatPath()
    if not lfs.attributes(path) then
        saved_coordinates = { ["Основной"] = {} }
        SaveCoordinatesData()
    else
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local data, _, err = json.decode(content, 1, nil)
            if not err and type(data) == "table" then
                saved_coordinates = data
            else
                saved_coordinates = { ["Основной"] = {} }
            end
        end
    end
    categories = {}
    for catName, _ in pairs(saved_coordinates) do
        table.insert(categories, catName)
    end
    if #categories == 0 then
        table.insert(categories, "Основной")
    end
end

-- =========================
-- Вспомогательные функции
-- =========================

-- Проигрывания звука, аудио
local function playNotificationSound(soundPath)
    if soundPath and soundPath ~= "" and doesFileExist(soundPath) then
        winmm.PlaySoundA(soundPath, nil, bit.bor(SND_ASYNC, SND_FILENAME))
    end
end

-- Функция обрезки пробелов
function string:trim()
    return self:match("^%s*(.-)%s*$")
end

-- Подсчет общего количества координат во всех категориях
local function getTotalCoordsCount()
    local count = 0
    for _, list in pairs(saved_coordinates) do
        count = count + #list
    end
    return count
end

-- Добавление координат в список последних
function addLastXYZ()
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local coordStr = string.format("%.1f, %.1f, %.1f", px, py, pz)
    table.insert(last_coordinates, coordStr)
    
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]:{FFFFFF} Координата (" .. coordStr .. ") добавлена в временный буфер!", -1)
    if ovlPushM then
        ovlPushM.show("success", "Временная координата добавлена: [y]" .. coordStr .. "[/]", 1.5)
    end
end

-- Форматирование последних координат (из таблицы "поля ввода" в текст, это делается чтобы копирование было в привычном стиле)
local function getFormattedLastXYZ()
    local text = ""
    for i, coord in ipairs(last_coordinates) do
        text = text .. string.format("%d. %s\n", i, coord)
    end
    return text
end

-- Очищает все последние координаты (из поля ввода в окне последних координат)
function clearLastXYZ()
    if #last_coordinates == 0 then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Ошибка, поле и так пустое!", -1)
        if ovlPushM then
            ovlPushM.show("error", "[y]Произошла ошибка![/]\nСписок уже пуст", 1.5)
        end
        return false
    end

    last_coordinates = {}
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Список последних координат успешно очищен!", -1)
    if ovlPushM then
        ovlPushM.show("success", "Список последних координат был очищен", 1.5)
    end
    return true
end

-- Расчёта размеров текста (Оверлея уведомлений)
function ovlPushM.calcSize(text, lineHeight)
    local maxWidth, lines = 0, 0
    for line in text:gmatch("[^\n]+") do
        local w = renderGetFontDrawTextLength(ovlPushM.font, line)
        if w > maxWidth then maxWidth = w end
        lines = lines + 1
    end
    return maxWidth, lines * lineHeight
end

-- Функция отрисовки цвета строки с тегами (Оверлея уведомлений)
function ovlPushM.drawRichLine(x, y, line, alpha)
    local ax = x
    local a = bit.lshift(math.floor(alpha * 255), 24)
    local color = ovlPushM.colors.default

    for chunk, tag in line:gmatch("([^%[]*)(%b[])") do
        if chunk ~= "" then
            renderFontDrawText(ovlPushM.font, chunk, ax, y, color + a)
            ax = ax + renderGetFontDrawTextLength(ovlPushM.font, chunk)
        end

        if tag == "[y]" then
            color = ovlPushM.colors.yellow
        elseif tag == "[/]" then
            color = ovlPushM.colors.default
        end
    end

    local tail = line:gsub(".*%]", "")
    if tail ~= "" then
        renderFontDrawText(ovlPushM.font, tail, ax, y, color + a)
    end
end

-- Управление отображением (Оверлея уведомлений)
function ovlPushM.show(typeOrText, textOrDuration, duration)
    local nType, nText, nDuration

    -- Автоопределение формата вызова для гибридной совместимости
    if ovlPushM.types[typeOrText] then
        nType = typeOrText
        nText = tostring(textOrDuration or "")
        nDuration = duration or 2.5
    else
        nType = "info"
        nText = tostring(typeOrText or "")
        nDuration = textOrDuration or 2.5
    end

    table.insert(ovlPushM.queue, {
        type = nType,
        text = nText,
        duration = nDuration
    })
end

-- Принудительная очистка оверлея и очереди
function ovlPushM.hide()
    ovlPushM.active = false
    ovlPushM.queue = {}
end

-- =========================
-- Регистрация команд
-- =========================

-- Открытие главного окна
function cmd_xyzmenu()
    window.mainMenu[0] = not window.mainMenu[0]
end

-- Открытие окна управления категориями
function cmd_catxyz()
    window.catSettings[0] = not window.catSettings[0]
end

-- Открытие окна последних координат
function cmd_lastxyz()
    window.lastXyz[0] = not window.lastXyz[0]
end

-- Вывод текущих координат в чат
function cmd_currentxyz()
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local coordsStr = string.format("%.1f, %.1f, %.1f", x, y, z)
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Текущие координаты: {FFD940}" .. coordsStr, -1)
	ovlPushM.show("Текущие координаты:\n[y]" .. coordsStr .. "[/]", 5)
end

-- Сохранение координат
function cmd_savexyz(arg)
    -- Проверка на пустые аргументы
    if not arg or #arg:trim() == 0 then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Введите команду: {FFD940}/savexyz {FFFFFF}название, имя списка", -1)
        return
    end
	
    local name, category = arg:match("^%s*(.-)%s*,%s*(.-)%s*$")

    if not name or not category or name == "" or category == "" then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Введите команду: {FFD940}/savexyz {FFFFFF}название, имя списка", -1)
        return
    end

    if not saved_coordinates[category] then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Произошла ошибка! {FFFFFF}Такого списка: [".. category .. "] не существует.", -1)
        return
    end

    -- Получаем координаты персонажа и сохраняем
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    table.insert(saved_coordinates[category], {
        name = u8(name),
        x = px,
        y = py,
        z = pz
    })

    SaveCoordinatesData()
    sampAddChatMessage(string.format("{FF1493}[Pixel XYZ Helper]: {35FF35}Координата '%s' успешно сохранена в категорию: '%s'!", name, category), -1)
end


-- Сохранение координат в таблицу (поле ввода в окне последних координат)
function cmd_savelastxyz()
    if not isCharInAnyCar(PLAYER_PED) and not isCharDead(PLAYER_PED) then
        addLastXYZ()
    else
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local coordStr = string.format("%.1f, %.1f, %.1f", px, py, pz)
        table.insert(last_coordinates, coordStr)
        
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]:{FFFFFF} Координата (" .. coordStr .. ") добавлена в буфер!", -1)
        if ovlPushM then
            ovlPushM.show("success", "Временная координата добавлена: [y]" .. coordStr .. "[/]", 1.5)
        end
    end
end

-- Очищает все последнии координаты из таблицы (поля ввода в окне последних координат)
function cmd_clearlastxyz()
    clearLastXYZ()
end

-- Копирование всех последних координат из таблицы (поля ввода в окне последних координат)
function cmd_copylastxyz()
    if not is_unlocked[0] then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Ошибка! Поле заблокировано.{FFFFFF} Разблокируйте его в окне /lastxyz!", -1)
        if ovlPushM then
            ovlPushM.show("error", "[r]Ошибка![/]\nПоле заблокировано!", 1.5)
        end
        return
    end

    if #last_coordinates == 0 then
        sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Список последних координат пуст!", -1)
        return
    end

    local fullText = getFormattedLastXYZ()
    setClipboardText(fullText)
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {35FF35}Все последние координаты успешно скопированы!", -1)
    if ovlPushM then
        ovlPushM.show("success", "[g]Скопировано![/]\n" .. #last_coordinates .. " коорд. в буфере", 1.5)
    end
end

-- Просмотр доступных команд
function cmd_xyzhelp()
    local prefix = "{FF1493}[Pixel XYZ Helper]: {FFFFFF}"
    sampAddChatMessage(prefix .. "Список всех доступных команд:", -1)
    sampAddChatMessage(prefix .. "/xyzmenu - открытие меню", -1)
    sampAddChatMessage(prefix .. "/xyzhelp - просмотр всех команд", -1)
    sampAddChatMessage(prefix .. "/currentxyz - текущие координаты", -1)
    sampAddChatMessage(prefix .. "/savexyz - ручное сохранение координат", -1)
	sampAddChatMessage(prefix .. "/catxyz - управление категориями", -1)
	sampAddChatMessage(prefix .. "/lastxyz - окно последних координат", -1)
	sampAddChatMessage(prefix .. "/savelastxyz - быстро сохранить последнии координаты в буфер", -1)
	sampAddChatMessage(prefix .. "/clearlastxyz - очистить список последних координат", -1)
	sampAddChatMessage(prefix .. "/copylastxyz - быстрое копирование последних координат из поля ввода", -1)
end

-- =========================
-- Главное окно
-- =========================
imgui.OnFrame(function() return window.mainMenu[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(720, 400), imgui.Cond.FirstUseEver)
    
    imgui.Begin("Pixel XYZ Helper", window.mainMenu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    
    -- Левый сайдбар
    imgui.BeginChild("Sidebar", imgui.ImVec2(210, 0), true)
        if Icons.logo then
            imgui.SetCursorPosX((210 - 80) / 2)
            imgui.Image(Icons.logo, imgui.ImVec2(80, 80))
        end
        
        imgui.SetCursorPosX((210 - imgui.CalcTextSize("Pixel XYZ Helper").x) / 2)
        imgui.TextColored(textColor, "Pixel XYZ Helper")
        
		imgui.SetCursorPosX((210 - (imgui.CalcTextSize("Author: ").x + imgui.CalcTextSize(authorName).x)) / 2)
		imgui.TextColored(gray1, "Author: ")
		imgui.SameLine(0, 0)
		imgui.TextColored(yellow1, authorName)
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local btnW, btnH = 186, 38

        local is1 = (current_tab == 1)
        if ButtonWithStyle(u8"Список координат", btnW, btnH, 
            is1 and imgui.ImVec4(0.88, 0.11, 0.28, 1.0) or imgui.ImVec4(0.15, 0.15, 0.16, 1.0),
            is1 and imgui.ImVec4(0.95, 0.24, 0.36, 1.0) or imgui.ImVec4(0.20, 0.20, 0.22, 1.0),
            is1 and imgui.ImVec4(0.74, 0.07, 0.23, 1.0) or imgui.ImVec4(0.25, 0.25, 0.28, 1.0)) then
            current_tab = 1
        end

        local is2 = (current_tab == 2)
        if ButtonWithStyle(u8"Сохранить координаты", btnW, btnH, 
            is2 and imgui.ImVec4(0.88, 0.11, 0.28, 1.0) or imgui.ImVec4(0.15, 0.15, 0.16, 1.0),
            is2 and imgui.ImVec4(0.95, 0.24, 0.36, 1.0) or imgui.ImVec4(0.20, 0.20, 0.22, 1.0),
            is2 and imgui.ImVec4(0.74, 0.07, 0.23, 1.0) or imgui.ImVec4(0.25, 0.25, 0.28, 1.0)) then
            current_tab = 2
        end

        local is3 = (current_tab == 3)
        if ButtonWithStyle(u8"Настройки", btnW, btnH, 
            is3 and imgui.ImVec4(0.88, 0.11, 0.28, 1.0) or imgui.ImVec4(0.15, 0.15, 0.16, 1.0),
            is3 and imgui.ImVec4(0.95, 0.24, 0.36, 1.0) or imgui.ImVec4(0.20, 0.20, 0.22, 1.0),
            is3 and imgui.ImVec4(0.74, 0.07, 0.23, 1.0) or imgui.ImVec4(0.25, 0.25, 0.28, 1.0)) then
            current_tab = 3
        end

        local is4 = (current_tab == 4)
        if ButtonWithStyle(u8"Поддержать автора", btnW, btnH, 
			imgui.ImVec4(0.15, 0.15, 0.16, 1.0),
            imgui.ImVec4(0.20, 0.20, 0.22, 1.0),
            imgui.ImVec4(0.25, 0.25, 0.28, 1.0)) then
			os.execute('explorer "https://valeyevboss.github.io/nikitavaleyev.github.io/"')
        end
    imgui.EndChild()

    imgui.SameLine()

    -- Правый контент
    imgui.BeginChild("ContentArea", imgui.ImVec2(0, 0), true)
        if current_tab == 1 then
            local totalCount = getTotalCoordsCount()
            imgui.TextColored(textColor, u8"Всего координат загружено: ")
            imgui.SameLine()
            imgui.TextColored(pink1, tostring(totalCount))
            imgui.Spacing()

            if totalCount == 0 then
                if Icons.notfound then
                    imgui.SetCursorPosY(80)
                    imgui.SetCursorPosX((imgui.GetWindowWidth() - 100) / 2)
                    imgui.Image(Icons.notfound, imgui.ImVec2(100, 100))
                end
                
                local emptyText = u8"Отсутствуют координаты, список пуст."
                imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(emptyText).x) / 2)
                imgui.TextColored(gray1, emptyText)
            else
				-- Список координат
				imgui.BeginChild("CoordListChild", imgui.ImVec2(0, 0), false)
				local global_id = 0

				for catName, coordsList in pairs(saved_coordinates) do
					if #coordsList > 0 then
						imgui.TextColored(green1, u8"Категория: [" .. u8(catName) .. "]")
						imgui.Separator()
						
						local itemToDelete = nil

						for i, item in ipairs(coordsList) do
							global_id = global_id + 1
							
							local push_ok = pcall(imgui.PushID_Int, global_id)
							if not push_ok then
								pcall(imgui.PushID, global_id)
							end

							local coordStr = string.format("%.1f, %.1f, %.1f", item.x, item.y, item.z)
							imgui.TextColored(textColor, string.format("%d. %s", i, item.name))
							imgui.SameLine()
							imgui.TextColored(yellow1, "(" .. coordStr .. ")")
							
							local rightBoundary = imgui.GetCursorPosX() + imgui.GetContentRegionAvail().x
							
							-- Копировать
							imgui.SameLine(rightBoundary - 65)
							imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
							imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.1))
							imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.2))

							if imgui.ImageButton(Icons.copy, imgui.ImVec2(18, 18), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0) then
								setClipboardText(coordStr)
								local coordName = u8:decode(item.name) or "Координата"
								sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFF00}Координаты " .. coordName .. " (" .. coordStr .. ") скопированы!", -1)
								ovlPushM.show("success", "Скопировано: [y]" .. coordName .. "[/]\n" .. coordStr, 1.5)
							end

							-- Удалить
							imgui.SameLine(rightBoundary - 30)
							if imgui.ImageButton(Icons.delete, imgui.ImVec2(18, 18), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0) then
								itemToDelete = i
							end

							imgui.PopStyleColor(3)

							pcall(imgui.PopID)
						end

						if itemToDelete then
							local deletedName = u8:decode(coordsList[itemToDelete].name) or "Координата"
							table.remove(coordsList, itemToDelete)
							SaveCoordinatesData()
							sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Координата " .. deletedName .. " была удалена!", -1)
							ovlPushM.show("success", "Координата [y]" .. deletedName .. "[/]\nуспешно удалена", 1)
						end

						imgui.Spacing()
					end
				end
				imgui.EndChild()
            end

		elseif current_tab == 2 then
			imgui.TextColored(textColor, u8"Категория:")
			imgui.SameLine()
			
			local startY = imgui.GetCursorPosY()

			StyledDropdown("save_cat", "", categories, selected_category_idx, 140)
			imgui.SameLine()

			imgui.SetCursorPosY(startY)

			-- Кнопка управления категориями
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.88, 0.11, 0.28, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.24, 0.36, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.74, 0.07, 0.23, 1.0))

            if Icons.settings then
                if imgui.ImageButton(Icons.settings, imgui.ImVec2(18, 18), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 4) then
                    window.catSettings[0] = true
                end
            else
                if imgui.Button(u8"?", imgui.ImVec2(26, 26)) then
                    window.catSettings[0] = true
                end
            end

            imgui.PopStyleColor(3)

			if imgui.IsItemHovered() then
				imgui.SetTooltip(u8"Управление категориями (создание / удаление)")
			end
			
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
			
            local currentInputStr = ffi.string(input_coord_name):trim()
            local isEmpty = (currentInputStr == "")

            imgui.TextColored(textColor, u8"Введите имя:")
            imgui.SameLine()

            InputCustom(260, function()
                imgui.InputText("##coord_name", input_coord_name, 128)
            end, isEmpty)

            local px, py, pz = getCharCoordinates(PLAYER_PED)
            local posStr = string.format("%.1f, %.1f, %.1f", px, py, pz)

            imgui.Spacing()
            imgui.TextColored(textColor, u8"Текущие координаты:")
            imgui.SameLine()
            imgui.TextColored(yellow1, posStr)

            local btnSaveWidth, btnSaveHeight = 180, 34
            imgui.SetCursorPosY(imgui.GetWindowHeight() - 48)
            imgui.SetCursorPosX((imgui.GetWindowWidth() - btnSaveWidth) / 2)
			
            if isEmpty then
                ButtonWithStyle(u8"Сохранить", btnSaveWidth, btnSaveHeight,
                    imgui.ImVec4(0.3, 0.3, 0.3, 0.5),
                    imgui.ImVec4(0.3, 0.3, 0.3, 0.5),
                    imgui.ImVec4(0.3, 0.3, 0.3, 0.5)
                )
            else
                if ButtonWithStyle(u8"Сохранить", btnSaveWidth, btnSaveHeight, imgui.ImVec4(0.13, 0.77, 0.36, 1.0), imgui.ImVec4(0.16, 0.85, 0.40, 1.0), imgui.ImVec4(0.10, 0.65, 0.30, 1.0)) then
                    local currentCategory = categories[selected_category_idx[0] + 1] or "Основной"
                    
                    if not saved_coordinates[currentCategory] then
                        saved_coordinates[currentCategory] = {}
                    end
                    
                    table.insert(saved_coordinates[currentCategory], {
                        name = currentInputStr,
                        x = px,
                        y = py,
                        z = pz
                    })
                    
                    SaveCoordinatesData()
					
					local savedName = u8:decode(currentInputStr)
					local categoryName = (currentCategory)
					
					sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {00FF00}Координата " .. savedName .. " сохранена в категорию: " .. categoryName .. "!", -1)
					ovlPushM.show("success", "Сохранено: [y]" .. savedName .. "[/]\nКатегория: " .. categoryName, 2)
					
                    input_coord_name[0] = 0
                    current_tab = 1 
                end
            end

		elseif current_tab == 3 then
			imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(0.45, 0.12, 0.25, 0.65))
			imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0.75, 0.20, 0.40, 0.85))
			imgui.PushStyleColor(imgui.Col.HeaderActive, imgui.ImVec4(0.55, 0.15, 0.30, 1.00))

			local headerFlags = imgui.TreeNodeFlags.Framed + imgui.TreeNodeFlags.NoAutoOpenOnLog

			-- =============================================================
			-- РАЗДЕЛ 1: ГОРЯЧИЕ КЛАВИШИ
			-- =============================================================
			if imgui.CollapsingHeader(u8" ГОРЯЧИЕ КЛАВИШИ", headerFlags) then
				imgui.Indent(10)
				imgui.Dummy(imgui.ImVec2(0, 5))
				
				imgui.TextColored(textColor, u8"Открытие главного меню:")
				imgui.SameLine(320)
				drawKeyInput("mainMenu", "Нажмите, чтобы изменить клавишу открытия меню")
				
				imgui.Dummy(imgui.ImVec2(0, 5))
				imgui.Unindent(10)
			end

			imgui.Spacing()

			-- =============================================================
			-- РАЗДЕЛ 2: ОВЕРЛЕИ И УВЕДОМЛЕНИЯ
			-- =============================================================
			if imgui.CollapsingHeader(u8" ОВЕРЛЕИ И УВЕДОМЛЕНИЯ", headerFlags) then
				imgui.Indent(10)
				imgui.Dummy(imgui.ImVec2(0, 5))
				
				-- Подраздел: Оверлей уведомлений
				imgui.TextColored(cyan1, u8"Оверлей уведомлений")
				imgui.Dummy(imgui.ImVec2(0, 5))
				
				imgui.SetCursorPosX(30)
				imgui.Text(u8"Видимость уведомлений")
				imgui.SameLine(320)
				if ToggleSwitch("overlay_push_m", overlayPushM) then
					settings.overlayPushM = overlayPushM[0]
					saveSettings()
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Включает и выключает отображение оверлея уведомлений на экране")
				end
				
				imgui.SetCursorPosX(30)
				imgui.Text(u8"Звуки уведомлений")
				imgui.SameLine(320)
				if ToggleSwitch("overlay_push_m_sound", overlayPushMSound) then
					settings.overlayPushMSound = overlayPushMSound[0]
					saveSettings()
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Включает и выключает воспроизведение звуков оверлея уведомлений")
				end

				imgui.SetCursorPosX(30)
				imgui.Text(u8"Позиция уведомлений")
				imgui.SameLine(320)
				if ButtonWithStyle(u8"Изменить##pushm", 100, 24, 
					imgui.ImVec4(0.88, 0.11, 0.28, 1.0), 
					imgui.ImVec4(0.95, 0.24, 0.36, 1.0), 
					imgui.ImVec4(0.74, 0.07, 0.23, 1.0)) then
					ovlPushM.editPos = true
					showCursor(true)
					if showOverlayMessage then
						showOverlayMessage("Режим редактирования: Перетащите оверлей уведомлений\n[y]ESC - сохранить[/]", 9999)
					end
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Переходит в режим интерактивного перемещения оверлея по экрану мышью")
				end

				imgui.Dummy(imgui.ImVec2(0, 5))
				
				-- Подраздел: Оверлей координат
				imgui.TextColored(cyan1, u8"Оверлей координат")
				imgui.Dummy(imgui.ImVec2(0, 5))
				
				imgui.SetCursorPosX(30)
				imgui.Text(u8"Отображение координат")
				imgui.SameLine(320)
				if ToggleSwitch("overlay_xyz", overlayXyz) then
					settings.overlayXyz = overlayXyz[0]
					saveSettings()
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Включает и выключает отображение информационного оверлея с координатами на экране")
				end

				imgui.SetCursorPosX(30)
				imgui.Text(u8"Фон оверлея")
				imgui.SameLine(320)
				if ToggleSwitch("overlay_xyz_bg", overlayXyzBackground) then
					settings.overlayXyzBackground = overlayXyzBackground[0]
					saveSettings()
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Добавляет затемнённую подложку под текст координат для лучшей читаемости")
				end

				imgui.SetCursorPosX(30)
				imgui.Text(u8"Позиция оверлея")
				imgui.SameLine(320)
				if ButtonWithStyle(u8"Изменить##xyz", 100, 24, 
					imgui.ImVec4(0.88, 0.11, 0.28, 1.0), 
					imgui.ImVec4(0.95, 0.24, 0.36, 1.0), 
					imgui.ImVec4(0.74, 0.07, 0.23, 1.0)) then
					ovlXyz.editPos = true
					showCursor(true)
					if showOverlayMessage then
						showOverlayMessage("Режим редактирования: Перетащите оверлей координат\n[y]ESC - сохранить[/]", 9999)
					end
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Переходит в режим интерактивного перемещения оверлея по экрану мышью")
				end

				imgui.SetCursorPosX(30)
				imgui.Text(u8"Размер оверлея:")
				imgui.SameLine(320)
				if StyledDropdown("ov_xyz_font_size", "", ovlXyz.fontSizes, ovlXyz.fontSizeIndex, 120) then
					settings.overlayXyzFontSize = ovlXyz.fontSizeValues[ovlXyz.fontSizeIndex[0] + 1]
					ovlXyz.font = renderCreateFont('Arial', settings.overlayXyzFontSize, 5)
					saveSettings()
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Выбор размера оверлея координат")
				end

				imgui.Dummy(imgui.ImVec2(0, 5))
				imgui.Unindent(10)
			end

			imgui.PopStyleColor(3)

			-- Оставляем место внизу, чтобы контент не перекрывался кнопкой при прокрутке
			imgui.Dummy(imgui.ImVec2(0, 40))

			-- Фиксируем кнопку сброса внизу текущей скролл-зоны
			local btnResetW, btnResetH = 180, 32
			local scrollY = imgui.GetScrollY()
			local windowH = imgui.GetWindowHeight()

			imgui.SetCursorPosY(scrollY + windowH - 45)
			imgui.SetCursorPosX((imgui.GetWindowWidth() - btnResetW) / 2)

			if ButtonWithStyle(u8"Сбросить настройки", btnResetW, btnResetH, 
				imgui.ImVec4(120/255, 0/255, 0/255, 1.0),
				imgui.ImVec4(160/255, 0/255, 0/255, 1.0),
				imgui.ImVec4(80/255, 0/255, 0/255, 1.0)) then
				resetSettings()
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip(u8"Сбрасывает настройки к дефолтным значениям.")
			end
		end
	imgui.EndChild()
    imgui.End()
end)

-- Окно управления категориями
imgui.OnFrame(function() return window.catSettings[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(360, 320), imgui.Cond.FirstUseEver)
    
    if imgui.Begin(u8"Управление категориями", window.catSettings, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        local rawInput = ffi.string(input_new_category):trim()
        local catInputStr = u8:decode(rawInput) or rawInput
        local isCatEmpty = (catInputStr == "")

        imgui.TextColored(textColor, u8"Создать новую категорию:")
        imgui.Spacing()

        InputCustom(240, function()
            imgui.InputText("##new_cat_name", input_new_category, 128)
        end, isCatEmpty)

        imgui.SameLine()
        
        -- Кнопка Создать
        if isCatEmpty then
            ButtonWithStyle(u8"Создать", 80, 26, imgui.ImVec4(0.3, 0.3, 0.3, 0.5), imgui.ImVec4(0.3, 0.3, 0.3, 0.5), imgui.ImVec4(0.3, 0.3, 0.3, 0.5))
        else
            if ButtonWithStyle(u8"Создать", 80, 26, imgui.ImVec4(0.13, 0.77, 0.36, 1.0), imgui.ImVec4(0.16, 0.85, 0.40, 1.0), imgui.ImVec4(0.10, 0.65, 0.30, 1.0)) then
                if not saved_coordinates[catInputStr] then
                    saved_coordinates[catInputStr] = {}
                
                    table.insert(categories, catInputStr)
                    selected_category_idx[0] = #categories - 1
                    SaveCoordinatesData()
                    
                    sampAddChatMessage(string.format("{FF1493}[Pixel XYZ Helper]: {35FF35}Категория '%s' успешно создана!", catInputStr), -1)
                    if ovlPushM then ovlPushM.show("success", "Категория [y]" .. catInputStr .. "[/]\nуспешно создана!", 2.0) end
                    
                    input_new_category[0] = 0
                else
                    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Ошибка! Категория с таким названием уже существует.", -1)
                    if ovlPushM then ovlPushM.show("error", "Категория уже существует!", 2.0) end
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        imgui.TextColored(textColor, u8"Список категорий:")
        imgui.Spacing()

        imgui.BeginChild("CategoriesManageList", imgui.ImVec2(0, 0), true)
            local categoryToDelete = nil

            for idx, cName in ipairs(categories) do
                local push_ok = pcall(imgui.PushID_Int, idx)
                if not push_ok then
                    pcall(imgui.PushID, idx)
                end

				local count = saved_coordinates[cName] and #saved_coordinates[cName] or 0
				imgui.TextColored(textColor, string.format("%d. %s", idx, u8(cName)))
				imgui.SameLine()
				imgui.TextColored(gray1, u8(string.format("(%d координат.)", count)))

                -- Кнопка удаления
                if cName ~= "Основной" then
                    local rightBoundary = imgui.GetCursorPosX() + imgui.GetContentRegionAvail().x
                    imgui.SameLine(rightBoundary - 25)
                    
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 0.2, 0.2, 0.2))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 0.2, 0.2, 0.4))

                    local isClicked = false
                    if Icons.delete then
                        isClicked = imgui.ImageButton(Icons.delete, imgui.ImVec2(16, 16), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0, imgui.ImVec4(0,0,0,0), imgui.ImVec4(1, 1, 1, 1.0))
                    else
                        isClicked = imgui.Button("X", imgui.ImVec2(20, 20))
                    end

                    if isClicked then
                        categoryToDelete = idx
                    end

                    imgui.PopStyleColor(3)
                end

                pcall(imgui.PopID)
            end

            -- Логика удаления выбранной категории
            if categoryToDelete then
                local delCatName = categories[categoryToDelete]
                
                -- 1. Удаляем из таблицы данных
                saved_coordinates[delCatName] = nil
                SaveCoordinatesData()

                -- 2. Удаляем из списка выпадающего меню
                table.remove(categories, categoryToDelete)

                -- 3. Корректируем выбранный индекс
                if selected_category_idx[0] >= #categories then
                    selected_category_idx[0] = math.max(0, #categories - 1)
                end

                sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {35FF35}Категория '{FFD940}" .. delCatName .. "{35FF35}' была удалена!", -1)
                if ovlPushM then ovlPushM.show("success", "Категория [y]" .. delCatName .. "[/]\nудалена!", 2.0) end
            end

        imgui.EndChild()
        imgui.End()
    end
end)

-- Окно последних координат
imgui.OnFrame(function() return window.lastXyz[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(425, 330), imgui.Cond.Always)
    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
	
    if imgui.Begin(u8"Последние координаты", window.lastXyz, flags) then
        
        -- Заголовок и кнопка Копировать
        imgui.TextColored(yellow1, u8"Последние координаты")
        imgui.SameLine(imgui.GetWindowWidth() - 50)
        
        local copyAlpha = is_unlocked[0] and 1.0 or 0.4
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.1 * copyAlpha))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.2 * copyAlpha))

        if imgui.ImageButton(Icons.copy, imgui.ImVec2(18, 18), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0, imgui.ImVec4(0,0,0,0), imgui.ImVec4(1, 1, 1, copyAlpha)) then
            if not is_unlocked[0] then
                sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FF0000}Ошибка! Поле заблокировано. Разблокируйте его переключателем ниже!", -1)
                if ovlPushM then
                    ovlPushM.show("error", "[r]Ошибка![/]\nПоле заблокировано!", 1.5)
                end
            elseif #last_coordinates == 0 then
                sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Список пуст, нечего копировать!", -1)
                if ovlPushM then
                    ovlPushM.show("warning", "Список пуст, нечего копировать!", 1.5)
                end
            else
                local fullText = getFormattedLastXYZ()
                setClipboardText(fullText)
                sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Все последние координаты скопированы!", -1)
                if ovlPushM then
                    ovlPushM.show("success", "Скопировано [y]" .. #last_coordinates .. "[/] коорд.", 1.5)
                end
            end
        end
        imgui.PopStyleColor(3)

        imgui.SameLine()

        -- Кнопка удалить
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.2))

        if imgui.ImageButton(Icons.delete, imgui.ImVec2(18, 18), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0, imgui.ImVec4(0,0,0,0), imgui.ImVec4(1, 1, 1, 1.0)) then
            clearLastXYZ()
        end
        imgui.PopStyleColor(3)

        imgui.Spacing()

        -- Поле ввода
        local formattedText = getFormattedLastXYZ()
        local buf = imgui.new.char[4096](u8(formattedText))

		InputLastXYZ(404, 150, function()
			imgui.InputTextMultiline("##last_xyz_area", buf, 4096, imgui.ImVec2(404, 150), imgui.InputTextFlags.ReadOnly)
		end, not is_unlocked[0])

        imgui.Spacing()

        -- Тоггл и текст "Разблокировать"
        CustomToggle("##unlock_xyz_toggle", is_unlocked)
        imgui.SameLine()
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 1)
        imgui.TextColored(textColor, u8"Разблокировать")

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Предупреждение
        imgui.TextColored(gray1, u8"Внимание: после каждого перезахода в игру данный")
        imgui.TextColored(gray1, u8"список с последними координатами сбрасывается.")

        imgui.End()
    end
end)

-- =========================
-- Оверлеи
-- =========================

-- Оверлей уведомлений
lua_thread.create(function()
    while true do
        local dt = wait(0) or 0.016

        -- Берем следующее сообщение из очереди
        if overlayPushM[0] and not ovlPushM.active and #ovlPushM.queue > 0 and ovlPushM.alpha <= 0 then
            local nextMsg = table.remove(ovlPushM.queue, 1)
            ovlPushM.text = nextMsg.text
            ovlPushM.type = nextMsg.type or "info"
            ovlPushM.duration = nextMsg.duration
            ovlPushM.timer = 0
            ovlPushM.active = true

            -- Проигрываем звук при появлении
            local typeConfig = ovlPushM.types[ovlPushM.type]
            if typeConfig and typeConfig.sound and (settings.overlayPushMSound ~= false) then
                playNotificationSound(typeConfig.sound)
            end
        end

        -- Анимация альфы и таймер
        if not ovlPushM.active or not overlayPushM[0] then
            ovlPushM.alpha = math.max(ovlPushM.alpha - dt * 5, 0)
        else
            ovlPushM.timer = ovlPushM.timer + dt
            ovlPushM.alpha = math.min(ovlPushM.alpha + dt * 5, 1)

            if ovlPushM.timer >= ovlPushM.duration then
                ovlPushM.active = false
            end
        end

        -- Позиция
        local posX = settings.overlayPushMPos and settings.overlayPushMPos.x or 20
        local posY = settings.overlayPushMPos and settings.overlayPushMPos.y or 20

        local renderText = ovlPushM.text
        local currentAlpha = ovlPushM.alpha

        if ovlPushM.editPos then
            currentAlpha = 1.0
            if renderText == "" then
                renderText = "Тестовое уведомление\n[y]Вы в режиме редактирования[/]"
            end
        end

        -- Отрисовка
        if currentAlpha > 0 and (overlayPushM[0] or ovlPushM.editPos) then
            local lineHeight = ovlPushM.fontSize + 8
            local textWidth, textHeight = ovlPushM.calcSize(renderText, lineHeight)
            
            local bgWidth  = textWidth + ovlPushM.padding * 2 + 6 -- +6px под цветной индикатор
            local bgHeight = textHeight + ovlPushM.padding * 2

            local alphaByte = math.floor(currentAlpha * 0xCC)
            local bgColor = bit.lshift(alphaByte, 24) + 0x000000

            -- 1. Режим редактирования (Перетаскивание)
            if ovlPushM.editPos then
                local mx, my = getCursorPos()
                local mouseDown = isKeyDown(VK_LBUTTON)

                if renderDrawBoxRounded then
                    renderDrawBoxRounded(posX - 2, posY - 2, bgWidth + 4, bgHeight + 4, ovlPushM.radius, 0xFFE01C47)
                else
                    renderDrawBox(posX - 2, posY - 2, bgWidth + 4, bgHeight + 4, 0xFFE01C47)
                end

                if not ovlPushM.isDragging and mouseDown then
                    if mx >= posX and mx <= posX + bgWidth and my >= posY and my <= posY + bgHeight then
                        ovlPushM.isDragging = true
                        ovlPushM.dragOffset.x = mx - posX
                        ovlPushM.dragOffset.y = my - posY
                    end
                end

                if ovlPushM.isDragging then
                    if mouseDown then
                        settings.overlayPushMPos.x = mx - ovlPushM.dragOffset.x
                        settings.overlayPushMPos.y = my - ovlPushM.dragOffset.y
                    else
                        ovlPushM.isDragging = false
                        saveSettings()
                    end
                end

                if isKeyJustPressed(VK_ESCAPE) then
                    ovlPushM.editPos = false
                    ovlPushM.isDragging = false
                    showCursor(false)
                    if hideOverlayMessage then hideOverlayMessage() end
                    saveSettings()
                end
            end

            -- 2. Отрисовка фона
            if renderDrawBoxRounded then
                renderDrawBoxRounded(posX, posY, bgWidth, bgHeight, ovlPushM.radius, bgColor)
            else
                renderDrawBox(posX, posY, bgWidth, bgHeight, bgColor)
            end

            -- 3. Отрисовка вертикальной цветной полоски индикатора типа
            local currentTypeConfig = ovlPushM.types[ovlPushM.type] or ovlPushM.types.info
            local accentAlpha = bit.lshift(math.floor(currentAlpha * 255), 24)
            local accentColor = currentTypeConfig.accentColor + accentAlpha

            if renderDrawBoxRounded then
                renderDrawBoxRounded(posX + 4, posY + 6, 3, bgHeight - 12, 2, accentColor)
            else
                renderDrawBox(posX + 4, posY + 6, 3, bgHeight - 12, accentColor)
            end

            -- 4. Отрисовка текста (смещен чуть вправо из-за полоски)
            local ty = posY + ovlPushM.padding
            for line in renderText:gmatch("[^\n]+") do
                ovlPushM.drawRichLine(posX + ovlPushM.padding + 6, ty, line, currentAlpha)
                ty = ty + lineHeight
            end
        end
    end
end)

-- Оверлей: Отображение координат на экране
lua_thread.create(function()
    while true do
        wait(0)
        if not overlayXyz[0] then goto skip end

        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local coordStr = string.format("%.1f, %.1f, %.1f", px, py, pz)
        local titleText = "XYZ: "
        
        local font = ovlXyz.font
        local clr = ovlXyz.colors
        
        local titleWidth = renderGetFontDrawTextLength(font, titleText)
        local coordsWidth = renderGetFontDrawTextLength(font, coordStr)
        local totalWidth = titleWidth + coordsWidth
        
        local fontSize = settings.overlayXyzFontSize or 11
        local padding = math.floor(fontSize * 0.5)
        local fontHeight = fontSize + 4
        
        local x = settings.overlayXyzPos.x or 20
        local y = settings.overlayXyzPos.y or 400

        -- Динамическая геометрия фона
        local bgX = x - padding
        local bgY = y - math.floor(padding / 2)
        local bgWidth = totalWidth + (padding * 2)
        local bgHeight = fontHeight + padding

        -- 1. Отрисовка фона (если включён)
        if overlayXyzBackground[0] then
            renderDrawBox(bgX, bgY, bgWidth, bgHeight, clr.bgDefault)
        end

        -- 2. Режим перетаскивания (Редактор)
        if ovlXyz.editPos then
            local mx, my = getCursorPos()
            local mouseDown = isKeyDown(VK_LBUTTON)

            renderDrawBox(bgX - 2, bgY - 2, bgWidth + 4, bgHeight + 4, clr.editBorder)
            if not overlayXyzBackground[0] then
                renderDrawBox(bgX, bgY, bgWidth, bgHeight, 0x55000000)
            end

            if not ovlXyz.isDragging and mouseDown then
                if mx >= bgX and mx <= bgX + bgWidth and my >= bgY and my <= bgY + bgHeight then
                    ovlXyz.isDragging = true
                    ovlXyz.dragOffset.x = mx - x
                    ovlXyz.dragOffset.y = my - y
                end
            end

            if ovlXyz.isDragging then
                if mouseDown then
                    settings.overlayXyzPos.x = mx - ovlXyz.dragOffset.x
                    settings.overlayXyzPos.y = my - ovlXyz.dragOffset.y
                else
                    ovlXyz.isDragging = false
                end
            end
        end

        -- 3. Отрисовка текста
        renderFontDrawText(font, titleText, x, y, clr.title)
        renderFontDrawText(font, coordStr, x + titleWidth, y, clr.coords)

        -- Выход из режима редактирования по ESC
        if ovlXyz.editPos and isKeyJustPressed(VK_ESCAPE) then
            ovlXyz.editPos = false
            ovlXyz.isDragging = false
            showCursor(false)
            if hideOverlayMessage then hideOverlayMessage() end
            saveSettings()
        end

        ::skip::
    end
end)

-- =========================
-- Основной цикл
-- =========================
function main()
    while not isSampAvailable() do wait(100) end
    
    local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    nickname = sampGetPlayerNickname(id) or "Unknown"

    sampRegisterChatCommand("xyzmenu", cmd_xyzmenu)
	sampRegisterChatCommand("xyzhelp", cmd_xyzhelp)
	sampRegisterChatCommand("currentxyz", cmd_currentxyz)
	sampRegisterChatCommand("savexyz", cmd_savexyz)
	sampRegisterChatCommand("catxyz", cmd_catxyz)
	sampRegisterChatCommand("lastxyz", cmd_lastxyz)
	sampRegisterChatCommand("savelastxyz", cmd_savelastxyz)
	sampRegisterChatCommand("copylastxyz", cmd_copylastxyz)
	sampRegisterChatCommand("clearlastxyz", cmd_clearlastxyz)

    -- Загрузка данных из файлов конфигурации
	loadSettings()
    loadCoordinatesData()
    
    while true do
        wait(0)

        -- Если скрипт ожидает нажатия клавиши для её смены
        if waitingKeyInputType then
            for k = 0, 255 do
                if k ~= 0x10 and k ~= 0x11 and k ~= 0x12 and 
                   k ~= 0xA0 and k ~= 0xA1 and k ~= 0xA2 and k ~= 0xA3 and k ~= 0xA4 and k ~= 0xA5 then
                    
                    if wasKeyPressed(k) then
                        local newKey = (k == 0x1B) and 0 or k -- Esc снимает клавишу (ставит 0)

                        if type(waitingKeyInputType) == "string" and settings.hotkeys[waitingKeyInputType] ~= nil then
                            settings.hotkeys[waitingKeyInputType] = newKey
                            saveSettings()
                            sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {35FF35}Клавиша успешно обновлена!", -1)
                            waitingKeyInputType = nil
                            ovlPushM.hide()
                        end
                        break
                    end
                end
            end
        else
            -- Автоматическая проверка открытия окон по горячим клавишам
            for windowName, targetKey in pairs(settings.hotkeys) do
                if targetKey and targetKey ~= 0 and wasKeyPressed(targetKey) then
                    if window[windowName] then
                        window[windowName][0] = not window[windowName][0]
                    end
                end
            end
        end
    end
end

-- =========================
-- Сообщение при запуске
-- =========================
lua_thread.create(function()
    wait(3000)
    sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Автор скрипта: {FFD700} Nikita Valeyev", -1)
	sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Альтернативный способ открытия меню доступен по команде /xyzmenu.", -1)
	sampAddChatMessage("{FF1493}[Pixel XYZ Helper]: {FFFFFF}Открыть окно помощи, просмотр всех доступных команд /xyzhelp.", -1)
end)