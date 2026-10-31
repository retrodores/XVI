; The text of xvi2's document as numbered lines, kept in the text store (see
; docs/TEXT-STORE.md).  This is the part of xvi2 that doesn't depend on the
; target: no screen, no keys.  The block is called doctext.
;
; xvi2 sees a line through a window of WIDTH columns, from first_col: fetch()
; fills a copy of them, padded with spaces, and commit() puts it back.  The
; window pans over longer lines.  Changes to a line's length go straight to
; the store (insert_at(), delete_at(), delete_to_end()), so what is past the
; window stays.  Everything else about the line is the store's business, so
; the store can be swapped (only pointers from read_room() and chunk() are
; used, and none is kept over a store call).
;
; Line numbers count from 1, like xvi2's.  There is always a line: the empty
; text is one empty line.  The line ending after the last line isn't in the
; text, load() takes it off and save() adds it.

%import diskio
%import gapbuffer
%import strings
%import xvi_platform

doctext {
    ; the columns of a line that can be seen at once
    const ubyte WIDTH = plat.TEXT_WIDTH
    ; how far the window moves when the cursor reaches its edge
    const ubyte PAN = WIDTH / 2
    ; xvi2 yanks a line at a time
    const uword YANK_SIZE = 1024

    uword count         ; the number of lines
    bool truncated      ; the last load() ran out of memory
    uword first_col     ; the first column of the window (from 0)

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
        first_col = 0
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

    ; returns the length of a line, 0 if there is no such line
    sub length(uword line) -> uword {
        uword start = pos(line)
        if start == buffer.NONE
            return 0
        return buffer.line_end(start) - start
    }

    ; copy the window on a line to dest (WIDTH + 1 bytes): WIDTH characters,
    ; padded with spaces, and a 0.  a line that doesn't exist, or ends before
    ; the window, comes out blank.
    sub fetch(uword line, pointer dest) {
        uword n = length(line)
        sys.memset(dest, WIDTH, $20)
        dest[WIDTH] = 0
        if n > first_col {
            n -= first_col
            if n > WIDTH
                n = WIDTH
            void buffer.copy_out(cache_pos + first_col, n, dest)
        }
    }

    ; replace what fetch() gave for a line with the WIDTH characters at text.
    ; spaces at the end go, unless the line goes on past the window: then
    ; the columns are replaced one for one.  a line that ends before the
    ; window gets spaces up to it.  returns false, with the line as it was,
    ; if it doesn't fit.
    sub commit(uword line, pointer text) -> bool {
        uword start = pos(line)
        uword line_len
        uword pad = 0
        ubyte old_len = 0
        ubyte new_len = WIDTH
        if start == buffer.NONE
            return true
        line_len = buffer.line_end(start) - start
        if line_len > first_col + WIDTH
            old_len = WIDTH
        else {
            while new_len != 0 and text[new_len - 1] == $20
                new_len--
            if line_len > first_col
                old_len = (line_len - first_col) as ubyte
            else if new_len != 0
                pad = first_col - line_len
        }
        if new_len == old_len and (new_len == 0 or buffer.match_at(text, new_len, start + first_col))
            return true
        if buffer.free() + old_len < new_len + pad
            return false
        repeat pad
            void buffer.insert_char($20, start + line_len)
        if old_len != 0
            void buffer.delete_nchar(old_len, start + first_col)
        if new_len != 0
            void buffer.insert_bytes(text, new_len, start + first_col)
        remember(line, start)
        return true
    }

    ; insert a character at column col of the window, with spaces first if
    ; the line ends before it.  returns false if there's no room.
    sub insert_at(uword line, ubyte col, ubyte c) -> bool {
        uword start = pos(line)
        uword line_len
        uword target = first_col + col
        uword pad = 0
        if start == buffer.NONE
            return true
        line_len = buffer.line_end(start) - start
        if target > line_len
            pad = target - line_len
        if buffer.free() < pad + 1
            return false
        repeat pad
            void buffer.insert_char($20, start + line_len)
        void buffer.insert_char(c, start + target)
        remember(line, start)
        return true
    }

    ; delete the character at column col of the window
    sub delete_at(uword line, ubyte col) {
        uword start = pos(line)
        uword target = first_col + col
        if start != buffer.NONE and target < buffer.line_end(start) - start {
            void buffer.delete_char(start + target)
            remember(line, start)
        }
    }

    ; delete from column col of the window to the end of the line
    sub delete_to_end(uword line, ubyte col) {
        uword start = pos(line)
        uword target = first_col + col
        uword end
        if start != buffer.NONE {
            end = buffer.line_end(start)
            if target < end - start {
                void buffer.delete_range(start + target, end)
                remember(line, start)
            }
        }
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
        if not plat.open_read(name)
            return false
        buffer.clear()
        first_col = 0
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
        if not plat.open_write(name)
            return false
        for i in 0 to buffer.chunks() - 1 {
            p, n = buffer.chunk(i)
            if not diskio.f_write(p, n)
                ok = false
        }
        if not diskio.f_write(&buffer.eol, 1)
            ok = false
        diskio.f_close_w()
        return ok and plat.write_ok()
    }
}
