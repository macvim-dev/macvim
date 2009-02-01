// A small python module that registers a font with ATS, given the name of
// the font.

#include <Python/Python.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>

static PyObject* loadfont(PyObject* self, PyObject* args) {
  PyObject*   result = Py_False;
  const char* path = NULL;
  int         ok = PyArg_ParseTuple(args, "s", &path);

  if (ok) {
    CFStringRef componentPath = CFStringCreateWithCString(kCFAllocatorDefault,
        path, kCFStringEncodingUTF8);
    CFURLRef componentURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
        componentPath, kCFURLPOSIXPathStyle, false);
    FSRef fsref;

    if (CFURLGetFSRef(componentURL, &fsref)) {
      OSStatus err = noErr;
      ATSFontContainerRef fontContainerRef;  // we don't deactivate the font
#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
      err = ATSFontActivateFromFileReference(&fsref,
          kATSFontContextLocal, kATSFontFormatUnspecified, NULL,
          kATSOptionFlagsDefault, &fontContainerRef);
#else
      FSSpec fsSpec;
      FSRef  fsRef;
      if ((err = FSGetCatalogInfo(
              &fsRef, kFSCatInfoNone, NULL, NULL, &fsSpec, NULL)) == noErr) {
        err = ATSFontActivateFromFileSpecification(&fsSpec,
            kATSFontContextLocal, kATSFontFormatUnspecified, NULL,
            kATSOptionFlagsDefault, &fontContainerRef);
      }

#endif

      if (err == noErr) {
        result = Py_True;
      }
    }
    CFRelease(componentURL);
    CFRelease(componentPath);       
  }
  return result;
}

static PyMethodDef LoadfontMethods[] = {
  { "loadfont", loadfont, METH_VARARGS, "Locally activates font from file." },
  { NULL, NULL, 0, NULL }
};

PyMODINIT_FUNC initloadfont(void) {
  Py_InitModule("loadfont", LoadfontMethods);
}
