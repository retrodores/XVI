; The text of xvi2's document as numbered lines, kept in the text store (see
; docs/TEXT-STORE.md).  This is the part of xvi2 that doesn't depend on the
; target: no screen, no keys.  The block is called doctext.
;
; xvi2 edits a fixed width copy of one line: fetch() fills it, padded with
; spaces, and commit() puts it back.  Everything else about the line is the
; store's business, so the store can be swapped (only pointers from
; read_room() and chunk() are used, and none is kept over a store call).
;
; Line numbers count from 1, like xvi2's.  There is always a line: the empty
; text is one empty line.  The line ending after the last line isn't in the
; text, load() takes it off and save() adds it.

%import diskio
%import gapbuffer
%import strings

doctext {
    ; the columns of a line that can be seen and edited.  a longer line keeps
    ; the rest, it is just not shown.
    const ubyte WIDTH = 76
    ; xvi2 yanks a line at a time
    const uword YANK_SIZE = 1024

    uword count         ; the number of lines
    bool truncated      ; the last load() ran out of memory

    ; a line whose position is known, so walking to the next line doesn't
    ; start from the top of the text.  it is only valid while buffer.changes
    ; is cache_changes.
    uword cache_line
    uword cache_pos
    uword cache_changes

    ; between the pieces load() reads: the last byte was a CR
    bool after_cr

    ; use the memory from start up to (not including) top for the text
    sub init(pointer start, pointer top) {
        buffer.eol = $0a
        buffer.yank_size = YANK_SIZE
        if buffer.PAGED
            buffer.yank_size = $ffff
        else
            buffer.yank_buf = memory("yank", YANK_SIZE, 1)
        buffer.init(start, top)
        clear()
    }

    ; a new empty text.  (what was yanked stays, to paste into the next file)
    sub clear() {
        buffer.clear()
        count = 1
        remember(1, 0)
    }

    sub remember(uword line, uword position) {
        cache_line = line
        cache_pos = position
        cache_changes = buffer.changes
    }

    ; returns the position of the start of a line, or buffer.NONE if there
    ; is no such line
    sub pos(uword line) -> uword {
        if line == 0 or line > count
            return buffer.NONE
        if cache_changes != buffer.changes or line < cache_line / 2
            remember(1, 0)
        while cache_line < line {
            cache_pos = buffer.next_line(cache_pos)
            cache_line++
        }
        while cache_line > line {
            cache_pos = buffer.prev_line(cache_pos)
            cache_line--
        }
        return cache_pos
    }

    ; copy a line to dest (WIDTH + 1 bytes): WIDTH characters, padded with
    ; spaces, and a 0.  a line that doesn't exist comes out blank.
    sub fetch(uword line, pointer dest) {
        uword position = pos(line)
        sys.memset(dest, WIDTH, $20)
        dest[WIDTH] = 0
        if position != buffer.NONE {
            dest[buffer.copy_line(position, dest, WIDTH)] = $20
            dest[WIDTH] = 0
        }
    }

    ; replace what fetch() gave for a line with the WIDTH characters at text.
    ; spaces at the end of them are dropped; what is past WIDTH in a longer
    ; line stays.  returns false, with the line as it was, if it doesn't fit.
    sub commit(uword line, pointer text) -> bool {
        uword start = pos(line)
        uword old_len
        ubyte new_len = WIDTH
        if start == buffer.NONE
            return true
        old_len = buffer.line_end(start) - start
        if old_len > WIDTH
            old_len = WIDTH
        while new_len != 0 and text[new_len - 1] == $20
            new_len--
        if new_len == old_len and (new_len == 0 or buffer.match_at(text, new_len, start))
            return true
        if buffer.free() + old_len < new_len
            return false
        if old_len != 0
            void buffer.delete_nchar(old_len, start)
        if new_len != 0
            void buffer.insert_bytes(text, new_len, start)
        remember(line, start)
        return true
    }

    ; a new empty line becomes the given line (up to count + 1, after the
    ; last line).  returns false if there's no room.
    sub insert_empty(uword line) -> bool {
        uword position
        if line > count {
            line = count + 1
            position = buffer.length()
            if not buffer.insert_char(buffer.eol, position)
                return false
            position++
        } else {
            position = pos(line)
            if not buffer.insert_char(buffer.eol, position)
                return false
        }
        count++
        remember(line, position)
        return true
    }

    ; delete a line.  the last one left just becomes empty.
    sub delete(uword line) {
        uword start = pos(line)
        uword next
        if start == buffer.NONE
            return
        next = buffer.next_line(start)
        if next != buffer.NONE {
            void buffer.delete_range(start, next)
            count--
            remember(line, start)
        } else if count == 1 {
            void buffer.delete_range(0, buffer.length())
            remember(1, 0)
        } else {
            ; the last line: the line ending before it goes with it
            next = pos(line - 1)
            void buffer.delete_range(start - 1, buffer.length())
            count--
            remember(line - 1, next)
        }
    }

    ; copy a line to the yank buffer.  returns false if it doesn't fit.
    sub yank(uword line) -> bool {
        uword start = pos(line)
        if start == buffer.NONE
            return false
        return buffer.yank(start, buffer.line_end(start) - start, true)
    }

    sub has_yank() -> bool {
        return buffer.yank_len != 0
    }

    ; what yank() copied becomes the given line (up to count + 1, after the
    ; last line).  returns false if there's no room.
    sub put(uword line) -> bool {
        uword position
        ; (the extra byte: the line ending needed at the end of the text)
        if buffer.free() <= buffer.yank_len
            return false
        if line > count {
            line = count + 1
            position = buffer.length() + 1
            void buffer.insert_char(buffer.eol, position - 1)
            void buffer.put(position)
            void buffer.delete_char(buffer.length() - 1)
        } else {
            position = pos(line)
            void buffer.put(position)
        }
        count++
        remember(line, position)
        return true
    }

    ; read a file as the new text.  CR LF and CR become LF and other bytes
    ; that can't be shown become spaces.  returns false if it can't be
    ; opened, and then the text is as it was.  truncated tells if the file
    ; didn't fit.
    sub load(str name) -> bool {
        pointer p
        uword room
        uword n
        uword kept
        uword position = 0
        ubyte extra
        if not diskio.f_open(name)
            return false
        buffer.clear()
        after_cr = false
        truncated = false
        ; (the gap buffer gives all its room at once)
        repeat {
            p, room = buffer.read_room(position)
            n = diskio.f_read(p, room) as uword
            kept = clean(p, n)
            buffer.read_done(kept)
            position += kept
            if not buffer.PAGED or n < room or room == 0
                break
        }
        if n == room and diskio.f_read(&extra, 1) == 1
            truncated = true
        diskio.f_close()
        if position != 0 and buffer.get(position - 1) == buffer.eol
            position--
        void buffer.loaded(position)
        count = buffer.line_number(position) + 1
        remember(1, 0)
        return true
    }

    ; make count bytes at p fit for the text, in place.  returns how many
    ; are left.
    sub clean(pointer p, uword n) -> uword {
        pointer dest = p
        pointer src = p
        ubyte c
        repeat n {
            c = @(src)
            src++
            if c == $0a and after_cr {
                after_cr = false
                continue
            }
            after_cr = c == $0d
            if c == $0d
                c = $0a
            else if c != $0a and (c < 32 or c > 126)
                c = $20
            @(dest) = c
            dest++
        }
        return (dest - p) as uword
    }

    ; write the text to a file, which must not exist yet.  returns false if
    ; that fails.
    sub save(str name) -> bool {
        pointer p
        uword n
        ubyte i
        bool ok = true
        if not diskio.f_open_w(name)
            return false
        for i in 0 to buffer.chunks() - 1 {
            p, n = buffer.chunk(i)
            if not diskio.f_write(p, n)
                ok = false
        }
        if not diskio.f_write(&buffer.eol, 1)
            ok = false
        diskio.f_close_w()
        return ok
    }
}
