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
        :gsub("—", "-")

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

local function addText(elements, text)
    if text and #text > 0 then
        table.insert(elements, {
            kind = "text",
            content = text
        })
    end
end

local function addSpacer(elements, size)
    table.insert(elements, {
        kind = "spacer",
        size = size or 8
    })
end

local function addButton(elements, label, url)
    if label and #label > 0 and url and #url > 0 then
        table.insert(elements, {
            kind = "button",
            label = label,
            url = url
        })
    end
end

local function parseNPRText(html)
    local root = htmlparser.parse(html)
    if not root then
        return nil, "Failed to parse HTML"
    end

    local elements = {}

    local headingNodes = root:select(".topic-heading")
    if (not headingNodes or not headingNodes[1]) then
        headingNodes = root:select("h1")
    end
    if headingNodes and headingNodes[1] then
        local headingText = extractText(headingNodes[1])
        if headingText then
            addText(elements, "*" .. headingText .. "*")
        end
    end

    local dateNodes = root:select(".topic-date")
    if dateNodes and dateNodes[1] then
        local dateText = extractText(dateNodes[1])
        if dateText then
            addText(elements, "_" .. dateText .. "_")
            addSpacer(elements, 8)
        end
    end

    local listLinks = root:select(".topic-container li a")
    if listLinks then
        for _, link in ipairs(listLinks) do
            local headline = extractText(link)
            if headline then
                addText(elements, headline)
                addButton(elements, "Read more", link.attributes and link.attributes.href)
                addSpacer(elements, 8)
            end
        end
    end

    if #elements == 0 then
        return nil, "No recognizable content"
    end

    return elements
end

return {
    {
        name = "NPR Text",
        pattern = "https://remy.wang/npr/index.html",
        parse = parseNPRText
    }
}
