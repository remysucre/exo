local htmlparser = import "htmlparser"

local entityMap = {
    ["&nbsp;"] = " ",
    ["&amp;"] = "&",
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&quot;"] = "\"",
    ["&#39;"] = "'"
}

local function decodeNumericEntity(entity)
    local hex = entity:match("^&#x([0-9a-fA-F]+);?$")
    if hex then
        return utf8.char(tonumber(hex, 16))
    end

    local decimal = entity:match("^&#(%d+);?$")
    if decimal then
        return utf8.char(tonumber(decimal))
    end

    return entity
end

local function cleanText(text)
    if not text then
        return nil
    end

    local cleaned = text
        :gsub("\r\n", "\n")
        :gsub("\t", " ")
        :gsub("\n+", " ")

    cleaned = cleaned:gsub("&[#%w]+;", function(entity)
        if entityMap[entity] then
            return entityMap[entity]
        end
        return decodeNumericEntity(entity) or entity
    end)

    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:match("^%s*(.-)%s*$")

    if cleaned and #cleaned > 0 then
        return cleaned
    end

    return nil
end

local function extractText(node)
    if not node then
        return nil
    end

    if node.getcontent then
        local ok, content = pcall(function()
            return node:getcontent()
        end)
        if ok and content and #content > 0 then
            local cleaned = cleanText(content)
            if cleaned then
                return cleaned
            end
        end
    end

    if node.gettext then
        local ok, raw = pcall(function()
            return node:gettext()
        end)
        if ok and raw and #raw > 0 then
            raw = raw:gsub("<[^>]+>", "")
            return cleanText(raw)
        end
    end

    return nil
end

local function createTextElement(text)
    return {
        kind = "text",
        content = text
    }
end

local function createButtonElement(label, url)
    return {
        kind = "button",
        label = label,
        url = url
    }
end

local function extend(target, items)
    if not target or not items then
        return target
    end

    for _, item in ipairs(items) do
        table.insert(target, item)
    end

    return target
end

local function collectText(root, selectors)
    local elements = {}
    if not selectors then
        return elements
    end

    for _, selector in ipairs(selectors) do
        local nodes = root:select(selector)
        if nodes then
            for _, node in ipairs(nodes) do
                local text = extractText(node)
                if text then
                    table.insert(elements, createTextElement(text))
                end
            end
        end
    end

    return elements
end

local function collectButtons(root, selectors)
    local buttons = {}
    if not selectors then
        return buttons
    end

    for _, selector in ipairs(selectors) do
        local nodes = root:select(selector)
        if nodes then
            for _, node in ipairs(nodes) do
                local label = extractText(node)
                local href = node.attributes and node.attributes.href
                if label and href and #label > 0 then
                    table.insert(buttons, createButtonElement(label, href))
                end
            end
        end
    end

    return buttons
end

local function parserWithSelectors(config)
    return {
        name = config.name,
        pattern = config.pattern,
        parse = function(html)
            local root = htmlparser.parse(html)
            if not root then
                return nil, "Failed to parse HTML"
            end

            local elements = {}
            extend(elements, collectText(root, config.text))
            extend(elements, collectButtons(root, config.buttons))

            if config.custom then
                config.custom(root, elements, {
                    createTextElement = createTextElement,
                    createButtonElement = createButtonElement,
                    extend = extend,
                    extractText = extractText
                })
            end

            if #elements == 0 then
                return nil, "No recognizable content"
            end

            return elements
        end
    }
end

local siteConfigs = {
    {
        name = "Google",
        pattern = "^https?://google%.com/?$",
        text = {"h1", "h2", "h3", "p"},
        buttons = {"a"}
    },
    {
        name = "HTTPBin HTML",
        pattern = "^https?://httpbin%.org/html$",
        text = {"h1", "p"},
        buttons = {"a"}
    },
    {
        name = "CERN Info",
        pattern = "^https?://info%.cern%.ch/.*",
        text = {"h1", "h2", "p", "ul > li"},
        buttons = {"a"}
    },
    {
        name = "Example.com",
        pattern = "^https?://example%.com/?$",
        text = {"h1", "p"},
        buttons = {"a"}
    },
    {
        name = "CS Monitor Article",
        pattern = "^https?://www%.csmonitor%.com/text_edition/.*",
        text = {
            "h1",
            "div[class*=\"story-bylines\"]",
            "article h2",
            "article h3",
            "article p"
        },
        buttons = {"article a"}
    },
    {
        name = "Remy's Homepage",
        pattern = "^https?://remy%.wang/.*",
        text = {"h1", "p"},
        buttons = {"a"}
    }
}

local siteParsers = {}
for _, config in ipairs(siteConfigs) do
    table.insert(siteParsers, parserWithSelectors(config))
end

return siteParsers
