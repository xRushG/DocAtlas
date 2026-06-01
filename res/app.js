let pages = [];
let APPCONFIG;
let miniSearch;
let lastQuery   = '';
let lastResults = [];

/*
  Global configuration.
  Everything that may change between installations should live here.
*/
const CONFIG = {
  dom: {
    sidebar: "da-sidebar-div",
    logo: "da-logo-div",
    homeButton: "da-home-btn",
    searchBox: "da-searchBox-ipt",
    themeToggle: "da-themeToggle-btn",
    content: "da-content-div"
  },

  theme: {
    default: "light",
    storageKey: "theme"
  },

  fallback: {
    style: "assets/default.style.css"
  }
};

/** Fetches app.json and stores the result in the global APPCONFIG variable. */
async function loadConfig() {
  const res = await fetch("app.json");
  if (!res.ok) throw new Error("app.json not found");
  APPCONFIG = await res.json();
}

/* --------------------------------------------------
   Utility functions
-------------------------------------------------- */

/* Create URL friendly slugs from headings */
function createSlug(text) {
  return text.toLowerCase()
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}



/* --------------------------------------------------
   Theme handling
-------------------------------------------------- */

/** Returns the currently active theme name, falling back to the configured default. */
function getTheme() {
  return localStorage.getItem(CONFIG.theme.storageKey) || CONFIG.theme.default;
}

/** Sets the browser tab title from APPCONFIG, defaulting to "DocAtlas" when unconfigured. */
function setPageTitle() {
  let pageTitle = APPCONFIG?.page?.title;

  if (!pageTitle || pageTitle.trim() === "") {
    pageTitle = "DocAtlas";
  }

  document.title = pageTitle;
}

/**
 * Applies the given theme to the document, persists it in localStorage,
 * and refreshes the logo and toggle icon to match.
 */
function setTheme(theme) {

  document.body.classList.remove("light", "dark");
  document.body.classList.add(theme);

  localStorage.setItem(CONFIG.theme.storageKey, theme);

  loadLogo();
  updateToggleIcon();
}

/** Updates the theme-toggle button's icon to reflect the current theme. */
function updateToggleIcon() {

  const btn = document.getElementById(CONFIG.dom.themeToggle);
  if (!btn) return;

  const theme = getTheme();
  btn.textContent = theme === "dark" ? "☀️" : "🌙";
}


/* --------------------------------------------------
   Design loading
-------------------------------------------------- */

/* Loads the logo depending on the active theme */
function loadLogo() {

  const logoDiv = document.getElementById(CONFIG.dom.logo);
  if (!logoDiv) return;
  if (!APPCONFIG.logo?.enabled) {
    console.warn("[Config] Logo disabled.");
    logoDiv.style.display = "none";
    return;
  }

  const theme = getTheme();
  const logoPath = APPCONFIG.logo[theme];

  logoDiv.innerHTML = "";

  const img = document.createElement("img");
  img.src = logoPath;

  img.onerror = () => {
    console.warn("Logo missing:", logoPath);
  };

  logoDiv.appendChild(img);
}


/**
 * Injects the custom stylesheet configured in APPCONFIG into the document head.
 * Does nothing when custom styles are disabled or the path is empty.
 */
async function loadStyle() {
  if (APPCONFIG.styles.useCustom == false) return;
  
  if (!APPCONFIG.styles?.path || APPCONFIG.styles.path.trim() === "") {
    console.warn("Custom stylesheet path is empty. Using default stylesheet.");
    return;
  }

  const custom = APPCONFIG.styles.path; 
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = custom;

  link.onerror = () => {
    console.warn("[Config] Custom stylesheet not found:", custom);
  };

  document.head.appendChild(link);
}


/* --------------------------------------------------
   Navigation / Sidebar
-------------------------------------------------- */

/**
 * Initialises the sidebar navigation: populates the global pages array from
 * .nav-item elements, wires up click handlers, and permanently expands top-level groups.
 */
function initNav() {
  pages = [];

  document.querySelectorAll(".nav-item").forEach(el => {
    pages.push({
      title: el.textContent.trim(),
      slug:  el.dataset.href,
      file:  el.dataset.file
    });

    const group = el.parentElement?.classList.contains("nav-group") ? el.parentElement : null;
    const isLevel1 = el.classList.contains("nav-level-1");

    el.onclick = () => {
      if (el.dataset.href) location.hash = el.dataset.href;
    };
  });

  // Level-1 groups always expanded and non-collapsible
  document.querySelectorAll(".nav-group").forEach(group => {
    if (group.querySelector(":scope > .nav-item.nav-level-1")) {
      group.classList.add("expanded");
    }
  });
}

/**
 * Expands the sidebar path to the page identified by slug and collapses all
 * other non-root groups.
 */
function expandNavPath(slug) {
  // Close all non-level-1 groups
  document.querySelectorAll(".nav-group:not(:has(> .nav-item.nav-level-1))")
    .forEach(g => g.classList.remove("expanded"));

  if (!slug) return;

  // Walk up the DOM from the active item and expand every ancestor nav-group
  const active = document.querySelector(`.nav-item[data-href="${slug}"]`);
  if (!active) return;

  let el = active.parentElement;
  while (el && el.id !== "da-navigation-div") {
    if (el.classList.contains("nav-group")) el.classList.add("expanded");
    el = el.parentElement;
  }
}

/** Loads the table-of-contents page as the application home screen. */
function loadHomePage() {
  const tocName = APPCONFIG?.tableOfContents?.name ?? "TableOfContent.html";
  loadPage(tocName, false, "");
}


/* --------------------------------------------------
   Markdown page loading
-------------------------------------------------- */

/**
 * Fetches a pre-rendered HTML page fragment and inserts it into the content area.
 * Rewrites relative image paths, applies syntax highlighting, injects copy buttons,
 * updates the URL hash, and marks the active navigation entry.
 *
 * @param {string}  file  - Path to the HTML file relative to sitesFolder.
 * @param {boolean} push  - Whether to push the slug to the URL hash.
 * @param {string}  slug  - Navigation slug identifying this page.
 */
async function loadPage(file, push = true, slug = null) {
file = file.replaceAll("\\", "/");
  try {
	
    const htmlFile = file.replace(/\.md$/, ".html");
    const res = await fetch(APPCONFIG.environment.sitesFolder + htmlFile);

    const html = await res.text();

	const basePath =
      APPCONFIG.environment.sitesFolder +
      file.substring(0, file.lastIndexOf("/") + 1);

    const contentDiv = document.getElementById(CONFIG.dom.content);
    contentDiv.innerHTML = html;

    // Rewrite relative image src values to absolute paths so images load
    // correctly regardless of the current URL hash.
    contentDiv.querySelectorAll("img").forEach(img => {
      const src = img.getAttribute("src");
      if (src && !src.startsWith("http") && !src.startsWith("/") && !src.startsWith("data:")) {
        img.src = basePath + src;
      }
    });

    document.querySelectorAll(`#${CONFIG.dom.content} pre code`).forEach((block) => {

      hljs.highlightElement(block);

      const pre = block.parentElement;

      const wrapper = document.createElement("div");
      wrapper.className = "code-block";

      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);

      // Determine the language label from the highlight.js class added to the <code> element.
      let language = "text";

      block.classList.forEach(cls => {
        if (cls.startsWith("language-")) {
          language = cls.replace("language-", "");
        }
      });

      // Language Label
      const label = document.createElement("div");
      label.className = "code-language";
      label.textContent = language;

      wrapper.appendChild(label);

      // Copy Button
      const button = document.createElement("button");
      button.className = "copy-button";
      button.textContent = "Copy";

      button.onclick = () => {
        navigator.clipboard.writeText(block.innerText);

        button.textContent = "Copied!";
        setTimeout(() => button.textContent = "Copy", 1500);
      };

      wrapper.appendChild(button);

    });

    if (push && slug && location.hash.substring(1) !== slug) {
      location.hash = slug;
    }

    // Only scroll to the top when loading a page, not when jumping to an in-page anchor.
	if (!location.hash.includes("::")) {
  window.scrollTo(0, 0);
}

    /* Update active navigation entry and expand its tree path */
    document.querySelectorAll(".nav-item")
      .forEach(el => el.classList.remove("active"));

    const activeSlug = location.hash.substring(1);
    const active = document.querySelector(`[data-href="${activeSlug}"]`);
    if (active) active.classList.add("active");

    expandNavPath(activeSlug);

    return true;

  } catch (err) {

    console.error(err);

  }
}

/* --------------------------------------------------
   Search loading
-------------------------------------------------- */
/**
 * Fetches the pre-built search index JSON and loads it into a MiniSearch instance
 * configured to search the title and text fields.
 */
async function loadSearch() {

  const res = await fetch(APPCONFIG.environment.searchIndexFile);
  const docs = await res.json();

  miniSearch = new MiniSearch({
    fields: ['title', 'text'],
    storeFields: ['title', 'href', 'pageTitle', 'snippet'],
    idField: 'href'
  });

  miniSearch.addAll(docs);

}

/**
 * Searches the MiniSearch index for the given query string.
 * Returns an empty array when the index is not yet loaded or the query is too short.
 */
function searchDocs(query) {

  if (!miniSearch) return [];
  if (!query || query.length < 2) return [];

  return miniSearch.search(query, {
    prefix: true,
    fuzzy: 0.2
  });

}

/** Escapes HTML special characters to prevent XSS in dynamically built markup. */
function escapeHtml(text) {
  return (text || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * Wraps each query word found in text with a <mark> tag.
 * Input text must already be HTML-escaped.
 */
function highlightQuery(text, query) {
  if (!text || !query) return text;
  const words = query.trim().split(/\s+/).filter(w => w.length > 1);
  let result = text;
  words.forEach(word => {
    const safe  = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    result = result.replace(new RegExp(`(${safe})`, 'gi'), '<mark>$1</mark>');
  });
  return result;
}

/** Slides the search panel into view and hides the flag button. */
function showSearchPanel() {
  document.getElementById('da-search-panel').classList.add('visible');
  document.getElementById('da-search-flag').classList.remove('visible');
}

/**
 * Slides the search panel out of view.
 * Shows the flag button afterwards if a query is still stored.
 */
function hideSearchPanel() {
  document.getElementById('da-search-panel').classList.remove('visible');
  if (lastQuery) {
    document.getElementById('da-search-flag').classList.add('visible');
  }
}

/**
 * Renders search results into the search panel and makes the panel visible.
 * Each result shows the page title, the matching section heading, and a highlighted snippet.
 */
function renderResults(results, query = '') {

  const inner = document.getElementById('da-search-panel-inner');

  let html = `<h1>Search Results <span class="search-count">${results.length}</span></h1>`;

  if (results.length === 0) {
    html += `<p class="search-empty">No results found.</p>`;
  }

  results.forEach(r => {
    const pageHref     = r.href.split('::')[0];
    const isSubsection = r.href.includes('::');
    const pageTitle    = escapeHtml(r.pageTitle || '');
    const sectionTitle = escapeHtml(r.title || '');
    const snippet      = highlightQuery(escapeHtml(r.snippet || ''), query);

    // Only show section heading separately when it differs from the page title
    const sectionHtml = (isSubsection && sectionTitle !== pageTitle) ? `
        <div class="search-result-section">
          <a href="#${r.href}">${sectionTitle}</a>
        </div>` : '';

    html += `
      <div class="search-result">
        <div class="search-result-page">
          <a href="#${pageHref}">${pageTitle}</a>
        </div>
        ${sectionHtml}
        ${snippet ? `<div class="search-result-snippet">${snippet}</div>` : ''}
      </div>`;
  });

  inner.innerHTML = html;
  showSearchPanel();
}

/* --------------------------------------------------
   Hash routing
-------------------------------------------------- */

/**
 * Responds to URL hash changes by loading the corresponding page.
 * Supports the slug::anchor format for deep-linking directly to a heading.
 */
function handleHashChange() {

  hideSearchPanel();

  const hash = location.hash.substring(1);
  //if (!hash) return;

  let slug = hash;
  let anchor = null;

  // neues Format: slug::anchor
  if (hash.includes("::")) {
    const parts = hash.split("::");
    slug = parts[0];
    anchor = parts[1];
  }

  const page = pages.find(p => p.slug === slug);
  if (!page) return;

  loadPage(page.file, false, slug).then(() => {

    if (anchor) {
      const el = document.getElementById(anchor);
      if (el) setTimeout(() => el.scrollIntoView(), 50);
    }

  });
}

window.addEventListener("hashchange", handleHashChange);

/* --------------------------------------------------
   Initialization
-------------------------------------------------- */

/** Applies the persisted theme so the correct styles are in place before content loads. */
function initUI() {
  setTheme(getTheme());
}

/**
 * Main entry point after configuration is loaded: loads the logo, builds the
 * navigation, and either restores the page indicated by the current URL hash
 * or falls back to the home page.
 */
function init() {
  loadLogo();
  initNav();
  if (location.hash) {
    handleHashChange();
  } else {
    loadHomePage();
  }
}


/* --------------------------------------------------
   Event bindings
-------------------------------------------------- */

  const toggle = document.getElementById(CONFIG.dom.themeToggle);

  if (toggle) {
    toggle.onclick = () => {
      const current = getTheme();
      const next = current === "light" ? "dark" : "light";
      setTheme(next);
    };
  }

document.getElementById(CONFIG.dom.searchBox).addEventListener("input", e => {

  const query = e.target.value;
  lastQuery   = query;

  if (query.length >= 2) {
    lastResults = searchDocs(query);
    renderResults(lastResults, query);
  } else {
    hideSearchPanel();
  }

});

document.getElementById('da-search-close').onclick = () => hideSearchPanel();

document.getElementById('da-search-flag').onclick = () => {
  renderResults(lastResults, lastQuery);
};

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') hideSearchPanel();
});

document.getElementById(CONFIG.dom.homeButton).onclick = () => {
  console.log("button clicked")
  loadHomePage();
};


/* --------------------------------------------------
   Start application
-------------------------------------------------- */
document.addEventListener("DOMContentLoaded", async () => {
  await loadConfig();
  setPageTitle();
  await loadStyle();
  await loadSearch();

  initUI();
  init();
});