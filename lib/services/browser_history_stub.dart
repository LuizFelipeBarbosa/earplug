typedef BrowserBackHandler = void Function();

void pushBrowserPath(String path) {}

void replaceBrowserPath(String path) {}

void Function() listenForBrowserBack(BrowserBackHandler handler) => () {};
