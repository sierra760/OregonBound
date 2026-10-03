import SwiftUI

// WIND1000:512×322. Source pane13:494×304 at(9,9); CODE5:3670–36f4 frame.
var originalPaper: Color {
    OriginalResources.colorMode == .monochrome ? .white : Color(red: 1, green: 246 / 255, blue: 137 / 255)
}

enum OriginalWindowLayout {
    static let portSpace = "original-window-port"
    static let contentOrigin = CGPoint(x: 9, y: 9)
    // Initialized CODE5 rectangle table: center panes2/4/10/12 and lower pane3.
    static let centerOrigin = CGPoint(x: 64, y: 9)
    static let lowerCenterOrigin = CGPoint(x: 64, y: 89)
    static let centerOffsetX = centerOrigin.x - contentOrigin.x
}

/// CODE5:3a12–3a86: the outer monochrome pen uses the port's gray pattern.
struct OriginalPaneFrame: View {
    let width: CGFloat
    let height: CGFloat
    var monochrome = OriginalResources.colorMode == .monochrome
    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .named(OriginalWindowLayout.portSpace)).origin
            ZStack(alignment: .topLeading) {
                if monochrome {
                    if let pattern = TextureLoader.quickDrawGray(width: Int(width) + 4, height: Int(height) + 4,
                                                                 originX: Int(origin.x) - 2, originY: Int(origin.y) - 2) {
                        Image(decorative: pattern, scale: 1).interpolation(.none)
                            .offset(x: -2, y: -2)
                    }
                } else {
                    Rectangle().fill(Color(.sRGB, red: Double(0xf500) / 65535,
                                           green: Double(0x9600) / 65535, blue: Double(0x1a00) / 65535))
                        .frame(width: width + 4, height: height + 4).offset(x: -2, y: -2)
                }
                Rectangle().fill(.black)
                    .frame(width: width + 2, height: height + 2).offset(x: -1, y: -1)
                (monochrome ? Color.white : originalPaper).frame(width: width, height: height)
            }
        }.frame(width: width, height: height, alignment: .topLeading)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension View {
    func originalPaneFrame(width: CGFloat, height: CGFloat) -> some View {
        background(alignment: .topLeading) { OriginalPaneFrame(width: width, height: height) }
    }
}

struct OriginalWindow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            content.frame(width: 494, height: 304)
                .originalPaneFrame(width: 494, height: 304)
                .offset(x: OriginalWindowLayout.contentOrigin.x, y: OriginalWindowLayout.contentOrigin.y)
            PixelArtwork(resource: 10128, monochromeResource: 128, frame: 0).frame(width: 498, height: 7).offset(x: 7)
            PixelArtwork(resource: 10128, monochromeResource: 128, frame: 3).frame(width: 7, height: 322).offset(x: 505)
            PixelArtwork(resource: 10128, monochromeResource: 128, frame: 2).frame(width: 498, height: 7).offset(x: 7, y: 315)
            PixelArtwork(resource: 10128, monochromeResource: 128, frame: 1).frame(width: 7, height: 322)
        }.frame(width: 512, height: 322)
            .coordinateSpace(name: OriginalWindowLayout.portSpace)
    }
}

struct OriginalButton: View {
    let title: String
    var isDefault = false
    var paper: Color = originalPaper
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(OriginalSystemPushButtonStyle(title: title, isDefault: isDefault, paper: paper))
            .accessibilityLabel(title)
    }
}

struct OriginalTextEntry: View {
    let label: String
    @Binding var text: String
    var font: BitmapFont? = .plain14
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextField("", text: $text).textFieldStyle(.plain).accessibilityLabel(label)
                .font(.custom("Times", size: font === BitmapFont.plain12 ? 12 : 14))
                .foregroundStyle(.clear).tint(.black)
                .labelsHidden()
            OriginalText(text: text, font: font).allowsHitTesting(false).accessibilityHidden(true)
        }.clipped()
    }
}

struct OriginalRegistrationView: View {
    @ObservedObject var game: GameController
    @State private var profession = Profession.banker
    @State private var names = Array(repeating: "", count: 5)
    @State private var initializedNames = false
    @State private var occupationHelp = false
    @State private var invalidLeader = false
    @State private var textEditRules = OriginalTextEditRules.State()
    @StateObject private var nameFocus = OriginalRegistrationFocusGroup()
    var body: some View {
        OriginalWindow {
            ZStack(alignment: .topLeading) {
                Group {
                originalPaper
                PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 0).frame(width: 135, height: 112)
                PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 2).frame(width: 135, height: 112).offset(x: 359)
                PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 3).frame(width: 26, height: 26).offset(y: 278)
                PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 4).frame(width: 26, height: 26).offset(x: 468, y: 278)
                OriginalText(text: "Name:").offset(x: 1)
                    .frame(width: 47, height: 18, alignment: .topLeading).offset(x: 162, y: 35)
                nameField(0).offset(x: 213, y: 35)
                OriginalSystemGroupFrame(width: 201, height: 183).offset(x: 26, y: 116)
                OriginalText(text: "  Occupation  ").offset(x: 1)
                    .frame(width: 91, height: 18, alignment: .topLeading).background(originalPaper).offset(x: 84, y: 111)
                ForEach(Array(Profession.allCases.enumerated()), id: \.element.id) { index, occupation in
                    OriginalSystemRadio(title: occupation.rawValue, selected: profession == occupation,
                                        width: 115, height: 20, paper: originalPaper) {
                        profession = occupation
                    }.offset(x: 46, y: CGFloat(131 + index * 20))
                }
                OriginalText(text: "The other people in your wagon:").offset(x: 1)
                    .frame(width: 232, height: 20, alignment: .topLeading).offset(x: 253, y: 125)
                ForEach(1..<5) { index in
                    nameField(index).offset(x: 305, y: CGFloat(156 + (index - 1) * 20))
                }
                OriginalIconChoice(icon: 9999, title: "", width: 42) { occupationHelp = true }
                    .accessibilityLabel("Occupation Help")
                    .frame(width: 42, height: 46).offset(x: 170, y: 182)
                OriginalButton(title: "OK") {
                    do {
                        let accepted = try OriginalRegistration.commitNames(leader: names[0], companions: Array(names.dropFirst()))
                        game.start(profession: profession, difficulty: .greenhorn, names: accepted, month: 4)
                    } catch { invalidLeader = true }
                }.frame(width: 80, height: 20).offset(x: 325, y: 263)
                }.disabled(occupationHelp || invalidLeader).allowsHitTesting(!occupationHelp && !invalidLeader).accessibilityHidden(occupationHelp || invalidLeader)
                if occupationHelp {
                    ZStack(alignment: .topLeading) {
                        originalPaper
                        OriginalTextPicture(resource: 2070).offset(x: 14, y: 5)
                        OriginalButton(title: "OK", isDefault: true) { occupationHelp = false }
                            .frame(width: 80, height: 20).offset(x: 207, y: 269)
                            #if !os(macOS)
                            .keyboardShortcut(.defaultAction)
                            #endif
                        OriginalGameDefaultButtonKeyboard { occupationHelp = false }
                    }
                }
                if invalidLeader {
                    ZStack(alignment: .topLeading) {
                        originalPaper
                        OriginalText(text: "You must enter a name for your wagon before starting on the trail.")
                            .frame(width: 476, height: 20).offset(x: 6, y: 125)
                        OriginalButton(title: "OK", isDefault: true) { invalidLeader = false }
                            .frame(width: 80, height: 20).offset(x: 207, y: 269)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }.onAppear {
            guard !initializedNames else { return }
            initializedNames = true
            names = OriginalRegistration.partyNames(pool: OriginalResources.strings(3006)) { game.random.bounded($0) }
        }
    }
    private func nameField(_ index: Int) -> some View {
        OriginalRegistrationTextField(label: index == 0 ? "Name" : "Person \(index + 1)", text: $names[index],
            rules: $textEditRules, focusGroup: nameFocus, fieldIndex: index, initialFocus: index == 0)
            .frame(width: 119, height: 15)
            .overlay(alignment: .topLeading) {
                // CODE5:3f56–3f70: InsetRect(-4,-3), PenNormal, FrameRect.
                Rectangle().strokeBorder(.black, lineWidth: 1).frame(width: 127, height: 21).offset(x: -4, y: -3)
            }
    }
}

struct OriginalTitleView: View {
    let load: () -> Void
    let travel: () -> Void
    let advance: () -> Void
    var body: some View {
        OriginalWindow {
            ZStack(alignment: .topLeading) {
                originalPaper.onTapGesture(perform: advance)
                OriginalTitleArtwork().frame(width: 494, height: 304).allowsHitTesting(false)
                // DITL 9000, items 2 and 3. The load action remains available even with no save.
                OriginalButton(title: "Load Game", action: load)
                    .frame(width: 110, height: 20).offset(x: 20, y: 270)
                OriginalButton(title: "Travel the Trail", action: travel)
                    .frame(width: 110, height: 20).offset(x: 364, y: 270)
            }
        }
    }
}

struct OriginalTextDialogView: View {
    let resource: Int
    let proceed: (Int) -> Void
    var body: some View {
        OriginalWindow { OriginalDialogContents(resource: resource, proceed: proceed) }
    }
}

/// Original DITL coordinates, usable in the full opening window or trail center pane.
struct OriginalDialogContents: View {
    let resource: Int
    var substitutions: [String] = []
    var hiddenItems: Set<Int> = []
    var font: BitmapFont?
    // Callback font tuples precede DITL child creation (CODE5:2da2).
    // Explicit caller fonts retain priority over these recovered defaults.
    private var staticFont: BitmapFont? {
        if let font { return font }
        if resource == 6183 { return .plain12 }
        return [6040, 6060, 8075].contains(resource) ? .bold12 : .bold14
    }
    private func centered(_ index: Int) -> Bool {
        [9161, 9201, 9202].contains(resource) || resource == 5221 && index == 1
    }
    let proceed: (Int) -> Void
    private struct Dialog: Decodable {
        struct Item: Decodable {
            struct Bounds: Decodable { let top: Int; let left: Int; let bottom: Int; let right: Int }
            let type: String
            let bounds: Bounds
            let data: String
        }
        let items: [Item]
    }
    private var items: [Dialog.Item] {
        guard let url = GameData.url(forResource: "ditl_\(resource)", withExtension: "json", subdirectory: "dialogs"),
              let data = try? Data(contentsOf: url), let dialog = try? JSONDecoder().decode(Dialog.self, from: data) else { return [] }
        return dialog.items
    }
    private func substituted(_ text: String) -> String {
        substitutions.enumerated().reduce(text) { value, entry in
            value.replacingOccurrences(of: "^\(entry.offset)", with: entry.element)
        }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if hiddenItems.contains(index) { EmptyView() }
                else if item.type == "staticText" {
                    OriginalTextBox(text: substituted(item.data), font: staticFont,
                                    width: item.bounds.right - item.bounds.left,
                                    height: item.bounds.bottom - item.bounds.top,
                                    centered: centered(index))
                        .offset(x: CGFloat(item.bounds.left), y: CGFloat(item.bounds.top))
                } else if item.type == "button" {
                    OriginalButton(title: item.data, isDefault: [5221, 6031, 6040, 6051, 6060, 6320, 8075, 9220].contains(resource), action: { proceed(index) })
                        .frame(width: CGFloat(item.bounds.right - item.bounds.left), height: CGFloat(item.bounds.bottom - item.bounds.top))
                        .offset(x: CGFloat(item.bounds.left), y: CGFloat(item.bounds.top))
                }
            }
        }
    }
}
