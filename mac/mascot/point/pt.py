import sys,math,subprocess,os
sys.path.insert(0,'/Users/nigelyeap/Documents/cad-training/mac/mascot/poses')
os.makedirs('/tmp/caddy_scratch',exist_ok=True);os.chdir('/tmp/caddy_scratch')
import make_poses as M
os.chdir('/Users/nigelyeap/Documents/cad-training/mac/mascot/point')
from PIL import Image,ImageDraw
T,AF,AS,P=M.T,M.AF,M.AS,M.P
star=lambda x,y,r,c='#fff': f'<path d="M{x} {y-r} Q{x} {y} {x+r} {y} Q{x} {y} {x} {y+r} Q{x} {y} {x-r} {y} Q{x} {y} {x} {y-r}Z" fill="{c}"/>'
ell=lambda x,y,rx,ry,c=T: f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"/>'
def eye(x,y,dx=0,dy=0): return ell(x+dx,y+dy,20,27)+star(x+dx+4,y+dy-9,10)+f'<circle cx="{x+dx-7}" cy="{y+dy+10}" r="3.5" fill="#fff"/>'
def eyes(dx=0,dy=0): return eye(192,244,dx,dy)+eye(320,244,dx,dy)
def arm(bx,by,tx,ty):
    a=math.atan2(ty-by,tx-bx);ux,uy=math.cos(a),math.sin(a)
    hx,hy=tx-ux*50,ty-uy*50
    ln=lambda x1,y1,x2,y2,w,c: f'<path d="M{x1:.0f} {y1:.0f} L{x2:.0f} {y2:.0f}" stroke="{c}" stroke-width="{w}" stroke-linecap="round" fill="none"/>'
    cir=lambda c,r: f'<circle cx="{hx:.0f}" cy="{hy:.0f}" r="{r}" fill="{c}"/>'
    return (ln(bx,by,hx,hy,50,AS)+cir(AS,36)+ln(hx,hy,tx,ty,32,AS)
            +ln(bx,by,hx,hy,36,AF)+cir(AF,22+0)+cir(AF,22)+ln(hx,hy,tx,ty,18,AF)+cir(AF,26))
mo=M.mouth('smile'); sp=M.sparkle
def mk(wl=None,wr=None,dx=0,dy=0,extra='',mouth=mo):
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'+M.body(True)+(wl or M.WL())+(wr or M.WR())+M.goggles_up()+M.blush(268)+eyes(dx,dy)+mouth+extra+'</svg>'
D=[('right',mk(wr=arm(396,300,490,286),dx=10,extra=sp(496,230,12))),
 ('left',mk(wl=arm(116,300,22,286),dx=-10,extra=sp(16,230,12))),
 ('up',mk(wr=arm(400,296,458,170),dy=-8,extra=sp(470,110,14))),
 ('up_left',mk(wl=arm(112,296,54,170),dx=-6,dy=-8,extra=sp(42,110,14))),
 ('down',mk(wr=arm(420,330,470,450),dy=6)),
 ('both_sides',mk(wl=arm(116,300,22,286),wr=arm(396,300,490,286),extra=sp(256,36,14))),
 ('at_you',mk(wr=arm(400,320,330,420),mouth=M.mouth('open'),extra=sp(440,200,12))),
 ('look_here',mk(wr=arm(396,300,490,286),dx=10,mouth=M.mouth('wide'),extra=M.txt('!',460,200,64))),]
cell=300;W=Image.new('RGB',(4*cell,2*(cell+22)),(255,255,255));d=ImageDraw.Draw(W)
for i,(n,s) in enumerate(D):
    f=f'{i+1}_{n}.svg';open(f,'w').write(s)
    subprocess.run(['qlmanage','-t','-s','280','-o','.',f],capture_output=True)
    im=Image.open(f+'.png').convert('RGBA');bg=Image.new('RGBA',im.size,(255,255,255,255));bg.alpha_composite(im)
    x,y=(i%4)*cell+10,(i//4)*(cell+22)+20;W.paste(bg.convert('RGB'),(x,y));d.text((x,y-14),f'{i+1} {n}',fill=(0,0,0))
W.save('point_sheet.png')
