{{flutter_js}}
{{flutter_build_config}}

setTimeout(function () {
  const splash = document.getElementById('ep-splash');
  if (splash) {
    splash.textContent = 'Still loading… reload the page';
  }
}, 30000);

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations()
    .then(function (registrations) {
      return Promise.all(registrations.map(function (registration) {
        return registration.unregister();
      }));
    })
    .catch(function () {});
}

if ('caches' in window) {
  caches.keys()
    .then(function (cacheKeys) {
      return Promise.all(
        cacheKeys
          .filter(function (cacheKey) {
            return cacheKey.startsWith('flutter-app-');
          })
          .map(function (cacheKey) {
            return caches.delete(cacheKey);
          }),
      );
    })
    .catch(function () {});
}

_flutter.loader.load({});
