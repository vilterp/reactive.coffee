SRC := `find src`

compile: builddir SRC
	coffee -cb -o build src

builddir:
	if [ ! -d build ]; then mkdir build; fi

examples: compile

clean:
	rm -r build

