; Wide-offset gap buffer spanning detected X16 RAM banks 4..last.
; No pointer into banked RAM escapes this module: disk I/O uses main-RAM staging.
%import bankram
%import strings
%import fastmem_platform
buffer {
    const bool PAGED = true
    const long NONE = -1
    const ubyte NUM_MARKS = 4
    const uword BLOCK = 512
    pointer work = memory("bankwork", BLOCK, 1)
    pointer io = memory("bankio", BLOCK, 1)
    long capacity
    long bufend
    long gappos
    long gapsize
    uword installed_banks
    bool modified
    uword changes
    ubyte eol = $0a
    long change_start = NONE
    long change_end
    long[NUM_MARKS] marks
    pointer yank_buf
    uword yank_size
    uword yank_len
    ; Editor undo is not connected; keep that boundary explicit.
    uword undo_size
    sub init(pointer unused_start, pointer unused_top) {
        installed_banks = bankram.banks()
        capacity = 0
        if installed_banks > bankram.RESERVED {
            capacity = installed_banks
            capacity -= bankram.RESERVED
            capacity <<= 13
        }
        clear()
    }
    sub clear() { void loaded(0) }
    sub loaded(long count) -> bool {
        if count < 0 or count > capacity
            return false
        bufend = count
        gappos = count
        gapsize = capacity - count
        ubyte i
        for i in 0 to NUM_MARKS-1
            marks[i] = 0
        modified = false
        changes++
        change_start = 0
        change_end = count
        return true
    }
    sub length() -> long { return bufend }
    sub free() -> long { return gapsize }
    sub change_reset() { change_start = NONE change_end = 0 }
    sub changed(long position) {
        modified = true
        changes++
        if change_start == NONE or position < change_start
            change_start = position
        change_end = bufend
    }
    sub set_mark(ubyte n, long position) { marks[n] = min(max(position, 0), bufend) }
    sub get_mark(ubyte n) -> long { return marks[n] }
    sub physical(long position) -> long {
        if position < gappos
            return position
        return position + gapsize
    }
    ; Transport chunks never cross the physical bank window.
    sub read_raw(long position, pointer dest, uword count) {
        uword n
        while count != 0 {
            n = min(count, 8192 - (position & $1fff) as uword)
            bankram.read(position, dest, n)
            position += n
            dest += n
            count -= n
        }
    }
    sub write_raw(long position, pointer source, uword count) {
        uword n
        while count != 0 {
            n = min(count, 8192 - (position & $1fff) as uword)
            bankram.write(position, source, n)
            position += n
            source += n
            count -= n
        }
    }
    sub get(long position) -> ubyte {
        if position < 0 or position >= bufend
            return 0
        read_raw(physical(position), io, 1)
        return io[0]
    }
    sub set(long position, ubyte value) -> bool {
        if position < 0 or position >= bufend
            return false
        io[0] = value
        write_raw(physical(position), io, 1)
        changed(position)
        return true
    }
    sub move_gap(long position) {
        position = min(max(position, 0), bufend)
        uword n
        while gappos > position {
            n = min(gappos - position, BLOCK as long) as uword
            read_raw(gappos-n, work, n)
            write_raw(gappos+gapsize-n, work, n)
            gappos -= n
        }
        while gappos < position {
            n = min(position-gappos, BLOCK as long) as uword
            read_raw(gappos+gapsize, work, n)
            write_raw(gappos, work, n)
            gappos += n
        }
    }
    sub inserted(uword count) {
        if count as long > gapsize
            count = gapsize as uword
        ubyte i
        for i in 0 to NUM_MARKS-1 {
            long mark = marks[i]
            if mark > gappos {
                mark += count
                marks[i] = mark
            }
        }
        gappos += count
        bufend += count
        gapsize -= count
        if count != 0
            changed(gappos-count)
    }
    sub insert_char(ubyte value, long position) -> bool {
        if gapsize == 0
            return false
        move_gap(position)
        io[0] = value
        write_raw(gappos, io, 1)
        inserted(1)
        return true
    }
    sub insert_bytes(pointer source, uword count, long position) -> bool {
        if count as long > gapsize
            return false
        move_gap(position)
        write_raw(gappos, source, count)
        inserted(count)
        return true
    }
    sub insert(str text, long position) -> bool { return insert_bytes(text, strings.length(text), position) }
    sub delete_nchar(long count, long position) -> long {
        if position < 0 or position >= bufend or count <= 0
            return 0
        count = min(count, bufend-position)
        move_gap(position)
        bufend -= count
        gapsize += count
        ubyte i
        for i in 0 to NUM_MARKS-1 {
            if marks[i] > position
                marks[i] = max(position, marks[i]-count)
        }
        changed(position)
        return count
    }
    sub delete_char(long position) -> bool { return delete_nchar(1, position) == 1 }
    sub delete_range(long start, long end) -> long { return delete_nchar(end-start, start) }
    sub copy_out(long position, uword count, pointer dest) -> uword {
        if position < 0 or position >= bufend
            return 0
        count = min(count as long, bufend-position) as uword
        uword first = 0
        if position < gappos {
            first = min(count as long, gappos-position) as uword
            read_raw(position, dest, first)
        }
        if count > first
            read_raw(physical(position+first), dest+first, count-first)
        return count
    }
    ; Disk input is staged in unbanked RAM so ROM calls cannot select the wrong bank.
    sub read_room(long position) -> pointer, uword {
        move_gap(position)
        return io, min(gapsize, BLOCK as long) as uword
    }
    sub read_done(uword count) {
        count = min(count as long, min(gapsize, BLOCK as long)) as uword
        write_raw(gappos, io, count)
        inserted(count)
    }
    ; Saving traverses logical text in bounded main-RAM chunks.
    sub chunks() -> uword {
        long total = bufend
        total += BLOCK-1
        total >>= 9
        return max(1, total as uword)
    }
    sub chunk(uword n) -> pointer, uword {
        long position = n
        position <<= 9
        return io, copy_out(position, BLOCK, io)
    }
    sub find_next(ubyte value, long position, long limit) -> long {
        limit = min(limit, bufend)
        position = max(position, 0)
        uword n
        uword found
        while position < limit {
            n = min(limit-position, BLOCK as long) as uword
            void copy_out(position, n, io)
            if fastmem.FAST
                found = fastmem.find(io as uword, n, value)
            else {
                found = 0
                while found < n and io[found] != value
                    found++
            }
            if found < n
                return position+found
            position += n
        }
        return limit
    }
    sub find_prev(ubyte value, long position) -> long {
        position = min(position, bufend)
        uword n
        while position > 0 {
            n = min(position, BLOCK as long) as uword
            position -= n
            void copy_out(position, n, io)
            while n != 0 {
                n--
                if io[n] == value
                    return position+n
            }
        }
        return NONE
    }
    sub match_at(pointer pattern, ubyte count, long position) -> bool {
        if position < 0 or position+count > bufend
            return false
        ubyte i
        for i in 0 to count-1 {
            if get(position+i) != pattern[i]
                return false
        }
        return true
    }
    sub line_end(long position) -> long { return find_next(eol, position, bufend) }
    sub line_start(long position) -> long {
        long found = find_prev(eol, position)
        if found == NONE
            return 0
        return found+1
    }
    sub next_line(long position) -> long {
        long end = line_end(position)
        if end >= bufend
            return NONE
        return end+1
    }
    sub prev_line(long position) -> long {
        long start = line_start(position)
        if start == 0
            return NONE
        return line_start(start-1)
    }
    sub line_number(long position) -> long {
        long at = 0
        long total = 0
        position = min(position, bufend)
        uword n
        uword i
        while at < position {
            n = min(position-at, BLOCK as long) as uword
            void copy_out(at, n, io)
            if fastmem.FAST
                total += fastmem.count(io as uword, n, eol)
            else {
                for i in 0 to n-1 {
                    if io[i] == eol
                        total++
                }
            }
            at += n
        }
        return total
    }
    sub yank(long start, long count, bool lines) -> bool {
        if count < 0 or count >= (yank_size as long)
            return false
        yank_len = copy_out(start, count as uword, yank_buf)
        if lines and (yank_len == 0 or yank_buf[yank_len-1] != eol) {
            yank_buf[yank_len] = eol
            yank_len++
        }
        return true
    }
    sub put(long position) -> bool { return insert_bytes(yank_buf, yank_len, position) }
    sub check() -> bool {
        return bufend >= 0 and gapsize >= 0 and bufend+gapsize == capacity and gappos >= 0 and gappos <= bufend
    }
}
