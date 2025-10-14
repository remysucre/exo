-- Site configuration for exo web browser
-- Each entry defines a supported website with URL pattern matching and XPath extraction rules

sites = {
  -- Google
  {
    name = "Google",
    pattern = "^https?://google%.com/?$",
    xpath = "//h1 | //h2 | //h3 | //p | //a"
  },

  -- HTTPBin HTML test page
  {
    name = "HTTPBin HTML",
    pattern = "^https?://httpbin%.org/html$",
    xpath = "//h1 | //p"
  },

  -- CERN (first website)
  {
    name = "CERN Info",
    pattern = "^https?://info%.cern%.ch/?$",
    xpath = "//h1 | //h2 | //p | //ul/li | //a"
  },

  -- Test with example.com
  {
    name = "Example.com Test",
    pattern = "^https?://example%.com/?$",
    xpath = "//h1 | //p"
  },

  -- CS Monitor Article Pages
  -- Pattern matches any article under /text_edition/
  -- More specific pattern comes first to match before the front page pattern
  {
    name = "CS Monitor Article",
    pattern = "^https?://www%.csmonitor%.com/text_edition/.*",
    xpath = "//h1 | //div[contains(@class, 'story-bylines')]//text() | //article//p | //article//h2 | //article//h3"
  },

  -- CS Monitor Front Page
  -- Pattern matches exactly the text edition front page
  {
    name = "Remy's Homepage",
    pattern = "^https?://remy%.wang/.*",
    xpath = "//h1 | //p"
  },

  -- Add more sites here following the same pattern
  -- {
  --   name = "Site Name",
  --   pattern = "^https://example%.com/path/.*",
  --   xpath = "//h1 | //h2 | //p"
  -- },
}

return sites
