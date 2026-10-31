<img width="150" alt="Icon-iOS" src="https://user-images.githubusercontent.com/35755386/169313051-fc0338da-f3bd-4da1-b752-99fd8fb96666.png">

# Title Capitalizr for iOS and macOS
An app that automatically **capitalizes** the **title** of your essay. Supports **MLA**, **APA**, **AP**, and **Chicago** styles.

> "You probably wouldn't capitalize words like "and", "to", and "for" and the app likewise leaves these lowercase."

*— An Anonymous Reddit Comment*

---

## Official Build 1.7

### [Download on the App Store](https://apps.apple.com/us/app/title-capitalizr/id1625011191)

We care about your **privacy**. Check out our [**user policy**](https://github.com/wonmor/Title-Capitalizr-iOS/blob/main/PRIVACY.md) to find out more about it!

---

## What's new in 1.7

- **Essay formatter (Pro)**: drop in a Word (.docx), PDF, RTF or text file, or paste a Google Docs link shared as "Anyone with the link", and get a correctly formatted paper in **MLA 9**, **APA 7** or **Chicago** (notes-bibliography or author-date): Times New Roman 12, double spacing, 1 inch margins, the running header with real page numbers, the MLA heading or an APA / Chicago title page, a title-cased title, 0.5 inch first-line indents and a Works Cited / References / Bibliography page that is sorted and uses hanging indents. Footnotes and italics are kept.
- **Citation checks**: fixes such as "(Smith, 12)" to "(Smith 12)" in MLA or "(Smith 2019)" to "(Smith, 2019)" in APA are listed and can be switched off one by one; sources cited but missing from the list (and the reverse) are flagged. Apple Intelligence can fill heading fields the rules couldn't find, always as a suggestion to confirm.
- **Export** Word (.docx), PDF, RTF or plain text, named like `Lastname_Title_MLA.docx`. Share sheet, Save to Files and Google Docs on iPhone; save panel, drag-out and a Google Drive hand-off on Mac.
- **Bauhaus redesign** with the Jost typeface, primary colours and square, ruled layouts.
- The title-case engine keeps acronyms and brand names (NASA, iPhone), capitalizes subtitles after a colon and follows APA's four-letter rule.

## What's new in 1.6

- **Smart Capitalize** (Apple Intelligence): on devices running iOS 26 / macOS 26 with Apple Intelligence turned on, the on-device Foundation Models framework applies your chosen style guide with proper handling of proper nouns, acronyms, hyphenated words and subtitles. The classic rule-based capitalizer stays the instant default, and the app simply shows "Apple Intelligence not available" everywhere else.
- **Suggest alternative titles**: three on-device rewrites of your title in the selected style.
- **Spelling and grammar checks**: the system spell checker (`UITextChecker` on iOS, `NSSpellChecker` on macOS) plus rule-based grammar checks for a/an, doubled words, missing apostrophes, first-word capitalization and subject-verb agreement. Issues are listed with one-tap fixes and a **Fix all** button; nothing changes until you accept it.
- **Settings** to switch each feature on or off, and a native **macOS** app.
- Everything runs on your device and needs no API keys.

---

## Building

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `Sources/project.yml` (the generated `Title Capitalizr.xcodeproj` is checked in too). Open `Sources/Title Capitalizr.xcodeproj` with Xcode 26 or later and run the `Title Capitalizr` scheme on an iPhone, iPad or your Mac. Unit tests for the grammar rules, the Apple Intelligence fallback and the essay formatter (docx reader and writer, MLA / APA / Chicago rules, a docx round trip, PDF / RTF / text exports) live in `Sources/Title CapitalizrTests`. In-app purchases can be tested with `Sources/StoreKit/TitleCapitalizr.storekit`, which the scheme uses when run from Xcode.

---

<table><tr>

<td valign="center"><img width="500" alt="Screenshot-1" src="https://user-images.githubusercontent.com/35755386/169195435-a5442bab-d120-492e-b4c8-7278fc0f8775.png"></td>

<td valign="center"><img width="500" alt="Screenshot-2" src="https://user-images.githubusercontent.com/35755386/169195438-f278513f-136f-4fa8-ad72-2ecfe6118931.png"></td>

<td valign="center"><img width="500" alt="Screenshot-3" src="https://user-images.githubusercontent.com/35755386/169195441-51e887a6-5e53-47ae-96ac-27718288066b.png"></td>

</tr></table>
