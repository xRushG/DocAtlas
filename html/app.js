let pages = [];
let APPCONFIG;
let miniSearch;

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
    navigation: "da-navigation-div",
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

function getTheme() {
  return localStorage.getItem(CONFIG.theme.storageKey) || CONFIG.theme.default;
}

function setPageTitle() {
  let pageTitle = APPCONFIG?.page?.title;

  if (!pageTitle || pageTitle.trim() === "") {
    pageTitle = "DocAtlas";
  }

  document.title = pageTitle;
}

function setTheme(theme) {

  document.body.classList.remove("light", "dark");
  document.body.classList.add(theme);

  localStorage.setItem(CONFIG.theme.storageKey, theme);

  loadLogo();
  updateToggleIcon();
}

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

async function loadMenu() {

  try {

    const res = await fetch(APPCONFIG.environment.navigationIndex);
    if (!res.ok) throw new Error(APPCONFIG.environment.navigationIndex + " not found");

    const data = await res.json();

    const nav = document.getElementById("da-navigation-div");
    nav.innerHTML = "";

    pages = [];
    data.forEach(node => addPages(node));
    renderNav(data);

	/* Initial page load when no hash exists */
	if (!location.hash && pages.length > 0) {
    location.hash = pages[0].slug;
	}

  } catch (err) {

    console.error(err);

    document.getElementById(CONFIG.dom.content).textContent =
      "Failed to load navigation.";

  }
}

function renderNav(nodes) {
  nodes.forEach(node => {
    if (node.level < 2) return;
    if (node.level > APPCONFIG.navigation.depth +1) return;

    const el = document.createElement("div");
  
    el.className = "nav-item";
    el.textContent = node.title;
    el.dataset.href = node.href;
    el.dataset.level = node.level;

    el.onclick = () => {
      location.hash = node.href;
    };

    document.getElementById(CONFIG.dom.navigation).appendChild(el);

    pages.push(node);
  });
}


/* --------------------------------------------------
   Markdown page loading
-------------------------------------------------- */

async function loadPage(file, push = true, slug = null) {
file = file.replaceAll("\\", "/");
  try {
	
    const htmlFile = file.replace(/\.md$/, ".html");
    const res = await fetch(APPCONFIG.environment.htmlSrcFolder + htmlFile);

    const html = await res.text();

	const basePath =
      APPCONFIG.environment.htmlSrcFolder +
      file.substring(0, file.lastIndexOf("/") + 1);

    const contentDiv = document.getElementById(CONFIG.dom.content);
    contentDiv.innerHTML = html;

    // Relative Bild-URLs auf absoluten basePath umschreiben
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

      // Sprache ermitteln
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

	if (!location.hash.includes("::")) {
  window.scrollTo(0, 0);
}

    /* Update active navigation entry */
    document.querySelectorAll(".nav-item")
      .forEach(el => el.classList.remove("active"));

    const active = document.querySelector(`[data-href="${location.hash.substring(1)}"]`);
    if (active) active.classList.add("active");

    return true;

  } catch (err) {

    console.error(err);

  }
}

function addPages(node) {

  pages.push({
    title: node.title,
    file: node.file,
    slug: node.href
  });

  if (!node.children) return;

  if (!Array.isArray(node.children)) {
    node.children = [node.children];
  }

  node.children.forEach(child => addPages(child));
}

/* --------------------------------------------------
   Search loading
-------------------------------------------------- */
async function loadSearch() {

  const res = await fetch(APPCONFIG.environment.searchIndex);
  const docs = await res.json();

  miniSearch = new MiniSearch({
    fields: ['title', 'text'],
    storeFields: ['title', 'href'],
    idField: 'href'
  });

  miniSearch.addAll(docs);

}

function searchDocs(query) {

  if (!miniSearch) return [];
  if (!query || query.length < 2) return [];

  return miniSearch.search(query, {
    prefix: true,
    fuzzy: 0.2
  });

}

function renderResults(results) {

  const content = document.getElementById(CONFIG.dom.content);

  let html = "<h1>Search Results</h1>";

  results.forEach(r => {

    html += `
      <div class="search-result">
        <a href="#${r.href}">
          <strong>${r.title}</strong>
        </a>
      </div>
    `;
  });

  content.innerHTML = html;
}

/* --------------------------------------------------
   Hash routing
-------------------------------------------------- */

function handleHashChange() {

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

function initUI() {
  setTheme(getTheme());
}

function init() {

  loadLogo();

  loadMenu().then(() => {
    if (location.hash) {
      handleHashChange();
    }
  });
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

  const results = searchDocs(e.target.value);

  renderResults(results);

});

document.getElementById(CONFIG.dom.homeButton).onclick = () => {
  location.hash = "";
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