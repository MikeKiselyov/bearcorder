import AppKit
import BugbearCore
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
                SectionLabel("People")
                PillPicker(options: TestData.PhoneCountry.allCases, selection: $country) { value in value.rawValue }
                    .frame(width: 260)
                    .tip("Country for names and phone number formats")
                Spacer()
                Button("Generate") { generatePeople() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Generate five new fake people")
                CopyButton(text: peopleAsText(), title: "Copy all", primary: false)
            }
            Text("Emails use reserved test domains, US and UK phones come from ranges set aside for fiction: nothing reaches a real person.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                HStack(spacing: 6) {
                    ValueRow(label: "Name", value: "\(person.firstName) \(person.lastName)", mono: false)
                    ValueRow(label: "Email", value: person.email)
                    ValueRow(label: "Phone", value: person.phone)
                }
            }
        }
        .onChange(of: country) { generatePeople() }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel("Card")
                PillPicker(options: TestData.CardBrand.allCases, selection: $brand) { value in value.rawValue }
                    .frame(width: 300)
                    .tip("Card brand, sets the number prefix and length")
                Spacer()
                Button("Generate") { generateCard() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Generate a new fake card number, expiry and CVC")
            }
            HStack(spacing: 6) {
                ValueRow(label: "Number · passes Luhn", value: card)
                ValueRow(label: "Expiry", value: expiry)
                    .frame(width: 120)
                ValueRow(label: "CVC", value: cvc)
                    .frame(width: 100)
            }
            Text("Random numbers in the right format, not real cards. Payment sandboxes (Stripe, Adyen) need their own test numbers.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .onChange(of: brand) { generateCard() }
    }

    private var ibanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel("IBAN")
                PillPicker(options: TestData.IBANCountry.allCases, selection: $ibanCountry) { value in value.rawValue }
                    .frame(width: 220)
                    .tip("Country of the IBAN, sets its length and format")
                Spacer()
                Button("Generate") { generateIBAN() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Generate a new IBAN with valid check digits")
            }
            ValueRow(label: "Valid check digits", value: iban)
        }
        .onChange(of: ibanCountry) { generateIBAN() }
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel("Passwords")
                Stepper("Length: \(passwordLength)", value: $passwordLength, in: 4...64)
                    .font(.system(size: 12))
                    .tip("Length of the generated passwords")
                Toggle("A-Z", isOn: $passwordUppercase).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip("Include uppercase letters")
                Toggle("0-9", isOn: $passwordDigits).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip("Include digits")
                Toggle("!@#", isOn: $passwordSymbols).toggleStyle(.checkbox).font(.system(size: 12))
                    .tip("Include symbols")
                Spacer()
                Button("Generate") { generatePasswords() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Generate three new passwords")
            }
            ForEach(passwords, id: \.self) { password in
                ValueRow(label: "\(password.count) characters", value: password)
            }
        }
        .onChange(of: passwordLength) { generatePasswords() }
        .onChange(of: passwordUppercase) { generatePasswords() }
        .onChange(of: passwordDigits) { generatePasswords() }
        .onChange(of: passwordSymbols) { generatePasswords() }
    }

    private var checkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Check a card number or IBAN")
            TextField("Paste a card number or IBAN", text: $checkInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .tip("Check whether a card number passes Luhn or an IBAN has valid check digits")
            if !checkInput.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 16) {
                    checkResult("Luhn (cards)", TestData.isValidLuhn(checkInput))
                    checkResult("IBAN checksum", TestData.isValidIBAN(checkInput))
                }
            }
        }
    }

    private func checkResult(_ title: String, _ valid: Bool) -> some View {
        Label("\(title): \(valid ? "valid" : "invalid")", systemImage: valid ? "checkmark.circle.fill" : "xmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(valid ? Theme.success : Theme.textSecondary)
    }

    private var edgeCaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Tricky inputs")
            Text("Strings that often break forms, layouts and backends. Copy one into the field you test.")
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
                PaneHeader(title: "Text") {
                    Button("Paste") {
                        input = NSPasteboard.general.string(forType: .string) ?? input
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip("Replace the text with the clipboard contents")
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
                            ValueRow(label: "After replace", value: replaced)
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
                TextField("Pattern", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .tip("Regular expression to test; matches are highlighted on the right")
                Text("/").foregroundStyle(Theme.textSecondary)
                Toggle("i", isOn: $caseInsensitive).toggleStyle(.checkbox).tip("Ignore case: A matches a")
                Toggle("m", isOn: $multiline).toggleStyle(.checkbox).tip("^ and $ match at every line")
                Toggle("s", isOn: $dotAll).toggleStyle(.checkbox).tip(". matches line breaks")
            }
            HStack(spacing: 10) {
                Text("Replace").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                TextField("Template, e.g. [$1] or ${id}", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .tip("Optional replacement to preview; use $1 or ${name} for groups")
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
            return "First \(RegexTester.limit) matches"
        }
        if current.matches.count == 1 {
            return "1 match"
        }
        return "\(current.matches.count) matches"
    }

    private func matchRow(index: Int, match: RegexTester.Match) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ValueRow(label: "Match \(index + 1) · at \(match.range.location)", value: match.value)
            ForEach(Array(match.groups.enumerated()), id: \.offset) { _, group in
                ValueRow(label: "Group \(group.name)", value: group.value ?? "(not matched)")
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
            text += AttributedString("\n… preview cut at \(previewLimit) characters")
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
            PaneHeader(title: "Text or link") {
                Button("Read from screen…") { Task { await readFromScreen() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip("Select an area of the screen with a QR code and read it")
                Button("Read from clipboard image") { Task { await readFromClipboard() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip("Read a QR code from an image on the clipboard")
            }
            CodeTextView(text: $input)
            ToolFooter {
                if let message = readMessage {
                    Text(message).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Open a staging link on your phone: show the code, scan it with the camera.")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        } right: {
            PaneHeader(title: "QR code") { EmptyView() }
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
                    Text("Type a link or text").foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            ToolFooter {
                Spacer()
                Button("Save PNG…") { save(image) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(image == nil)
                    .tip("Save the QR code as a PNG file")
                Button("Copy image") { copy(image) }
                    .buttonStyle(AccentButtonStyle(isEnabled: image != nil))
                    .disabled(image == nil)
                    .tip("Copy the QR code image to paste into a chat or document")
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
            readMessage = "No image on the clipboard"
            return
        }
        await show(QRCode.read(cgImage))
    }

    private func show(_ payloads: [String]) async {
        if payloads.isEmpty {
            readMessage = "No QR code found"
            return
        }
        input = payloads.joined(separator: "\n")
        if payloads.count == 1 {
            readMessage = "Read 1 code"
        } else {
            readMessage = "Read \(payloads.count) codes"
        }
    }

    private func copy(_ image: NSImage?) {
        guard let qr = image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([qr])
    }

    private func save(_ image: NSImage?) {
        guard let qr = image, let data = QRCode.pngData(qr) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qr-code.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
