%encoding iso
%import editor_hooks
%import xvitext
%import tap
main {
    pointer arena = memory("documentarena",2048,1)
    pointer window = memory("window",77,1)
    pointer raw = memory("raw",32,1)
    sub reset() {
        buffer.undo_size = 0
        doctext.init(arena,arena+2048)
    }
    sub start() {
        uword n
        reset()
        tap.ok(doctext.count == 1 and doctext.length(1) == 0, "empty document has one line")
        tap.ok(doctext.pos(0) == buffer.NONE and doctext.pos(2) == buffer.NONE, "invalid lines return sentinel")
        tap.ok(doctext.insert_at(1,0,'a') and doctext.length(1) == 1, "insert in empty line")
        tap.ok(doctext.insert_at(1,3,'d') and buffer.get(1) == ' ' and buffer.get(3) == 'd', "insertion past end pads spaces")
        doctext.delete_at(1,0)
        tap.ok(doctext.length(1) == 3 and buffer.get(2) == 'd', "delete visible character")
        doctext.delete_to_end(1,1)
        tap.ok(doctext.length(1) == 1, "delete to end of line")
        reset()
        tap.ok(doctext.insert_empty(2) and doctext.count == 2 and doctext.pos(2) == 1, "append empty line")
        void doctext.insert_at(2,0,'b')
        void doctext.insert_empty(1)
        tap.ok(doctext.count == 3 and doctext.length(1) == 0 and doctext.length(3) == 1, "insert line before first")
        doctext.delete(1)
        tap.ok(doctext.count == 2 and doctext.length(2) == 1, "delete first line updates positions")
        doctext.delete(2)
        tap.ok(doctext.count == 1 and buffer.length() == 0, "delete last line removes preceding newline")
        void doctext.insert_at(1,0,'z')
        doctext.delete(1)
        tap.ok(doctext.count == 1 and doctext.length(1) == 0, "delete sole line leaves empty document")
        reset()
        void doctext.insert_at(1,0,'a')
        void doctext.insert_at(1,1,'b')
        tap.ok(doctext.yank(1) and doctext.has_yank(), "yank document line")
        tap.ok(doctext.put(2) and doctext.count == 2 and doctext.length(2) == 2, "paste after last line")
        tap.ok(doctext.put(1) and doctext.count == 3 and doctext.pos(3) == 6, "paste before first line")
        doctext.clear()
        tap.ok(doctext.has_yank() and doctext.put(1), "yank survives new document")
        reset()
        sys.memset(window,76,'x')
        window[76] = 0
        tap.ok(doctext.commit(1,window) and doctext.length(1) == 76, "commit full visible window")
        doctext.first_col = 76
        void doctext.insert_at(1,0,'Y')
        tap.ok(doctext.length(1) == 77 and buffer.get(76) == 'Y', "insert beyond original visible width")
        doctext.first_col = 0
        doctext.fetch(1,window)
        window[0] = 'Q'
        tap.ok(doctext.commit(1,window) and buffer.get(76) == 'Y' and doctext.length(1) == 77, "commit preserves text beyond visible window")
        doctext.first_col = 70
        doctext.fetch(1,window)
        tap.ok(window[6] == 'Y' and window[7] == ' ' and window[76] == 0, "panned fetch pads and terminates window")
        doctext.delete_at(1,6)
        tap.ok(doctext.length(1) == 76, "panned delete uses absolute column")
        reset()
        doctext.fetch(1,window)
        tap.ok(window[0] == ' ' and window[75] == ' ' and window[76] == 0, "empty fetch returns padded window")
        sys.memcopy("a\r\x0ab\rc\x0ad",raw,8)
        doctext.after_cr = false
        n = doctext.clean(raw,8)
        tap.ok(n == 7 and raw[1] == $0a and raw[3] == $0a and raw[5] == $0a, "normalize CRLF CR and LF")
        raw[0] = 1
        raw[1] = 255
        doctext.after_cr = false
        n = doctext.clean(raw,2)
        tap.ok(n == 2 and raw[0] == ' ' and raw[1] == ' ', "unsupported bytes become spaces")
        raw[0] = $0d
        doctext.after_cr = false
        n = doctext.clean(raw,1)
        raw[0] = $0a
        raw[1] = 'x'
        n = doctext.clean(raw,2)
        tap.ok(n == 1 and raw[0] == 'x', "CRLF split between chunks normalizes once")
        tap.ok(buffer.check(), "document edits preserve buffer invariants")
        tap.done()
    }
}
