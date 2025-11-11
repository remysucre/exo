-- exo: A web browser for Playdate
-- Main entry point

import "CoreLibs/graphics"
import "CoreLibs/ui"
import "CoreLibs/sprites"

local gfx <const> = playdate.graphics
local sprite <const> = gfx.sprite
local siteParsers = import "siteparsers"

-- State
local currentURL = nil
local currentContent = nil
local scrollOffset = 0
local statusMessage = "Connecting to WiFi..."
local pendingURL = nil  -- URL to load in next update

local pageImage = nil
local pageHeight = 0
local linkSprites = {}
local cursorSprite = nil
local cursorSize = 8
local cursorPosition = { x = 200, y = 120 }
local cursorSpeed = 3
local hoveredLinkSprite = nil
local linkHighlightPadding = 2

-- Network state
local networkReady = false

-- Fetch state (async networking)
local fetchState = nil  -- nil, "fetching", "done", "error"
local fetchConn = nil
local fetchHTML = ""
local fetchError = nil
local fetchURL = nil
local fetchParser = nil
local historyStack = {}
local navigatingBack = false

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

local function clearLinkSprites()
    for _, spr in ipairs(linkSprites) do
        spr:remove()
    end
    linkSprites = {}
    hoveredLinkSprite = nil
end

local function ensureCursorSprite()
    if cursorSprite then
        return
    end

    cursorSprite = sprite.new()
    cursorSprite:setSize(cursorSize, cursorSize)
    cursorSprite:setCenter(0.5, 0.5)
    cursorSprite:setCollideRect(0, 0, cursorSize, cursorSize)
    cursorSprite.isHoveringLink = false
    function cursorSprite:draw(x, y, w, h)
        if self.isHoveringLink then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, 0, w, h)
            gfx.setColor(gfx.kColorWhite)
            gfx.drawRect(0, 0, w, h)
            gfx.setColor(gfx.kColorBlack)
        else
            gfx.drawRect(0, 0, w, h)
        end
    end
    cursorSprite:setZIndex(1000)
    cursorSprite:add()
    cursorSprite:moveTo(cursorPosition.x, cursorPosition.y)
end

ensureCursorSprite()

local function moveCursor(dx, dy)
    if not cursorSprite then
        return
    end
    if dx == 0 and dy == 0 then
        return
    end

    cursorPosition.x = cursorPosition.x + dx
    cursorPosition.y = cursorPosition.y + dy

    local halfSize = cursorSize / 2
    cursorPosition.x = math.max(halfSize, math.min(400 - halfSize, cursorPosition.x))
    cursorPosition.y = math.max(halfSize, math.min(240 - halfSize, cursorPosition.y))
    cursorSprite:moveTo(cursorPosition.x, cursorPosition.y)
end

local function attachLinkSprite(x, y, width, height, url)
    if not url or #url == 0 then
        return
    end

    local spr = sprite.new()
    spr:setSize(width, height)
    spr:setCenter(0, 0)
    spr:setCollideRect(0, 0, width, height)
    spr.pageX = x
    spr.pageY = y
    spr.wordWidth = width
    spr.wordHeight = height
    spr.linkURL = url
    function spr:draw() end
    spr:setZIndex(-10)
    spr:add()
    table.insert(linkSprites, spr)
end

local function updateLinkSpritePositions(drawOffset)
    for _, spr in ipairs(linkSprites) do
        local screenY = spr.pageY - drawOffset
        spr:moveTo(
            spr.pageX + spr.wordWidth / 2,
            screenY + spr.wordHeight / 2
        )
    end
end

local function tokenizeText(text)
    local tokens = {}
    if not text then
        return tokens
    end

    local len = #text
    local i = 1
    while i <= len do
        local char = text:sub(i, i)
        if char:match("%s") then
            local j = i
            while j <= len and text:sub(j, j):match("%s") do
                j = j + 1
            end
            table.insert(tokens, {
                type = "space",
                value = text:sub(i, j - 1)
            })
            i = j
        else
            local j = i
            while j <= len and not text:sub(j, j):match("%s") do
                j = j + 1
            end
            table.insert(tokens, {
                type = "word",
                value = text:sub(i, j - 1)
            })
            i = j
        end
    end

    return tokens
end

local function markSkippableSpaces(tokens)
    for idx, token in ipairs(tokens) do
        if token.type == "space" then
            local prev = tokens[idx - 1]
            local nextToken = tokens[idx + 1]
            if prev and prev.type == "word" then
                local prevLower = prev.value:lower()
                if prevLower == "<a" or prevLower:match("^href=") then
                    token.skip = true
                end
            end
            if nextToken and nextToken.type == "word" and nextToken.value:lower() == "</a>" then
                token.skip = true
            end
        end
    end
end

local function extractHrefValue(word)
    return word:match("href%s*=%s*\"([^\"]+)\"")
        or word:match("href%s*=%s*'([^']+)'")
        or word:match("href%s*=%s*([^%s>]+)")
end

local function layoutTextBlock(text, startY, words)
    if not text or #text == 0 then
        return startY
    end

    local tokens = tokenizeText(text)
    if #tokens == 0 then
        return startY
    end

    markSkippableSpaces(tokens)

    local lineX = 0
    local lineY = startY
    local linkActive = false
    local currentLink = nil
    local blockBottom = lineY + textLineHeight

    for _, token in ipairs(tokens) do
        if token.type == "word" then
            local lowerValue = token.value:lower()
            if lowerValue == "<a" then
                linkActive = true
                currentLink = nil
            elseif lowerValue == "</a>" then
                linkActive = false
                currentLink = nil
            elseif linkActive and not currentLink and lowerValue:match("^href=") then
                currentLink = extractHrefValue(token.value)
            else
                local wordWidth = gfx.getTextSize(token.value)
                if lineX > 0 and lineX + wordWidth > contentWidth then
                    lineX = 0
                    lineY = lineY + textLineHeight
                end

                table.insert(words, {
                    text = token.value,
                    x = lineX,
                    y = lineY,
                    width = wordWidth,
                    height = textLineHeight,
                    link = (linkActive and currentLink) or nil
                })

                lineX = lineX + wordWidth
            end
        elseif not token.skip then
            local whitespace = token.value
            local newlineCount = 0
            whitespace = whitespace:gsub("\n", function()
                newlineCount = newlineCount + 1
                return ""
            end)

            if newlineCount > 0 then
                lineX = 0
                lineY = lineY + textLineHeight * newlineCount
            end

            local spaceCount = #whitespace
            if spaceCount > 0 then
                local spaceWidth = gfx.getTextSize(" ")
                for _ = 1, spaceCount do
                    if lineX + spaceWidth > contentWidth then
                        lineX = 0
                        lineY = lineY + textLineHeight
                    end
                    lineX = lineX + spaceWidth
                end
            end
        end

    end

    blockBottom = math.max(blockBottom, lineY + textLineHeight)
    return blockBottom
end
local function preparePageImage(elements)
    pageImage = nil
    pageHeight = 0
    clearLinkSprites()

    if not elements or #elements == 0 then
        statusMessage = "Loading..."
        return
    end

    gfx.setFont(textFonts.regular)

    local layout = {
        words = {},
        buttons = {}
    }
    local currentY = 0

    for _, element in ipairs(elements) do
        if element.kind == "spacer" then
            currentY = currentY + (element.size or paragraphSpacing)
        elseif element.kind == "button" then
            local label = element.label or element.content or "Link"
            local _, textHeight = gfx.getTextSize(label)
            local buttonHeight = (textHeight or textLineHeight) + linkHighlightPadding * 2
            table.insert(layout.buttons, {
                label = label,
                url = element.url,
                y = currentY,
                height = buttonHeight
            })
            currentY = currentY + buttonHeight + buttonSpacing
        else
            local text = element.content or ""
            local blockBottom = layoutTextBlock(text, currentY, layout.words)
            currentY = blockBottom + paragraphSpacing
        end
    end

    local contentHeight = math.max(currentY, (240 - contentPadding * 2))
    local imageHeight = contentHeight + contentPadding * 2
    local imageWidth = contentWidth + contentPadding * 2

    local image = gfx.image.new(imageWidth, imageHeight)
    gfx.lockFocus(image)
    gfx.clear(gfx.kColorWhite)
    gfx.setFont(textFonts.regular)

    for _, word in ipairs(layout.words) do
        local drawX = contentPadding + word.x
        local drawY = contentPadding + word.y

        if word.link then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(drawX - 1, drawY, word.width + 2, word.height)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        gfx.drawText(word.text, drawX, drawY)

        if word.link then
            attachLinkSprite(drawX - 1, drawY, word.width + 2, word.height, word.link)
        end
    end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    for _, button in ipairs(layout.buttons) do
        local label = button.label or "Link"
        local textWidth, _ = gfx.getTextSize(label)
        local buttonWidth = math.min(textWidth or contentWidth, contentWidth)
        local drawX = contentPadding
        local drawY = contentPadding + button.y
        local height = button.height

        gfx.setColor(gfx.kColorBlack)
        gfx.fillRoundRect(drawX - linkHighlightPadding, drawY, buttonWidth + linkHighlightPadding * 2, height, 4)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(label, drawX, drawY + linkHighlightPadding)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)

        attachLinkSprite(drawX - linkHighlightPadding, drawY, buttonWidth + linkHighlightPadding * 2, height, button.url)
    end

    gfx.unlockFocus()
    gfx.setColor(gfx.kColorBlack)

    pageImage = image
    pageHeight = imageHeight
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
    statusMessage = "Loading..."
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
        clearLinkSprites()
        return
    end

    local drawOffset = math.floor(scrollOffset + 0.5)
    pageImage:draw(0, -drawOffset)
    updateLinkSpritePositions(drawOffset)
end

gfx.sprite.setBackgroundDrawingCallback(function()
    renderContent()
end)

local function refreshHoveredLink()
    hoveredLinkSprite = nil
    if not cursorSprite then
        return
    end

    local overlapping = cursorSprite:overlappingSprites()
    for _, spr in ipairs(overlapping) do
        if spr.linkURL then
            hoveredLinkSprite = spr
            break
        end
    end

    cursorSprite.isHoveringLink = hoveredLinkSprite ~= nil
end

local function handleCursorInput()
    local dx, dy = 0, 0
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        dx = dx - cursorSpeed
    end
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        dx = dx + cursorSpeed
    end
    if playdate.buttonIsPressed(playdate.kButtonUp) then
        dy = dy - cursorSpeed
    end
    if playdate.buttonIsPressed(playdate.kButtonDown) then
        dy = dy + cursorSpeed
    end

    if dx ~= 0 or dy ~= 0 then
        moveCursor(dx, dy)
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
                if currentURL and currentURL ~= fetchURL and not navigatingBack then
                    table.insert(historyStack, currentURL)
                end
                currentContent = content
                currentURL = fetchURL
                navigatingBack = false
                statusMessage = "Loaded " .. #content .. " elements"
                scrollOffset = 0
                preparePageImage(currentContent)
            end
        end

        hoveredLinkSprite = nil

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
        navigatingBack = false
    end

    handleCursorInput()
    refreshHoveredLink()

    -- Handle input
    local crankChange = playdate.getCrankChange()
    if crankChange ~= 0 then
        scrollOffset = scrollOffset + crankChange
        clampScroll()
    end

    if playdate.buttonJustPressed(playdate.kButtonB) then
        if #historyStack > 0 then
            local previousURL = table.remove(historyStack)
            pageImage = nil
            navigatingBack = true
            statusMessage = "Loading previous page..."
            pendingURL = previousURL
        else
            statusMessage = "No previous page"
        end
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        if hoveredLinkSprite and hoveredLinkSprite.linkURL then
            local targetURL = resolveURL(currentURL, hoveredLinkSprite.linkURL)
            if targetURL then
                pageImage = nil
                statusMessage = "Loading..."
                pendingURL = targetURL
                print("Following link:", targetURL)
            end
        end
    end

    gfx.sprite.redrawBackground()
    gfx.sprite.update()
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
