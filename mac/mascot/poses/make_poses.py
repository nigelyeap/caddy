"""Generates the 16 Caddy poses as SVG, then a contact sheet. Run: uv run --with pillow python make_poses.py"""
import math, subprocess, os
from PIL import Image, ImageDraw
T='#1F7A72'; AF='#F6B23C'; AS='#E09A20'; CR='#FFF4DC'; P='#F4A6A0'; BL='#3FA3F6'; LT='#A9DDD7'; Y='#FFD23F'; TS='#6FB9AF'
def path(d,f='none',s=None,w=14):
    s=f' stroke="{s}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"' if s else ''
    return f'<path d="{d}" fill="{f}"{s}/>'
def st(d,w=16,c=T): return path(d,'none',c,w)
def wing(bx,by,tx,ty,w=26):
    dx,dy=tx-bx,ty-by; L=math.hypot(dx,dy); nx,ny=-dy/L*w,dx/L*w
    mx,my=(bx+tx)/2,(by+ty)/2
    return path(f'M{bx+nx*.5:.0f} {by+ny*.5:.0f} Q{mx+nx*1.4:.0f} {my+ny*1.4:.0f} {tx:.0f} {ty:.0f} Q{mx-nx*1.4:.0f} {my-ny*1.4:.0f} {bx-nx*.5:.0f} {by-ny*.5:.0f}Z',AF,AS,14)
WL=lambda: wing(98,318,60,372)      # resting wings
WR=lambda: wing(414,318,452,372)
def body(shell=True,dy=0):
    s=path('M242 104 C216 50 266 18 296 44 C268 48 262 74 276 104 Z',AF,AS)
    s+='<circle cx="256" cy="262" r="178" fill="#F6B23C" stroke="#E09A20" stroke-width="14"/>'
    if shell: s+=f'<g transform="translate(0 18)">'+path('M70 300 L116 336 L163 300 L210 336 L256 300 L302 336 L349 300 L396 336 L442 300 C442 420 360 482 256 482 C152 482 70 420 70 300 Z',CR,AS)+'</g>'
    return s
def goggles_up():
    return st('M120 212 Q256 56 392 212',18,T)+path('M172 138 a31 31 0 1 0 62 0 a31 31 0 1 0 -62 0 M278 138 a31 31 0 1 0 62 0 a31 31 0 1 0 -62 0',LT,BL,16)
def goggles_down():
    return (st('M100 222 L412 222',18,T)+path('M168 222 a38 38 0 1 0 76 0 a38 38 0 1 0 -76 0 M268 222 a38 38 0 1 0 76 0 a38 38 0 1 0 -76 0',LT,BL,16)
        +f'<path d="M184 210 Q192 194 208 192 M284 210 Q292 194 308 192" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round"/>')
blush=lambda y=268: f'<ellipse cx="140" cy="{y}" rx="24" ry="14" fill="{P}"/><ellipse cx="372" cy="{y}" rx="24" ry="14" fill="{P}"/>'
def dot(x,y,r=15,dx=0,dy=0): return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{T}"/><circle cx="{x+dx+r*.3:.0f}" cy="{y+dy-r*.35:.0f}" r="{r*.34:.0f}" fill="#fff"/>'
def eyes(k):
    if k=='exc': return st('M168 256 L216 240 L168 224')+st('M344 256 L296 240 L344 224')
    if k=='arch': return st('M176 250 Q196 218 216 250')+st('M296 250 Q316 218 336 250')
    if k=='dot': return dot(192,242,15)+dot(320,242,15)
    if k=='wide': return dot(192,240,21)+dot(320,240,21)
    if k=='up': return dot(192,236,16,2,-3)+dot(320,236,16,2,-3)
    if k=='left': return dot(186,242,16,-4,0)+dot(314,242,16,-4,0)
    if k=='right': return dot(198,242,16,4,0)+dot(326,242,16,4,0)
    if k=='flat': return st('M168 246 L216 246')+st('M296 246 L344 246')
    if k=='wink': return dot(192,242,15)+st('M296 250 Q316 218 336 250')
    if k=='heart':
        h=lambda x:path(f'M{x} 262 C{x-34} 236 {x-26} 214 {x-12} 214 C{x-4} 214 {x} 220 {x} 226 C{x} 220 {x+4} 214 {x+12} 214 C{x+26} 214 {x+34} 236 {x} 262Z','#FF6B8B','#FF6B8B',6)
        return h(192)+h(320)
    if k=='sad': return dot(192,246,15)+dot(320,246,15)+st('M164 214 L214 228',10,AS)+st('M348 214 L298 228',10,AS)
def mouth(k):
    if k=='smile': return st('M232 272 Q256 296 280 272',13)
    if k=='w': return st('M230 274 Q243 292 256 274 Q269 292 282 274',11)
    if k=='open': return path('M236 266 Q256 308 276 266Z',T,T,8)+path('M248 290 Q256 301 264 290 Q256 284 248 290Z',P)
    if k=='wide': return path('M222 262 Q256 322 290 262Z',T,T,8)+path('M242 296 Q256 312 270 296 Q256 288 242 296Z',P)
    if k=='O': return f'<ellipse cx="256" cy="284" rx="14" ry="18" fill="{T}"/>'
    if k=='flat': return st('M238 282 L274 282',12)
    if k=='frown': return st('M234 290 Q256 268 278 290',12)
    if k=='wavy': return st('M228 284 Q242 270 256 284 Q270 298 284 284',11)
sparkle=lambda x,y,s=14,c=Y: path(f'M{x} {y-s} Q{x} {y} {x+s} {y} Q{x} {y} {x} {y+s} Q{x} {y} {x-s} {y} Q{x} {y} {x} {y-s}Z',c,'#D9A400',3)
def lines(x,y,sgn): return ''.join(st(f'M{x+sgn*a} {y+b} L{x+sgn*(a+26)} {y+b*1.8:.0f}',9,TS) for a,b in ((0,-30),(8,0),(0,30)))
bulb=lambda x,y: path(f'M{x} {y} a28 28 0 1 1 28 -2 q-12 12 -10 30 h-18 q2 -18 -10 -28Z',Y,'#D9A400',8)+st(f'M{x+4} {y+36} h22',8,'#D9A400')+''.join(st(f'M{x+14+dx} {y-46+dy} l{dx//2} {dy//2-6}',7,'#D9A400') for dx,dy in((-50,20),(0,-4),(50,20)))
def txt(t,x,y,s=60,c=BL): return f'<text x="{x}" y="{y}" font-family="Arial Rounded MT Bold,Helvetica,Arial" font-weight="800" font-size="{s}" fill="{c}" text-anchor="middle">{t}</text>'
def make(name,eye,mo,g='up',wl=None,wr=None,extra='',shell=True,bl=268):
    s=body(shell)+(wl or WL())+(wr or WR())
    s+= goggles_up() if g=='up' else goggles_down() if g=='down' else ''
    s+= blush(bl)+(eyes(eye) if g!='down' else '')+mouth(mo)+extra
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{s}</svg>'
tear=path('M158 268 q-12 22 0 30 q12 -8 0 -30Z',LT,BL,4)
POSES=[
 ('hello',        make('hello','arch','open',wr=wing(410,300,462,210))),
 ('point_right',  make('pr','right','smile',wr=wing(396,296,506,286,34))),
 ('point_left',   make('pl','left','smile',wl=wing(116,296,6,286,34))),
 ('point_up',     make('pu','up','smile',wr=wing(400,290,470,150,34),extra=sparkle(490,120))),
 ('talking',      make('t','dot','O',extra=lines(430,250,1)+lines(82,250,-1))),
 ('explaining',   make('e','dot','wide',wl=wing(98,318,38,262),wr=wing(414,318,474,262))),
 ('thinking',     make('th','up','flat',wr=wing(412,330,304,296,32),extra=txt('?',420,150))),
 ('idea',         make('i','wide','open',wr=wing(410,300,452,190),extra=bulb(386,60))),
 ('cheer',        make('c','exc','wide',wl=wing(98,300,56,190),wr=wing(414,300,456,190),extra=sparkle(60,130)+sparkle(452,110,18)+sparkle(30,220,10))),
 ('love_it',      make('l','heart','open',extra=sparkle(430,110,16,'#FF6B8B'))),
 ('wink',         make('w','wink','smile',extra=sparkle(344,224,12,'#fff'))),
 ('scanning',     make('s','dot','smile','down',wr=wing(396,296,506,286,34),extra=st('M430 190 L486 150 M436 222 L500 222 M430 254 L486 294',8,BL))),
 ('oops',         make('o','sad','wavy',extra=path('M388 150 q-14 26 0 36 q14 -10 0 -36Z',LT,BL,4))),
 ('sleepy',       make('z','flat','w',extra=txt('z',420,130,46,TS)+txt('Z',452,90,62,TS))),
 ('sad',          make('sd','sad','frown',extra=tear)),
 ('hatching',     None),
]
def hatching():
    sh=CR
    s=path('M242 104 C216 50 266 18 296 44 C268 48 262 74 276 104 Z',AF,AS)
    s='<g transform="translate(256 330) scale(.78) translate(-256 -330)">'+s+'<circle cx="256" cy="262" r="178" fill="#F6B23C" stroke="#E09A20" stroke-width="14"/>'+'</g>'
    s+='<g transform="translate(0 34)">'+path('M60 330 L110 372 L160 330 L210 372 L256 330 L302 372 L350 330 L400 372 L452 330 C452 440 370 498 256 498 C142 498 60 440 60 330Z',CR,AS)+'</g>'
    s+=sparkle(60,200,16)+sparkle(450,170,20)+sparkle(420,260,10)
    face=f'<g transform="translate(256 330) scale(.78) translate(-256 -330)">{goggles_up()}{blush(268)}{eyes("exc")}{mouth("open")}</g>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{s}{face}</svg>'
POSES[-1]=('hatching',hatching())
cell=300
W=Image.new('RGB',(4*cell,4*(cell+24)),(255,255,255));d=ImageDraw.Draw(W)
for i,(n,svg) in enumerate(POSES):
    f=f'{i+1:02d}_{n}.svg';open(f,'w').write(svg)
    subprocess.run(['qlmanage','-t','-s',str(cell-20),'-o','.',f],capture_output=True)
    im=Image.open(f+'.png').convert('RGBA');bg=Image.new('RGBA',im.size,(255,255,255,255));bg.alpha_composite(im)
    x,y=(i%4)*cell+10,(i//4)*(cell+24)+22;W.paste(bg.convert('RGB'),(x,y));d.text((x,y-16),f'{i+1} {n}',fill=(0,0,0))
    os.remove(f+'.png')
W.save('sheet.png');print(len(POSES))
