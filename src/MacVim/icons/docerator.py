from Foundation import *
from AppKit import *

import itertools
import math
import operator
import os

from optparse import OptionParser


# Resources
DEFAULT_BACKGROUND = '/System/Library/CoreServices/CoreTypes.bundle/' + \
    'Contents/Resources/GenericDocumentIcon.icns'  # might require leopard?


# Cache both images and background renderers globally
imageCache = {}
bgCache = {}


# Make us not crash
# http://www.cocoabuilder.com/archive/message/cocoa/2008/8/6/214964
NSApplicationLoad()


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
    if (r.bitmapFormat() & ~NSAlphaFirstBitmapFormat !=
            NSAlphaNonpremultipliedBitmapFormat) or \
        r.bitsPerPixel() != 32 or \
        r.isPlanar() or \
        r.samplesPerPixel() != 4:
      raise Exception("Unsupported image format")
    return self.bitmapRep.bitmapData()

  def rgbaIndices(self):
    r = self.bitmapRep
    if r.bitmapFormat() & NSAlphaFirstBitmapFormat != 0:
      return 1, 2, 3, 0
    else:
      return 0, 1, 2, 3

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
      raise Exception('Failed to load image: ' + str(param))

  def surfaceOfSize(self, w, h):
    """Returns an ARGB, non-premultiplied surface of size w*h or throws."""
    r = None
    for rep in self.image.representations():
      # Cocoa reports fraction widths for pngs (wtf?!), so use round()
      if map(lambda x: int(round(x)), rep.size()) == [w, h]:
        r = rep
        break

    # XXX: Resample in this case? That'd make the program easier to use, but
    #      can silently create blurry backgrounds. Since this happens with
    #      the app icon anyways, this might not be a huge deal?
    if not r:
      raise Exception('Unsupported size %dx%d', w, h)
    return Surface(r)

  def blend(self):
    self.compositeInRect( ((0, 0), self.image.size()) )

  def compositeInRect(self, r, mode=NSCompositeSourceOver):
    self.image.drawInRect_fromRect_operation_fraction_(r, NSZeroRect,
        mode, 1.0)

  def sizes(self):
    s = set()
    for rep in self.image.representations():
      s.add(tuple(map(lambda x: int(round(x)), rep.size())))
    return s


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

  def __init__(self, bg, icon=None, r={}):
    self.bgRenderer = bg
    self.icon = icon
    self.cache = {}
    self.rect = r

  def drawIcon(self, s):
    if not self.icon:
      return

    assert s in [16, 32, 128, 256, 512]
    a = list(self.rect[s])

    # convert from `flow` coords to cocoa
    a[2] = -a[2]  # mirror y

    w, h = s*a[1], s*a[3]
    self.icon.compositeInRect( (((s-w)/2 + a[0], (s-h)/2 + a[2]), (w, h)) )

  def drawAtSize(self, s):
    if not self.icon:
      # No need to split the background if no icons is interleaved -- take
      # the faster code path in that case.
      self.bgRenderer.rawGroundAtSize(s).draw()
      return

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
  dr, dg, db, da = r.rgbaIndices()

  ground = Surface(w, h, premultiplyAlpha=False)
  shadow = Surface(w, h, premultiplyAlpha=False)

  grounddata = ground.data()
  shadowdata = shadow.data()

  for y in xrange(h):
    for x in xrange(w):
      idx = y*bps + 4*x
      ia = data[idx + da]
      ir = data[idx + dr]
      ig = data[idx + dg]
      ib = data[idx + db]
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


def createIcon(s, bg, textRenderer, text):

  # Fill in background
  output = bg.backgroundAtSize(s).copy()

  # Draw text on top of shadow
  context = Context(output)
  if s in text and text[s]:
    textRenderer.drawTextAtSize(text[s], s)
  context.done()

  return output


def textDictFromTextList(l):
  assert 1 <= len(l) <= 3
  if len(l) == 1:
    return dict.fromkeys([16, 32, 128, 256, 512], l[0])
  elif len(l) == 2:
    return dict(zip([16, 32], 2*[l[1]]) + zip((128, 256, 512), 3*[l[0]]))
  elif len(l) == 3:
    return dict([(16, l[2]), (32, l[1])] + zip((128, 256, 512), 3*[l[0]]))


def saveIcns(icons, icnsName, makeIcns='./makeicns'):
  """Creates an icns file with several variants.

  Params:
    icons: A dict that contains icon size as key and Surface as value.
           Valid keys are 512, 256, 128, 32, 16
    icnsname: Name of the output file
  """
  # If IconFamily was less buggy, we could wrap it into a python module and
  # call it directly, which is about a lot faster. However, IconFamily does not
  # work with NSAlphaNonpremultipliedBitmapFormat correctly, so this has to
  # wait.
  #import IconFamily
  #typeDict = {
      #16: IconFamily.kSmall32BitData,
      #32: IconFamily.kLarge32BitData,
      #128: IconFamily.kThumbnail32BitData,
      #256: IconFamily.kIconServices256PixelDataARGB,
      #512: IconFamily.IconServices512PixelDataARGB,
  #}
  #maskDict = {
      #16: IconFamily.kSmall8BitMask,
      #32: IconFamily.kLarge8BitMask,
      #128: IconFamily.kThumbnail8BitMask,
  #}
  #output = IconFamily.IconFamily.iconFamily()
  #for s, icon in icons.items():
    #output.setIconFamilyElement_fromBitmapImageRep_(typeDict[s], icon.bitmapRep)
    #if s in maskDict:
      #output.setIconFamilyElement_fromBitmapImageRep_(
          #maskDict[s], icon.bitmapRep)
  #output.writeToFile_(icnsName)
  TMPFILE = 'docerator_tmp_%d.png'
  try:
    args = []
    for s, icon in icons.items():
      assert s in [512, 256, 128, 32, 16]
      assert icon.size() == [s, s]
      icon.save(TMPFILE % s)
      args.append('-%d %s' % (s, TMPFILE % s))
    return \
        os.system('%s %s -out %s' % (makeIcns, ' '.join(args), icnsName)) == 0
  finally:
    for s in icons:
      if os.access(TMPFILE % s, os.F_OK):
        os.remove(TMPFILE % s)


def getOutname(options):
  def saneBasename(p):
    """ '/my/path/to/file.txt' -> 'file' """
    return os.path.splitext(os.path.basename(p))[0]
  textPart = 'Generic'
  if options.text:
    textPart = options.text.split(',')[0]
  if options.appicon:
    base = saneBasename(options.appicon)
  else:
    base = saneBasename(getBgName(options))
  return '%s-%s.icns' % (base, textPart)


def cachedImage(filename):
  absPath = os.path.abspath(filename)
  if not absPath in imageCache:
    imageCache[absPath] = Image(absPath)
  return imageCache[absPath]


def cachedBackground(img, split):
  key = (img, split)
  if not key in bgCache:
    bgCache[key] = SplittableBackground(img, shouldSplit=split)
  return bgCache[key]


# taken from running flow on preview
defaultRects = {
    16: (-0.30890000000000001, 0.4919, -1.2968, 0.4743),
    32: (-0.27810000000000001,
      0.58930000000000005,
      -2.2292999999999998,
      0.57140000000000002),
    128: (1.1774, 0.56820000000000004, -0.8246, 0.56799999999999995),
    256: (0.5917, 0.56489999999999996, -1.8994, 0.56499999999999995),
    512: (0.68700000000000006,
      0.56530000000000002,
      -4.2813999999999997,
      0.56540000000000001)
    }


def getBgName(options):
  if not hasattr(options, 'background') \
      or options.background in ['default-split', 'default-unsplit']:
    return DEFAULT_BACKGROUND
  else:
    return options.background


class IconGenerator(object):
  def __init__(self, options):
    if hasattr(options, 'textrenderer') and options.textrenderer:
      self.textRenderer = options.textrenderer()
    else:
      self.textRenderer = TextRenderer()
    
    # Prepare input images
    splitBackground = options.background == 'default-split'
    self.bgIcon = cachedImage(getBgName(options))

    self.testIcon = None
    if options.appicon:
      self.testIcon = cachedImage(options.appicon)

    rects = defaultRects.copy()
    rects[16] = [ 0.0000, 0.5000, -1.0000, 0.5000]  # manually, better
    if hasattr(options, 'rects'):
      rects.update(options.rects)

    bg = cachedBackground(self.bgIcon, splitBackground)

    if hasattr(options, 'backgroundrenderer') and options.backgroundrenderer:
      self.bgRenderer = options.backgroundrenderer(bg, self.testIcon, rects)
    else:
      self.bgRenderer = BackgroundRenderer(bg, self.testIcon, rects)

    self.testtext = textDictFromTextList(options.text.split(','))

  def createIconAtSize(self, s):
    return createIcon(s, self.bgRenderer, self.textRenderer, self.testtext)


def iconGenerator(**kwargs):
  return IconGenerator(optsFromDict(**kwargs))


def makedocicon_opts(options):
  renderer = IconGenerator(options)

  if hasattr(options, 'sizes') and options.sizes:
    if isinstance(options.sizes, list):
      sizes = options.sizes
    else:
      sizes = map(int, options.sizes.split(','))
  else:
    sizes = renderer.bgIcon.sizes()
    if renderer.testIcon:
      sizes = sizes.intersection(renderer.testIcon.sizes())
    sizes = sorted(map(operator.itemgetter(0), sizes))

  icons = dict([(s, renderer.createIconAtSize(s)) for s in sizes])

  if options.debug:
    for s, icon in icons.iteritems():
      icon.save(options.debug % s)

  if hasattr(options, 'outname') and options.outname:
    outname = options.outname
  else:
    outname = getOutname(options)
  if saveIcns(icons, outname, options.makeicns):
    print 'Wrote', outname
  else:
    print 'Failed to write %s. Make sure makeicns is in your path.' % outname


def optsFromDict(**kwargs):
  options, _ = getopts().parse_args([])  # get default options
  for k in kwargs:
    setattr(options, k, kwargs[k])
  return options


def makedocicon(**kwargs):
  makedocicon_opts(optsFromDict(**kwargs))


def makedocicons_opts(options):
  if not hasattr(options, 'text') or not options.text:
    options.text = ['']
  texts = options.text
  for text in texts:
    options.text = text
    makedocicon_opts(options)


def makedocicons(**kwargs):
  makedocicons_opts(optsFromDict(**kwargs))


def getopts():
  parser = OptionParser(usage='%prog [options]', version='%prog 1.01')
  parser.add_option('--background', '--bg', default='default-split',
      help='Used as background (special values: "default-split" (default), ' \
          '"default-unsplit").')
  parser.add_option('--appicon', help='App icon, defaults to no icon.')

  parser.add_option('--text', help='Text on icon. Defaults to empty. '
      'More than one text is supported, multiple docicons are generated in '
      'that case.', action='append')
  parser.add_option('--sizes', help='Sizes of icons. ' \
      'Defaults to all sizes available in input appicon. Example: "512,128,16"')
  # XXX(Nico): This has to go
  parser.add_option('--debug', help='If set, write out pngs for all variants.' \
      ' This needs to look like "debug%d.png".')
  # XXX(Nico): This has to go once IconFamily is less buggy and can be used
  # directly
  parser.add_option('--makeicns', help='Path to makeicns binary',
      default='./makeicns')
  return parser


def main():
  options, args = getopts().parse_args()
  makedocicons_opts(options)


if __name__ == '__main__':
  main()
