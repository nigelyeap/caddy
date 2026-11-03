import subprocess
from PIL import Image,ImageDraw
T='#1F7A72';AF='#F6B23C';AS='#E09A20';CR='#FFF4DC';P='#F4A6A0';BL='#3FA3F6';LT='#A9DDD7'
def path(d,f='none',s=None,w=14):
    s=f' stroke="{s}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"' if s else ''
    return f'<path d="{d}" fill="{f}"{s}/>'
st=lambda d,w=14,c=T:path(d,'none',c,w)
body=(path('M242 104 C216 50 266 18 296 44 C268 48 262 74 276 104 Z',AF,AS)+'<circle cx="256" cy="262" r="178" fill="#F6B23C" stroke="#E09A20" stroke-width="14"/>'
 +'<g transform="translate(0 18)">'+path('M70 300 L116 336 L163 300 L210 336 L256 300 L302 336 L349 300 L396 336 L442 300 C442 420 360 482 256 482 C152 482 70 420 70 300 Z',CR,AS)+'</g>'
 +st('M120 212 Q256 56 392 212',18)+path('M172 138 a31 31 0 1 0 62 0 a31 31 0 1 0 -62 0 M278 138 a31 31 0 1 0 62 0 a31 31 0 1 0 -62 0',LT,BL,16)
 +f'<ellipse cx="140" cy="270" rx="24" ry="14" fill="{P}"/><ellipse cx="372" cy="270" rx="24" ry="14" fill="{P}"/>'+st('M232 274 Q256 298 280 274',13))
X1,X2,Y=192,320,244
def both(f): return f(X1,-1)+f(X2,1)
W_='<circle cx="{}" cy="{}" r="{}" fill="#fff"/>'
def circ(x,y,r,c=T): return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>'
def ell(x,y,rx,ry,c=T): return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"/>'

star=lambda x,y,r,c='#fff': f'<path d="M{x} {y-r} Q{x} {y} {x+r} {y} Q{x} {y} {x} {y+r} Q{x} {y} {x-r} {y} Q{x} {y} {x} {y-r}Z" fill="{c}"/>'
E={
 '1 half moon wide':   both(lambda x,s: path(f'M{x-26} {Y-2} A26 26 0 0 0 {x+26} {Y-2}Z',T,T,6)),
 '2 half moon + shine':both(lambda x,s: path(f'M{x-25} {Y-4} A25 25 0 0 0 {x+25} {Y-4}Z',T,T,6)+circ(x+8,Y+8,5,'#fff')),
 '3 half moon tall':   both(lambda x,s: path(f'M{x-21} {Y-10} A21 30 0 0 0 {x+21} {Y-10}Z',T,T,6)+ell(x+6,Y+8,5,6,'#fff')),
 '4 star oval':        both(lambda x,s: ell(x,Y,20,28)+star(x+2,Y-7,11)),
 '5 star oval big':    both(lambda x,s: ell(x,Y,23,31)+star(x+3,Y-8,15)+circ(x-8,Y+14,4,'#fff')),
 '6 star + dot':       both(lambda x,s: ell(x,Y,20,27)+star(x+4,Y-9,10)+circ(x-7,Y+10,3.5,'#fff')),
 '7 oval big shine':   both(lambda x,s: ell(x,Y,18,27)+ell(x-4,Y-9,8,11,'#fff')),
 '8 oval shine+dot':   both(lambda x,s: ell(x,Y,19,27)+ell(x-4,Y-9,8,10,'#fff')+circ(x+7,Y+11,4,'#fff')),
 '9 wide oval':        both(lambda x,s: ell(x,Y,25,20)+ell(x-5,Y-6,10,8,'#fff')),
 '10 oval look right': both(lambda x,s: ell(x+6,Y,18,27)+ell(x+10,Y-9,8,11,'#fff')),
 '11 star look up':    both(lambda x,s: ell(x,Y-4,20,27)+star(x+2,Y-16,11)),
 '12 half moon + star':both(lambda x,s: path(f'M{x-25} {Y-4} A25 25 0 0 0 {x+25} {Y-4}Z',T,T,6)+star(x+6,Y+8,8)),
}
cell=300
Wd=Image.new('RGB',(4*cell,3*(cell+10)),(255,255,255));d=ImageDraw.Draw(Wd)
for i,(n,e) in enumerate(E.items()):
    f=f'b{i+1:02d}.svg';open(f,'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="40 90 432 330">{body}{e}</svg>')
    subprocess.run(['qlmanage','-t','-s',str(cell),'-o','.',f],capture_output=True)
    im=Image.open(f+'.png').convert('RGBA');bg=Image.new('RGBA',im.size,(255,255,255,255));bg.alpha_composite(im)
    x,y=(i%4)*cell,(i//4)*(cell+10)+10;Wd.paste(bg.convert('RGB').crop((0,0,cell,cell-30)),(x,y+14));d.text((x+8,y),n,fill=(0,0,0))
Wd.save('eyes2_sheet.png')
