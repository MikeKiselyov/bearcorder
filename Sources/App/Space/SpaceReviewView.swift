import AppCore
import SwiftUI

/// A review list: a checkbox per row, the total of what is ticked, and a confirmation with the same
/// numbers. After a removal it shows what was freed, what was left alone and why, and for folders
/// that went to the Trash a button to delete them for good.
struct SpaceReviewView: View {
    @Bindable var review: SpaceReview
    var model: SpaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if review.rows.isEmpty {
                Text(L("space.review.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($review.rows) { $row in
                            rowView($row)
                            Divider().overlay(Theme.border)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .glassCard(cornerRadius: 12)
            }
            if let result = review.lastResult {
                resultView(result)
            }
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(L("space.review.ticked", review.selectedCount, review.rows.count))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(L("space.review.selectAll")) { setAll(true) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
                .tip(L("space.review.selectAll.tip"))
            Button(L("space.review.selectNone")) { setAll(false) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
                .tip(L("space.review.selectNone.tip"))
        }
        .font(.system(size: 12))
        // While a question is open the ticks it counted stay as they are.
        .disabled(review.isRemoving || review.rows.isEmpty || review.isConfirming)
    }

    private func setAll(_ checked: Bool) {
        for index in review.rows.indices {
            review.rows[index].isChecked = checked
        }
    }

    // MARK: Rows

    private func rowView(_ row: Binding<SpaceReview.Row>) -> some View {
        let item = row.wrappedValue
        return HStack(spacing: 10) {
            Toggle(isOn: row.isChecked) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(review.isRemoving || review.isConfirming)
            .accessibilityLabel(item.path)
            .tip(L("space.review.row.tip"))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shortPath(item.path))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if review.isProjectList {
                Text(ageText(item.age))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(SpaceModel.format(item.bytes))
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .trailing)
            Button(L("space.review.show")) { model.reveal(URL(fileURLWithPath: item.path)) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(L("space.review.show.label", item.path))
                .tip(L("space.review.show.tip"))
        }
        .padding(.vertical, 6)
    }

    /// The path with the home folder written as ~.
    private func shortPath(_ path: String) -> String {
        let home = model.home.standardizedFileURL.path
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func ageText(_ age: Int?) -> String {
        guard let days = age else {
            return L("space.review.age.unknown")
        }
        if days == 0 {
            return L("space.review.age.today")
        }
        return L("space.review.age.days", days)
    }

    // MARK: Result

    private func resultView(_ result: SpaceReview.RemovalResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !result.removed.isEmpty {
                Label(freedText(result), systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.skipped.isEmpty {
                Text(L("space.review.result.skipped", result.skipped.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                if result.skipped.count > 4 {
                    ScrollView {
                        skippedList(result)
                    }
                    .frame(height: 80)
                } else {
                    skippedList(result)
                }
            }
            if !result.trashed.isEmpty {
                if review.isConfirmingForGood {
                    forGoodConfirmation(result)
                } else {
                    Button(SpaceReviewView.forGoodText(result)) { review.askDeleteForGood() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(review.isRemoving)
                        .tip(L("space.review.forGood.tip"))
                }
            }
        }
    }

    /// "Delete these 2 folders for good, 1.2 GB": the button and the one that confirms it.
    static func forGoodText(_ result: SpaceReview.RemovalResult) -> String {
        return L("space.review.forGood", result.trashed.count, SpaceModel.format(result.trashedTotal))
    }

    /// Asked after "Delete … for good": the same count and size, Cancel keeps them in the Trash.
    private func forGoodConfirmation(_ result: SpaceReview.RemovalResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("space.review.forGood.confirm", result.trashed.count, SpaceModel.format(result.trashedTotal)))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L("space.review.cancel")) { review.isConfirmingForGood = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .tip(L("space.review.cancel.tip"))
                Button(SpaceReviewView.forGoodText(result)) {
                    Task {
                        await review.deleteTrashedForGood()
                        await model.measure(force: true)
                    }
                }
                .buttonStyle(AccentButtonStyle(isEnabled: !review.isRemoving))
                .disabled(review.isRemoving)
                .tip(L("space.review.forGood.confirm.tip"))
            }
        }
        .padding(10)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func skippedList(_ result: SpaceReview.RemovalResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(result.skipped.enumerated()), id: \.offset) { item in
                Text(L("space.review.result.skippedRow", shortPath(item.element.path), item.element.reason))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func freedText(_ result: SpaceReview.RemovalResult) -> String {
        let size = SpaceModel.format(result.freedBytes)
        if !result.trashed.isEmpty {
            return L("space.review.result.trashed", size)
        }
        return L("space.review.result.freed", size)
    }

    // MARK: Footer

    private var actionText: String {
        return SpaceReviewView.actionText(review)
    }

    /// What the footer button and the confirmation say: the same count and size in both.
    static func actionText(_ review: SpaceReview) -> String {
        let size = SpaceModel.format(review.selectedBytes)
        if review.movesToTrash {
            return L("space.review.action.trash", review.selectedCount, size)
        }
        if review.isProjectList {
            return L("space.review.action.deleteFolders", review.selectedCount, size)
        }
        return L("space.review.action.deleteItems", review.selectedCount, size)
    }

    @ViewBuilder
    private var footer: some View {
        if review.isConfirming {
            confirmation
        } else {
            let canRemove = review.selectedCount > 0 && !review.isRemoving
            HStack(spacing: 10) {
                Text(review.movesToTrash ? L("space.review.note.trash") : L("space.review.note.delete"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if review.isRemoving {
                    ProgressView().controlSize(.small)
                }
                Button(actionText) {
                    review.isConfirmingForGood = false
                    review.isConfirming = true
                }
                    .buttonStyle(AccentButtonStyle(isEnabled: canRemove))
                    .disabled(!canRemove)
                    .tip(L("space.review.action.tip"))
            }
        }
    }

    /// Asked after the footer button, with the same numbers on the button that removes.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.movesToTrash ? L("space.review.confirm.trash", actionText) : L("space.review.confirm.delete", actionText))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L("space.review.cancel")) { review.isConfirming = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .tip(L("space.review.cancel.tip"))
                let canConfirm = review.selectedCount > 0 && !review.isRemoving
                Button(actionText) {
                    Task {
                        await review.remove()
                        await model.measure(force: true)
                    }
                }
                .buttonStyle(AccentButtonStyle(isEnabled: canConfirm))
                .disabled(!canConfirm)
                .tip(review.movesToTrash ? L("space.review.confirm.trash.tip") : L("space.review.confirm.delete.tip"))
            }
        }
        .padding(10)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The dependency folders found in projects, as a row among the categories: the last result and
/// when it was found, or Find projects… The menu panel never searches; it opens the window.
struct ProjectsRow: View {
    @Bindable var model: SpaceModel
    var compact = false
    var tint: TileTint = .teal
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: 12) {
            IconTile(systemImage: "folder.badge.gearshape", tint: tint, size: compact ? 26 : 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("space.projects.title")).font(.system(size: 13, weight: .semibold))
                if compact {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(L("space.projects.detail"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !compact {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if model.isScanningProjects {
                ProgressView().controlSize(.small)
            }
            if model.projectReview != nil {
                Button(L("space.review"), action: onOpen)
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
                    .accessibilityLabel(L("space.review.label", L("space.projects.title")))
                    .tip(L("space.projects.review.tip"))
            } else {
                Button(L("space.projects.open"), action: onOpen)
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
                    .tip(L("space.projects.open.tip"))
            }
        }
        .padding(.vertical, compact ? 6 : 10)
    }

    /// "18.3 GB, found 2 hr. ago", or what is going on when there is no result yet.
    private var summary: String {
        if model.isScanningProjects {
            return L("space.projects.searching")
        }
        guard let review = model.projectReview, let date = model.projectsScannedAt else {
            return L("space.projects.notSearched")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: date, relativeTo: Date())
        return L("space.projects.found", SpaceModel.format(review.totalBytes), when)
    }
}
