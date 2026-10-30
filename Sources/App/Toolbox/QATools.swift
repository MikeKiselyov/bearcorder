import AppKit
import AppCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Test data

struct TestDataTool: View {
    @State private var country = TestData.PhoneCountry.us
    @State private var people: [TestData.Person] = []
    @State private var brand = TestData.CardBrand.visa
    @State private var card = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var ibanCountry = TestData.IBANCountry.germany
    @State private var iban = ""
    @State private var passwordLength = 16
    @State private var passwordUppercase = true
    @State private var passwordDigits = true
    @State private var passwordSymbols = true
    @State private var passwords: [String] = []
    @State private var checkInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                peopleSection
                cardSection
                ibanSection
                passwordSection
                checkSection
                edgeCaseSection
            }
            .padding(16)
        }
        .onAppear {
            generatePeople()
            generateCard()
            generateIBAN()
            generatePasswords()
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel(L("toolbox.testData.people"))
                PillPicker(options: TestData.PhoneCountry.allCases, selection: $country) { value in value.rawValue }
                    .frame(width: 260)
                    .tip(L("toolbox.testData.country.tip"))
                Spacer()
                Button(L("toolbox.button.generate")) { generatePeople() }
                    .accessibilityLabel(L("toolbox.testData.generatePeople"))
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("toolbox.testData.generatePeople.tip"))
                CopyButton(text: peopleAsText(), title: L("toolbox.button.copyAll"), primary: false)
            }
            Text(L("toolbox.testData.people.note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                HStack(spacing: 6) {
                    ValueRow(label: L("toolbox.testData.name"), value: "\(person.firstName) \(person.lastName)", mono: false)
                    ValueRow(label: L("toolbox.testData.email"), value: person.email)
                    ValueRow(label: L("toolbox.testData.phone"), value: person.phone)
                }
            }
        }
        .onChange(of: country) { generatePeople() }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel(L("toolbox.testData.card"))
                PillPicker(options: TestData.CardBrand.allCases, selection: $brand) { value in value.rawValue }
                    .frame(width: 300)
                    .tip(L("toolbox.testData.brand.tip"))
                Spacer()
                Button(L("toolbox.button.generate")) { generateCard() }
                    .accessibilityLabel(L("toolbox.testData.generateCard"))
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("toolbox.testData.generateCard.tip"))
            }
            HStack(spacing: 6) {
                ValueRow(label: L("toolbox.testData.cardNumber"), value: card)
                ValueRow(label: L("toolbox.testData.expiry"), value: expiry)
                    .frame(width: 120)
                ValueRow(label: "CVC", value: cvc)
                    .frame(width: 100)
            }
            Text(L("toolbox.testData.card.note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .onChange(of: brand) { generateCard() }
    }

    private var ibanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel(L("toolbox.testData.iban"))
                PillPicker(options: TestData.IBANCountry.allCases, selection: $ibanCountry) { value in value.rawValue }
                    .frame(width: 220)
                    .tip(L("toolbox.testData.ibanCountry.tip"))
                Spacer()
                Button(L("toolbox.button.generate")) { generateIBAN() }
                    .accessibilityLabel(L("toolbox.testData.generateIBAN"))
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("toolbox.testData.generateIBAN.tip"))
            }
            ValueRow(label: L("toolbox.testData.validCheckDigits"), value: iban)
        }
        .onChange(of: ibanCountry) { generateIBAN() }
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel(L("toolbox.testData.passwords"))
                Stepper(L("toolbox.testData.passwordLength", passwordLength), value: $passwordLength, in: 4...64)
                    .font(.system(size: 12))
                    .tip(L("toolbox.testData.passwordLength.tip"))
                Toggle(L("toolbox.testData.uppercase"), isOn: $passwordUppercase).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip(L("toolbox.testData.uppercase.tip"))
                Toggle(L("toolbox.testData.digits"), isOn: $passwordDigits).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip(L("toolbox.testData.digits.tip"))
                Toggle(L("toolbox.testData.symbols"), isOn: $passwordSymbols).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip(L("toolbox.testData.symbols.tip"))
                Spacer()
                Button(L("toolbox.button.generate")) { generatePasswords() }
                    .accessibilityLabel(L("toolbox.testData.generatePasswords"))
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("toolbox.testData.generatePasswords.tip"))
            }
            ForEach(passwords, id: \.self) { password in
                ValueRow(label: L("toolbox.testData.passwordCharacters", password.count), value: password)
            }
        }
        .onChange(of: passwordLength) { generatePasswords() }
        .onChange(of: passwordUppercase) { generatePasswords() }
        .onChange(of: passwordDigits) { generatePasswords() }
        .onChange(of: passwordSymbols) { generatePasswords() }
    }

    private var checkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L("toolbox.testData.check"))
            TextField(L("toolbox.testData.check.placeholder"), text: $checkInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .tip(L("toolbox.testData.check.tip"))
            if !checkInput.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 16) {
                    checkResult(L("toolbox.testData.check.luhn"), TestData.isValidLuhn(checkInput))
                    checkResult(L("toolbox.testData.check.iban"), TestData.isValidIBAN(checkInput))
                }
            }
        }
    }

    private func checkResult(_ title: String, _ valid: Bool) -> some View {
        Label(valid ? L("toolbox.testData.check.valid", title) : L("toolbox.testData.check.invalid", title), systemImage: valid ? "checkmark.circle.fill" : "xmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(valid ? Theme.success : Theme.textSecondary)
    }

    private var edgeCaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L("toolbox.testData.tricky"))
            Text(L("toolbox.testData.tricky.note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(TestData.edgeCases) { edgeCase in
                    ValueRow(label: edgeCase.name, value: edgeCase.value)
                }
            }
        }
    }

    private func generatePeople() {
        var generator = SystemRandomNumberGenerator()
        var list: [TestData.Person] = []
        for _ in 0..<5 {
            list.append(TestData.person(country: country, using: &generator))
        }
        people = list
    }

    private func peopleAsText() -> String {
        var lines: [String] = []
        for person in people {
            lines.append("\(person.firstName) \(person.lastName)\t\(person.email)\t\(person.phone)")
        }
        return lines.joined(separator: "\n")
    }

    private func generateCard() {
        var generator = SystemRandomNumberGenerator()
        card = TestData.cardNumber(brand: brand, using: &generator)
        expiry = TestData.cardExpiry(using: &generator)
        var cvcLength = 3
        if brand == .amex {
            cvcLength = 4
        }
        var digits = ""
        for _ in 0..<cvcLength {
            digits += String(Int.random(in: 0...9, using: &generator))
        }
        cvc = digits
    }

    private func generateIBAN() {
        var generator = SystemRandomNumberGenerator()
        iban = TestData.iban(country: ibanCountry, using: &generator)
    }

    private func generatePasswords() {
        var generator = SystemRandomNumberGenerator()
        let rules = TestData.PasswordRules(length: passwordLength, uppercase: passwordUppercase, digits: passwordDigits, symbols: passwordSymbols)
        var list: [String] = []
        for _ in 0..<3 {
            list.append(TestData.password(rules, using: &generator))
        }
        passwords = list
    }
}

// MARK: - Regex

struct RegexTool: View {
    @Binding var input: String
    @State private var pattern = #"\b(?<id>[A-Z]+-\d+)\b"#
    @State private var replacement = ""
    @State private var caseInsensitive = false
    @State private var multiline = true
    @State private var dotAll = false

    /// Highlighting very long text makes typing slow; past this the preview is cut.
    private let previewLimit = 20_000

    private var result: RegexTester.Result {
        var options = RegexTester.Options()
        options.caseInsensitive = caseInsensitive
        options.multiline = multiline
        options.dotMatchesLineBreaks = dotAll
        var template: String? = nil
        if !replacement.isEmpty {
            template = replacement
        }
        return RegexTester.run(pattern: pattern, text: input, options: options, replacement: template)
    }

    var body: some View {
        let current = result
        VStack(spacing: 0) {
            patternBar(current)
            SplitPanes {
                PaneHeader(title: L("toolbox.regex.text")) {
                    Button(L("toolbox.button.paste")) {
                        input = NSPasteboard.general.string(forType: .string) ?? input
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip(L("toolbox.regex.paste.tip"))
                }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: matchTitle(current)) { EmptyView() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(highlighted(current))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        if let replaced = current.replaced {
                            ValueRow(label: L("toolbox.regex.afterReplace"), value: replaced)
                        }
                        ForEach(Array(current.matches.prefix(200).enumerated()), id: \.offset) { index, match in
                            matchRow(index: index, match: match)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear {
            if input.isEmpty {
                input = "Fixed QA-7590 and QA-7612, reopened DEV-88.\nSee https://jira.example.com/browse/QA-7590"
            }
        }
    }

    private func patternBar(_ current: RegexTester.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("/").foregroundStyle(Theme.textSecondary)
                TextField(L("toolbox.regex.pattern"), text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .tip(L("toolbox.regex.pattern.tip"))
                Text("/").foregroundStyle(Theme.textSecondary)
                Toggle(L("toolbox.regex.flag.i"), isOn: $caseInsensitive).toggleStyle(.checkbox).tip(L("toolbox.regex.flag.i.tip"))
                Toggle(L("toolbox.regex.flag.m"), isOn: $multiline).toggleStyle(.checkbox).tip(L("toolbox.regex.flag.m.tip"))
                Toggle(L("toolbox.regex.flag.s"), isOn: $dotAll).toggleStyle(.checkbox).tip(L("toolbox.regex.flag.s.tip"))
            }
            HStack(spacing: 10) {
                Text(L("toolbox.regex.replace")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                TextField(L("toolbox.regex.template"), text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .tip(L("toolbox.regex.template.tip"))
                if let error = current.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
            }
        }
        .font(.system(size: 12))
        .padding(12)
        .background(Theme.sidebar)
    }

    private func matchTitle(_ current: RegexTester.Result) -> String {
        if current.truncated {
            return L("toolbox.matches.first", RegexTester.limit)
        }
        return L("toolbox.matches", current.matches.count)
    }

    private func matchRow(index: Int, match: RegexTester.Match) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ValueRow(label: L("toolbox.regex.match", index + 1, match.range.location), value: match.value)
            ForEach(Array(match.groups.enumerated()), id: \.offset) { _, group in
                ValueRow(label: L("toolbox.regex.group", group.name), value: group.value ?? L("toolbox.regex.notMatched"))
                    .padding(.leading, 16)
            }
        }
    }

    private func highlighted(_ current: RegexTester.Result) -> AttributedString {
        let source = input as NSString
        let limit = min(source.length, previewLimit)
        var text = AttributedString()
        var cursor = 0
        for match in current.matches {
            if match.range.location >= limit { break }
            if match.range.location > cursor {
                text += AttributedString(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let end = min(match.range.location + match.range.length, limit)
            var piece = AttributedString(source.substring(with: NSRange(location: match.range.location, length: end - match.range.location)))
            piece.backgroundColor = Theme.accent.opacity(0.45)
            text += piece
            cursor = end
        }
        if cursor < limit {
            text += AttributedString(source.substring(with: NSRange(location: cursor, length: limit - cursor)))
        }
        if source.length > limit {
            text += AttributedString("\n" + L("toolbox.regex.previewCut", previewLimit))
        }
        return text
    }
}

// MARK: - QR code

struct QRTool: View {
    @Binding var input: String
    @State private var readMessage: String?

    var body: some View {
        let image = QRCode.image(for: input)
        SplitPanes {
            PaneHeader(title: L("toolbox.qr.input")) {
                Button(L("toolbox.qr.readScreen")) { Task { await readFromScreen() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip(L("toolbox.qr.readScreen.tip"))
                Button(L("toolbox.qr.readClipboard")) { Task { await readFromClipboard() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip(L("toolbox.qr.readClipboard.tip"))
            }
            CodeTextView(text: $input)
            ToolFooter {
                if let message = readMessage {
                    Text(message).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(L("toolbox.qr.footer"))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        } right: {
            PaneHeader(title: L("toolbox.qr.code")) { EmptyView() }
            VStack {
                Spacer()
                if let qr = image {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 320)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(L("toolbox.qr.empty")).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            ToolFooter {
                Spacer()
                Button(L("toolbox.qr.save")) { save(image) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(image == nil)
                    .tip(L("toolbox.qr.save.tip"))
                Button(L("toolbox.qr.copyImage")) { copy(image) }
                    .buttonStyle(AccentButtonStyle(isEnabled: image != nil))
                    .disabled(image == nil)
                    .tip(L("toolbox.qr.copyImage.tip"))
            }
        }
    }

    private func readFromScreen() async {
        guard let file = await ScreenshotCapture.capture(.area) else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let image = ImageFiles.load(file) else { return }
        await show(QRCode.read(image))
    }

    private func readFromClipboard() async {
        guard let image = NSImage(pasteboard: NSPasteboard.general), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            readMessage = L("toolbox.qr.noImage")
            return
        }
        await show(QRCode.read(cgImage))
    }

    private func show(_ payloads: [String]) async {
        if payloads.isEmpty {
            readMessage = L("toolbox.qr.noCode")
            return
        }
        input = payloads.joined(separator: "\n")
        readMessage = L("toolbox.qr.read", payloads.count)
    }

    private func copy(_ image: NSImage?) {
        guard let qr = image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([qr])
    }

    private func save(_ image: NSImage?) {
        guard let qr = image, let data = QRCode.pngData(qr) else { return }
        if let url = SystemActions.chooseSaveLocation(name: "qr-code.png", type: .png) {
            try? data.write(to: url)
        }
    }
}
