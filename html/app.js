let pages = [];
let APPCONFIG;

/*
  Global configuration.
  Everything that may change between installations should live here.
*/
const CONFIG = {
  dom: {
    nav: "nav",
    content: "content",
    logo: "logo",
    themeToggle: "themeToggle"
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

    const res = await fetch(APPCONFIG.environment.navigationFile);
    if (!res.ok) throw new Error(APPCONFIG.environment.navigationFile + " not found");

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
          //console.log("Current SLUG: " + slug + " HASH: " + location.hash.substring(1));

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

  if (!Array.isArray(node.children)) return;

  node.children.forEach(child => addPages(child));
}

/* --------------------------------------------------
   Hash routing
-------------------------------------------------- */

function handleHashChange() {
  const hash = location.hash.substring(1);
  if (!hash) return;

  const parts = hash.split("/");
  const slug = parts[0];
  const anchor = parts.slice(1).join("/");

  const page = findPageBySlug(slug);
  if (!page) return;

  loadPage(page.file, false, slug).then(() => {
    if (anchor) {
      const el = document.getElementById(anchor);
      if (el) el.scrollIntoView();
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


/* --------------------------------------------------
   Start application
-------------------------------------------------- */
(async () => {
  await loadConfig();
  await loadStyle();

  initUI();
  init();
})();