const CACHE = 'spotigraj-v10';
const ASSETS = [
  '/',
  '/index.html',
  '/landing.html',
  '/manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  // Tylko GET, pomijamy Supabase i Stripe
  if (e.request.method !== 'GET') return;
  if (e.request.url.includes('supabase.co')) return;
  if (e.request.url.includes('stripe.com')) return;

  const path = new URL(e.request.url).pathname;
  const isHtml = path === '/' || path.endsWith('.html');

  if (isHtml) {
    // Network-first: zawsze świeży HTML, cache jako fallback offline
    e.respondWith(
      fetch(e.request)
        .then(res => {
          caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
  } else {
    // Cache-first: statyczne assety (ikony, obrazki) — brak zbędnego transferu
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(res => {
          caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        });
      })
    );
  }
});

// Powiadomienia push
self.addEventListener('push', e => {
  const data = e.data?.json() || {};
  e.waitUntil(
    self.registration.showNotification(data.title || 'Spotigraj', {
      body: data.body || 'Masz nową aktywność!',
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      data: data.data || {},
    })
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const data = e.notification.data || {};

  // Ustal cel nawigacji na podstawie typu powiadomienia
  let url, message;
  if (data.type === 'match' && data.otherUserId) {
    url = '/#messages/chat/' + data.otherUserId;
    message = { type: 'OPEN_CHAT', senderId: data.otherUserId };
  } else if (data.sender_id) {
    url = '/#messages/chat/' + data.sender_id;
    message = { type: 'OPEN_CHAT', senderId: data.sender_id };
  } else {
    url = '/#messages';
    message = null;
  }

  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(windowClients => {
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          if (message) client.postMessage(message);
          return;
        }
      }
      return clients.openWindow(url);
    })
  );
});
