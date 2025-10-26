// HTML Parser for Playdate using lexbor
// Provides CSS selector-based content extraction

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lexbor/html/html.h>
#include <lexbor/css/css.h>
#include <lexbor/selectors/selectors.h>

#include "pd_api.h"

static PlaydateAPI* pd = NULL;

// Structure to collect results from selector callbacks
typedef struct {
    char* json;
    size_t size;
    size_t capacity;
    int itemCount;
} ResultCollector;

// Initialize result collector
static ResultCollector* resultCollectorCreate() {
    ResultCollector* collector = malloc(sizeof(ResultCollector));
    if (!collector) return NULL;

    collector->capacity = 4096;
    collector->json = malloc(collector->capacity);
    if (!collector->json) {
        free(collector);
        return NULL;
    }

    strcpy(collector->json, "[");
    collector->size = 1;
    collector->itemCount = 0;

    return collector;
}

// Append to result collector, growing buffer if needed
static int resultCollectorAppend(ResultCollector* collector, const char* str) {
    size_t len = strlen(str);
    size_t needed = collector->size + len + 1;

    if (needed > collector->capacity) {
        size_t newCapacity = collector->capacity * 2;
        while (newCapacity < needed) {
            newCapacity *= 2;
        }

        char* newJson = realloc(collector->json, newCapacity);
        if (!newJson) return 0;

        collector->json = newJson;
        collector->capacity = newCapacity;
    }

    strcpy(collector->json + collector->size, str);
    collector->size += len;

    return 1;
}

// Free result collector
static void resultCollectorDestroy(ResultCollector* collector) {
    if (collector) {
        if (collector->json) free(collector->json);
        free(collector);
    }
}

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

// Callback for lexbor selector results
static lxb_status_t selectorCallback(lxb_dom_node_t *node, lxb_css_selector_specificity_t spec, void *ctx) {
    ResultCollector* collector = (ResultCollector*)ctx;

    // Get node type (tag name)
    const char* nodeType = "text";
    if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
        lxb_dom_element_t* element = lxb_dom_interface_element(node);
        const lxb_char_t* tagName = lxb_dom_element_local_name(element, NULL);
        if (tagName) {
            nodeType = (const char*)tagName;
        }
    }

    // Get node text content
    size_t contentLen = 0;
    lxb_char_t* content = lxb_dom_node_text_content(node, &contentLen);
    if (!content || contentLen == 0) {
        if (content) lxb_dom_document_destroy_text(node->owner_document, content);
        return LXB_STATUS_OK;
    }

    // Clean the text
    char* cleanedContent = cleanText((const char*)content);
    lxb_dom_document_destroy_text(node->owner_document, content);

    if (!cleanedContent || strlen(cleanedContent) == 0) {
        if (cleanedContent) free(cleanedContent);
        return LXB_STATUS_OK;
    }

    // Escape for JSON
    char* escapedContent = escapeJSON(cleanedContent);
    free(cleanedContent);

    if (!escapedContent) {
        return LXB_STATUS_OK;
    }

    // Build JSON object: {"type":"h1","content":"..."}
    char buffer[256];
    if (collector->itemCount > 0) {
        resultCollectorAppend(collector, ",");
    }

    snprintf(buffer, sizeof(buffer), "{\"type\":\"%s\",\"content\":\"", nodeType);
    resultCollectorAppend(collector, buffer);
    resultCollectorAppend(collector, escapedContent);
    resultCollectorAppend(collector, "\"}");

    free(escapedContent);
    collector->itemCount++;

    return LXB_STATUS_OK;
}

// parseHTML(html_string, css_selector) -> JSON string or (nil, error)
static int parseHTML(lua_State* L) {
    // Get arguments
    const char* html = pd->lua->getArgString(1);
    const char* cssSelector = pd->lua->getArgString(2);

    if (!html || !cssSelector) {
        pd->lua->pushNil();
        pd->lua->pushString("Invalid arguments");
        return 2;
    }

    // Create HTML document
    lxb_html_document_t* document = lxb_html_document_create();
    if (!document) {
        pd->lua->pushNil();
        pd->lua->pushString("Failed to create document");
        return 2;
    }

    // Parse HTML
    lxb_status_t status = lxb_html_document_parse(document,
                                                    (const lxb_char_t*)html,
                                                    strlen(html));
    if (status != LXB_STATUS_OK) {
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to parse HTML");
        return 2;
    }

    // Create CSS parser
    lxb_css_parser_t* parser = lxb_css_parser_create();
    if (!parser) {
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to create CSS parser");
        return 2;
    }

    status = lxb_css_parser_init(parser, NULL);
    if (status != LXB_STATUS_OK) {
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to initialize CSS parser");
        return 2;
    }

    // Create selector engine
    lxb_selectors_t* selectors = lxb_selectors_create();
    if (!selectors) {
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to create selectors");
        return 2;
    }

    status = lxb_selectors_init(selectors);
    if (status != LXB_STATUS_OK) {
        lxb_selectors_destroy(selectors, true);
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to initialize selectors");
        return 2;
    }

    // Parse CSS selector
    lxb_css_selector_list_t* list = lxb_css_selectors_parse(parser,
                                                              (const lxb_char_t*)cssSelector,
                                                              strlen(cssSelector));
    if (!list) {
        lxb_selectors_destroy(selectors, true);
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to parse CSS selector");
        return 2;
    }

    // Create result collector
    ResultCollector* collector = resultCollectorCreate();
    if (!collector) {
        lxb_selectors_destroy(selectors, true);
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        pd->lua->pushNil();
        pd->lua->pushString("Out of memory");
        return 2;
    }

    // Find matching nodes
    lxb_dom_node_t* body = lxb_dom_interface_node(lxb_html_document_body_element(document));
    status = lxb_selectors_find(selectors, body, list, selectorCallback, collector);

    // Close JSON array
    resultCollectorAppend(collector, "]");

    // Cleanup
    lxb_selectors_destroy(selectors, true);
    lxb_css_parser_destroy(parser, true);
    lxb_html_document_destroy(document);

    if (status != LXB_STATUS_OK) {
        resultCollectorDestroy(collector);
        pd->lua->pushNil();
        pd->lua->pushString("Failed to find elements");
        return 2;
    }

    // Return JSON string
    pd->lua->pushString(collector->json);
    resultCollectorDestroy(collector);

    return 1;
}

#ifdef _WINDLL
__declspec(dllexport)
#endif
int eventHandler(PlaydateAPI* playdate, PDSystemEvent event, uint32_t arg) {
    if (event == kEventInit) {
        pd = playdate;
        pd->system->logToConsole("HTML Parser extension (lexbor) initializing...");
    } else if (event == kEventInitLua) {
        // Register the parseHTML function after Lua is initialized
        const char* err;
        if (!pd->lua->addFunction(parseHTML, "parseHTML", &err)) {
            pd->system->logToConsole("Error registering parseHTML: %s", err);
            return 1;
        }

        pd->system->logToConsole("HTML Parser extension (lexbor) loaded");
    }

    return 0;
}
