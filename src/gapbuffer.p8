; The gap buffer: a text store in one block of memory (see buffer.p8 for
; what a text store is and does).  The VIC-20 uses it.
;
; Memory layout (ram addresses):
;
;   ramstart           gapstart        gapend          ramtop
;   |  text before gap  |      gap      |  text after gap |
;
; - The gap is all of the free memory, so text always ends at ramtop
;   and the buffer never needs to "grow".  free() is simply gapsize.
; - gapend is *inclusive* (last byte of the gap), so an empty gap
;   has gapend == gapstart - 1.
; - Invariants kept by every routine:
;     gapsize == gapend - gapstart + 1
;     bufend + gapsize == ramtop - ramstart
;     gappos == gapstart - ramstart
;
; Buffer offsets (bufend, gappos, positions, marks) never include the gap.
; The gap position is internal: editors keep their cursor (and the top of
; the screen etc.) in marks, which are adjusted by inserts and deletes.

%import buffer
%import fastmem_platform

buffer {
    ; not a page store: read_room() gives all the room there is at once,
    ; so a file is read in one piece, and a delete is logged in one piece.
    ; (code only a page store needs can be left out with it)
    const bool PAGED = false

    ; the gap buffer's own variables: private, the editor uses the
    ; routines (the tests use gap_position(), check() and scramble_gap())

    ; ram address based coordinates
    private pointer ramstart  ; start of buffer ram
    private pointer ramtop    ; 1 byte past the last usable byte

    ; zero relative buffer coordinates
    private uword gappos    ; buffer offset of the gap

    ; gap buffer coordinates are ram addresses
    private pointer gapstart  ; first byte of the gap, moves
    private pointer gapend    ; last byte of the gap (inclusive), moves
    private uword gapsize     ; current size of the gap, also the free memory

    ; use the memory from start up to (not including) top and empty the buffer
    sub init(pointer start, pointer top) {
        ramstart = start
        ramtop = top
        clear()
    }

    ; empty the buffer, the gap becomes all of ramstart..ramtop-1
    sub clear() {
        void loaded(0)
    }

    ; call after placing count bytes of text at ramstart (e.g. a file load).
    ; the gap is placed after the text and all marks are reset to 0.
    ; returns false if it can't fit.
    sub loaded(uword count) -> bool {
        ubyte i
        if count > ramtop - ramstart
            return false
        bufend = count
        gappos = count
        gapstart = ramstart + count
        gapend = ramtop - 1
        gapsize = (ramtop - gapstart) as uword
        for i in 0 to NUM_MARKS - 1
            marks[i] = 0
        modified = false
        change_start = 0
        change_end = count
        undo_len = 0
        undo_lost = false
        return true
    }

    ; returns free memory
    sub free() -> uword {
        return gapsize
    }

    ; returns the length of the text
    sub length() -> uword {
        return bufend
    }

    ; get the character at a specific offset
    ; returns 0 for offsets past the end of the text
    sub get(uword offset) -> ubyte {
        if offset >= bufend
            return 0
        return @(buffer2ram(offset))
    }

    ; overwrite the character at offset (for overtype / replace).
    ; the gap does not move.  returns false past the end of the text.
    sub set(uword offset, ubyte value) -> bool {
        pointer p
        if offset >= bufend
            return false
        p = buffer2ram(offset)
        log_change('s', offset, p, 1)
        @(p) = value
        modified = true
        changes++
        note_change(offset, 1, 1)
        return true
    }

    ;
    ; moving the gap
    ;

    ; move the gap to position, clamped to the end of the text.
    ; editing routines and read_room() do this themselves; it can make
    ; chunk(0) hold the whole text.  the text in between moves to the
    ; other side of the gap, in pieces no larger than the gap so they never
    ; overlap.
    sub move_gap(uword position) {
        pointer target
        uword n
        if position > bufend
            position = bufend
        target = ramstart + position
        if gapsize == 0 {
            ; no gap: ram and buffer coordinates are the same
            gapstart = target
            gapend = target - 1
        }
        ; moving left
        while gapstart > target {
            n = min((gapstart - target) as uword, gapsize)
            gapstart -= n
            gapend -= n
            sys.memcopy(gapstart, gapend + 1, n)
        }
        ; moving right
        while gapstart < target {
            n = min((target - gapstart) as uword, gapsize)
            sys.memcopy(gapend + 1, gapstart, n)
            gapstart += n
            gapend += n
        }
        gappos = position
    }

    ;
    ; inserting
    ;

    ; insert a character at position.
    ; returns false if the buffer is full.
    sub insert_char(ubyte input, uword position) -> bool {
        if gapsize == 0
            return false
        move_gap(position)
        @(gapstart) = input
        inserted(1)
        return true
    }

    ; insert count bytes from src at position, any byte values allowed.
    ; src must not point into the buffer itself (use copy_out first).
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert_bytes(pointer src, uword count, uword position) -> bool {
        if count > gapsize
            return false
        move_gap(position)
        sys.memcopy(src, gapstart, count)
        inserted(count)
        return true
    }

    ; room to read text into at position (e.g. from a file): returns its
    ; ram address and how many bytes fit (the gap).  write at most that
    ; many there, then call read_done() with the number written.
    sub read_room(uword position) -> pointer, uword {
        move_gap(position)
        return gapstart, gapsize
    }

    ; count bytes were written at read_room(), make them part of the text
    alias read_done = inserted

    ; count bytes were written at the gap (gapstart), make them part of
    ; the text
    sub inserted(uword count) {
        if count > gapsize
            count = gapsize
        if count != 0 {
            log_change('i', gappos, gapstart, count)
            note_change(gappos, count, 0)
        }
        gapstart += count
        gapsize -= count
        marks_inserted(gappos, count)
        gappos += count
        bufend += count
        if count != 0 {
            modified = true
            changes++
        }
    }

    ;
    ; deleting
    ;

    ; delete up to count characters starting at position.
    ; returns the number of characters actually deleted.
    sub delete_nchar(uword count, uword position) -> uword {
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        move_gap(position)
        log_change('d', position, gapend + 1, count)
        note_change(position, 0, count)
        gapend += count
        gapsize += count
        bufend -= count
        marks_deleted(position, count)
        modified = true
        changes++
        return count
    }

    ;
    ; no recovery after a crash with the gap buffer (see pagestore.p8):
    ; these are for the editor's code that PAGED leaves out
    ;

    const ubyte META_SIZE = 48
    ubyte recoverable
    uword synced_changes

    sub sync(uword meta) {
    }

    sub clean() {
    }

    sub recover(uword meta) -> bool {
        return false
    }

    ;
    ; the yank buffer, in main RAM at yank_buf
    ;

    ; copy count bytes of text at start into the yank buffer, with a line
    ; ending after them if lines is set and they don't end with one.
    ; returns false (and keeps what was in it) if they don't fit.
    sub yank(uword start, uword count, bool lines) -> bool {
        if count > yank_size - 1
            return false
        yank_len = copy_out(start, count, yank_buf)
        if lines and (yank_len == 0 or yank_buf[yank_len - 1] != eol) {
            yank_buf[yank_len] = eol
            yank_len++
        }
        return true
    }

    ; insert the yank buffer at position.  returns false (and inserts
    ; nothing) if it doesn't fit.
    sub put(uword position) -> bool {
        return insert_bytes(yank_buf, yank_len, position)
    }

    ;
    ; the undo log (see buffer.p8), in main RAM at undo_buf
    ;

    private sub log_change(ubyte kind, uword position, pointer data, uword count) {
        uword start
        uword last_pos
        uword last_count
        if undo_size == 0 or undo_off
            return
        if undo_new {
            undo_new = false
            undo_len = 0
            undo_lost = false
            undo_reversed = false
        }
        if undo_lost
            return
        if undo_len != 0 and undo_buf[undo_len - 1] == 'i' {
            last_count = peekw(undo_buf + undo_len - 3)
            last_pos = peekw(undo_buf + undo_len - 5)
            start = undo_len - 7 - last_count
            ; typing on after the last insert: make that insert longer
            if kind == 'i' and position == last_pos + last_count and undo_len + count <= undo_size {
                sys.memcopy(data, undo_buf + undo_len - 5, count)
                put_record(start, last_count + count, last_pos, 'i')
                return
            }
            ; deleting the end of what the last insert added: make it shorter
            if kind == 'd' and position >= last_pos and position + count == last_pos + last_count {
                last_count -= count
                undo_len = start
                if last_count != 0
                    put_record(start, last_count, last_pos, 'i')
                return
            }
        }
        if count > undo_size - undo_len or undo_size - undo_len - count < 7 {
            undo_lost = true
            return
        }
        sys.memcopy(data, undo_buf + undo_len + 2, count)
        put_record(undo_len, count, position, kind)
    }

    ; write the rest of the record whose count data bytes follow start:
    ; the count before the data, the position, count and kind after it.
    ; the log ends after the record.
    private sub put_record(uword start, uword count, uword position, ubyte kind) {
        pointer p = undo_buf + start
        pokew(p, count)
        p += count + 2
        pokew(p, position)
        pokew(p + 2, count)
        p[4] = kind
        undo_len = start + count + 7
    }

    ; revert the logged change (or re-do it, if it was just undone).
    ; returns the lowest position changed, or NONE if there is nothing to undo.
    sub undo() -> uword {
        uword lowest = NONE
        uword at
        uword count
        uword position
        if not can_undo()
            return NONE
        undo_off = true
        if undo_reversed {
            ; re-do: the records in the order they were made
            at = 0
            while at < undo_len {
                count = peekw(undo_buf + at)
                position = peekw(undo_buf + at + count + 2)
                undo_record(at + count + 7, count, position)
                lowest = min(lowest, position)
                at += count + 7
            }
        } else {
            ; undo: the last record first
            at = undo_len
            while at != 0 {
                count = peekw(undo_buf + at - 3)
                position = peekw(undo_buf + at - 5)
                undo_record(at, count, position)
                lowest = min(lowest, position)
                at -= count + 7
            }
        }
        undo_off = false
        undo_reversed = not undo_reversed
        undo_new = false
        return lowest
    }

    ; apply the opposite of the record ending at end, and turn the record
    ; into that opposite so the next undo() reverses it again
    private sub undo_record(uword end, uword count, uword position) {
        pointer data = undo_buf + end - 5 - count
        ubyte old
        when undo_buf[end - 1] {
            'i' -> {
                void delete_nchar(count, position)
                undo_buf[end - 1] = 'd'
            }
            'd' -> {
                void insert_bytes(data, count, position)
                undo_buf[end - 1] = 'i'
            }
            's' -> {
                old = get(position)
                void set(position, @(data))
                @(data) = old
            }
        }
    }

    ;
    ; reading
    ;

    ; copy up to count characters starting at position to dest.
    ; returns the number of characters copied.
    sub copy_out(uword position, uword count, pointer dest) -> uword {
        uword n1 = 0
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        if count == 0
            return 0
        ; part before the gap
        if position < gappos {
            n1 = min(count, gappos - position)
            sys.memcopy(ramstart + position, dest, n1)
        }
        ; part after the gap
        if count > n1
            sys.memcopy(buffer2ram(position + n1), dest + n1, count - n1)
        return count
    }

    ; the text in pieces, to go through all of it in order without
    ; changing it (saving, translating): chunk(0) to chunk(chunks() - 1)
    ; return the ram address and length of each piece.  the gap buffer has
    ; two, the text before and after the gap (either may be empty).
    sub chunks() -> ubyte {
        return 2
    }

    sub chunk(ubyte n) -> pointer, uword {
        if n == 0
            return ramstart, gappos
        return gapend + 1, bufend - gappos
    }

    ;
    ; searching
    ;

    ; returns the offset of the first value at or after position and
    ; before limit (limit is clamped to the end of the text).
    ; returns limit if it is not found.
    sub find_next(ubyte value, uword position, uword limit) -> uword {
        if fastmem.FAST
            return fast_find_next(value, position, limit)
        else {
            pointer p
            uword stop
            if limit > bufend
                limit = bufend
            ; part before the gap
            if position < gappos {
                stop = min(limit, gappos)
                p = ramstart + position
                while position < stop {
                    if @(p) == value
                        return position
                    p++
                    position++
                }
            }
            ; part after the gap
            if position < limit {
                p = buffer2ram(position)
                while position < limit {
                    if @(p) == value
                        return position
                    p++
                    position++
                }
            }
            return limit
        }
    }

    private sub fast_find_next(ubyte value, uword position, uword limit) -> uword {
        uword n
        if limit > bufend
            limit = bufend
        ; part before the gap, then after it (to their ends: limit is
        ; checked after)
        if position < gappos {
            n = gappos - position
            position += fastmem.find(ramstart as uword + position, n, value)
            if position != gappos
                goto done
        }
        if position < bufend
            position += fastmem.find(buffer2ram(position) as uword, bufend - position, value)
done:
        if position > limit
            position = limit
        return position
    }

    ; returns the offset of the last value before position, or NONE.
    sub find_prev(ubyte value, uword position) -> uword {
        if fastmem.FAST
            return fast_find_prev(value, position)
        else {
            pointer p
            if position > bufend
                position = bufend
            ; part after the gap
            if position > gappos {
                p = buffer2ram(position - 1)
                while position > gappos {
                    position--
                    if @(p) == value
                        return position
                    p--
                }
            }
            ; part before the gap
            if position > 0 {
                p = ramstart + position - 1
                while position > 0 {
                    position--
                    if @(p) == value
                        return position
                    p--
                }
            }
            return NONE
        }
    }

    private sub fast_find_prev(ubyte value, uword position) -> uword {
        uword found
        if position > bufend
            position = bufend
        ; part after the gap
        if position > gappos {
            found = fastmem.find_back(gapend as uword + 1, position - gappos, value)
            if found != NONE
                return gappos + found
            position = gappos
        }
        ; part before the gap
        found = fastmem.find_back(ramstart as uword, position, value)
        if found != NONE
            return found
        return NONE
    }

    ; returns the start of line number line, or NONE if there aren't
    ; that many lines
    sub line_offset(uword line) -> uword {
        uword position = 0
        while line > 0 {
            position = next_line(position)
            if position == NONE
                return NONE
            line--
        }
        return position
    }

    ; returns the line number of position
    sub line_number(uword position) -> uword {
        if fastmem.FAST
            return fast_line_number(position)
        else {
            uword line = 0
            uword found = 0
            if position > bufend
                position = bufend
            repeat {
                found = find_next(eol, found, position)
                if found >= position
                    return line
                line++
                found++
            }
        }
    }

    private sub fast_line_number(uword position) -> uword {
        if position > bufend
            position = bufend
        ; the line endings before position: before the gap, and after it
        if position <= gappos
            return fastmem.count(ramstart as uword, position, eol)
        return fastmem.count(ramstart as uword, gappos, eol) + fastmem.count(gapend as uword + 1, position - gappos, eol)
    }

    ;
    ; addresses
    ;

    ; returns the *ram* address of the character at buffer offset bufaddr
    ; skipping over the gap if needed.
    sub buffer2ram(uword bufaddr) -> pointer {
        pointer temp = ramstart + bufaddr
        if temp < gapstart
            return temp
        return temp + gapsize
    }

    ; returns the ram address one past the last byte of text, which
    ; is always ramtop since the text after the gap is kept against it.
    sub ramend() -> pointer {
        return ramstart + bufend + gapsize
    }


    ;
    ; for the tests (the editor doesn't call these, so they are left out of
    ; its builds)
    ;

    ; the gap's position in the text
    sub gap_position() -> uword {
        return gappos
    }

    ; fill the gap with junk, so reading gap bytes by mistake can't give
    ; stale copies of the text
    sub scramble_gap() {
        if gapsize != 0
            sys.memset(gapstart, gapsize, '#')
    }

    ; whether the invariants at the top of this file hold
    sub check() -> bool {
        if gapend != gapstart + gapsize - 1
            return false
        if bufend + gapsize != ramtop - ramstart
            return false
        if gapstart - ramstart != gappos
            return false
        return ramend() == ramtop
    }

} ; end of buffer block (gap buffer)
