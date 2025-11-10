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

local function parseNPRArticle(html)
    local root = htmlparser.parse(html)
    if not root then
        return nil, "Failed to parse HTML"
    end

    local elements = {}
    local container = root:select("article .story-container")[1] or root

    local titleNode = container:select(".story-title")[1] or container:select("h1")[1]
    if titleNode then
        local titleText = extractText(titleNode)
        if titleText then
            addText(elements, "*" .. titleText .. "*")
        end
    end

    local metaNodes = container:select(".story-head p")
    if metaNodes then
        for _, node in ipairs(metaNodes) do
            local text = extractText(node)
            if text and #text > 0 then
                addText(elements, text)
            end
        end
    end

    addSpacer(elements, 10)

    local paragraphs = container:select(".paragraphs-container p")
    if paragraphs then
        for _, p in ipairs(paragraphs) do
            local htmlText = p:gettext()
            if htmlText then
                htmlText = htmlText:gsub("<a[^>]*>(.-)</a>", "%1")
                htmlText = htmlText:gsub("<[^>]+>", "")
                local cleaned = cleanText(htmlText)
                if cleaned then
                    addText(elements, cleaned)
                end
            end
        end
    end

    if #elements == 0 then
        return nil, "No recognizable content"
    end

    return elements
end

local function parseCBCLiteArticle(html)
    local root = htmlparser.parse(html)
    if not root then
        return nil, "Failed to parse HTML"
    end

    local article = root:select("article#article")[1] or root:select("article")[1]
    if not article then
        return nil, "No article element"
    end

    local elements = {}

    local titleNode = article:select("h1, h2")[1]
    if titleNode then
        local titleText = extractText(titleNode)
        if titleText then
            addText(elements, "_" .. titleText .. "_")
        end
    end

    local usedParagraphs = {}
    local metaNodes = article:select("> p")
    if metaNodes then
        for index, node in ipairs(metaNodes) do
            local text = extractText(node)
            if text and #text > 0 then
                addText(elements, text)
                usedParagraphs[node] = true
            end
            if index >= 2 then
                break
            end
        end
    end

    addSpacer(elements, 8)

    local segmentNodes = article:select("div.article_segment__aglub p")
    local paragraphNodes = {}

    if segmentNodes then
        for _, p in ipairs(segmentNodes) do
            table.insert(paragraphNodes, p)
        end
    else
        paragraphNodes = article:select("p") or {}
    end
    if paragraphNodes then
        for _, p in ipairs(paragraphNodes) do
            local class = p.attributes and p.attributes.class or ""
            if not usedParagraphs[p] and not class:match("embed") and not class:match("related") then
                local htmlText = p:gettext()
                if htmlText then
                    htmlText = htmlText:gsub("<a[^>]*>(.-)</a>", "%1")
                    htmlText = htmlText:gsub("<[^>]+>", "")
                    local cleaned = cleanText(htmlText)
                    if cleaned and #cleaned > 0 then
                        addText(elements, cleaned)
                    end
                end
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
        name = "NPR frontpage",
        pattern = "^https?://text%.npr%.org/?$",
        parse = parseNPRText
    },
    {
        name = "NPR articles",
        pattern = "^https?://text%.npr%.org/nx.*",
        parse = parseNPRArticle
    },
    {
        name = "CBC Lite Article",
        pattern = "^https?://www.cbc.ca/lite/story/9.6972932",
        parse = parseCBCLiteArticle
    }
}
