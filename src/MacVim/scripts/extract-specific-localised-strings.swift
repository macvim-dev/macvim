#! /usr/bin/swift

// MacVim changes
//
// This script was taken from Douglas Hill's Gist in order to quickly extract official translations from Apple's
// glossary files for translations for MacVim menus: https://gist.github.com/douglashill/c5b08a9099883475294d27cecc56ec29
//
// A variable called `isMainMenu` was added to toggle between generating translations for Vim menus (which are in `.vim`
// files with menutranslate commands) or MacVim nib menus (which use .strings files). It could be changed by passing
// --vimMenu or --mainMenu as command parameters in.
//
// The Localisation struct also has a new `vimMenuTrans` member to store the Vim translation file's name to output to,
// as that file name depends on the locale (some are done in the latin1 file, while others in the utf-8 ones, etc).
//
// To use this:
// 1. First download all the glossaries from Apple Developer, and mount the DMG's.
// 2. Run this script with --mainMenu. This will generate the translations for MainMenu.xib. Copy each locale's
//    Localizable.strings into each MainMenu.strings in MacVim.
// 3. Run this script with --vimMenu. This should output the updated string names to the individual locale's .vim
//    translation files.

var isMainMenu = true
for argument in CommandLine.arguments {
    switch argument {
    case "--vimMenu":
        isMainMenu = false

    case "--mainMenu":
        isMainMenu = true

    case "--help":
        print("extract-specific-localised-strings.swift [--vimMenu] [--mainMenu]")
        exit(0)

    default:
        continue
    }
}


// Douglas Hill, March 2020
// This file is made available under the MIT license included at the bottom of this file.

/*
 Extracts specific localised strings from Apple’s glossary files.

 This script helped with localisation for KeyboardKit (https://github.com/douglashill/KeyboardKit) by leveraging Apple’s existing translations.

 More detail in the article at https://douglashill.co/localisation-using-apples-glossaries/

 It reads each needed translation by looking up translations for specific keys in specific glossary files.

 ## Adapting for other projects

 1. Set the outputDirectory below.
 2. Change neededLocalisations to the keys your project needs.

 ## Generating the .strings files

 1. Download all macOS and iOS glossary DMGs from the Apple Developer website (sign in required): https://developer.apple.com/download/more
 2. Mount all of these DMGs on your Mac. There should be about 80. DiskImageMounter may get stuck if you try mounting ~20 or more at once, so opening in batches of ~15 is recommended.
 3. Run this script. Look out for any errors in the console. That may indicate some DMGs failed to mount, or Apple removed a localisation key or added one so the lookup is ambiguous.
 4. Manually edit all the .strings file for quality of translation. Pay special attention to American English (en.lproj) because it’s generated from Australian English.

 ## Adding new localised strings

 1. Locate the same text used in Apple software and identify the glossary where this can be found and the key used.
 2. Add this as a `NeededLocalisation` in the `neededLocalisations` array in the script `main.swift`. This order of this array is matches the final order in the `.strings` files. It should be sorted alphabetically by key.
 3. Follow the steps for generating above.
 */

import Foundation

// MARK: Input data

/// The directory containing the .lproj directories where the .strings files will be written.
var outputDirectory = URL(fileURLWithPath: "./xib_strings")
if !isMainMenu {
    outputDirectory = URL(fileURLWithPath: "../../../runtime/lang/macvim_menu")
}

// Possible improvement:
// We identify using glossary -> key, which could be ambiguous because there are entries from
// many .strings files in each glossary file, so there can be duplicate keys in the glossary.
// This is handled by finding all matches and printing an error if there are multiple matches.
// It would be better to identify each needed localisation by glossary -> filename -> key.

/// A localised strings entry that we want to extract from Apple’s glossary files.
struct NeededLocalisation {
    /// The key to use in the generated KeyboardKit .strings file.
    let targetKey: String
    /// The key (AKA Position) that Apple uses in their glossary.
    let appleKey: String
    /// The file base name of the glossary file in which this localisation can be found. I.e. the filename is glossaryFilename.lg.
    let glossaryFilename: String
}

// These are the translations we need for MainMenu.xib, which contains the app menu as well.
let neededLocalisations_mainmenu_xib = [
    // Preferences…
    NeededLocalisation(targetKey: "129.title", appleKey: "501.title", glossaryFilename: "TextEdit"),
    // Services
    NeededLocalisation(targetKey: "130.title", appleKey: "503.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "131.title", appleKey: "504.title", glossaryFilename: "TextEdit"),
    // Clear Menu
    NeededLocalisation(targetKey: "272.title", appleKey: "461.title", glossaryFilename: "TextEdit"),
    // Hide Others
    NeededLocalisation(targetKey: "145.title", appleKey: "515.title", glossaryFilename: "TextEdit"),
    // Show All
    NeededLocalisation(targetKey: "150.title", appleKey: "517.title", glossaryFilename: "TextEdit"),

    // File
    NeededLocalisation(targetKey: "218.title", appleKey: "279.title", glossaryFilename: "TextEdit"),
    // File
    NeededLocalisation(targetKey: "217.title", appleKey: "274.title", glossaryFilename: "TextEdit"),
    // New Window (Main menu and Dock menu)
    NeededLocalisation(targetKey: "219.title",  appleKey: "82.title", glossaryFilename: "WebBrowser"),
    NeededLocalisation(targetKey: "338.title",  appleKey: "82.title", glossaryFilename: "WebBrowser"),
    // Open…
    NeededLocalisation(targetKey: "261.title", appleKey: "276.title", glossaryFilename: "TextEdit"),
    // Open Recent
    NeededLocalisation(targetKey: "271.title", appleKey: "459.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "262.title", appleKey: "459.title", glossaryFilename: "TextEdit"),
    // Close
    NeededLocalisation(targetKey: "248.title", appleKey: "419.title", glossaryFilename: "TextEdit"),

    // Edit
    NeededLocalisation(targetKey: "282.title", appleKey: "4.title", glossaryFilename: "TextEdit"),
    // Edit
    NeededLocalisation(targetKey: "281.title", appleKey: "96.title", glossaryFilename: "TextEdit"),
    // Undo
    NeededLocalisation(targetKey: "283.title", appleKey: "dRJ-4n-Yzg.title", glossaryFilename: "Notes"),
    // Redo
    NeededLocalisation(targetKey: "284.title", appleKey: "6dh-zS-Vam.title", glossaryFilename: "Notes"),
    // Cut
    NeededLocalisation(targetKey: "286.title", appleKey: "124.title", glossaryFilename: "TextEdit"),
    // Copy
    NeededLocalisation(targetKey: "287.title", appleKey: "120.title", glossaryFilename: "TextEdit"),
    // Paste
    NeededLocalisation(targetKey: "288.title", appleKey: "112.title", glossaryFilename: "TextEdit"),
    // Select All
    NeededLocalisation(targetKey: "291.title", appleKey: "101.title", glossaryFilename: "TextEdit"),

    // Window
    NeededLocalisation(targetKey: "310.title", appleKey: "475.title", glossaryFilename: "TextEdit"),
    // Window
    NeededLocalisation(targetKey: "309.title", appleKey: "474.title", glossaryFilename: "TextEdit"),
    // Minimize
    NeededLocalisation(targetKey: "311.title", appleKey: "477.title", glossaryFilename: "TextEdit"),
    // Zoom
    NeededLocalisation(targetKey: "312.title", appleKey: "Zoom", glossaryFilename: "AppKit"),
    // Bring All to Front
    NeededLocalisation(targetKey: "314.title", appleKey: "Bring All to Front", glossaryFilename: "AppKit"),

    // Help
    NeededLocalisation(targetKey: "233.title", appleKey: "526.title", glossaryFilename: "TextEdit"),
    // Help
    NeededLocalisation(targetKey: "232.title", appleKey: "524.title", glossaryFilename: "TextEdit"),
]

// These are the translations for the Vim menus that MacVim re-named to fit Apple's HIG better.
let neededLocalisations_vim = [
    NeededLocalisation(targetKey: "New\\ Window",  appleKey: "82.title", glossaryFilename: "WebBrowser"),
    NeededLocalisation(targetKey: "New\\ Tab",  appleKey: "649.title", glossaryFilename: "WebBrowser"),
    NeededLocalisation(targetKey: "Open…", appleKey: "276.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Open\\ Recent", appleKey: "459.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Close\\ Window<Tab>:qa", appleKey: "Close Window", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Close<Tab>:q", appleKey: "419.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Save\\ As…<Tab>:sav", appleKey: "281.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Save\\ All", appleKey: "284.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Find",  appleKey: "317.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Find…",  appleKey: "311.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Find\\ Next",  appleKey: "312.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Find\\ Previous",  appleKey: "314.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Use\\ Selection\\ for\\ Find", appleKey: "316.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Font", appleKey: "159.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Show\\ Fonts", appleKey: "172.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Bigger", appleKey: "543.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Smaller", appleKey: "544.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Minimize", appleKey: "477.title", glossaryFilename: "TextEdit"),
    NeededLocalisation(targetKey: "Minimize\\ All", appleKey: "Minimize All", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Zoom", appleKey: "Zoom", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Zoom\\ All", appleKey: "Zoom All", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Show\\ Next\\ Tab", appleKey: "Show Next Tab", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Show\\ Previous\\ Tab", appleKey: "Show Previous Tab", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Bring\\ All\\ to\\ Front", appleKey: "Bring All to Front", glossaryFilename: "AppKit"),
    NeededLocalisation(targetKey: "Release\\ Notes", appleKey: "Release Notes (WFContentItemPropertyName)", glossaryFilename: "Shortcuts"),
]

var neededLocalisations = neededLocalisations_mainmenu_xib
if !isMainMenu {
    neededLocalisations = neededLocalisations_vim
}

struct Localisation {
    /// The language code as used for .lproj directories.
    let code: String
    /// Vim menu translation file name
    let vimMenuTrans: String
    /// Enough of the volume name for Apple’s DMG to pick this localisation out from the others. E.g. just ‘French’ would not enough because it would match both Universal French and Canadian French.
    let volumeName: String
}

let localisations = [
//    Localisation(code: "ar", volumeName: "Arabic"),
    Localisation(code: "ca", vimMenuTrans: "ca_es.latin1", volumeName: "Catalan"),
    Localisation(code: "cs", vimMenuTrans: "cs_cz.utf-8", volumeName: "Czech"),
    Localisation(code: "da", vimMenuTrans: "da.utf-8", volumeName: "Danish"),
    Localisation(code: "de", vimMenuTrans: "de_de.latin1", volumeName: "German"),
//    Localisation(code: "el", volumeName: "Greek"),
//    Localisation(code: "en", volumeName: "Australian English"), // Apple does not provide a glossary for en.
//    Localisation(code: "en-AU", volumeName: "Australian English"),
//    Localisation(code: "en-GB", volumeName: "British English"),
    Localisation(code: "es", vimMenuTrans: "es_es.latin1", volumeName: "Spanish"),
//    Localisation(code: "es-419", volumeName: "Latin"),
    Localisation(code: "fi", vimMenuTrans: "fi_fi.latin1", volumeName: "Finnish"),
    Localisation(code: "fr", vimMenuTrans: "fr_fr.latin1", volumeName: "Universal French"),
//    Localisation(code: "fr-CA", volumeName: "Canadian"),
//    Localisation(code: "he", volumeName: "Hebrew"),
//    Localisation(code: "hi", volumeName: "Hindi"),
//    Localisation(code: "hr", volumeName: "Croatian"),
    Localisation(code: "hu", vimMenuTrans: "hu_hu.utf-8", volumeName: "Hungarian"),
//    Localisation(code: "id", volumeName: "Indonesian"),
    Localisation(code: "it", vimMenuTrans: "it_it.latin1", volumeName: "Italian"),
    Localisation(code: "ja", vimMenuTrans: "ja_jp.utf-8", volumeName: "Japanese"),
    Localisation(code: "ko", vimMenuTrans: "ko_kr.utf-8", volumeName: "Korean"),
//    Localisation(code: "ms", volumeName: "Malay"),
    Localisation(code: "nb", vimMenuTrans: "no_no.latin1", volumeName: "Norwegian"),
    Localisation(code: "nl", vimMenuTrans: "nl_nl.latin1", volumeName: "Dutch"),
    Localisation(code: "pl", vimMenuTrans: "pl_pl.utf-8", volumeName: "Polish"),
    Localisation(code: "pt-BR", vimMenuTrans: "pt_br", volumeName: "Brazilian"),
    Localisation(code: "pt-PT", vimMenuTrans: "pt_pt", volumeName: "Portuguese"),
//    Localisation(code: "ro", volumeName: "Romanian"),
    Localisation(code: "ru", vimMenuTrans: "ru_ru", volumeName: "Russian"),
//    Localisation(code: "sk", volumeName: "Slovak"),
    Localisation(code: "sv", vimMenuTrans: "sv_se.latin1", volumeName: "Swedish"),
//    Localisation(code: "th", volumeName: "Thai"),
    Localisation(code: "tr", vimMenuTrans: "tr_tr.utf-8", volumeName: "Turkish"),
//    Localisation(code: "uk", volumeName: "Ukrainian"),
//    Localisation(code: "vi", volumeName: "Vietnamese"),
    Localisation(code: "zh-Hans", vimMenuTrans: "zh_cn.utf-8", volumeName: "Simplified Chinese"),
    Localisation(code: "zh-Hant", vimMenuTrans: "zh_tw.utf-8", volumeName: "Traditional Chinese"),
//    Localisation(code: "zh-HK", volumeName: "Hong Kong"),
]

// MARK: - Support

extension Collection {
    /// The only element in the collection, or nil if there are multiple or zero elements.
    var single: Element? { count == 1 ? first! : nil }
}

extension URL {
    public func appendingPathComponents(_ pathComponents: [String]) -> URL {
        return pathComponents.enumerated().reduce(self) { url, pair in
            return url.appendingPathComponent(pair.element, isDirectory: pair.offset + 1 < pathComponents.count)
        }
    }
}

extension XMLElement {
    func singleChild(withName name: String) -> XMLElement? {
        elements(forName: name).single
    }
}

extension XMLNode {
    var textOfSingleChild: String? {
        guard let singleChild = children?.single, singleChild.kind == .text else {
            return nil
        }
        return singleChild.stringValue
    }
}

/// A localisation entry parsed from a glossary.
struct LocalisationEntry {
    /// The file where the entry was read from.
    let fileURL: URL
    /// The usage description to help with translation.
    let comment: String?
    /// The key to look up this string. This is optional because some Apple strings files use just whitespace as a key and NSXMLDocument can not read whitespace-only text elements.
    let key: String?
    /// The English text.
    let base: String
    /// The localised text.
    let translation: String
}

func readLocalisationEntriesFromFile(at fileURL: URL) -> [LocalisationEntry] {
    let doc = try! XMLDocument(contentsOf: fileURL, options: [.nodePreserveWhitespace])

    return doc.rootElement()!.elements(forName: "File").flatMap { file -> [LocalisationEntry] in
        file.elements(forName: "TextItem").compactMap { textItem -> LocalisationEntry? in
            let translationSet = textItem.singleChild(withName: "TranslationSet")!

            guard let base = translationSet.singleChild(withName: "base")!.textOfSingleChild, let translation = translationSet.singleChild(withName: "tran")!.textOfSingleChild else {
                return nil
            }

            return LocalisationEntry(
                fileURL: fileURL,
                comment: textItem.singleChild(withName: "Description")!.textOfSingleChild,
                key: textItem.singleChild(withName: "Position")!.textOfSingleChild,
                base: base,
                translation: translation
            )
        }
    }
}

func memoisedReadLocalisationEntriesFromFile(at fileURL: URL) -> [LocalisationEntry] {
    enum __ { static var results: [URL: [LocalisationEntry]] = [:] }

    if let existingResult = __.results[fileURL] {
        return existingResult
    }

    let newResult = readLocalisationEntriesFromFile(at: fileURL)
    __.results[fileURL] = newResult
    return newResult
}

// MARK: - The script itself

let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])!

for localisation in localisations {
    // This reduces peak memory usage from ~2GB to ~200MB.
    autoreleasepool { () -> Void in

        let matchingVolumes = volumes.filter { fileURL -> Bool in
            fileURL.lastPathComponent.contains(localisation.volumeName)
        }

        print("ℹ️ Localising \(localisation.volumeName) (\(localisation.code)) from \(matchingVolumes.count) volumes.") // There should be 2 volumes.

        let lines = neededLocalisations.compactMap { neededLocalisation -> String? in
            let localisationEntries = matchingVolumes.flatMap { volumeURL -> [LocalisationEntry] in
                let glossaryFilePaths = try! FileManager.default.contentsOfDirectory(at: volumeURL, includingPropertiesForKeys: nil, options: []).filter { fileURL in
                    fileURL.lastPathComponent.contains(neededLocalisation.glossaryFilename)
                }

                return glossaryFilePaths.flatMap { fileURL -> [LocalisationEntry] in
                    memoisedReadLocalisationEntriesFromFile(at: fileURL).filter { entry in
                        entry.key == neededLocalisation.appleKey
                    }
                }
            }

            let translations: Set<String> = Set<String>(localisationEntries.map { $0.translation })

            guard let translation = translations.single else {
                print("❌ Wrong number of matches for \(neededLocalisation.appleKey) in files matching \(neededLocalisation.glossaryFilename): \(translations)")
                return nil
            }

            if isMainMenu {
                return """
                "\(neededLocalisation.targetKey)" = "\(translation)";
                """
            }
            else {
                let escapedTranslation = translation.replacingOccurrences(of: " ", with: "\\ ", options: .literal, range: nil)
                                                    .replacingOccurrences(of: " ", with: "\\ ", options: .literal, range: nil)

                return """
                menutrans \(neededLocalisation.targetKey) \(escapedTranslation)
                """
            }
        }

        var targetStringsFileURL = outputDirectory.appendingPathComponents(["\(localisation.code).lproj", "Localizable.strings"])
        if !isMainMenu {
            targetStringsFileURL = outputDirectory.appendingPathComponents(["menu_\(localisation.vimMenuTrans).apple.vim"])
        }

        try! FileManager.default.createDirectory(at: targetStringsFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        if isMainMenu {
            try! """
                // The strings below were generated from Apple localization glossaries (\(localisation.volumeName)).
                // See extract-specific-localised-strings.swift for details.
                // Do no modify directly!

                \(lines.joined(separator: "\n"))

                """.write(to: targetStringsFileURL, atomically: false, encoding: .utf8)
        }
        else {
            try! """
                " This file was generated from Apple localization glossaries (\(localisation.volumeName)).
                " Do not modify this file directly!

                \(lines.joined(separator: "\n"))

                """.write(to: targetStringsFileURL, atomically: false, encoding: .utf8)
        }
    }
}

/*
 The MIT License (MIT)

 Copyright 2020 Douglas Hill

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 the Software, and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
