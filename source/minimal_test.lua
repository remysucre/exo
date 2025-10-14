-- Minimal reproducible example: Google.com returns no data on Playdate
-- This demonstrates that HTTP GET to google.com receives headers but no body data

-- State tracking
local testStarted = false
local testComplete = false
local dataReceived = false

-- HTTP connection
local httpConn = nil
local receivedData = ""
local startTime = playdate.getCurrentTimeMilliseconds()

function timeLog(text)
    local now = playdate.getCurrentTimeMilliseconds()
    local elapsed = now - startTime
    print(string.format("[%i ms] %s", elapsed, text))
end

function testGoogleFetch()
    if testStarted then return end
    testStarted = true

    timeLog("=== Testing example.com ===")
    timeLog("Starting HTTP GET...")

    local server = "google.com"
    local path = "/"
    local useSSL = true

    -- Create HTTP connection
    httpConn = playdate.network.http.new(server, nil, useSSL, "minimal test")
    if not httpConn then
        timeLog("ERROR: Failed to create HTTP connection")
        testComplete = true
        return
    end

    timeLog("HTTP connection created")

    httpConn:setConnectTimeout(10)
    httpConn:setReadTimeout(5)
    httpConn:setKeepAlive(true)  -- KEY: Enable keep-alive like the working example

    -- Headers callback
    httpConn:setHeadersReadCallback(function()
        timeLog("Headers received")
        local status = httpConn:getResponseStatus()
        timeLog("Response status: " .. tostring(status))

        local headers = httpConn:getResponseHeaders()
        if headers then
            timeLog("Response headers:")
            for k, v in pairs(headers) do
                timeLog("  " .. k .. ": " .. v)
            end
        end
    end)

    -- Data available callback (following working example pattern)
    httpConn:setRequestCallback(function()
        timeLog("requestCallback called")

        -- Show progress
        local current, total = httpConn:getProgress()
        timeLog(string.format("Progress: %i / %i", current, total))

        -- Check bytes available
        local bytes = httpConn:getBytesAvailable()
        timeLog(string.format("Bytes available: %i", bytes))

        if bytes > 0 then
            -- Read the data
            local data = httpConn:read(bytes)
            if data then
                timeLog(string.format("Read %i bytes", #data))
                receivedData = receivedData .. data
                timeLog(string.format("Total received: %i bytes", #receivedData))

                -- Show preview
                if #data > 0 then
                    local preview = string.sub(data, 1, math.min(100, #data))
                    timeLog("Data preview: " .. preview)
                end

                dataReceived = true  -- Set flag like working example
            else
                timeLog("read() returned nil")
            end
        end
    end)

    -- Request complete callback
    httpConn:setRequestCompleteCallback(function()
        timeLog("requestComplete called")
        local err = httpConn:getError()
        if err then
            timeLog("Error: " .. tostring(err))
            if err ~= "Connection closed" then
                testComplete = true
            end
        end
    end)

    -- Connection closed callback
    httpConn:setConnectionClosedCallback(function()
        timeLog("connectionClosed called")
    end)

    -- Start the GET request
    timeLog("Sending GET request to https://" .. server .. path)
    local success, err = httpConn:get(path, {
        ["User-Agent"] = "Mozilla/5.0 (compatible; Playdate)",
        ["Accept"] = "text/html,*/*"
    })

    if not success then
        timeLog("ERROR: GET request failed: " .. tostring(err))
        testComplete = true
        return
    end

    timeLog("GET request sent successfully")
end

function playdate.update()
    -- Follow working example pattern: check if data received, then close
    if dataReceived and not testComplete then
        timeLog("Data was received, closing connection")

        -- Print final results
        timeLog("=== FINAL RESULTS ===")
        timeLog("Total data received: " .. #receivedData .. " bytes")

        if #receivedData == 0 then
            timeLog("ISSUE: No body data received!")
        else
            timeLog("SUCCESS: Received data!")
            timeLog("First 200 chars:")
            timeLog(string.sub(receivedData, 1, math.min(200, #receivedData)))
        end

        -- Close connection like working example
        httpConn:close()
        testComplete = true
    end

    -- Wait if not complete yet
    if testStarted and not testComplete and not dataReceived then
        local err = httpConn and httpConn:getError()
        if err then
            timeLog("Waiting for data... Error: " .. tostring(err))
        end
    end
end

-- Enable networking and auto-start test
timeLog("Initializing network...")
playdate.network.setEnabled(true, function(err)
    if err then
        timeLog("Network error: " .. tostring(err))
    else
        timeLog("Network ready!")
        -- Automatically start the test
        testGoogleFetch()
    end
end)
