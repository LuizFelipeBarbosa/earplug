{{flutter_js}}
{{flutter_build_config}}

setTimeout(function () {
  const splash = document.getElementById('ep-splash');
  if (splash) {
    splash.textContent = 'Still loading… reload the page';
  }
}, 30000);

_flutter.loader.load({});
