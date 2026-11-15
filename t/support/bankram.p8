; Test-only bank transport for the Prog8 VM. Production code is unchanged.
bankram {
    const uword RESERVED = 4
    pointer storage = memory("vmbankedram", 491520, 1)
    sub banks() -> uword { return 64 }
    sub read(long offset, pointer dest, uword count) {
        sys.memcopy(storage + offset, dest, count)
    }
    sub write(long offset, pointer source, uword count) {
        sys.memcopy(source, storage + offset, count)
    }
}
