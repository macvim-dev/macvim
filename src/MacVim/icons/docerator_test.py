import docerator
import unittest


class TextDictFromTextListTest(unittest.TestCase):

  def testBasic(self):

    self.assertEquals({16: 'a', 32: 'a', 128: 'a', 256: 'a', 512: 'a'},
        docerator.textDictFromTextList(['a']))
    self.assertEquals({16: 'b', 32: 'b', 128: 'a', 256: 'a', 512: 'a'},
        docerator.textDictFromTextList(['a', 'b']))
    self.assertEquals({16: 'c', 32: 'b', 128: 'a', 256: 'a', 512: 'a'},
        docerator.textDictFromTextList(['a', 'b', 'c']))


class OutnameTest(unittest.TestCase):

  class FakeOptions(object):
    def __init__(self, **kwargs):
      for k in kwargs:
        self.__setattr__(k, kwargs[k])

  def testBasic(self):
    options = OutnameTest.FakeOptions(
        appicon = '/Applications/iTunes.app/Contents/Resources/iTunes.icns',
        text='MP3')
    self.assertEquals('iTunes-MP3.icns', docerator.getOutname(options))

  def testTextList(self):
    options = OutnameTest.FakeOptions(
        appicon = '/Applications/iTunes.app/Contents/Resources/iTunes.icns',
        text='PYTHON,PY')
    self.assertEquals('iTunes-PYTHON.icns',
        docerator.getOutname(options))

  def testEmptyText(self):
    options = OutnameTest.FakeOptions(
        appicon = '/Applications/iTunes.app/Contents/Resources/iTunes.icns',
        text='')
    self.assertEquals('iTunes-Generic.icns', docerator.getOutname(options))
    options = OutnameTest.FakeOptions(
        appicon = '/Applications/iTunes.app/Contents/Resources/iTunes.icns',
        text=None)
    self.assertEquals('iTunes-Generic.icns',
        docerator.getOutname(options))

  def testEmptyIcon(self):
    options = OutnameTest.FakeOptions(appicon=None, text='MP3')
    self.assertEquals('GenericDocumentIcon-MP3.icns',
        docerator.getOutname(options))
    options = OutnameTest.FakeOptions(appicon=None, text='')
    self.assertEquals('GenericDocumentIcon-Generic.icns',
        docerator.getOutname(options))
    options = OutnameTest.FakeOptions(appicon=None, text='',
        background='/Applications/Bla/bgicon.icns')
    self.assertEquals('bgicon-Generic.icns',
        docerator.getOutname(options))


# XXX(Nico): Look at the doctest module.


if __name__ == '__main__':
  unittest.main()
