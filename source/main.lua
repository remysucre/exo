-- exo: A web browser for Playdate
-- Main entry point

import "CoreLibs/graphics"
import "CoreLibs/ui"

local gfx <const> = playdate.graphics
local sites = import "sites"
local htmlparser = import "htmlparser"

-- State
local currentURL = nil
local currentContent = nil
local scrollOffset = 0
local statusMessage = "Connecting to WiFi..."
local pendingURL = nil  -- URL to load in next update

-- Network state
local networkReady = false

-- Fetch state (async networking)
local fetchState = nil  -- nil, "fetching", "done", "error"
local fetchConn = nil
local fetchHTML = ""
local fetchError = nil
local fetchURL = nil
local fetchSite = nil

-- Parse HTML using lua-htmlparser and extract content with CSS selectors
function parseHTML(html, selectors)
    -- Parse HTML
    local root = htmlparser.parse(html)
    if not root then
        return nil, "Failed to parse HTML"
    end

    -- Use the library's built-in selector support
    local results = {}

    for _, selector in ipairs(selectors) do
        -- Use library's select() method
        local elements = root:select(selector)

        if elements then
            for _, element in ipairs(elements) do
                -- Get text content
                local text = element:getcontent()
                if text and #text > 0 then
                    -- Strip extra whitespace
                    text = text:match("^%s*(.-)%s*$")

                    if #text > 0 then
                        table.insert(results, {
                            type = element.name and element.name:lower() or "unknown",
                            content = text
                        })
                    end
                end
            end
        end
    end

    -- Return results table directly (no JSON encoding needed)
    return results
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

    -- Find matching site configuration
    local matchedSite = nil
    for _, site in ipairs(sites) do
        if string.match(url, site.pattern) then
            matchedSite = site
            break
        end
    end

    if not matchedSite then
        statusMessage = "Error: No rules for this URL"
        currentContent = nil
        return
    end

    statusMessage = "Matched: " .. matchedSite.name

    -- Start async fetch
    fetchURL = url
    fetchSite = matchedSite
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

    -- Draw status bar
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, 400, 20)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText(statusMessage, 5, 4)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Draw content
    if not currentContent then
        gfx.drawText("No content loaded", 10, 30)
        gfx.drawText("Enter a URL to begin", 10, 50)
        return
    end

    local y = 30 - scrollOffset
    local lineHeight = 16

    for _, element in ipairs(currentContent) do
        if y > 20 and y < 240 then  -- Only draw visible elements
            local text = element.content

            -- Different styling based on element type
            if element.type == "h1" then
                gfx.setFont(gfx.getSystemFont(gfx.font.kVariantBold))
                lineHeight = 20
            elseif element.type == "h2" then
                gfx.setFont(gfx.getSystemFont(gfx.font.kVariantBold))
                lineHeight = 18
            elseif element.type == "h3" then
                gfx.setFont(gfx.getSystemFont(gfx.font.kVariantBold))
                lineHeight = 16
            else
                gfx.setFont(gfx.getSystemFont(gfx.font.kVariantNormal))
                lineHeight = 16
            end

            -- Word wrap text
            local maxWidth = 380
            local words = {}
            for word in string.gmatch(text, "%S+") do
                table.insert(words, word)
            end

            local line = ""
            for _, word in ipairs(words) do
                local testLine = line == "" and word or line .. " " .. word
                local textWidth = gfx.getTextSize(testLine)

                if textWidth > maxWidth then
                    if line ~= "" then
                        gfx.drawText(line, 10, y)
                        y += lineHeight
                        line = word
                    else
                        -- Single word is too long, draw it anyway
                        gfx.drawText(word, 10, y)
                        y += lineHeight
                        line = ""
                    end
                else
                    line = testLine
                end
            end

            if line ~= "" then
                gfx.drawText(line, 10, y)
                y += lineHeight
            end

            -- Add spacing after elements
            y += 4
        else
            -- Still need to calculate height even if not visible
            -- for accurate scrolling
            local text = element.content
            local maxWidth = 380
            local textWidth = gfx.getTextSize(text)
            local lines = math.ceil(textWidth / maxWidth)

            if element.type == "h1" then
                y += lines * 20 + 4
            elseif element.type == "h2" then
                y += lines * 18 + 4
            else
                y += lines * 16 + 4
            end
        end
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

        -- Parse HTML with CSS selectors (returns Lua table)
        local content, err = parseHTML(fetchHTML, fetchSite.selector)
        if not content then
            statusMessage = "Error: " .. (err or "Parse failed")
            currentContent = nil
        else
            currentContent = content
            currentURL = fetchURL
            statusMessage = "Loaded " .. #content .. " elements"
        end

        -- Clean up
        fetchHTML = ""
        fetchURL = nil
        fetchSite = nil
    elseif fetchState == "error" then
        fetchState = nil
        statusMessage = "Error: " .. (fetchError or "Unknown error")
        currentContent = nil

        -- Clean up
        fetchHTML = ""
        fetchURL = nil
        fetchSite = nil
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
end

-- Enable networking
playdate.network.setEnabled(true, function(err)
    if err then
        print("Network error:", err)
        statusMessage = "Network error: " .. err
        networkReady = false
    else
        print("Network enabled")
        networkReady = true
        statusMessage = "Network ready - Press A to load remy.wang"
    end
end)

-- Test URL - A button to fetch remy.wang
function playdate.AButtonDown()
    pendingURL = "https://remy.wang/index.html"
    statusMessage = "Queued: " .. pendingURL
    print("Loading URL:", pendingURL)
end
