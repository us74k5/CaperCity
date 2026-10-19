"""Decoders for Crime Fighter graphics: BGI-style planar blocks (.CUT/.SPF) and IFF ILBM (.SPF)."""
import struct, sys, os
from PIL import Image

EGA = [(0,0,0),(0,0,170),(0,170,0),(0,170,170),(170,0,0),(170,0,170),(170,85,0),(170,170,170),
       (85,85,85),(85,85,255),(85,255,85),(85,255,255),(255,85,85),(255,85,255),(255,255,85),(255,255,255)]

def blocks(d):
    """Yield (w, rows, data) for each [u16 0][u16 size][u16 w-1][u16 h-1][data][pad2] block."""
    off = 0
    while off + 8 <= len(d):
        z, size = struct.unpack_from('<HH', d, off)
        w1, h1 = struct.unpack_from('<HH', d, off + 4)
        W = w1 + 1; bpr = (W + 7) // 8
        datalen = size - 6
        rows = datalen // (bpr * 4)
        yield W, rows, d[off + 8: off + 8 + rows * bpr * 4]
        off += 4 + size

def planar_to_img(W, rows, data, order=(0,1,2,3), pal=EGA):
    bpr = (W + 7) // 8
    img = Image.new('P', (W, rows)); img.putpalette([c for p in pal for c in p])
    px = img.load()
    for y in range(rows):
        base = y * bpr * 4
        planes = [data[base + p*bpr: base + (p+1)*bpr] for p in range(4)]
        for x in range(W):
            bit = 7 - (x & 7); v = 0
            for i, p in enumerate(order):
                if planes[p][x >> 3] >> bit & 1: v |= 1 << i
            px[x, y] = v
    return img

def decode_bgi(path, **kw):
    d = open(path, 'rb').read()
    parts = [planar_to_img(W, r, data, **kw) for W, r, data in blocks(d)]
    if len(parts) == 1: return parts[0]
    W = max(p.width for p in parts); H = sum(p.height for p in parts)
    out = Image.new('P', (W, H)); out.putpalette(parts[0].getpalette()); y = 0
    for p in parts: out.paste(p, (0, y)); y += p.height
    return out

def decode_ilbm(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'FORM' and d[8:12] == b'ILBM'
    off = 12; pal = None; body = None
    while off < len(d) - 8:
        cid = d[off:off+4]; n = struct.unpack('>I', d[off+4:off+8])[0]; c = d[off+8:off+8+n]
        if cid == b'BMHD':
            W, H, _, _, nplanes, mask, comp = struct.unpack('>HHhhBBB', c[:11])
        elif cid == b'CMAP': pal = [tuple(c[i:i+3]) for i in range(0, len(c), 3)]
        elif cid == b'BODY': body = c
        off += 8 + n + (n & 1)
    bpr = ((W + 15) // 16) * 2
    raw = bytearray(); i = 0
    if comp == 1:
        need = bpr * nplanes * H
        while len(raw) < need and i < len(body):
            n = body[i]; i += 1
            if n < 128: raw += body[i:i+n+1]; i += n + 1
            elif n > 128: raw += bytes([body[i]]) * (257 - n); i += 1
    else: raw = bytearray(body)
    img = Image.new('P', (W, H)); img.putpalette([c for p in pal for c in p] + [0]*(768-3*len(pal)))
    px = img.load()
    for y in range(H):
        for x in range(W):
            v = 0
            for p in range(nplanes):
                if raw[(y*nplanes + p)*bpr + (x >> 3)] >> (7 - (x & 7)) & 1: v |= 1 << p
            px[x, y] = v
    return img

def decode(path, **kw):
    with open(path, 'rb') as f: head = f.read(4)
    return decode_ilbm(path) if head == b'FORM' else decode_bgi(path, **kw)

if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    decode(src).save(dst)
