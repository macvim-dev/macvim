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


def splitGenericDocumentIcon(img, s):
  """Takes the generic document icon and splits it into a background and a
  shadow layer. For the 32x32 and 16x16 variants, the white pixels of the page
  curl are hardcoded into the otherwise transparent shadow layer."""

  r = None
  for rep in img.representations():
    if map(int, rep.size()) == [s, s]:
      r = rep
      break

  if not r:
    raise Exception('Unsupported size %d', s)

  # XXX: This is a bit slow in python, perhaps do this in C

  if r.bitmapFormat() != (NSAlphaNonpremultipliedBitmapFormat |
        NSAlphaFirstBitmapFormat) or \
      r.bitsPerPixel() != 32 or \
      r.isPlanar() or \
      r.samplesPerPixel() != 4:
    raise Exception("Unsupported image format")

  w, h = map(int, r.size())  # cocoa returns floats. cocoa ftw.
  bps = 4*w
  data = r.bitmapData()

  # These do not have alpha first!
  ground = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bitmapFormat_bytesPerRow_bitsPerPixel_(
      None, w, h, 8, 4, True, False, NSDeviceRGBColorSpace,
      NSAlphaNonpremultipliedBitmapFormat, 0, 0)

  shadow = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bitmapFormat_bytesPerRow_bitsPerPixel_(
      None, w, h, 8, 4, True, False, NSDeviceRGBColorSpace,
      NSAlphaNonpremultipliedBitmapFormat, 0, 0)

  grounddata = ground.bitmapData()
  shadowdata = shadow.bitmapData()

  for y in xrange(h):
    for x in xrange(w):
      idx = y*bps + 4*x
      ia, ir, ig, ib = data[idx:idx + 4]
      if ia != chr(255):
        # buffer objects don't support slice assignment :-(
        grounddata[idx] = ir
        grounddata[idx + 1] = ig
        grounddata[idx + 2] = ib
        grounddata[idx + 3] = ia
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
      shadowdata[idx] = chr(0)
      shadowdata[idx + 1] = chr(0)
      shadowdata[idx + 2] = chr(0)
      shadowdata[idx + 3] = chr(255 - ord(ir))


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


def drawText(text, s):
  """Draws text `s` into the current context of size `s`."""

  # This looks not exactly like the font on Preview.app's document icons,
  # but I believe that's because Preview's icons are drawn by Photoshop,
  # and Adobe's font rendering is different from Apple's.
  fontname = 'LucidaGrande-Bold'

  # Prepare text format
  style = NSMutableParagraphStyle.new()
  style.setParagraphStyle_(NSParagraphStyle.defaultParagraphStyle())
  style.setAlignment_(NSCenterTextAlignment)
  # http://developer.apple.com/documentation/Cocoa/Conceptual/AttributedStrings/Articles/standardAttributes.html#//apple_ref/doc/uid/TP40004903
  attribs = {
    NSParagraphStyleAttributeName: style,
    NSForegroundColorAttributeName: NSColor.colorWithDeviceWhite_alpha_(
        0.34, 1)
  }
  if s == 512:
    attribs[NSFontAttributeName] = NSFont.fontWithName_size_(fontname, 72.0)
    attribs[NSKernAttributeName] = -1.0  # tighten font a bit
  elif s == 256:
    attribs[NSFontAttributeName] = NSFont.fontWithName_size_(fontname, 36.0)
    attribs[NSKernAttributeName] = -1.0  # tighten font a bit
  elif s == 128:
    attribs[NSFontAttributeName] = NSFont.fontWithName_size_(fontname, 18.0)
  elif s == 32:
    #attribs[NSFontAttributeName] = NSFont.fontWithName_size_(
      #'LucidaSans-Demi', 7.0)
    attribs[NSKernAttributeName] = -0.25  # tighten font a bit
    if NSFontAttributeName not in attribs:
      attribs[NSFontAttributeName] = NSFont.fontWithName_size_(fontname, 7.0)
  elif s == 16:
    attribs[NSFontAttributeName] = NSFont.fontWithName_size_(fontname, 3.0)

  if not attribs[NSFontAttributeName]:
    print 'Failed to load font', fontname
    sys.exit(1)

  textRects = {
      512: ((0, 7), (512, 119)),
      128: ((0, 6), (128, 26.5)),
      256: ((0, 7), (256, 57)),
      }

  if s in [128, 256, 512]:
    text.drawInRect_withAttributes_(textRects[s], attribs)
  elif s == 32:
    #text.drawInRect_withAttributes_( ((1, 1), (31, 9)), attribs)

    # Try to align text on pixel boundary:
    ts = text.sizeWithAttributes_(attribs)
    attribs[NSParagraphStyleAttributeName] = \
        NSParagraphStyle.defaultParagraphStyle()
    text.drawAtPoint_withAttributes_( (math.floor((32.0-ts[0])/2) + 0.5, 1.5),
        attribs)

    # for demibold roman:
    #text.drawInRect_withAttributes_( ((0, 1), (31, 11)), attribs)
  elif s == 16:
    text.drawInRect_withAttributes_( ((1, 1), (15, 5)), attribs)


def createIcon(outname, text, ground, icon, shadow=None, s=512,
    shorttext=None):

  output = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bitmapFormat_bytesPerRow_bitsPerPixel_(
      None, s, s, 8, 4, True, False, NSDeviceRGBColorSpace, 0, 0, 0)

  # Draw!
  NSGraphicsContext.saveGraphicsState();
  context = NSGraphicsContext. graphicsContextWithBitmapImageRep_(output);
  context.setShouldAntialias_(True);
  context.setImageInterpolation_(NSImageInterpolationHigh);
  NSGraphicsContext.setCurrentContext_(context);


  # luckily, cocoa simply copies the 128x128 version over for s = 128
  # and does no resampling.
  ground.draw()
  #bg.drawInRect_fromRect_operation_fraction_(
      #((0, 0), (s, s)),
      #NSZeroRect, NSCompositeCopy, 1.0)

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

  if s in [16, 32, 128, 256, 512]:
    a = transforms[s]

    # convert from `flow` coords to cocoa
    a[2] = -a[2]  # mirror y

    w, h = s*a[1], s*a[3]
    icon.drawInRect_fromRect_operation_fraction_(
        (((s-w)/2 + a[0], (s-h)/2 + a[2]), (w, h)),
        NSZeroRect, NSCompositeSourceOver, 1.0)


  # Overlay shadow.
  # shadow needs to be composited, so it needs to be in an nsimage
  shadowImg = NSImage.alloc().initWithSize_( (s, s) )
  shadowImg.addRepresentation_(shadow)
  shadowImg.drawInRect_fromRect_operation_fraction_(
      ((0, 0), (s, s)),
      NSZeroRect, NSCompositeSourceOver, 1.0)


  # draw text on top of shadow
  if s in [16, 32] and shorttext:
    text = shorttext
  drawText(text, s)


  NSGraphicsContext.restoreGraphicsState();

  # Save
  png = output.representationUsingType_properties_(NSPNGFileType, None)
  png.writeToFile_atomically_(outname, True)


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
    for name in vimIcons:
      if name == GENERIC_ICON_NAME: continue
      icnsName = '%s.icns' % name
      if os.access(icnsName, os.F_OK):
        os.remove(icnsName)
      os.symlink('%s.icns' % GENERIC_ICON_NAME, icnsName)
    return
  # Make us not crash
  # http://www.cocoabuilder.com/archive/message/cocoa/2008/8/6/214964
  NSApplicationLoad()

  # Prepare input images
  bg = NSImage.alloc().initWithContentsOfFile_(BACKGROUND)
  if not bg:
    print 'Failed to load', bgname
    sys.exit(1)

  grounds, shadows = zip(*[splitGenericDocumentIcon(bg, s) for s in sizes])
  grounds = dict(zip(sizes, grounds))
  shadows = dict(zip(sizes, shadows))

  icon = NSImage.alloc().initWithContentsOfFile_(appIcon)
  if not icon:
    print 'Failed to load', appIcon
    sys.exit(1)

  if not os.access(makeIcns, os.X_OK):
    print 'Cannot find makeicns at %s', makeIcns
    return

  # create LARGE and SMALL icons first...
  for name, t in vimIcons.iteritems():
    text, size = t
    if size == LINK: continue
    print name
    icnsName = '%s.icns' % name

    for s in sizes:
      st = shorttext.get(name)
      if st: st = NSString.stringWithString_(st)
      createIcon(TMPFILE % s, NSString.stringWithString_(text),
          grounds[s], icon, shadows[s], s=s, shorttext=st)

    if size == LARGE:
      os.system('%s -512 %s -128 %s -32 %s -16 %s -out %s' % (makeIcns,
        TMPFILE % 512, TMPFILE % 128, TMPFILE % 32, TMPFILE % 16, icnsName))
    elif size == SMALL:
      os.system('%s -128 %s -32 %s -16 %s -out %s' % (makeIcns,
        TMPFILE % 128, TMPFILE % 32, TMPFILE % 16, icnsName))

  del text, size, name, t

  # ...create links later (to make sure the link targets exist)
  for name, t in vimIcons.iteritems():
    text, size = t
    if size != LINK: continue
    print 'symlinking', name
    icnsName = '%s.icns' % name

    # remove old version of icns
    if os.access(icnsName, os.F_OK):
      os.remove(icnsName)
    os.symlink('%s.icns' % GENERIC_ICON_NAME, icnsName)



if __name__ == '__main__':
  try:
    main()
  finally:
    for s in sizes:
      if os.access(TMPFILE % s, os.F_OK):
        os.remove(TMPFILE % s)
