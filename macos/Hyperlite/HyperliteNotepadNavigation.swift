import Foundation

extension HyperliteNotepadState {
    func displayName(for identifier: String) -> String {
        HyperliteNoteDate.displayName(for: identifier, calendar: calendar)
    }

    func selectDateIdentifier(_ identifier: String, focus: Bool = false) async {
        guard let date = HyperliteNoteDate.date(from: identifier, calendar: calendar) else {
            errorMessage = HyperliteNotepadError.invalidDate(identifier).localizedDescription
            return
        }
        await selectDate(date, focus: focus)
    }

    func selectDate(_ candidate: Date, focus: Bool = false) async {
        let target = calendar.startOfDay(for: candidate)
        let currentDate = calendar.startOfDay(for: now())
        await navigate(
            to: target,
            focus: focus,
            activateDaily: true,
            followCurrentDate: target == currentDate
        )
    }

    func focusPinned() {
        activate(.notepad)
        requestFocus(.pinned)
    }

    func focusDaily() {
        activate(.daily)
        requestFocus(.daily)
    }
}
