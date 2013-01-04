# not sure if this is insane
# TODO: it always remakes the core :P
CORE_SRC := $(shell find src/core)
BROWSER_SRC := src/browserenv.coffee
NODE_SRC := src/nodeenv.coffee src/node-all.coffee
DEBUGGER_SRC := $(shell find src/debugger/coffee)
DEBUG_SERVER_SRC := src/debugger/server.coffee
DEBUG_CSS := src/debugger/style.css
DEBUG_HTML := src/debugger/debugger.html

core: builddir $(CORE_SRC)
	if [ ! -d build/core ]; then mkdir build/core; fi
	coffee -cb -o build/core src/core

browser: builddir core $(BROWSER_SRC)
	if [ ! -d build/browser ]; then mkdir build/browser; fi
	coffee -cb -o build $(BROWSER_SRC)
	cat build/core/core.js build/core/models.js build/core/util.js build/browserenv.js build/core/debuggee.js > build/browser/reactive.js

node: builddir core $(NODE_SRC)
	if [ ! -d build/node ]; then mkdir build/node; fi
	coffee -cb -o build/node $(NODE_SRC)

debugger: debugserver debugjs debugcss debughtml

debuggerdir: builddir
	if [ ! -d build/debugger ]; then mkdir build/debugger; fi

debuggerstatic: debuggerdir
	if [ ! -d build/debugger/static ]; then mkdir build/debugger/static; fi

debugserver: debuggerdir node $(DEBUG_SERVER_SRC)
	coffee -cb -o build/debugger $(DEBUG_SERVER_SRC)
	echo '#!/usr/bin/env node' | cat - build/debugger/server.js > /tmp/out && mv /tmp/out build/debugger/server.js
	chmod 777 build/debugger/server.js

debugjs: debuggerstatic browser $(DEBUGGER_SRC)
	if [ ! -d build/debugger/static/js ]; then mkdir build/debugger/static/js; fi
	coffee -cb -o build/debugger/static/js $(DEBUGGER_SRC)
	cp build/browser/reactive.js build/debugger/static/js

debugcss: debuggerstatic $(DEBUG_CSS)
	cp $(DEBUG_CSS) build/debugger/static

debughtml: debuggerstatic $(DEBUG_HTML)
	cp $(DEBUG_HTML) build/debugger/static

builddir:
	if [ ! -d build ]; then mkdir build; fi

examples: core

clean:
	rm -r build
