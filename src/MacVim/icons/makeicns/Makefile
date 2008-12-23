CFLAGS = -fpascal-strings -O2

.PHONY: clean dist

makeicns: makeicns.o IconFamily.o NSString+CarbonFSRefCreation.o
	g++ -o makeicns $^ -O2 \
	  -framework Foundation -framework AppKit -framework Carbon

clean:
	rm -rf makeicns.o IconFamily.o NSString+CarbonFSRefCreation.o

dist: makeicns
	rm -rf makeicns-1.0.zip
	zip makeicns-1.0.zip Makefile makeicns.m IconFamily.m IconFamily.h \
	  NSString+CarbonFSRefCreation.m NSString+CarbonFSRefCreation.h \
	  makeicns
