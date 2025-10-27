-- Site configuration for exo web browser
-- Each entry defines a supported website with URL pattern matching and CSS selector extraction rules

sites = {
  -- Google
  {
    name = "Google",
    pattern = "^https?://google%.com/?$",
    selector = {"h1", "h2", "h3", "p", "a"}
  },

  -- HTTPBin HTML test page
  {
    name = "HTTPBin HTML",
    pattern = "^https?://httpbin%.org/html$",
    selector = {"h1", "p"}
  },

  -- CERN (first website)
  {
    name = "CERN Info",
    pattern = "^https?://info%.cern%.ch/.*",
    selector = {"h1", "h2", "p", "ul > li", "a"}
  },

  -- Test with example.com
  {
    name = "Example.com Test",
    pattern = "^https?://example%.com/?$",
    selector = {"h1", "p"}
  },

  -- CS Monitor Article Pages
  -- Pattern matches any article under /text_edition/
  -- More specific pattern comes first to match before the front page pattern
  {
    name = "CS Monitor Article",
    pattern = "^https?://www%.csmonitor%.com/text_edition/.*",
    selector = {"h1", "div[class*=\"story-bylines\"]", "article p", "article h2", "article h3"}
  },

  -- Remy's Homepage
  {
    name = "Remy's Homepage",
    pattern = "^https?://remy%.wang/.*",
    selector = {"h1", "p"}
  },

  -- Add more sites here following the same pattern
  -- {
  --   name = "Site Name",
  --   pattern = "^https://example%.com/path/.*",
  --   selector = {"h1", "h2", "p"}
  -- },
}

return sites
