-- exo: A web browser for Playdate
-- Main entry point

import "CoreLibs/graphics"
import "CoreLibs/ui"

local gfx <const> = playdate.graphics
local sites = import "sites"

-- State
local currentURL = nil
local currentContent = nil
local scrollOffset = 0
local statusMessage = "exo browser ready"
local pendingURL = nil  -- URL to load in next update

-- Load the parseHTML function from C extension
-- This will be registered by the C code
-- parseHTML(html_string, xpath_query) -> {{type="h1", content="..."}, ...}

function loadURL(url)
    statusMessage = "Loading: " .. url
    currentURL = url
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

    -- Fetch HTML content
    local html = fetchHTML(url)
    if not html then
        statusMessage = "Error: Failed to fetch page"
        currentContent = nil
        return
    end

    -- Parse HTML with XPath (returns JSON string)
    local jsonString, err = parseHTML(html, matchedSite.xpath)
    if not jsonString then
        statusMessage = "Error: " .. (err or "Parse failed")
        currentContent = nil
        return
    end

    -- Parse JSON
    local content = json.decode(jsonString)
    if not content then
        statusMessage = "Error: Failed to parse JSON"
        currentContent = nil
        return
    end

    currentContent = content
    statusMessage = "Loaded " .. #content .. " elements"
end

function fetchHTML(url)
    -- HTTP fetch using Playdate's networking API
    statusMessage = "Fetching HTML..."
    print("fetchHTML called with URL:", url)

    -- Parse URL to get server and path
    local server, path = string.match(url, "^https?://([^/]+)(.*)$")
    if not server then
        statusMessage = "Error: Invalid URL"
        print("Failed to parse URL")
        return nil
    end

    if path == "" then
        path = "/"
    end

    local useSSL = string.match(url, "^https://") ~= nil
    print("Server:", server, "Path:", path, "SSL:", useSSL)

    -- Create HTTP connection
    local conn = playdate.network.http.new(server, nil, useSSL, "exo browser needs to fetch web content")
    if not conn then
        statusMessage = "Error: Failed to create connection"
        print("Failed to create HTTP connection")
        return nil
    end

    print("HTTP connection created")

    conn:setConnectTimeout(10)
    conn:setReadTimeout(2)

    local html = ""
    local headersReceived = false
    local done = false

    -- Callback when headers are received
    conn:setHeadersReadCallback(function()
        print("Headers received")
        headersReceived = true
        local status = conn:getResponseStatus()
        print("Response status:", status)
        local headers = conn:getResponseHeaders()
        if headers then
            for k, v in pairs(headers) do
                print("Header:", k, "=", v)
            end
        end
    end)

    -- Callback when request is complete
    conn:setRequestCompleteCallback(function()
        print("Request complete callback")

        -- Read any remaining data
        while true do
            local available = conn:getBytesAvailable()
            if available == 0 then
                break
            end
            print("Reading remaining", available, "bytes")
            local data = conn:read(available)
            if data then
                print("Read", #data, "bytes")
                html = html .. data
            else
                break
            end
        end

        done = true
    end)

    conn:setConnectionClosedCallback(function()
        print("Connection closed callback")
        done = true
    end)

    -- Start the request
    print("Starting GET request...")
    local success, err = conn:get(path, {
        ["User-Agent"] = "exo-browser/1.0 (Playdate)"
    })

    if not success then
        statusMessage = "Error: " .. (err or "Request failed")
        print("GET request failed:", err)
        return nil
    end

    print("GET request queued successfully")

    -- Wait for completion
    local timeout = 30  -- 30 seconds
    local startTime = playdate.getCurrentTimeMilliseconds()

    while not done do
        local elapsed = (playdate.getCurrentTimeMilliseconds() - startTime) / 1000
        if elapsed > timeout then
            statusMessage = "Error: Request timeout"
            print("Request timed out after", elapsed, "seconds")
            conn:close()
            return nil
        end

        -- Read available data
        if headersReceived then
            local available = conn:getBytesAvailable()
            if available > 0 then
                print("Bytes available:", available)
                local data = conn:read(available)
                if data then
                    print("Read", #data, "bytes")
                    html = html .. data
                end
            end
        end

        -- Yield to allow callbacks to run
        coroutine.yield()
    end

    print("Request completed, closing connection")
    conn:close()

    -- Check for errors
    local connError = conn:getError()
    if connError then
        statusMessage = "Error: " .. connError
        print("Connection error:", connError)
        return nil
    end

    if #html == 0 then
        statusMessage = "Error: No data received"
        print("No data received from server")
        return nil
    end

    print("Successfully fetched", #html, "bytes")
    return html
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
    -- Handle pending URL load (can't do from button handler due to yield restrictions)
    if pendingURL then
        local url = pendingURL
        pendingURL = nil
        loadURL(url)
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

-- Test with a hardcoded URL for now
-- TODO: Add URL entry UI
statusMessage = "exo browser - Press A to load test page"

function playdate.AButtonDown()
    -- For testing: try a simple HTTP endpoint
    -- Can't call loadURL directly from button handler due to yield restrictions
    -- Using a simple test URL to verify networking works
    pendingURL = "http://example.com"
    statusMessage = "Queued URL for loading..."
end
