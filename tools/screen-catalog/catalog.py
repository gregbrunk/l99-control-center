"""Read-only catalog of the L99 interface file. Opens only the given file; no devices."""
import hashlib, json, struct, sys, zlib, collections
from pathlib import Path

SRC = Path(sys.argv[1]); OUT = Path(sys.argv[2])
data = SRC.read_bytes()
assert hashlib.sha256(data).hexdigest().startswith('4cb3fa5c'), 'unexpected file'
OUT.mkdir(parents=True, exist_ok=True); (OUT/'img').mkdir(exist_ok=True); (OUT/'pages').mkdir(exist_ok=True)
u16 = lambda o: struct.unpack_from('<H', data, o)[0]
u32 = lambda o: struct.unpack_from('<I', data, o)[0]
H = [u32(i) for i in range(0, 0x58, 4)]
PT, PN = H[2], H[3]; ANT, ANN = H[10], H[11]; BT, BN = H[8], H[9]; IT, IN = H[12], H[13]

def png(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y*w*4:(y+1)*w*4]) for y in range(h))
    def chunk(t, d): c = t + d; return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

def c565(v): return ((v >> 11) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31, 255)
def c4444(v): return (((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17, (v >> 12) * 17)

cache = {}
def decode(addr, w, h, size, fmt):
    key = (addr, w, h, size, fmt)
    if key in cache: return cache[key]
    px = None
    if size and 0 < w <= 2048 and 0 < h <= 2048 and addr + size <= len(data):
        if fmt in (0, 1, 2) and size == w * h * 2:
            vals = struct.unpack_from(f'<{w*h}H', data, addr)
            f = c4444 if fmt == 2 else c565
            px = bytearray(); [px.extend(f(v)) for v in vals]
        elif fmt == 3 and data[addr:addr+2] == b'LT':
            try:
                n = data[addr+6]; inner = u32(addr+8); cur = addr + 12 + n * 516; out = []
                for ci in range(n):
                    t = addr + 12 + ci * 516; hd = u32(t); ln = hd & 0xffffff; mode = hd >> 24
                    pal = struct.unpack_from('<256H', data, t + 4); content = data[cur:cur+ln]
                    if mode == 1:
                        for i in range(0, ln, 2): out.extend([pal[content[i+1]]] * (content[i] + 1))
                    else: out.extend(pal[b] for b in content)
                    cur += ln
                if len(out) == w * h:
                    px = bytearray(); [px.extend(c565(v)) for v in out]
            except Exception: px = None
    cache[key] = px
    return px

def desc(o):
    a, w, h, p = struct.unpack_from('<IHHI', data, o)
    return dict(addr=a, w=w, h=h, size=p & 0xffffff, fmt=p >> 24)

icons = [[desc(IT + (b * IN + i) * 12) for i in range(IN)] for b in range(2)]
anims = []
for g in range(ANN):
    ft, fc = struct.unpack_from('<II', data, ANT + g * 8)
    fr = []
    for f in range(fc):
        a, _, w, h, p = struct.unpack_from('<IIHHI', data, ft + f * 16)
        fr.append(dict(addr=a, w=w, h=h, size=p & 0xffffff, fmt=p >> 24))
    anims.append(fr)

def records(p, n, fam):
    end = p + n; res = []
    while p < end:
        typ = u16(p); pre = 5 if fam == 'd' else 3; lb = data[p+pre-1]; ln = lb & 0x7f
        pay = data[p+pre:p+pre+ln]
        r = dict(off=p, type=typ, len=ln, lb=lb, payload=pay.hex())
        if fam == 'd':
            r['param'] = u16(p + 2)
            if ln >= 2: r['words'] = list(struct.unpack_from(f'<{ln//2}H', pay))
        else:
            r['base'] = typ & 0x3fff
            if ln >= 2: r['words'] = list(struct.unpack_from(f'<{ln//2}H', pay))
        res.append(r); p += pre + ln
    assert p == end
    return res

pages = []
for i in range(PN):
    dp, dn, tp, tn = struct.unpack_from('<IHIH', data, PT + i * 12)
    pages.append(dict(id=i, d=records(dp, dn, 'd'), t=records(tp, tn, 't'), doff=dp, dlen=dn, toff=tp, tlen=tn))

def blit(canvas, px, w, h, x, y):
    for yy in range(h):
        cy = y + yy
        if not 0 <= cy < 480: continue
        for xx in range(w):
            cx = x + xx
            if not 0 <= cx < 320: continue
            s = (yy * w + xx) * 4; a = px[s+3]
            if a == 0: continue
            d = (cy * 320 + cx) * 4
            if a == 255: canvas[d:d+4] = px[s:s+4]
            else:
                for k in range(3): canvas[d+k] = (px[s+k] * a + canvas[d+k] * (255 - a)) // 255

def icon_px(bank, i):
    if not 0 <= i < IN: return None
    d = icons[bank][i]; px = decode(**d)
    return (px, d['w'], d['h']) if px else None

saved = set()
def save_icon(bank, i):
    k = (bank, i)
    if k in saved: return
    r = icon_px(bank, i)
    if r: png(OUT/'img'/f'b{bank}_{i:03d}.png', r[1], r[2], r[0]); saved.add(k)

for pg in pages:
    canvas = bytearray([0, 0, 0, 255] * 320 * 480)
    used = []
    for r in pg['d']:
        w = r.get('words', [])
        if r['type'] == 3 and r['len'] == 14:
            used.append(w[3]); ic = icon_px(0, w[3])
            if ic: blit(canvas, ic[0], ic[1], ic[2], w[1], w[2])
        elif r['type'] == 5 and r['len'] >= 12 and w[5] < len(anims):
            f = anims[w[5]][0]; px = decode(**f)
            if px: blit(canvas, px, f['w'], f['h'], w[1], w[2])
    for r in pg['t']:
        w = r.get('words', [])
        if r['base'] == 1 and r['len'] == 16 and w[5] != 0xFFFF:
            used.append(w[5]); used.append(w[6]); ic = icon_px(0, w[5])
            if ic: blit(canvas, ic[0], ic[1], ic[2], w[0], w[1])
    png(OUT/'pages'/f'p{pg["id"]:02d}.png', 320, 480, canvas)
    pg['icons_used'] = sorted(set(x for x in used if x != 0xFFFF))
    for i in pg['icons_used']: save_icon(0, i)

for i in range(IN): save_icon(0, i)
for g, fr in enumerate(anims):
    f = fr[0]; px = decode(**f)
    if px: png(OUT/'img'/f'anim{g}_f0.png', f['w'], f['h'], px)

json.dump(dict(header=H, pages=pages, icons=icons, anims=[[f for f in fr] for fr in anims]), open(OUT/'catalog.json', 'w'))
for pg in pages:
    dt = collections.Counter(r['type'] for r in pg['d']); tt = collections.Counter(hex(r['type']) for r in pg['t'])
    print(pg['id'], 'display', dict(dt), 'touch', dict(tt))
print('anims', [(len(f), f[0]['w'], f[0]['h']) for f in anims])
