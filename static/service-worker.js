const CACHE_NAME = "messager-cache-v2";
const URLS_TO_CACHE = [
  "/static/manifest.webmanifest",
  "/static/logo.svg"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(URLS_TO_CACHE))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  const url = new URL(event.request.url);
  const networkFirstPaths = [
    "/",
    "/index.html",
    "/static/index.html",
    "/static/config.js",
    "/static/supabase-js.js"
  ];

  if (url.origin === self.location.origin && networkFirstPaths.includes(url.pathname)) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
