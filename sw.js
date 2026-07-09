const CACHE = "school-app-github-v57";
const SCAN_LIMITED_EMAIL = "scan.appklunschool@gmail.com";
const ASSETS = [
  "./",
  "./index.html",
  "./scanner.html",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png"
];

function patchIndexHtml(html){
  const marker = '  if(isDirector)menus=menus.filter(item=>!["att","grade"].includes(item.id));';
  const replacement = `  if(String(email||"").toLowerCase()==="${SCAN_LIMITED_EMAIL}")menus=menus.filter(item=>["scan","hist","att"].includes(item.id));\n${marker}`;
  return html.includes(replacement) ? html : html.replace(marker, replacement);
}

async function patchIndexResponse(response){
  const headers = new Headers(response.headers);
  headers.delete("content-length");
  headers.set("content-type", "text/html; charset=UTF-8");
  return new Response(patchIndexHtml(await response.text()), {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function isIndexRequest(request){
  const url = new URL(request.url);
  return url.origin === location.origin && (url.pathname.endsWith("/") || url.pathname.endsWith("/index.html"));
}

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener("fetch", e => {
  if (e.request.url.includes("supabase.co")) return;
  e.respondWith((async () => {
    const shouldPatchIndex = isIndexRequest(e.request);
    try {
      const response = await fetch(e.request);
      return shouldPatchIndex ? patchIndexResponse(response) : response;
    } catch {
      const cached = await caches.match(e.request);
      if (cached && shouldPatchIndex) return patchIndexResponse(cached);
      return cached;
    }
  })());
});
