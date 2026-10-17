/* ShareOS service worker – only makes the web interface installable as an
 * app. Nothing is cached: the NAS is always asked directly, so the app never
 * shows stale data, and /ubus calls are never touched. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
