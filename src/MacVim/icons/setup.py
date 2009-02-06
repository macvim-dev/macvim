from distutils.core import setup, Extension

setup(name="loadfont", version="1.0",
	ext_modules = [Extension("loadfont", ["loadfont.c"])])

