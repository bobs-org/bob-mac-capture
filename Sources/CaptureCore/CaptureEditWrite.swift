import Foundation

/// Returns the UTF-8 byte window written in `new` between the strings' common
/// prefix and common suffix. This is an edit window, not capture grammar;
/// callers only test whether a Bob-supplied byte offset falls inside it.
/// Pure deletions and unchanged strings write no bytes and return nil.
public func captureWrittenByteRange(from old: String, to new: String) -> CaptureRange? {
    let oldBytes = Array(old.utf8)
    let newBytes = Array(new.utf8)

    var prefixLength = 0
    while prefixLength < oldBytes.count,
          prefixLength < newBytes.count,
          oldBytes[prefixLength] == newBytes[prefixLength]
    {
        prefixLength += 1
    }

    var suffixLength = 0
    while suffixLength < oldBytes.count - prefixLength,
          suffixLength < newBytes.count - prefixLength,
          oldBytes[oldBytes.count - 1 - suffixLength]
              == newBytes[newBytes.count - 1 - suffixLength]
    {
        suffixLength += 1
    }

    let writtenEnd = newBytes.count - suffixLength
    guard prefixLength < writtenEnd else {
        return nil
    }
    return CaptureRange(start: prefixLength, end: writtenEnd)
}

/// True when the UTF-8 byte immediately before Bob's ID part was written.
public func captureEditWroteSeparator(_ written: CaptureRange?, before partStart: Int) -> Bool {
    guard partStart >= 1, let written else {
        return false
    }
    let separatorOffset = partStart - 1
    return written.start <= separatorOffset && separatorOffset < written.end
}
