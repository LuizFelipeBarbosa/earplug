import 'dart:js_interop';

import 'package:web/web.dart' as web;

typedef BrowserBackHandler = void Function();

void pushBrowserPath(String path) {
  if ('${web.window.location.pathname}${web.window.location.search}' == path) {
    return;
  }
  web.window.history.pushState(null, '', path);
}

void replaceBrowserPath(String path) {
  web.window.history.replaceState(null, '', path);
}

void Function() listenForBrowserBack(BrowserBackHandler handler) {
  final listener = ((web.Event _) => handler()).toJS;
  web.window.addEventListener('popstate', listener);
  return () => web.window.removeEventListener('popstate', listener);
}
