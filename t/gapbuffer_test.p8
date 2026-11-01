%encoding iso
%import gapbuffer
%import tap
main {
    pointer arena = memory("arena", 512, 1)
    pointer scratch = memory("scratch", 512, 1)
    pointer yankspace = memory("yankspace", 32, 1)
    pointer undospace = memory("undospace", 128, 1)
    sub same(str expected) -> bool {
        uword i
        if buffer.length() != strings.length(expected)
            return false
        for i in 0 to buffer.length()-1 {
            if buffer.get(i) != expected[i]
                return false
        }
        return true
    }
    sub reset() {
        buffer.undo_size = 0
        buffer.init(arena, arena + 512)
        buffer.eol = $0a
        buffer.yank_buf = yankspace
        buffer.yank_size = 32
    }
    sub start() {
        uword n
        pointer p
        reset()
        tap.ok(buffer.length() == 0 and buffer.free() == 512 and buffer.check(), "empty buffer and invariants")
        tap.ok(buffer.get(0) == 0 and buffer.delete_nchar(1,0) == 0, "empty reads and deletes")
        tap.ok(buffer.insert("abc",0) and same("abc"), "insert initial text")
        void buffer.insert_char('X',0)
        tap.ok(same("Xabc"), "insert at beginning")
        void buffer.insert_char('Y',2)
        tap.ok(same("XaYbc"), "insert in middle")
        void buffer.insert_char('Z',999)
        tap.ok(same("XaYbcZ"), "insert beyond end clamps to end")
        buffer.move_gap(1)
        buffer.scramble_gap()
        tap.ok(same("XaYbcZ") and buffer.check(), "move gap left and poison free space")
        buffer.move_gap(5)
        buffer.scramble_gap()
        tap.ok(same("XaYbcZ") and buffer.check(), "move gap right and poison free space")
        tap.ok(buffer.copy_out(0,512,scratch) == 6 and scratch[2] == 'Y' and scratch[5] == 'Z', "copy across gap clamps at end")
        tap.ok(buffer.set(2,'Q') and same("XaQbcZ"), "overwrite character")
        tap.ok(not buffer.set(6,'!') and buffer.get(6) == 0, "overwrite past end rejected")
        tap.ok(buffer.delete_char(0) and same("aQbcZ"), "delete first character")
        tap.ok(buffer.delete_range(1,3) == 2 and same("acZ"), "delete middle range")
        tap.ok(buffer.delete_nchar(999,2) == 1 and same("ac"), "delete through end clamps")
        tap.ok(buffer.delete_range(2,1) == 0 and same("ac"), "reversed range is unchanged")
        buffer.set_mark(0,1)
        void buffer.insert_char('!',0)
        tap.ok(buffer.get_mark(0) == 2, "marks move with inserted text")
        void buffer.delete_nchar(2,0)
        tap.ok(buffer.get_mark(0) == 0, "marks inside deletion clamp")
        reset()
        void buffer.insert("ab\x0acd\x0aef",0)
        buffer.move_gap(4)
        buffer.scramble_gap()
        tap.ok(buffer.find_next($0a,0,512) == 2 and buffer.find_prev($0a,8) == 5, "search across gap in both directions")
        tap.ok(buffer.find_next('z',0,8) == 8 and buffer.find_prev('z',8) == buffer.NONE, "missing search sentinels")
        tap.ok(buffer.line_offset(1) == 3 and buffer.line_number(7) == 2, "line offsets and numbering")
        tap.ok(buffer.line_start(4) == 3 and buffer.line_end(4) == 5, "line boundaries")
        tap.ok(buffer.next_line(6) == buffer.NONE and buffer.prev_line(0) == buffer.NONE, "first and last line sentinels")
        tap.ok(buffer.yank(3,2,true) and buffer.yank_len == 3 and yankspace[2] == $0a, "line yank includes newline")
        tap.ok(buffer.put(0) and same("cd\x0aab\x0acd\x0aef"), "paste yanked text")
        reset()
        sys.memset(scratch,512,'k')
        tap.ok(buffer.insert_bytes(scratch,512,0) and buffer.free() == 0 and buffer.check(), "fill buffer exactly")
        tap.ok(not buffer.insert_char('x',0) and buffer.length() == 512, "full buffer rejects insertion")
        buffer.move_gap(256)
        tap.ok(buffer.get(0) == 'k' and buffer.get(511) == 'k' and buffer.check(), "move zero-sized gap")
        void buffer.delete_nchar(10,250)
        tap.ok(not buffer.insert_bytes(scratch,11,0) and buffer.length() == 502 and buffer.check(), "oversized insert leaves buffer intact")
        reset()
        sys.memset(scratch,512,'A')
        scratch[255] = $0a
        scratch[256] = $0a
        void buffer.insert_bytes(scratch,400,0)
        buffer.move_gap(200)
        buffer.scramble_gap()
        tap.ok(buffer.find_next($0a,0,400) == 255, "forward scan across 256-byte boundary")
        tap.ok(buffer.find_prev($0a,400) == 256 and buffer.find_prev($0a,256) == 255, "reverse scan across page boundary")
        tap.ok(buffer.line_number(400) == 2 and buffer.line_number(256) == 1, "count newlines across page and gap")
        n = buffer.copy_out(0,400,scratch)
        tap.ok(n == 400 and scratch[255] == $0a and scratch[256] == $0a and scratch[399] == 'A' and buffer.check(), "copy page-sized text across poisoned gap")
        reset()
        p,n = buffer.read_room(0)
        sys.memcopy("load",p,4)
        buffer.read_done(4)
        tap.ok(same("load") and buffer.check(), "read-room commit")
        tap.ok(not buffer.loaded(513) and same("load"), "oversized loaded count rejected")
        reset()
        buffer.undo_init(undospace,128)
        buffer.undo_mark()
        void buffer.insert("abc",0)
        tap.ok(buffer.can_undo(), "insert recorded for undo")
        void buffer.undo()
        tap.ok(buffer.length() == 0 and buffer.check(), "undo insertion")
        void buffer.undo()
        tap.ok(same("abc") and buffer.check(), "redo insertion")
        buffer.undo_mark()
        void buffer.delete_char(1)
        void buffer.undo()
        tap.ok(same("abc"), "undo deletion")
        buffer.undo_mark()
        void buffer.set(1,'X')
        void buffer.undo()
        tap.ok(same("abc"), "undo replacement")
        reset()
        tap.ok(not buffer.can_undo() and buffer.check(), "reset clears undo and invariants")
        tap.done()
    }
}
