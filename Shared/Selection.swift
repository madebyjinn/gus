/// Which row is picked once a list lands.
enum Selection {
    /// Until you've picked a row yourself (arrows, or a pointer that really moved) since the text last
    /// changed, it's the first. After that your row stays picked as late results arrive, unless an answer
    /// lands on top: that's what you asked for.
    static func pick(after ids: [String], keeping keepID: String?, picked: Bool, answerOnTop: Bool) -> Int {
        guard picked, let keepID, let i = ids.firstIndex(of: keepID) else { return 0 }
        if answerOnTop, i != 0 { return 0 }
        return i
    }
}
