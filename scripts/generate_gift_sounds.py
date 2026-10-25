"""Original Pulse sound design. Reproducible synthesis, no sampled music.
Python stdlib + ffmpeg. Outputs small mono Vorbis assets at 24 kHz.
"""
from pathlib import Path
import array, math, random, subprocess, tempfile, wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 24000
SKUS = ['rose','heart','coffee','star','fire','crown','diamond','rocket',
        'galaxy','saturn','trophy','butterfly','castle','fireworks','pearl']

def synth(sku, output):
    duration = 7.5 if sku == 'rocket' else 8 if sku == 'castle' else 3 if sku == 'crown' else 3.8
    rng = random.Random(SKUS.index(sku) + 431)
    data = array.array('h')
    low = 0.0
    def bell(t, at, hz, strength=.25, decay=3):
        u = t - at
        if u < 0 or u > 2: return 0
        attack = min(1, u * 180)
        return strength * attack * math.exp(-decay*u) * (
            math.sin(math.tau*hz*u) + .30*math.sin(math.tau*hz*2.76*u)*math.exp(-u*4))
    def thump(t, at, strength=.3):
        u = t-at
        return strength * math.sin(math.tau*(74*u-32*u*u)) * math.exp(-u*17) if 0 <= u < .4 else 0
    def brass(t, at, hz, length=.6):
        u = t-at
        if not 0 < u < length: return 0
        envelope = min(1,u/.06) * min(1,(length-u)/.13)
        return .13*envelope*sum(math.sin(math.tau*hz*n*u+.012*math.sin(u*27))/n**1.45 for n in range(1,7))
    for i in range(round(RATE * duration)):
        t = i/RATE
        white = rng.uniform(-1,1)
        low = .94*low + .06*white
        value = 0
        if sku == 'rocket':
            if t < 1.9:
                envelope = min(1,t/.3) * min(1,(2.0-t)/.4)
                value += envelope*(.44*low + .11*math.sin(math.tau*48*t))
            if 1.8 < t < 4.5:
                value += .018*math.sin(math.tau*(140*t + 25*t*t)) * math.sin((t-1.8)/2.7*math.pi)
            if 4.1 < t < 6.375:
                envelope = math.sin((t-4.1)/2.275*math.pi)
                value += envelope*(.33*low + .07*math.sin(math.tau*64*t))
            value += thump(t,6.375,.4) + bell(t,6.85,784,.17) + bell(t,7.05,1175,.12)
        elif sku == 'castle':
            for at,hz in [(0.15,196),(.7,247),(1.25,294),(6.1,294),(6.1,392),(6.65,494)]:
                value += brass(t,at,hz,.7)
            if 1.5 < t < 3.2:
                u=t-1.5
                value += .045*math.sin(math.tau*(92*u-11*u*u)) * math.sin(u/1.7*math.pi) + .04*low
            value += thump(t,3.2,.16)
            for at in [3.3,3.8,4.3,4.8,5.3,5.8]: value += thump(t,at,.12)
        elif sku in ['rose','crown','star','diamond','pearl']:
            notes = {'rose':[659,830,988], 'crown':[523,659,784,1047],
                'star':[1047,1568,2093], 'diamond':[1319,1760,2637], 'pearl':[988,784,659]}[sku]
            for n,hz in enumerate(notes): value += bell(t,.12+n*.26,hz,.20 if sku!='crown' else .24,2.6)
            if sku == 'pearl':
                for at in [.15,.75,1.4]:
                    u=t-at
                    if 0<u<.18:value += .15*math.sin(math.tau*(1400*u-1800*u*u))*math.exp(-u*25)
        elif sku == 'heart':
            for at in [.15,1.2,2.25]: value += thump(t,at,.2) + thump(t,at+.24,.12)
            value += bell(t,.3,392,.08,1.7)+bell(t,1.4,494,.09,1.8)
        elif sku == 'coffee':
            value += bell(t,.18,1650,.17,7)+bell(t,.4,2200,.08,8)
            if .5<t<2:value += low*.045*math.sin((t-.5)/1.5*math.pi)
        elif sku == 'fire':
            if .1<t<3:value += low*.18
            for at in [.15,.4,.7,.9,1.2,1.6,1.8,2.4,2.7]:
                u=t-at
                if 0<u<.035:value += white*.16*math.exp(-u*130)
        elif sku in ['galaxy','saturn']:
            envelope=math.sin(math.pi*t/duration)**2
            value += envelope*(.05*math.sin(math.tau*(110*t+8*t*t))+.055*low)
            for n,hz in enumerate([440,659,880]): value+=bell(t,.3+n*.6,hz,.12,1.7)
        elif sku == 'trophy':
            for at,hz in [(.1,262),(.6,330),(1.1,392),(1.1,523)]:value += brass(t,at,hz,.7)
        elif sku == 'butterfly':
            value += .15*low*(.5+.5*math.sin(t*math.tau*10))*math.sin(math.pi*t/duration)
            for n,hz in enumerate([880,1175,1568]):value+=bell(t,.3+n*.45,hz,.08,4)
        elif sku == 'fireworks':
            for at in [.5,1.5,2.5]:
                u=t-at
                value+=thump(t,at,.25)
                if 0<u<.6:value+=white*.17*math.exp(-u*7)
        value *= min(1,t/.025)*min(1,(duration-t)/.06)
        # Soft limiting preserves the transients without digital clipping.
        data.append(round(math.tanh(value*1.4)*25000))
    import sys
    if sys.byteorder != 'little': data.byteswap()
    with tempfile.TemporaryDirectory() as temp:
        source=Path(temp)/'original.wav'
        with wave.open(str(source),'wb') as w:
            w.setparams((1,2,RATE,0,'NONE','not compressed'));w.writeframes(data.tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(source),'-c:a','libvorbis','-q:a','3',str(output)],check=True)

if __name__ == '__main__':
    directory=ROOT/'assets/audio';directory.mkdir(parents=True,exist_ok=True)
    for sku in SKUS:
        target=directory/f'gift_{sku}.ogg';synth(sku,target);print(target.name,target.stat().st_size)
