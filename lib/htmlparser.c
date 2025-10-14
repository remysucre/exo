// HTML Parser for Playdate using libxml2
// Provides XPath-based content extraction

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libxml/HTMLparser.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include "pd_api.h"

static PlaydateAPI* pd = NULL;

// Clean up text content - remove extra whitespace, trim
static char* cleanText(const char* text) {
    if (!text) return NULL;

    // Allocate buffer
    size_t len = strlen(text);
    char* cleaned = malloc(len + 1);
    if (!cleaned) return NULL;

    // Remove leading/trailing whitespace and collapse internal whitespace
    int writePos = 0;
    int lastWasSpace = 1;  // Start as true to skip leading spaces

    for (size_t i = 0; i < len; i++) {
        char c = text[i];

        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (!lastWasSpace && writePos > 0) {
                cleaned[writePos++] = ' ';
                lastWasSpace = 1;
            }
        } else {
            cleaned[writePos++] = c;
            lastWasSpace = 0;
        }
    }

    // Remove trailing space
    if (writePos > 0 && cleaned[writePos - 1] == ' ') {
        writePos--;
    }

    cleaned[writePos] = '\0';

    return cleaned;
}

// Escape a string for JSON
static char* escapeJSON(const char* str) {
    if (!str) return NULL;

    size_t len = strlen(str);
    // Worst case: every char needs escaping (e.g., all quotes)
    char* escaped = malloc(len * 2 + 1);
    if (!escaped) return NULL;

    int writePos = 0;
    for (size_t i = 0; i < len; i++) {
        char c = str[i];
        if (c == '"' || c == '\\') {
            escaped[writePos++] = '\\';
            escaped[writePos++] = c;
        } else if (c == '\n') {
            escaped[writePos++] = '\\';
            escaped[writePos++] = 'n';
        } else if (c == '\r') {
            escaped[writePos++] = '\\';
            escaped[writePos++] = 'r';
        } else if (c == '\t') {
            escaped[writePos++] = '\\';
            escaped[writePos++] = 't';
        } else {
            escaped[writePos++] = c;
        }
    }
    escaped[writePos] = '\0';
    return escaped;
}

// parseHTML(html_string, xpath_query) -> JSON string or (nil, error)
static int parseHTML(lua_State* L) {
    // Get arguments
    const char* html = pd->lua->getArgString(1);
    const char* xpathQuery = pd->lua->getArgString(2);

    if (!html || !xpathQuery) {
        pd->lua->pushNil();
        pd->lua->pushString("Invalid arguments");
        return 2;
    }

    // Parse HTML
    htmlDocPtr doc = htmlReadMemory(html, strlen(html), NULL, NULL,
                                    HTML_PARSE_RECOVER | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING);

    if (!doc) {
        pd->lua->pushNil();
        pd->lua->pushString("Failed to parse HTML");
        return 2;
    }

    // Create XPath context
    xmlXPathContextPtr xpathCtx = xmlXPathNewContext(doc);
    if (!xpathCtx) {
        xmlFreeDoc(doc);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to create XPath context");
        return 2;
    }

    // Evaluate XPath
    xmlXPathObjectPtr xpathObj = xmlXPathEvalExpression((xmlChar*)xpathQuery, xpathCtx);
    if (!xpathObj) {
        xmlXPathFreeContext(xpathCtx);
        xmlFreeDoc(doc);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to evaluate XPath");
        return 2;
    }

    // Get the node set
    xmlNodeSetPtr nodes = xpathObj->nodesetval;
    int nodeCount = nodes ? nodes->nodeNr : 0;

    // Build JSON string
    // Start with reasonable buffer size
    size_t jsonSize = 4096;
    char* json = malloc(jsonSize);
    if (!json) {
        xmlXPathFreeObject(xpathObj);
        xmlXPathFreeContext(xpathCtx);
        xmlFreeDoc(doc);
        pd->lua->pushNil();
        pd->lua->pushString("Out of memory");
        return 2;
    }

    strcpy(json, "[");
    int jsonPos = 1;
    int itemCount = 0;

    // Process each node
    for (int i = 0; i < nodeCount; i++) {
        xmlNodePtr node = nodes->nodeTab[i];

        // Get node type (tag name)
        const char* nodeType = "text";
        if (node->type == XML_ELEMENT_NODE && node->name) {
            nodeType = (const char*)node->name;
        } else if (node->type == XML_TEXT_NODE || node->type == XML_CDATA_SECTION_NODE) {
            nodeType = "text";
        }

        // Get node content
        xmlChar* content = xmlNodeGetContent(node);
        if (!content) continue;

        // Clean the text
        char* cleanedContent = cleanText((const char*)content);
        xmlFree(content);

        if (!cleanedContent || strlen(cleanedContent) == 0) {
            if (cleanedContent) free(cleanedContent);
            continue;
        }

        // Escape for JSON
        char* escapedContent = escapeJSON(cleanedContent);
        free(cleanedContent);

        if (!escapedContent) continue;

        // Build JSON object: {"type":"h1","content":"..."}
        size_t needed = jsonPos + strlen(nodeType) + strlen(escapedContent) + 100;
        if (needed > jsonSize) {
            jsonSize = needed * 2;
            char* newJson = realloc(json, jsonSize);
            if (!newJson) {
                free(json);
                free(escapedContent);
                xmlXPathFreeObject(xpathObj);
                xmlXPathFreeContext(xpathCtx);
                xmlFreeDoc(doc);
                pd->lua->pushNil();
                pd->lua->pushString("Out of memory");
                return 2;
            }
            json = newJson;
        }

        if (itemCount > 0) {
            json[jsonPos++] = ',';
        }

        jsonPos += sprintf(json + jsonPos, "{\"type\":\"%s\",\"content\":\"%s\"}",
                          nodeType, escapedContent);

        free(escapedContent);
        itemCount++;
    }

    json[jsonPos++] = ']';
    json[jsonPos] = '\0';

    // Cleanup
    xmlXPathFreeObject(xpathObj);
    xmlXPathFreeContext(xpathCtx);
    xmlFreeDoc(doc);

    // Return JSON string
    pd->lua->pushString(json);
    free(json);

    return 1;
}

#ifdef _WINDLL
__declspec(dllexport)
#endif
int eventHandler(PlaydateAPI* playdate, PDSystemEvent event, uint32_t arg) {
    if (event == kEventInit) {
        pd = playdate;
        pd->system->logToConsole("HTML Parser extension initializing...");
    } else if (event == kEventInitLua) {
        // Register the parseHTML function after Lua is initialized
        const char* err;
        if (!pd->lua->addFunction(parseHTML, "parseHTML", &err)) {
            pd->system->logToConsole("Error registering parseHTML: %s", err);
            return 1;
        }

        pd->system->logToConsole("HTML Parser extension loaded");
    }

    return 0;
}
