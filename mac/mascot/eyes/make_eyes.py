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
E={
 '1 tall glossy':      both(lambda x,s: ell(x,Y,19,28)+ell(x+5,Y-10,7,9,'#fff')+circ(x-6,Y+12,4,'#fff')),
 '2 big bead':         both(lambda x,s: circ(x,Y,24)+circ(x+8,Y-9,8,'#fff')+circ(x-8,Y+10,4,'#fff')),
 '3 smiling dot':      both(lambda x,s: circ(x,Y-4,15)+circ(x+5,Y-9,5,'#fff')+st(f'M{x-22} {Y+20} Q{x} {Y+34} {x+22} {Y+20}',6,AS)),
 '4 half moon':        both(lambda x,s: path(f'M{x-24} {Y+2} A24 24 0 0 0 {x+24} {Y+2}Z',T,T,6)),
 '5 white and pupil':  both(lambda x,s: circ(x,Y,28,'#fff')+f'<circle cx="{x}" cy="{Y}" r="28" fill="none" stroke="{T}" stroke-width="7"/>'+circ(x+6*s*-1,Y-2,15)+circ(x+9*s*-1,Y-8,5,'#fff')),
 '6 star shine':       both(lambda x,s: ell(x,Y,19,26)+path(f'M{x+3} {Y-16} q0 8 8 8 q-8 0 -8 8 q0 -8 -8 -8 q8 0 8 -8Z','#fff')),
 '7 iris':             both(lambda x,s: ell(x,Y,23,28)+ell(x,Y+6,15,18,'#3FA196')+ell(x-6,Y-10,7,9,'#fff')+circ(x+8,Y+12,4,'#fff')),
 '8 tiny lash':        both(lambda x,s: ell(x,Y,15,22)+circ(x+4,Y-8,5,'#fff')+st(f'M{x+s*14} {Y-14} l{s*12} {-8}',6)),
 '9 round and brows':  both(lambda x,s: circ(x,Y+2,17)+circ(x+5,Y-4,5.5,'#fff')+st(f'M{x-18} {Y-34} Q{x} {Y-46} {x+18} {Y-34}',7,AS)),
 '10 smile arches down': both(lambda x,s: st(f'M{x-20} {Y-6} Q{x} {Y+26} {x+20} {Y-6}',14)),
 '11 oval + big shine': both(lambda x,s: ell(x,Y,20,26)+ell(x-5,Y-8,9,11,'#fff')),
 '12 dot + lid':       both(lambda x,s: circ(x,Y+2,16)+circ(x+5,Y-4,5,'#fff')+st(f'M{x-22} {Y-14} Q{x} {Y-28} {x+22} {Y-14}',8)),
}
cell=300
Wd=Image.new('RGB',(4*cell,3*(cell+10)),(255,255,255));d=ImageDraw.Draw(Wd)
for i,(n,e) in enumerate(E.items()):
    f=f'{i+1:02d}.svg';open(f,'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="40 90 432 330">{body}{e}</svg>')
    subprocess.run(['qlmanage','-t','-s',str(cell),'-o','.',f],capture_output=True)
    im=Image.open(f+'.png').convert('RGBA');bg=Image.new('RGBA',im.size,(255,255,255,255));bg.alpha_composite(im)
    x,y=(i%4)*cell,(i//4)*(cell+10)+10;Wd.paste(bg.convert('RGB').crop((0,0,cell,cell-30)),(x,y+14));d.text((x+8,y),n,fill=(0,0,0))
Wd.save('eyes_sheet.png')
