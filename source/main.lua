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
    regular = gfx.getSystemFont(gfx.font.kVariantNormal)
}
local defaultFontHeight = textFonts.regular and textFonts.regular:getHeight() or 16
local textLineHeight = math.max(defaultFontHeight, 16)

local function drawTextBlock(text, startX, startY, maxWidth)
    if not text or #text == 0 then
        return startY
    end

    gfx.setFont(textFonts.regular)
    local _, measuredHeight = gfx.getTextSizeForMaxWidth(text, maxWidth)
    local blockHeight = measuredHeight or textLineHeight
    gfx.drawText(text, startX, startY, maxWidth, blockHeight)

    return startY + blockHeight
end

local selectionIndicatorHeight = 2
local selectionLineY = 50
local linkHighlightPadding = 2

local function drawButtonElement(element, x, y, maxWidth)
    local font = textFonts.regular
    gfx.setFont(font)

    local label = element.label or element.content or "Link"
    local text = label
    local textWidth, textHeight = gfx.getTextSize(text)
    local buttonHeight = textHeight or textLineHeight

    local isSelected = (y <= selectionLineY) and ((y + buttonHeight) >= selectionLineY)

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

    local width, height = gfx.drawText(text, x, y)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    gfx.drawLine(x, y + buttonHeight + selectionIndicatorHeight, x + width, y + buttonHeight + selectionIndicatorHeight)

    return buttonHeight, isSelected
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
    local success, err = fetchConn:get(path, {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Accept-Language"] = "en-US,en;q=0.9"
    })

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

    -- Draw content
    if not currentContent then
        gfx.drawText(statusMessage or "Loading...", 10, 10)
        hoveredButton = nil
        return
    end

    local y = 10 - scrollOffset
    local contentLeft = 10
    local contentWidth = 380
    local selectedButton = nil

    for _, element in ipairs(currentContent) do
        if element.kind == "button" then
            local height, isSelected = drawButtonElement(element, contentLeft, y, contentWidth)
            if isSelected then
                selectedButton = element
            end
            y += height + 8
        else
            local text = element.content or ""
            y = drawTextBlock(text, contentLeft, y, contentWidth)
            y += 4
        end
    end

    hoveredButton = selectedButton
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
            local content, parseErr = fetchParser.parse(fetchHTML, fetchURL)
            if not content then
                statusMessage = "Error: " .. (parseErr or "Parse failed")
                currentContent = nil
            else
                currentContent = content
                currentURL = fetchURL
                statusMessage = "Loaded " .. #content .. " elements"
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
        if scrollOffset < 0 then
            scrollOffset = 0
        end
    end

    -- Button controls
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        scrollOffset -= 20
        if scrollOffset < 0 then
            scrollOffset = 0
        end
    end

    if playdate.buttonJustPressed(playdate.kButtonDown) then
        scrollOffset += 20
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
        pendingURL = "https://text.npr.org"
        print("Auto-loading URL:", pendingURL)
    end
end)
