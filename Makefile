compile: builddir build/reactive.js

builddir:
	if [ ! -d build ]; then mkdir build; fi

examples: compile

build/reactive.js: reactive.coffee
	coffee -c -o build reactive.coffee

clean:
	rm -r build

