# Creates a document icon from an app icon and an optional text.

# The font is not quite right, use this script to create a document icon
# for 'PDF' and compare the D with the D in Preview's pdf.icns

# http://www.macresearch.org/cocoa-scientists-part-xx-python-scriptersmeet-cocoa
import os
import sys
try:
  from Foundation import *
  from AppKit import *
  dont_create = False
except:
  dont_create = True  # most likely because we're on tiger

# icon types
LARGE = 0  # 512, 128, 32, 16; about 96kB
SMALL = 1  # 128, 32, 16; about 36kB
LINK = 2  # Create link to generic icon; 4kB (== smallest block size on HFS+)

# path to makeicns binary
MAKEICNS = 'makeicns/makeicns'

# List of icons to create
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
    'MacVim-csfg': [u'CFDG', LINK], #D
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
    'MacVim-bsh': [u'BSH', LINK], #D
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
    'MacVim-gtd': [u'GTD', LINK], #D
}


# Resources
BACKGROUND = '/System/Library/CoreServices/CoreTypes.bundle/' + \
    'Contents/Resources/GenericDocumentIcon.icns'  # might require leopard?
APPICON = 'vim-noshadow-512.png'
#APPICON = 'vim-noshadow-no-v-512.png'


def createIcon(outname, text, iconname=APPICON, bgname=BACKGROUND):
  # Prepare input images
  bg = NSImage.alloc().initWithContentsOfFile_(bgname)
  if not bg:
    print 'Failed to load', bgname
    sys.exit(1)

  icon = NSImage.alloc().initWithContentsOfFile_(iconname)
  if not icon:
    print 'Failed to load', iconname
    sys.exit(1)


  # Prepare text format
  style = NSMutableParagraphStyle.new()
  style.setParagraphStyle_(NSParagraphStyle.defaultParagraphStyle())
  style.setAlignment_(NSCenterTextAlignment)
  # http://developer.apple.com/documentation/Cocoa/Conceptual/AttributedStrings/Articles/standardAttributes.html#//apple_ref/doc/uid/TP40004903
  fontname = 'LucidaGrande-Bold'
  attribs = {
      NSParagraphStyleAttributeName: style,
      NSParagraphStyleAttributeName: style,
      NSFontAttributeName: NSFont.fontWithName_size_(fontname, 72.0),
      NSKernAttributeName: -1.0,  # tighten font a bit
      NSForegroundColorAttributeName: NSColor.colorWithDeviceWhite_alpha_(
        0.34, 1)
  }

  if not attribs[NSFontAttributeName]:
    print 'Failed to load font', fontname
    sys.exit(1)


  # Draw!
  bg.lockFocus()
  w, h = 289, 289
  icon.drawInRect_fromRect_operation_fraction_(
      (((512-w)/2 + 1, 405 - h), (w, h)),
      NSZeroRect, NSCompositeSourceOver, 1.0)
  text.drawInRect_withAttributes_( ((0, 7), (512, 119)), attribs)
  bg.unlockFocus()

  # Save
  # http://www.cocoadev.com/index.pl?NSImageToJPEG (this is retarded)
  tmp = NSBitmapImageRep.imageRepWithData_(bg.TIFFRepresentation())
  png = tmp.representationUsingType_properties_(NSPNGFileType, None)
  png.writeToFile_atomically_(outname, True)


TMPFILE = 'make_icons_tmp.png'
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

  #createIcon('test.png',
      #NSString.stringWithString_(u'PDF'), iconname='preview.icns')

  if not os.access(makeIcns, os.X_OK):
    print 'Cannot find makeicns at', makeIcns
    return

  # create LARGE and SMALL icons first...
  for name, t in vimIcons.iteritems():
    text, size = t
    if size == LINK: continue
    print name
    icnsName = '%s.icns' % name

    createIcon(TMPFILE, NSString.stringWithString_(text), appIcon)
    if size == LARGE:
      os.system('%s -512 %s -128 %s -32 %s -16 %s -out %s' % (makeIcns,
        TMPFILE, TMPFILE, TMPFILE, TMPFILE, icnsName))
    elif size == SMALL:
      os.system('%s -128 %s -32 %s -16 %s -out %s' % (makeIcns,
        TMPFILE, TMPFILE, TMPFILE, icnsName))

  # ...create links later (to make sure the link targets exist)
  for name, t in vimIcons.iteritems():
    text, size = t
    if size != LINK: continue
    print name
    icnsName = '%s.icns' % name

    # remove old version of icns
    if os.access(icnsName, os.F_OK):
      os.remove(icnsName)
    os.symlink('%s.icns' % GENERIC_ICON_NAME, icnsName)


if __name__ == '__main__':
  try:
    main()
  finally:
    if os.access(TMPFILE, os.F_OK):
      os.remove(TMPFILE)
