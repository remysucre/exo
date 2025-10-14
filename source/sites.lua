-- Site configuration for exo web browser
-- Each entry defines a supported website with URL pattern matching and XPath extraction rules

sites = {
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
    name = "CS Monitor Front Page",
    pattern = "^https?://www%.csmonitor%.com/text_edition$",
    xpath = "//h2 | //a[contains(@href, 'text_edition')] | //p"
  },

  -- Add more sites here following the same pattern
  -- {
  --   name = "Site Name",
  --   pattern = "^https://example%.com/path/.*",
  --   xpath = "//h1 | //h2 | //p"
  -- },
}

return sites
