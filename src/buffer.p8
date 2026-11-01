; The text store's interface and the parts of it that don't depend on how
; the text is kept.  A text store is the block "buffer"; gapbuffer.p8 (one
; block of memory with a gap) and pagestore.p8 (pages) each add the rest
; of it, and a program imports one of them.
;
; Positions are zero relative offsets in the text (0 to length()); all
; positions passed in are clamped to that.  Editors keep their cursor (and
; the top of the screen etc.) in marks, which are adjusted by inserts and
; deletes.  The variables should be treated as read-only outside this
; block, except eol and modified.
;
; Each store has these routines (see either file):
;   init(start, top)  clear()  loaded(count)  free()  length()
;   get(pos)  set(pos, value)  insert_char(c, pos)  insert_bytes(src, n, pos)
;   read_room(pos)  read_done(count)  delete_nchar(n, pos)
;   copy_out(pos, n, dest)  chunks()  chunk(n)
;   find_next(value, pos, limit)  find_prev(value, pos)
;   line_offset(line)  line_number(pos)
; and uses bufend, note_change(), marks_inserted(), marks_deleted() and
; log_change() below for every change.

%import strings

buffer {
%option merge

    ; returned by searches and line routines when there is no result
    const uword NONE = $ffff
    ; marks are positions that move along with inserts and deletes
    const ubyte NUM_MARKS = 4

    private uword bufend    ; length of the text (1 past the last character)

    ; (variables marked private are the store's own: use the routines)

    ; line ending character used by the line routines
    ubyte eol = $0d

    ; set by every change to the text, cleared by loaded() / clear().
    ; the editor clears it after saving.
    bool modified
    ; counts every change to the text (it wraps around): compare two
    ; readings to see whether anything changed in between
    uword changes
    ; the text from change_start up to change_end may differ from what it
    ; was at the last change_reset() (NONE if nothing changed).  text before
    ; change_start is the same, text after change_end is the same but moved
    ; by the change in length().  for redrawing only what changed.
    uword change_start = NONE
    uword change_end

    private uword[NUM_MARKS] marks

    ; the yank buffer (see yank()): yank_len bytes; it can hold yank_size
    ; less one.  the gap buffer keeps it at yank_buf, the page store in its
    ; pages.  set yank_buf and yank_size before using it.
    pointer yank_buf
    uword yank_size
    uword yank_len

    ; undo log for one change (see undo_init(), or set undo_buf and
    ; undo_size); disabled while undo_size is 0
    pointer undo_buf
    uword undo_size
    private uword undo_len  ; bytes used
    private bool undo_new   ; the next change starts a new log
    bool undo_lost          ; the change didn't fit, it can't be undone
    bool undo_reversed      ; the log was undone, undoing again redoes it
    private bool undo_off   ; not logging (while undoing)

    ;
    ; change tracking
    ;

    ; forget the changes so far (after redrawing them)
    sub change_reset() {
        change_start = NONE
        change_end = 0
    }

    ; count bytes at position were replaced by inserted new ones
    private sub note_change(uword position, uword inserted, uword deleted) {
        if change_start == NONE {
            change_start = position
            change_end = position + inserted
            return
        }
        ; the end of the earlier change moves with this one
        if change_end > position {
            if change_end - position > deleted
                change_end = change_end - deleted + inserted
            else
                change_end = position + inserted
        }
        if position < change_start
            change_start = position
        if position + inserted > change_end
            change_end = position + inserted
    }

    ;
    ; marks
    ;

    ; set mark m to position (clamped to the end of the text)
    sub set_mark(ubyte m, uword position) {
        if position > bufend
            position = bufend
        marks[m] = position
    }

    sub get_mark(ubyte m) -> uword {
        return marks[m]
    }

    ; count bytes were inserted at position: marks after it move right.
    ; a mark exactly at position stays, so text inserted there ends up after it.
    private sub marks_inserted(uword position, uword count) {
        ubyte i
        for i in 0 to NUM_MARKS - 1 {
            if marks[i] > position
                marks[i] += count
        }
    }

    ; count bytes were deleted at position: marks inside the deleted
    ; range move to position, marks after it move left.
    private sub marks_deleted(uword position, uword count) {
        ubyte i
        for i in 0 to NUM_MARKS - 1 {
            if marks[i] > position {
                if marks[i] - position <= count
                    marks[i] = position
                else
                    marks[i] -= count
            }
        }
    }

    ;
    ; inserting and deleting
    ;

    ; insert a string at position.
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert(str input, uword position) -> bool {
        return insert_bytes(input, strings.length(input), position)
    }

    ; delete the character at position (like vi 'x').
    ; returns false if there is no character at position.
    sub delete_char(uword position) -> bool {
        return delete_nchar(1, position) == 1
    }

    ; delete the characters from position start up to (not including) end.
    ; returns the number of characters actually deleted.
    sub delete_range(uword start, uword end) -> uword {
        if end <= start
            return 0
        return delete_nchar(end - start, start)
    }

    ;
    ; undo
    ;
    ; every insert, delete and set() is recorded in the undo log, until
    ; undo_mark() says the next change starts a new log.  so the log holds
    ; one editor command (e.g. a whole insert session).  undo() reverts it,
    ; and undo() again re-does it.  loaded() and clear() empty the log.
    ;
    ; each log record is: count (2 bytes), count data bytes, position
    ; (2 bytes), count (2 bytes) and the kind: 'i' inserted, 'd' deleted,
    ; 's' set (the data is the byte it replaced).  the count at both ends
    ; lets the log be walked in both directions.  each store keeps the log
    ; its own way (log_change(), undo()).
    ;

    ; use size bytes at buf for the undo log (the page store keeps it in
    ; its pages: buf isn't used, size is the most it may hold)
    sub undo_init(pointer buf, uword size) {
        undo_buf = buf
        undo_size = size
        undo_len = 0
        undo_lost = false
    }

    ; forget the logged change (after changing the text behind the buffer's back)
    sub undo_clear() {
        undo_len = 0
        undo_lost = false
    }

    ; the next change starts a new undo log (call before each editor command)
    sub undo_mark() {
        undo_new = true
    }

    ; bytes in the undo log (for the tests)
    sub undo_bytes() -> uword {
        return undo_len
    }

    ; true if there is a change to undo (or redo)
    sub can_undo() -> bool {
        return undo_len != 0 and not undo_lost
    }

    ;
    ; reading and searching
    ;

    ; copy the line (or the next maxlen characters of it) starting at position
    ; to dest, without the line ending, followed by a 0 byte.
    ; dest must have room for maxlen + 1 bytes.
    ; returns the number of characters copied.  if that is maxlen and
    ; get(position + maxlen) is not eol the line continues (wraps).
    sub copy_line(uword position, pointer dest, uword maxlen) -> uword {
        uword limit
        uword n = 0
        if position < bufend {
            if maxlen > bufend - position
                limit = bufend
            else
                limit = position + maxlen
            n = find_next(eol, position, limit) - position
            void copy_out(position, n, dest)
        }
        @(dest + n) = 0
        return n
    }

    ; true if the count bytes at pattern are in the text at position
    sub match_at(pointer pattern, ubyte count, uword position) -> bool {
        ubyte i
        if count as uword > bufend or position > bufend - count
            return false
        for i in 0 to count - 1 {
            if get(position + i) != pattern[i]
                return false
        }
        return true
    }

    ; returns the offset of the first occurrence of the count bytes at
    ; pattern that starts at or after position and ends at or before limit,
    ; or NONE.  count must be at least 1.
    sub find_bytes(pointer pattern, ubyte count, uword position, uword limit) -> uword {
        if limit > bufend
            limit = bufend
        repeat {
            position = find_next(pattern[0], position, limit)
            if position >= limit
                return NONE
            if position + count <= limit and match_at(pattern, count, position)
                return position
            position++
        }
    }

    ; returns the offset of the last occurrence of the count bytes at
    ; pattern that starts before position, or NONE.  count must be at least 1.
    sub find_bytes_prev(pointer pattern, ubyte count, uword position) -> uword {
        repeat {
            position = find_prev(pattern[0], position)
            if position == NONE
                return NONE
            if match_at(pattern, count, position)
                return position
        }
    }

    ;
    ; lines
    ;
    ; every eol starts a new line, so "a<eol>" is two lines: "a" and "".
    ; line numbers are zero relative.
    ;

    ; returns the offset of the start of the line containing position
    sub line_start(uword position) -> uword {
        uword found = find_prev(eol, position)
        if found == NONE
            return 0
        return found + 1
    }

    ; returns the offset of the eol ending the line containing position,
    ; or the end of the text for the last line
    sub line_end(uword position) -> uword {
        return find_next(eol, position, bufend)
    }

    ; returns the start of the line after the one containing position,
    ; or NONE if it is the last line
    sub next_line(uword position) -> uword {
        uword end = line_end(position)
        if end >= bufend
            return NONE
        return end + 1
    }

    ; returns the start of the line before the one containing position,
    ; or NONE if it is the first line
    sub prev_line(uword position) -> uword {
        uword start = line_start(position)
        if start == 0
            return NONE
        return line_start(start - 1)
    }

}
