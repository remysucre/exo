-- exo: A web browser for Playdate
-- Main entry point

import "CoreLibs/graphics"
import "CoreLibs/ui"

local gfx <const> = playdate.graphics
local siteParsers = import "siteparsers"

-- State
local currentURL = nil
local currentContent = nil
local scrollOffset = 0
local statusMessage = "Connecting to WiFi..."
local pendingURL = nil  -- URL to load in next update

-- Button selection state (determined during render)
local hoveredButton = nil
local pageImage = nil
local pageButtons = {}
local pageHeight = 0

-- Network state
local networkReady = false

-- Fetch state (async networking)
local fetchState = nil  -- nil, "fetching", "done", "error"
local fetchConn = nil
local fetchHTML = ""
local fetchError = nil
local fetchURL = nil
local fetchParser = nil

-- Rendering helpers
local textFonts = {
    regular = gfx.font.new("fonts/Asheville-Sans-14-Bold"),
    italic = gfx.font.new("fonts/Asheville-Sans-14-Bold-Oblique"),
    bold = gfx.font.new("fonts/Asheville-Sans-14-Bolder")
}

gfx.setFontFamily({
    [playdate.graphics.font.kVariantNormal] = textFonts.regular,
    [playdate.graphics.font.kVariantBold] = textFonts.bold,
    [playdate.graphics.font.kVariantItalic] = textFonts.italic
})
local defaultFontHeight = textFonts.regular and textFonts.regular:getHeight() or 16
local textLineHeight = math.max(defaultFontHeight, 16)
local contentPadding = 10
local contentWidth = 400 - contentPadding * 2
local paragraphSpacing = 4
local buttonSpacing = 8

local function clampScroll()
    local viewportHeight = 240
    local maxOffset = math.max(0, pageHeight - viewportHeight)
    if scrollOffset > maxOffset then
        scrollOffset = maxOffset
    end
    if scrollOffset < 0 then
        scrollOffset = 0
    end
end

local function preparePageImage(elements)
    pageImage = nil
    pageButtons = {}
    pageHeight = 0

    if not elements or #elements == 0 then
        return
    end

    gfx.setFont(textFonts.regular)

    local textCommands = {}
    local currentY = 0

    for _, element in ipairs(elements) do
        if element.kind == "spacer" then
            currentY += element.size or paragraphSpacing
        elseif element.kind == "button" then
            local label = element.label or element.content or "Link"
            local _, height = gfx.getTextSize(label)
            height = height or textLineHeight
            table.insert(pageButtons, {
                label = label,
                url = element.url,
                y = currentY,
                height = height
            })
            currentY += height + buttonSpacing
        else
            local text = element.content or ""
            local _, height = gfx.getTextSizeForMaxWidth(text, contentWidth)
            height = height or textLineHeight
            table.insert(textCommands, {
                text = text,
                y = currentY,
                height = height
            })
            currentY += height + paragraphSpacing
        end
    end

    local totalHeight = math.max(currentY + 200, (240 - contentPadding * 2))
    local imageHeight = totalHeight + contentPadding * 2
    local imageWidth = contentWidth + contentPadding * 2

    local image = gfx.image.new(imageWidth, imageHeight)
    gfx.lockFocus(image)
    gfx.clear(gfx.kColorWhite)
    gfx.setFont(textFonts.regular)

    for _, command in ipairs(textCommands) do
        gfx.drawText(command.text, contentPadding, contentPadding + command.y, contentWidth, command.height)
    end

    gfx.unlockFocus()
    gfx.setColor(gfx.kColorBlack)

    pageImage = image
    pageHeight = imageHeight
end

local selectionIndicatorHeight = 2
local selectionLineY = 100
local linkHighlightPadding = 2

local function drawButtonElement(label, x, y, isSelected)
    gfx.setFont(textFonts.regular)

    local textWidth, textHeight = gfx.getTextSize(label)
    local buttonHeight = textHeight or textLineHeight

    if isSelected then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(
            x - linkHighlightPadding,
            y - linkHighlightPadding,
            (textWidth or 0) + linkHighlightPadding * 2,
            buttonHeight + linkHighlightPadding * 2
        )
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    else
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end

    local width = gfx.drawText(label, x, y)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    gfx.drawLine(x, y + buttonHeight + selectionIndicatorHeight, x + width, y + buttonHeight + selectionIndicatorHeight)

end

local function resolveURL(base, href)
    if not href or href == "" then
        return nil
    end

    if href:match("^https?://") then
        return href
    end

    if href:match("^[%a]+:") then
        return href
    end

    if not base then
        return href
    end

    local origin = base:match("^(https?://[^/]+)")
    if not origin then
        return href
    end

    if href:sub(1, 1) == "/" then
        return origin .. href
    end

    local path = base:match("^https?://[^/]+(.*/)")
    if path then
        return origin .. path .. href
    end

    return origin .. "/" .. href
end

function loadURL(url)
    -- Check if network is ready
    if not networkReady then
        statusMessage = "Waiting for network..."
        pendingURL = url  -- Re-queue it
        return
    end

    statusMessage = "Loading: " .. url
    scrollOffset = 0

    -- Find matching site parser
    local matchedParser = nil
    for _, parser in ipairs(siteParsers) do
        if string.match(url, parser.pattern) then
            matchedParser = parser
            break
        end
    end

    if not matchedParser then
        statusMessage = "Error: No rules for this URL"
        currentContent = nil
        return
    end

    statusMessage = "Matched: " .. matchedParser.name

    -- Start async fetch
    fetchURL = url
    fetchParser = matchedParser
    fetchHTML = ""
    fetchError = nil
    fetchState = "fetching"

    fetchHTMLAsync(url)
end

function fetchHTMLAsync(url)
    -- HTTP fetch using Playdate's networking API (async, no blocking)
    statusMessage = "Fetching HTML..."
    print("fetchHTMLAsync called with URL:", url)

    -- Parse URL to get server and path
    local server, path = string.match(url, "^https?://([^/]+)(.*)$")
    if not server then
        fetchState = "error"
        fetchError = "Invalid URL"
        print("Failed to parse URL")
        return
    end

    if path == "" then
        path = "/"
    end
    print("Fetching URL:", url, "Server:", server, "Path:", path)

    local useSSL = string.match(url, "^https://") ~= nil
    print("Server:", server, "Path:", path, "SSL:", useSSL)

    -- Create HTTP connection
    fetchConn = playdate.network.http.new(server, nil, useSSL, "exo browser needs to fetch web content")
    if not fetchConn then
        fetchState = "error"
        fetchError = "Failed to create connection"
        print("Failed to create HTTP connection")
        return
    end

    print("HTTP connection created")

    fetchConn:setConnectTimeout(10)
    fetchConn:setReadTimeout(2)

    -- Callback when headers are received
    fetchConn:setHeadersReadCallback(function()
        print("Headers received")
        local status = fetchConn:getResponseStatus()
        print("Response status:", status)

        if status == 0 or status >= 400 then
            fetchState = "error"
            fetchError = "HTTP error " .. status
        end

        local headers = fetchConn:getResponseHeaders()
        if headers then
            for k, v in pairs(headers) do
                print("Header:", k, "=", v)
            end
        end
    end)

    -- Callback when data is available
    fetchConn:setRequestCallback(function()
        print("Request callback - data available")
        local available = fetchConn:getBytesAvailable()
        if available > 0 then
            print("Reading", available, "bytes")
            local data = fetchConn:read(available)
            if data then
                print("Read", #data, "bytes")
                fetchHTML = fetchHTML .. data
            end
        end
    end)

    -- Callback when request is complete
    fetchConn:setRequestCompleteCallback(function()
        print("Request complete callback")

        -- Read any remaining data
        local available = fetchConn:getBytesAvailable()
        if available > 0 then
            print("Reading final", available, "bytes")
            local data = fetchConn:read(available)
            if data then
                print("Read", #data, "bytes")
                fetchHTML = fetchHTML .. data
            end
        end

        -- Check for errors
        local err = fetchConn:getError()
        if err then
            print("Connection error:", err)
            fetchState = "error"
            fetchError = err
        elseif #fetchHTML == 0 then
            print("No data received")
            fetchState = "error"
            fetchError = "No data received"
        else
            print("Successfully fetched", #fetchHTML, "bytes")
            fetchState = "done"
        end

        fetchConn:close()
        fetchConn = nil
    end)

    fetchConn:setConnectionClosedCallback(function()
        print("Connection closed callback")
        if fetchState == "fetching" then
            -- Connection closed before completion
            if #fetchHTML == 0 then
                fetchState = "error"
                fetchError = "Connection closed with no data"
            else
                fetchState = "done"
            end
        end
    end)

    -- Start the request
    print("Starting GET request...")
    local headerLines = {
        "Host: " .. server,
        "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language: en-US,en;q=0.9",
        "Connection: close"
    }
    -- local success, err = fetchConn:get(path, table.concat(headerLines, "\r\n"))
    local success, err = fetchConn:get(path)

    if not success then
        fetchState = "error"
        fetchError = err or "Request failed"
        print("GET request failed:", err)
        return
    end

    print("GET request queued successfully")
end

function renderContent()
    gfx.clear()

    if not pageImage then
        gfx.drawText(statusMessage or "Loading...", contentPadding, contentPadding)
        hoveredButton = nil
        return
    end

    local drawOffset = math.floor(scrollOffset + 0.5)
    pageImage:draw(0, -drawOffset)
    hoveredButton = nil

    for _, button in ipairs(pageButtons) do
        local screenY = contentPadding + button.y - drawOffset
        local buttonBottom = screenY + button.height

        if buttonBottom < -20 then
            goto continue
        end

        if screenY > 260 then
            break
        end

        local isSelected = (screenY <= selectionLineY) and (buttonBottom >= selectionLineY)
        drawButtonElement(button.label, contentPadding, screenY, isSelected)
        if isSelected then
            hoveredButton = button
        end

        ::continue::
    end
end

function playdate.update()
    -- Handle pending URL load
    if pendingURL then
        local url = pendingURL
        pendingURL = nil
        loadURL(url)
    end

    -- Handle fetch completion
    if fetchState == "done" then
        fetchState = nil
        statusMessage = "Parsing HTML..."

        if not fetchParser then
            statusMessage = "Error: Missing parser for content"
            currentContent = nil
        else
            print("Using parser:", fetchParser.name or "unknown")
            print("---- HTML START ----")
            print(fetchHTML)
            print("---- HTML END ----")
            local content, parseErr = fetchParser.parse(fetchHTML, fetchURL)
            if not content then
                statusMessage = "Error: " .. (parseErr or "Parse failed")
                currentContent = nil
                preparePageImage(nil)
            else
                currentContent = content
                currentURL = fetchURL
                statusMessage = "Loaded " .. #content .. " elements"
                scrollOffset = 0
                preparePageImage(currentContent)
            end
        end

        hoveredButton = nil

        -- Clean up
        fetchHTML = ""
        fetchURL = nil
        fetchParser = nil
    elseif fetchState == "error" then
        fetchState = nil
        statusMessage = "Error: " .. (fetchError or "Unknown error")
        currentContent = nil
        preparePageImage(nil)

        -- Clean up
        fetchHTML = ""
        fetchURL = nil
        fetchParser = nil
        fetchError = nil
    end

    renderContent()

    -- Handle input
    local crankChange = playdate.getCrankChange()
    if crankChange ~= 0 then
        scrollOffset += crankChange
        clampScroll()
    end

    -- Button controls
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        scrollOffset -= 20
        clampScroll()
    end

    if playdate.buttonJustPressed(playdate.kButtonDown) then
        scrollOffset += 20
        clampScroll()
    end

    -- Follow button under selection line
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if hoveredButton and hoveredButton.url then
            local targetURL = resolveURL(currentURL, hoveredButton.url)
            if targetURL then
                pendingURL = targetURL
                print("Following link:", targetURL)
            end
        end
    end
end

-- Enable networking and load page automatically
playdate.network.setEnabled(true, function(err)
    if err then
        print("Network error:", err)
        statusMessage = "Network error: " .. err
        networkReady = false
    else
        print("Network enabled")
        networkReady = true
        -- Load page immediately
        pendingURL = "https://www.cbc.ca/lite/news?sort=latest"
        print("Auto-loading URL:", pendingURL)
    end
end)
