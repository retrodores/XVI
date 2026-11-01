 ; Test-only document geometry and file adapter; no screen or keyboard emulation.
%import diskio
plat {
    const ubyte TEXT_WIDTH = 76
    sub open_read(str name) -> bool { return diskio.f_open(name) }
    sub open_write(str name) -> bool { return diskio.f_open_w(name) }
    sub write_ok() -> bool { return true }
}
