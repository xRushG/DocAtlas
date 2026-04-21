let pages = [];
let APPCONFIG;
let miniSearch;

/*
  Global configuration.
  Everything that may change between installations should live here.
*/
const CONFIG = {
  dom: {
    nav: "nav",
    content: "content",
    logo: "logo",
    themeToggle: "themeToggle",
    searchBox: "searchBox"
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
  
  console.log(APPCONFIG);
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

/* Lookup page by slug inside the flat page index */
function findPageBySlug(slug) {
  return pages.find(p => p.slug === slug);
}


/* --------------------------------------------------
   Theme handling
-------------------------------------------------- */

function getTheme() {
  return localStorage.getItem(CONFIG.theme.storageKey) || CONFIG.theme.default;
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
  if (APPCONFIG.styles.useCustom == false)  return;
  
  if (APPCONFIG.styles.path == null || APPCONFIG.styles.path.trim() === "") {
    console.warn("Custom stylesheet path is empty. Using default stylesheet.");
    return;
  }

  const custom = APPCONFIG.styles.path; 
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = custom;

  // verhindert nur JS-seitige Eskalation
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

    const nav = document.getElementById(CONFIG.dom.nav);
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

function renderNav(nodes, level = 0) {

  if (level >= APPCONFIG.navigation.depth) return;

  nodes.forEach(node => {

    const el = document.createElement("div");
    el.className = level === 0 ? "nav-group" : "nav-item";
    el.textContent = node.title;
    el.dataset.slug = node.slug;

    el.onclick = () => {
      if (node.file) {
        location.hash = node.slug;
      }
    };

    document.getElementById(CONFIG.dom.nav).appendChild(el);

    pages.push(node);

    if (node.children && Array.isArray(node.children)) {
      renderNav(node.children, level + 1);
    }

  });
}


/* --------------------------------------------------
   Markdown page loading
-------------------------------------------------- */

async function loadPage(file, push = true, slug = null) {

  try {
	  console.log("LoadPage: " + APPCONFIG.environment.markdownFolder + file);
    //console.trace("loadPage called");
	
    const res = await fetch(APPCONFIG.environment.markdownFolder + file);
    if (!res.ok) throw new Error("Page not found");

    const md = await res.text();

	const basePath =
      APPCONFIG.environment.markdownFolder +
      file.substring(0, file.lastIndexOf("/") + 1);

    /* Fix relative image paths inside markdown */
    const fixedMd = md.replace(
      /!\[(.*?)\]\((.*?)\)/g,
      (match, alt, src) => {

        if (src.startsWith("http") || src.startsWith("/")) {
          return match;
        }

        return `![${alt}](${basePath}${src})`;
      }
    );

	const renderer = new marked.Renderer();

    /*
      Build hierarchical heading IDs:
      H1 -> section
      H2 -> section/subsection
      H3 -> section/subsection/topic
    */
    let headingStack = [];

    renderer.heading = function (token) {

      const raw = token.text;
      const level = token.depth;

      const clean = raw.replace(/<[^>]+>/g, "");
      const slug = createSlug(clean);

      headingStack = headingStack.slice(0, level - 1);
      headingStack[level - 1] = slug;

      const path = headingStack.join("/");

      return `<h${level} id="${path}">${raw}</h${level}>`;
    };

    document.getElementById(CONFIG.dom.content).innerHTML =
      marked.parse(fixedMd, { renderer });

    /*document.querySelectorAll("#content pre code").forEach((block) => {
      // Syntax Highlight
      hljs.highlightElement(block);

      const pre = block.parentElement;

      // Wrapper erstellen
      const wrapper = document.createElement("div");
      wrapper.className = "code-block";

      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);

      // Copy Button
      const button = document.createElement("button");
      button.className = "copy-button";
      button.textContent = "Copy";

      button.onclick = () => {

        navigator.clipboard.writeText(block.innerText);

        button.textContent = "Copied!";
        setTimeout(() => {
          button.textContent = "Copy";
        }, 1500);
      };

      wrapper.appendChild(button);

    });*/
    document.querySelectorAll("#content pre code").forEach((block) => {

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

	window.scrollTo(0, 0);

    /* Update active navigation entry */
    document.querySelectorAll(".nav-item, .nav-group")
      .forEach(el => el.classList.remove("active"));

    const active = document.querySelector(`[data-slug="${slug}"]`);
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
    slug: node.slug
  });

  if (!node.children) return;

  //if (!Array.isArray(node.children)) return;
  if (node.children && !Array.isArray(node.children)) {
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
    storeFields: ['title', 'slug'],
    idField: 'slug'
  });

  miniSearch.addAll(docs);

}

function searchDocs(query) {

  if (!query || query.length < 2) return [];

  return miniSearch.search(query, {
    prefix: true,
    fuzzy: 0.2
  });

}

function renderResults(results) {

  const content = document.getElementById("content");

  let html = "<h1>Search Results</h1>";

  results.forEach(r => {

    html += `
      <div class="search-result">
        <a href="#${r.slug}">
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
  if (!hash) return;

  let page = findPageBySlug(hash);
let anchor = null;

if (!page) {
  const parts = hash.split("/");
  let slug = parts.shift();
  anchor = parts.join("/");

  page = findPageBySlug(slug);
}

if (!page) return;

loadPage(page.file, false, page.slug).then(() => {
  if (anchor) {
    const el = document.getElementById(anchor);
    if (el) el.scrollIntoView();
  }
});
}

window.addEventListener("hashchange", handleHashChange);

/* --------------------------------------------------
   Higlighting
-------------------------------------------------- */


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

document.getElementById(CONFIG.dom.themeToggle).onclick = () => {

  const toggle = document.getElementById(CONFIG.dom.themeToggle);

  if (toggle) {
    toggle.onclick = () => {
      const current = getTheme();
      const next = current === "light" ? "dark" : "light";
      setTheme(next);
    };
  }

};

document.getElementById(CONFIG.dom.searchBox).addEventListener("input", e => {

  const results = searchDocs(e.target.value);

  renderResults(results);

});


/* --------------------------------------------------
   Start application
-------------------------------------------------- */
(async () => {
  await loadConfig();
  await loadStyle();
  await loadSearch();

  initUI();
  init();
})();