# Creates a document icon from an app icon and an optional text.

# The font is not quite right, use this script to create a document icon
# for 'PDF' and compare the D with the D in Preview's pdf.icns

# http://www.macresearch.org/cocoa-scientists-part-xx-python-scriptersmeet-cocoa
try:
  from Foundation import *
  from AppKit import *
  dont_create = False
except:
  dont_create = True  # most likely because we're on tiger

import math
import os
import sys

# icon types
LARGE = 0  # 512, 128, 32, 16; about 96kB
SMALL = 1  # 128, 32, 16; about 36kB
LINK = 2  # Create link to generic icon; 4kB (== smallest block size on HFS+)

# path to makeicns binary
MAKEICNS = 'makeicns/makeicns'

# List of icons to create
# XXX: 32x32 variants only support 3-4 letters of text
GENERIC_ICON_NAME = 'MacVim-generic'
vimIcons = {
    GENERIC_ICON_NAME: [u'', LARGE],
    'MacVim-vim': [u'VIM', LARGE],
    'MacVim-txt': [u'TXT', SMALL],
    'MacVim-tex': [u'TEX', SMALL],
    'MacVim-h': [u'H', SMALL],
    'MacVim-c': [u'C', SMALL],
    'MacVim-m': [u'M', SMALL],
    'MacVim-mm': [u'MM', SMALL],
    'MacVim-cpp': [u'C\uff0b\uff0b', SMALL],  # fullwidth plusses
    'MacVim-java': [u'JAVA', SMALL],
    'MacVim-f': [u'FTRAN', SMALL],
    'MacVim-html': [u'HTML', SMALL],
    'MacVim-xml': [u'XML', SMALL],
    'MacVim-js': [u'JS', SMALL],
    'MacVim-perl': [u'PERL', SMALL],
    'MacVim-py': [u'PYTHON', SMALL],
    'MacVim-php': [u'PHP', SMALL],
    'MacVim-rb': [u'RUBY', SMALL],
    'MacVim-bash': [u'SH', SMALL],
    'MacVim-patch': [u'DIFF', SMALL],
    'MacVim-applescript': [u'\uf8ffSCPT', SMALL],  # apple sign
    'MacVim-as': [u'FLASH', LINK],
    'MacVim-asp': [u'ASP', LINK],
    'MacVim-bib': [u'BIB', LINK],
    'MacVim-cs': [u'C#', LINK],
    'MacVim-csfg': [u'CFDG', LINK],
    'MacVim-csv': [u'CSV', LINK],
    'MacVim-tsv': [u'TSV', LINK],
    'MacVim-cgi': [u'CGI', LINK],
    'MacVim-cfg': [u'CFG', LINK],
    'MacVim-css': [u'CSS', SMALL],
    'MacVim-dtd': [u'DTD', LINK],
    'MacVim-dylan': [u'DYLAN', LINK],
    'MacVim-erl': [u'ERLANG', SMALL],
    'MacVim-fscript': [u'FSCPT', SMALL],
    'MacVim-hs': [u'HS', SMALL],
    'MacVim-inc': [u'INC', LINK],
    'MacVim-ics': [u'ICS', SMALL],
    'MacVim-ini': [u'INI', LINK],
    'MacVim-io': [u'IO', LINK],
    'MacVim-bsh': [u'BSH', LINK],
    'MacVim-properties': [u'PROP', LINK],
    'MacVim-jsp': [u'JSP', SMALL],
    'MacVim-lisp': [u'LISP', SMALL],
    'MacVim-log': [u'LOG', SMALL],
    'MacVim-wiki': [u'WIKI', SMALL],
    'MacVim-ps': [u'PS', LINK],
    #'MacVim-plist': [u'PLIST', SMALL],
    'MacVim-sch': [u'SCHEME', SMALL],
    'MacVim-sql': [u'SQL', SMALL],
    'MacVim-tcl': [u'TCL', SMALL],
    'MacVim-xsl': [u'XSL', LINK],
    'MacVim-vcf': [u'VCARD', SMALL],
    'MacVim-vb': [u'VBASIC', LINK],
    'MacVim-yaml': [u'YAML', SMALL],
    'MacVim-gtd': [u'GTD', LINK],
}

shorttext = {
    u'MacVim-py': u'PY',
    u'MacVim-rb': u'RB',
    u'MacVim-perl': u'PL',
    u'MacVim-applescript': u'\uf8ffS',
    u'MacVim-erl': u'ERL',
    u'MacVim-fscript': u'FSCR',
    u'MacVim-sch': u'SCM',
    u'MacVim-vcf': u'VCF',
    u'MacVim-vb': u'VB',
}


# Resources
BACKGROUND = '/System/Library/CoreServices/CoreTypes.bundle/' + \
    'Contents/Resources/GenericDocumentIcon.icns'  # might require leopard?
APPICON = 'vim-noshadow-512.png'
#APPICON = 'vim-noshadow-no-v-512.png'

class Surface(object):
  """Represents a simple bitmapped image."""

  def __init__(self, *p, **kw):
    if not 'premultiplyAlpha' in kw:
      kw['premultiplyAlpha'] = True
    if len(p) == 1 and isinstance(p[0], NSBitmapImageRep):
      self.bitmapRep = p[0]
    elif len(p) == 2 and isinstance(p[0], int) and isinstance(p[1], int):
      format = NSAlphaFirstBitmapFormat
      if not kw['premultiplyAlpha']:
        format += NSAlphaNonpremultipliedBitmapFormat
      self.bitmapRep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bitmapFormat_bytesPerRow_bitsPerPixel_(
          None, p[0], p[1], 8, 4, True, False, NSDeviceRGBColorSpace,
          format, 0, 0)

    if not hasattr(self, 'bitmapRep') or not self.bitmapRep:
      raise Exception('Failed to create surface: ' + str(p))

  def size(self):
    return map(int, self.bitmapRep.size())  # cocoa returns floats. cocoa ftw

  def data(self):
    """Returns data in ARGB order (on intel, at least)."""
    r = self.bitmapRep
    if r.bitmapFormat() != (NSAlphaNonpremultipliedBitmapFormat |
          NSAlphaFirstBitmapFormat) or \
        r.bitsPerPixel() != 32 or \
        r.isPlanar() or \
        r.samplesPerPixel() != 4:
      raise Exception("Unsupported image format")
    return self.bitmapRep.bitmapData()

  def save(self, filename):
    """Saves image as png file."""
    self.bitmapRep.representationUsingType_properties_(NSPNGFileType, None) \
        .writeToFile_atomically_(filename, True)

  def draw(self):
    self.bitmapRep.draw()

  def context(self):
    # Note: Cocoa only supports contexts with premultiplied alpha
    return NSGraphicsContext.graphicsContextWithBitmapImageRep_(self.bitmapRep)

  def copy(self):
    return Surface(self.bitmapRep.copy())


class Image(object):
  """Represents an image that can consist of several Surfaces."""

  def __init__(self, param):
    if isinstance(param, str):
      self.image = NSImage.alloc().initWithContentsOfFile_(param)
    elif isinstance(param, Surface):
      self.image = NSImage.alloc().initWithSize_( param.size() )
      self.image.addRepresentation_(param.bitmapRep)

    if not self.image:
      raise Exception('Failed to load image: ' + str(filename))

  def surfaceOfSize(self, w, h):
    """Returns an ARGB, non-premultiplied surface of size w*h or throws."""
    r = None
    for rep in self.image.representations():
      if map(int, rep.size()) == [w, h]:
        r = rep
        break
    if not r:
      raise Exception('Unsupported size %dx%d', w, h)
    return Surface(r)

  def blend(self):
    self.compositeInRect( ((0, 0), self.image.size()) )

  def compositeInRect(self, r, mode=NSCompositeSourceOver):
    self.image.drawInRect_fromRect_operation_fraction_(r, NSZeroRect,
        mode, 1.0)


class Context(object):
  # Tiger has only Python2.3, so we can't use __enter__ / __exit__ for this :-(

  def __init__(self, surface):
    NSGraphicsContext.saveGraphicsState()
    c = surface.context()
    c.setShouldAntialias_(True);
    c.setImageInterpolation_(NSImageInterpolationHigh);
    NSGraphicsContext.setCurrentContext_(c)

  def done(self):
    NSGraphicsContext.restoreGraphicsState()


class SplittableBackground(object):

  def __init__(self, unsplitted, shouldSplit=True):
    self.unsplitted = unsplitted
    self.shouldSplit = shouldSplit
    self.ground = {}
    self.shadow = {}

  def rawGroundAtSize(self, s):
    return self.unsplitted.surfaceOfSize(s, s)

  def groundAtSize(self, s):
    if not self.shouldSplit:
      return self.rawGroundAtSize(s)
    self._performSplit(s)
    return self.ground[s]

  def shadowAtSize(self, s):
    if not self.shouldSplit:
      return None
    self._performSplit(s)
    return self.shadow[s]

  def _performSplit(self, s):
    if s in self.ground:
      assert s in self.shadow
      return
    assert s not in self.shadow
    ground, shadow = splitGenericDocumentIcon(self.unsplitted, s)
    self.ground[s] = ground
    self.shadow[s] = shadow


class BackgroundRenderer(object):

  def __init__(self, bg, icon=None):
    self.bgRenderer = bg
    self.icon = icon
    self.cache = {}

  def drawIcon(self, s):
    if not self.icon:
      return
    # found by flow program, better than anything i came up with manually before
    # (except for the 16x16 variant :-( )
    transforms = {
        512: [ 0.7049, 0.5653, -4.2432, 0.5656],
        256: [ 0.5690, 0.5658, -1.9331, 0.5656],
        128: [ 1.1461, 0.5684, -0.8482, 0.5681],

         32: [-0.2682, 0.5895, -2.2130, 0.5701],  # intensity
         #32: [-0.2731, 0.5898, -2.2262, 0.5729],  # rgb (no rmse difference)

         #16: [-0.3033, 0.4909, -1.3235, 0.4790],  # program, intensity
         #16: [-0.3087, 0.4920, -1.2990, 0.4750],  # program, rgb mode
         16: [ 0.0000, 0.5000, -1.0000, 0.5000],  # manually, better
        }

    assert s in [16, 32, 128, 256, 512]
    a = transforms[s]

    # convert from `flow` coords to cocoa
    a[2] = -a[2]  # mirror y

    w, h = s*a[1], s*a[3]
    self.icon.compositeInRect( (((s-w)/2 + a[0], (s-h)/2 + a[2]), (w, h)) )

  def drawAtSize(self, s):
    self.bgRenderer.groundAtSize(s).draw()
    self.drawIcon(s)
    if self.bgRenderer.shouldSplit:
      # shadow needs to be composited, so it needs to be in an image
      Image(self.bgRenderer.shadowAtSize(s)).blend()

  def backgroundAtSize(self, s):
    if not s in self.cache:
      result = Surface(s, s)
      context = Context(result)
      self.drawAtSize(s)
      context.done()
      self.cache[s] = result
    return self.cache[s]


def splitGenericDocumentIcon(img, s):
  """Takes the generic document icon and splits it into a background and a
  shadow layer. For the 32x32 and 16x16 variants, the white pixels of the page
  curl are hardcoded into the otherwise transparent shadow layer."""

  w, h = s, s
  r = img.surfaceOfSize(w, h)
  bps = 4*w
  data = r.data()

  ground = Surface(w, h, premultiplyAlpha=False)
  shadow = Surface(w, h, premultiplyAlpha=False)

  grounddata = ground.data()
  shadowdata = shadow.data()

  for y in xrange(h):
    for x in xrange(w):
      idx = y*bps + 4*x
      ia, ir, ig, ib = data[idx:idx + 4]
      if ia != chr(255):
        # buffer objects don't support slice assignment :-(
        grounddata[idx] = ia
        grounddata[idx + 1] = ir
        grounddata[idx + 2] = ig
        grounddata[idx + 3] = ib
        shadowdata[idx] = chr(0)
        shadowdata[idx + 1] = chr(0)
        shadowdata[idx + 2] = chr(0)
        shadowdata[idx + 3] = chr(0)
        continue

      assert ir == ig == ib
      grounddata[idx] = chr(255)
      grounddata[idx + 1] = chr(255)
      grounddata[idx + 2] = chr(255)
      grounddata[idx + 3] = chr(255)
      shadowdata[idx] = chr(255 - ord(ir))
      shadowdata[idx + 1] = chr(0)
      shadowdata[idx + 2] = chr(0)
      shadowdata[idx + 3] = chr(0)

  # Special-case 16x16 and 32x32 cases: Make some pixels on the fold white.
  # Ideally, I could make the fold whiteish in all variants, but I can't.
  whitePix = { 16: [(10, 2), (10, 3), (11, 3), (10, 4), (11, 4), (12, 4)],
               32: [(21, 4), (21, 5), (22, 5), (21, 6), (22, 6), (23, 6)]}
  if (w, h) in [(16, 16), (32, 32)]:
    for x, y in whitePix[w]:
      idx = y*bps + 4*x
      shadowdata[idx] = chr(255)
      shadowdata[idx + 1] = chr(255)
      shadowdata[idx + 2] = chr(255)
      shadowdata[idx + 3] = chr(255)

  return ground, shadow


class TextRenderer(object):

  def __init__(self):
    self.cache = {}

  def attribsAtSize(self, s):
    if s not in self.cache:
      self.cache[s] = self._attribsAtSize(s)
    return self.cache[s]

  def centeredStyle(self):
    style = NSMutableParagraphStyle.new()
    style.setParagraphStyle_(NSParagraphStyle.defaultParagraphStyle())
    style.setAlignment_(NSCenterTextAlignment)
    return style

  def _attribsAtSize(self, s):
    # This looks not exactly like the font on Preview.app's document icons,
    # but I believe that's because Preview's icons are drawn by Photoshop,
    # and Adobe's font rendering is different from Apple's.
    fontname = 'LucidaGrande-Bold'

    # Prepare text format
    fontsizes = { 512: 72.0,  256: 36.0,  128: 18.0,  32: 7.0,  16: 3.0 }
    # http://developer.apple.com/documentation/Cocoa/Conceptual/AttributedStrings/Articles/standardAttributes.html#//apple_ref/doc/uid/TP40004903
    attribs = {
      NSParagraphStyleAttributeName: self.centeredStyle(),
      NSForegroundColorAttributeName: NSColor.colorWithDeviceWhite_alpha_(
          0.34, 1),
      NSFontAttributeName: NSFont.fontWithName_size_(fontname, fontsizes[s])
    }

    # tighten font a bit for some sizes
    if s in [256, 512]:
      attribs[NSKernAttributeName] = -1.0
    elif s == 32:
      attribs[NSKernAttributeName] = -0.25

    if not attribs[NSFontAttributeName]:
      raise Exception('Failed to load font %s' % fontname)
    return attribs

  def drawTextAtSize(self, text, s):
    """Draws text `s` into the current context of size `s`."""

    textRects = {
        512: ((0, 7), (512, 119)),
        128: ((0, 6), (128, 26.5)),
        256: ((0, 7), (256, 57)),
         16: ((1, 1), (15, 5)),
         #32: ((1, 1), (31, 9))
        }

    attribs = self.attribsAtSize(s)
    text = NSString.stringWithString_(text)
    if s in [16, 128, 256, 512]:
      text.drawInRect_withAttributes_(textRects[s], attribs)
    elif s == 32:
      # Try to align text on pixel boundary:
      attribs = attribs.copy()
      attribs[NSParagraphStyleAttributeName] = \
          NSParagraphStyle.defaultParagraphStyle()
      ts = text.sizeWithAttributes_(attribs)
      text.drawAtPoint_withAttributes_( (math.floor((32.0-ts[0])/2) + 0.5, 1.5),
          attribs)


class OfficeTextRenderer(TextRenderer):
  """Uses Office's LucidaSans font for 32x32.

  This font looks much better for certain strings (e.g. "PDF") but much worse
  for most others (e.g. "VIM", "JAVA") -- and office fonts are usually not
  installed. Hence, this class is better not used.
  """

  def _attribsAtSize(self, s):
    self.useOfficeFont = False
    attribs = TextRenderer._attribsAtSize(self, s)
    if s == 32:
      font = NSFont.fontWithName_size_('LucidaSans-Demi', 7.0)
      if font:
        attribs[NSFontAttributeName] = font
        attribs[NSKernAttributeName] = 0
        self.useOfficeFont = True
    return attribs

  def drawTextAtSize(self, text, s):
    attribs = self.attribsAtSize(s)
    if not self.useOfficeFont or s != 32:
      TextRenderer.drawTextAtSize(self, text, s)
      return
    text = NSString.stringWithString_(text)
    text.drawInRect_withAttributes_( ((0, 1), (31, 11)), attribs)


def createIcon(outname, s, bg, textRenderer, text, shorttext=None):

  # Fill in background
  output = bg.backgroundAtSize(s).copy()

  # Draw text on top of shadow
  context = Context(output)
  if s in [16, 32] and shorttext:
    text = shorttext
  textRenderer.drawTextAtSize(text, s)
  context.done()

  # Save
  output.save(outname)


def createLinks(icons, target):
  assert len(icons) > 0
  for name in icons:
    icnsName = '%s.icns' % name
    if os.access(icnsName, os.F_OK):
      os.remove(icnsName)
    os.symlink(target, icnsName)


TMPFILE = 'make_icons_tmp_%d.png'
sizes = [512, 128, 32, 16]
def main():
  srcdir = os.getcwd()
  if len(sys.argv) > 1:
    os.chdir(sys.argv[1])
  appIcon = os.path.join(srcdir, APPICON)
  makeIcns = os.path.join(srcdir, MAKEICNS)

  if dont_create:
    print "PyObjC not found, only using a stock icon for document icons."
    import shutil
    shutil.copyfile(BACKGROUND, '%s.icns' % GENERIC_ICON_NAME)
    createLinks([name for name in vimIcons if name != GENERIC_ICON_NAME],
        '%s.icns' % GENERIC_ICON_NAME)
    return
  # Make us not crash
  # http://www.cocoabuilder.com/archive/message/cocoa/2008/8/6/214964
  NSApplicationLoad()

  textRenderer = TextRenderer()
  #textRenderer = OfficeTextRenderer()

  # Prepare input images
  bgIcon = Image(BACKGROUND)

  #bg = SplittableBackground(bgIcon, shouldSplit=False)
  bg = SplittableBackground(bgIcon, shouldSplit=True)

  icon = Image(appIcon)
  bgRenderer = BackgroundRenderer(bg, icon)

  if not os.access(makeIcns, os.X_OK):
    print 'Cannot find makeicns at %s', makeIcns
    return

  # create LARGE and SMALL icons first...
  for name, t in vimIcons.iteritems():
    text, size = t
    if size == LINK: continue
    print name
    icnsName = '%s.icns' % name

    if size == SMALL:
      currSizes = [128, 32, 16]
      args = '-128 %s -32 %s -16 %s' % (
          TMPFILE % 128, TMPFILE % 32, TMPFILE % 16)
    elif size == LARGE:
      currSizes = [512, 128, 32, 16]
      args = '-512 %s -128 %s -32 %s -16 %s' % (
          TMPFILE % 512, TMPFILE % 128, TMPFILE % 32, TMPFILE % 16)

    st = shorttext.get(name)
    for s in currSizes:
      createIcon(TMPFILE % s, s, bgRenderer, textRenderer, text, shorttext=st)

    os.system('%s %s -out %s' % (makeIcns, args, icnsName))

  del text, size, name, t

  # ...create links later (to make sure the link targets exist)
  createLinks([name for (name, t) in vimIcons.items() if t[1] == LINK],
      '%s.icns' % GENERIC_ICON_NAME)


if __name__ == '__main__':
  try:
    main()
  finally:
    for s in sizes:
      if os.access(TMPFILE % s, os.F_OK):
        os.remove(TMPFILE % s)
