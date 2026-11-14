; Commander X16 native text-store byte scans and copies.
%import fastmem

fastmem {
%option merge
    ; Production uses native helpers; VM tests select portable scans.
    const bool FAST = true
}
