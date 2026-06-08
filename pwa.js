/* Registers the service worker so the app is installable (website + Microsoft Store).
   Safe no-op on file:// or browsers without service-worker support. */
if ('serviceWorker' in navigator && location.protocol.indexOf('http') === 0) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('service-worker.js').catch(function () {});
  });
}
