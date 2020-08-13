#! /usr/bin/env python
"""
This script adds a license file to a DMG. Requires Xcode and a plain ascii text
license file or an RTF license file.
Obviously only runs on a Mac.

Copyright (C) 2011-2019 Jared Hobbs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
"""
from __future__ import unicode_literals
from subprocess import check_call, check_output, call, CalledProcessError
import argparse
import logging as logger
import os
import sys
import tempfile

logger.basicConfig(format='%(message)s', level=logger.DEBUG)


class Path(str):
    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        os.unlink(self)


def mktemp(dir=None, suffix=''):
    fd, filename = tempfile.mkstemp(dir=dir, suffix=suffix)
    os.close(fd)
    return Path(filename)


def escape(s):
    return s.strip().replace('\\', '\\\\').replace('"', '\\"')


def main(options):
    dmg_file = options.dmg_file
    output = options.output or dmg_file
    license = options.license_file
    if dmg_file != output:
        check_call(['cp', dmg_file, output])
        dmg_file = output
    with mktemp('.') as tmp_file:
        with open(tmp_file, 'w') as f:
            f.write("""\
data 'TMPL' (128, "LPic") {
    $"1344 6566 6175 6C74 204C 616E 6775 6167"
    $"6520 4944 4457 5244 0543 6F75 6E74 4F43"
    $"4E54 042A 2A2A 2A4C 5354 430B 7379 7320"
    $"6C61 6E67 2049 4444 5752 441E 6C6F 6361"
    $"6C20 7265 7320 4944 2028 6F66 6673 6574"
    $"2066 726F 6D20 3530 3030 4457 5244 1032"
    $"2D62 7974 6520 6C61 6E67 7561 6765 3F44"
    $"5752 4404 2A2A 2A2A 4C53 5445"
};

data 'LPic' (5000) {
    $"0000 0002 0000 0000 0000 0000 0004 0000"
};

data 'STR#' (5000, "English buttons") {
    $"0006 0D45 6E67 6C69 7368 2074 6573 7431"
    $"0541 6772 6565 0844 6973 6167 7265 6505"
    $"5072 696E 7407 5361 7665 2E2E 2E7A 4966"
    $"2079 6F75 2061 6772 6565 2077 6974 6820"
    $"7468 6520 7465 726D 7320 6F66 2074 6869"
    $"7320 6C69 6365 6E73 652C 2063 6C69 636B"
    $"2022 4167 7265 6522 2074 6F20 6163 6365"
    $"7373 2074 6865 2073 6F66 7477 6172 652E"
    $"2020 4966 2079 6F75 2064 6F20 6E6F 7420"
    $"6167 7265 652C 2070 7265 7373 2022 4469"
    $"7361 6772 6565 2E22"
};

data 'STR#' (5002, "English") {
    $"0006 0745 6E67 6C69 7368 0541 6772 6565"
    $"0844 6973 6167 7265 6505 5072 696E 7407"
    $"5361 7665 2E2E 2E7B 4966 2079 6F75 2061"
    $"6772 6565 2077 6974 6820 7468 6520 7465"
    $"726D 7320 6F66 2074 6869 7320 6C69 6365"
    $"6E73 652C 2070 7265 7373 2022 4167 7265"
    $"6522 2074 6F20 696E 7374 616C 6C20 7468"
    $"6520 736F 6674 7761 7265 2E20 2049 6620"
    $"796F 7520 646F 206E 6F74 2061 6772 6565"
    $"2C20 7072 6573 7320 2244 6973 6167 7265"
    $"6522 2E"
};\n\n""")
            with open(license, 'r') as l_file:
                kind = 'RTF ' if license.lower().endswith('.rtf') else 'TEXT'
                f.write('data \'{}\' (5000, "English") {{\n'.format(kind))

                for line in l_file:
                    if len(line) < 1000:
                        f.write('    "{}\\n"\n'.format(escape(line)))
                    else:
                        for liner in line.split('.'):
                            f.write('    "{}. \\n"\n'.format(escape(liner)))
                f.write('};\n\n')
            f.write("""\
data 'styl' (5000, "English") {
    $"0003 0000 0000 000C 0009 0014 0000 0000"
    $"0000 0000 0000 0000 0027 000C 0009 0014"
    $"0100 0000 0000 0000 0000 0000 002A 000C"
    $"0009 0014 0000 0000 0000 0000 0000"
};\n""")
        call(['hdiutil', 'unflatten', '-quiet', dmg_file])
        ret = check_call([options.rez, '-a', tmp_file, '-o', dmg_file])
        call(['hdiutil', 'flatten', '-quiet', dmg_file])
        if options.compression is not None:
            tmp_dmg = '{}.temp.dmg'.format(dmg_file)
            check_call(['cp', dmg_file, tmp_dmg])
            os.remove(dmg_file)
            args = ['hdiutil', 'convert', tmp_dmg, '-quiet', '-format']
            if options.compression == 'bz2':
                args.append('UDBZ')
            elif options.compression == "gz":
                args.extend(['UDZO', '-imagekey', 'zlib-devel=9'])
            args.extend(['-o', dmg_file])
            check_call(args)
            os.remove(tmp_dmg)
    if ret == 0:
        logger.info("Successfully added license to '{}'".format(dmg_file))
    else:
        logger.error("Failed to add license to '{}'".format(dmg_file))


if __name__ == '__main__':
    try:
        rez_path = check_output(
            ['xcrun', '--find', 'Rez'],
        ).strip().decode('utf-8')
    except CalledProcessError:
        rez_path = '/Library/Developer/CommandLineTools/usr/bin/Rez'
    parser = argparse.ArgumentParser(
        description="""\
This program adds a software license agreement to a DMG file.
It requires Xcode and either a plain ascii text <license_file>
or a <license_file.rtf> with the RTF contents.

See --help for more details.""",
    )
    parser.add_argument(
        'dmg_file',
        help='the path to the dmg file which will receive the license',
    )
    parser.add_argument(
        'license_file',
        help='the path to the plain ascii or RTF license file; for RTF files, '
             'the file must use a .rtf extension',
    )
    parser.add_argument(
        '--rez',
        '-r',
        action='store',
        default=rez_path,
        help='the path to the Rez tool; defaults to %(default)s',
    )
    parser.add_argument(
        '--compression',
        '-c',
        action='store',
        choices=('bz2', 'gz'),
        default=None,
        help='optionally compress dmg using specified compression type; '
             'choices are bz2 and gz',
    )
    parser.add_argument(
        '--output',
        '-o',
        action='store',
        default=None,
        help='specify an output DMG file; if not given, the license will be '
             'directly applied to the input DMG file',
    )
    options = parser.parse_args()
    if not os.path.exists(options.rez):
        logger.error('Failed to find Rez at "{}"!\n'.format(options.rez))
        parser.print_usage()
        sys.exit(1)
    main(options)
