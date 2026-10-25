"""Original Pulse jungle lion cinematic. Blender 4.5 LTS, CPU Cycles.
Run: blender -b --python scripts/render_lion_gift.py -- <output-directory> [preview]
The animation is rendered media; Flutter never needs a heavy 3D engine for it.
"""
import bpy, math, random, sys
from pathlib import Path
from mathutils import Vector
random.seed(71)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
out=Path(args[0] if args else '/tmp/pulse-lion-frames');out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=8;s.cycles.use_denoising=True
s.cycles.max_bounces=4;s.cycles.diffuse_bounces=2;s.cycles.glossy_bounces=2
s.render.resolution_x=432;s.render.resolution_y=768;s.render.resolution_percentage=100
s.render.fps=24;s.frame_start=1;s.frame_end=168
s.render.image_settings.file_format='PNG';s.render.filepath=str(out/'frame_')
s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.012,.032,.022,1);s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.3;s.view_settings.view_transform='AgX'

def mat(name,color,rough=.5,metal=0,noise=False,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;n=m.node_tree.nodes;p=n.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if emission:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
 if noise:
  t=n.new('ShaderNodeTexNoise');t.inputs['Scale'].default_value=65;t.inputs['Detail'].default_value=3
  bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22;bump.inputs['Distance'].default_value=.035
  m.node_tree.links.new(t.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],p.inputs['Normal'])
 return m
fur=mat('Warm ochre velvet fur',(.48,.235,.065),.65,noise=True)
lightfur=mat('Golden muzzle',(.8,.58,.29),.65,noise=True)
cream=mat('Ivory muzzle and whiskers',(.82,.72,.52),.6)
black=mat('Obsidian nose and pupils',(.012,.009,.008),.28)
mouthmat=mat('Deep mouth',(.018,.004,.004),.85)
tongue=mat('Tongue',(.32,.055,.075),.4)
tooth=mat('Ivory fangs',(.95,.84,.57),.28)
eye=mat('Amber eyes',(.95,.37,.025),.2,emission=.25)
glint=mat('Eye catchlights',(1,.92,.65),.12,emission=1)
manemats=[mat('Mane strand '+str(i),(.12+i*.018,.048+i*.01,.017+i*.004),.65,noise=True) for i in range(9)]
leafmats=[mat('Rainforest leaves '+str(i),(.018+i*.007,.075+i*.018,.034+i*.006),.4) for i in range(6)]
bark=mat('Tree bark',(.085,.055,.032),.88,noise=True)
ground=mat('Forest soil',(.045,.055,.025),.92,noise=True)
rockmat=mat('Mossy stone',(.10,.14,.105),.85,noise=True)

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o

def sphere(name,loc,scale,material,parent=None,segments=24):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=12,location=(0,0,0));o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=scale;o.data.materials.append(material)
 for f in o.data.polygons:f.use_smooth=True
 return o

def cone(name,loc,radius,depth,material,parent=None,tip=0,rot=(0,0,0)):
 bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=radius,radius2=tip,depth=depth);o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.rotation_euler=rot;o.data.materials.append(material)
 for f in o.data.polygons:f.use_smooth=True
 return o

def curve(name,points,radius,material,parent=None):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=radius;c.bevel_resolution=2
 spline=c.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
 for p,co in zip(spline.bezier_points,points):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.parent=parent;o.data.materials.append(material);return o

root=empty('Lion travel rig')
sphere('Muscular torso',(0,.14,1.28),(.43,1.03,.55),fur,root)
sphere('Powerful shoulders',(0,-.55,1.43),(.49,.51,.66),fur,root)
sphere('Haunches',(0,.78,1.22),(.43,.45,.5),fur,root)
sphere('Chest bib',(0,-.82,1.25),(.34,.28,.48),lightfur,root)
head=empty('Expressive head',(0,-.9,1.87),root)
sphere('Mane foundation',(0,.04,.03),(.69,.48,.78),manemats[3],head)
# Layered sculpted locks give the silhouette depth instead of a flat lion icon.
for i in range(94):
 a=i*2.39996;r=.58+random.random()*.08
 x=math.cos(a)*r;z=math.sin(a)*r*1.16
 o=cone('Tapered mane lock',(x,.03+random.uniform(-.12,.12),z),random.uniform(.07,.12),random.uniform(.14,.26),random.choice(manemats),head,tip=.035)
 direction=Vector((x,-.18,z));o.rotation_euler=direction.to_track_quat('Z','Y').to_euler()
for i in range(90):
 a=random.uniform(0,math.tau);x=math.cos(a)*.53;z=math.sin(a)*.67
 curve('Flowing mane filament',[(x,-.25,z),(x*1.07,-.3,z*1.08),(x*1.17,-.22,z*1.23)],.007,random.choice(manemats),head)
sphere('Sculpted face',(0,-.34,.12),(.44,.39,.47),fur,head)
for side in [-1,1]:
 sphere('Ear',(side*.42,.015,.62),(.16,.095,.17),fur,head)
 sphere('Ear inner',(side*.42,-.065,.62),(.105,.035,.115),manemats[1],head)
 sphere('Cheek',(side*.31,-.48,-.045),(.16,.23,.25),lightfur,head)
 sphere('Brow ridge',(side*.23,-.62,.37),(.2,.09,.09),fur,head)
 sphere('Amber iris',(side*.226,-.69,.275),(.082,.045,.07),eye,head)
 sphere('Vertical pupil',(side*.226,-.727,.275),(.022,.014,.054),black,head)
 sphere('Catchlight',(side*.20,-.741,.3),(.013,.008,.013),glint,head)
 sphere('Muzzle pad',(side*.145,-.68,-.065),(.19,.17,.16),cream,head)
 for j in range(4):
  z=-.035-j*.041
  curve('Whisker',[(side*.19,-.79,z),(side*.43,-.84,z+.02),(side*(.6+j*.025),-.80,z+.04)],.0035,cream,head)
# Wedge nose, chin hinge and visible teeth.
verts=[(-.13,-.83,.045),(.13,-.83,.045),(0,-.875,-.06),(-.1,-.75,.08),(.1,-.75,.08)]
mesh=bpy.data.meshes.new('Nose mesh');mesh.from_pydata(verts,[],[(0,1,2),(0,3,4,1),(3,0,2),(4,2,1),(3,2,4)])
o=bpy.data.objects.new('Lion nose',mesh);bpy.context.collection.objects.link(o);o.parent=head;o.data.materials.append(black)
mouth=sphere('Roaring mouth',(0,-.56,-.2),(.27,.18,.22),mouthmat,head)
jaw=empty('Jaw hinge',(0,-.48,-.18),head)
sphere('Lower chin',(0,-.18,-.08),(.24,.24,.12),cream,jaw)
sphere('Tongue',(0,-.2,.015),(.13,.16,.035),tongue,jaw)
for side in [-1,1]:
 cone('Upper canine fang',(side*.17,-.69,-.22),0,.22,tooth,head,tip=.045)
 cone('Lower canine',(side*.17,-.23,.07),.035,.13,tooth,jaw,tip=0)
for x in [-.10,-.05,0,.05,.1]:
 cone('Small lower tooth',(x,-.35,.04),.018,.055,tooth,jaw)
# Four articulated running legs and distinct paws.
legs=[]
for front in [True,False]:
 for side in [-1,1]:
  y=-.61 if front else .73
  leg=empty(('Front' if front else 'Rear')+' leg',(side*.34,y,1.33),root);legs.append((leg,front,side))
  sphere('Upper leg',(0,0,-.28),(.17,.2,.4),fur,leg)
  sphere('Lower leg',(0,-.025,-.73),(.105,.115,.3),fur,leg)
  sphere('Broad paw',(0,-.12,-1.0),(.18,.26,.13),lightfur,leg)
  for toe in [-.1,0,.1]:sphere('Paw toe',(toe,-.27,-1.01),(.055,.105,.075),lightfur,leg,16)
tail=empty('Tail sweep',(0,1.0,1.33),root)
curve('Long lion tail',[(0,0,0),(0,.4,.14),(.1,.85,.26),(.25,1.3,.43)],.052,fur,tail)
sphere('Tail tuft',(.25,1.3,.43),(.12,.2,.14),manemats[1],tail)
# Rainforest floor, rocks, trunks and layered fern silhouettes.
bpy.ops.mesh.primitive_plane_add(size=80);bpy.context.object.data.materials.append(ground)
for i in range(25):
 x=random.choice([-1,1])*random.uniform(2.2,7);y=random.uniform(-8,17);h=random.uniform(5,10)
 cone('Rainforest trunk',(x,y,h/2),random.uniform(.18,.38),h,bark,tip=.12)
 for j in range(3):sphere('Canopy',(x+random.uniform(-1.4,1.4),y+random.uniform(-1.2,1.2),h), (2.1,1.9,1.3),random.choice(leafmats),segments=12)
for i in range(44):
 x=random.choice([-1,1])*random.uniform(1.4,5.2);y=random.uniform(-5,14)
 if i<15:sphere('Moss rock',(x,y,.12),(random.uniform(.2,.6),.4,.25),rockmat,segments=12)
 fern=empty('Fern',(x,y,0))
 for j in range(7):
  a=j*math.tau/7+random.random()*.3;l=random.uniform(.5,1.3);end=(math.cos(a)*l,math.sin(a)*l,.25+l*.3)
  curve('Fern stem',[(0,0,0),(end[0]*.55,end[1]*.55,.65*l),end],.012,leafmats[3],fern)
  for k in range(1,7):
   t=k/7;cx=end[0]*t;cy=end[1]*t;cz=math.sin(t*math.pi)*.5*l+.12;w=.18*(1-t)+.025
   for side in [-1,1]:
    v=[(cx,cy,cz),(cx+side*math.cos(a+math.pi/2)*w,cy+side*math.sin(a+math.pi/2)*w,cz+.07),(cx+end[0]*.09,cy+end[1]*.09,cz+.02)]
    me=bpy.data.meshes.new('Fern blade');me.from_pydata(v,[],[(0,1,2)]);ob=bpy.data.objects.new('Fern blade',me);bpy.context.collection.objects.link(ob);ob.parent=fern;ob.data.materials.append(random.choice(leafmats))
# Dust motes and floating gold fireflies.
firemat=mat('Golden motes',(1,.52,.06),.25,emission=3)
for i in range(42):sphere('Firefly',(random.uniform(-3,3),random.uniform(-3,8),random.uniform(.4,4)),(.009,.009,.009),firemat,segments=8)
def area(name,loc,power,color,size,target=(0,0,1)):
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Golden key',(3,-4,6),1800,(1,.72,.38),5)
area('Moon rim',(-4,2,5),2600,(.2,.68,1),4)
area('Warm canopy light',(1,5,8),2200,(1,.8,.44),4)
area('Face fill',(-1,-5,3),400,(.65,.8,1),3)
bpy.ops.object.camera_add(location=(3,-7,3));cam=bpy.context.object;s.camera=cam;cam.data.lens=43
cam.data.dof.use_dof=True;cam.data.dof.focus_object=head;cam.data.dof.aperture_fstop=4
# Frame-by-frame authored motion: run, settle, lift head, roar, close jaw.
for f in range(1,169):
 t=(f-1)/24;run=max(0,1-min(max((t-2.6)/.8,0),1));travel=max(0,4.7*(1-min(t/3.4,1))**1.6)
 root.location=(0,travel,-.18+.07*math.sin(t*17)*run);root.rotation_euler.z=.018*math.sin(t*8)*run
 root.keyframe_insert('location',frame=f);root.keyframe_insert('rotation_euler',frame=f)
 for leg,front,side in legs:
  phase=t*15+(0 if front else math.pi)+(0 if side==1 else math.pi)
  leg.rotation_euler.x=.65*math.sin(phase)*run;leg.keyframe_insert('rotation_euler',frame=f)
 roar=max(0,math.sin(min(max((t-3.6)/2.5,0),1)*math.pi))
 jaw.rotation_euler.x=roar*.9;jaw.keyframe_insert('rotation_euler',frame=f)
 mouth.scale.z=.09+roar*.20;mouth.keyframe_insert('scale',frame=f)
 head.rotation_euler.x=-.12*roar+.035*math.sin(t*12)*run;head.rotation_euler.z=-.08*roar;head.keyframe_insert('rotation_euler',frame=f)
 tail.rotation_euler.z=.2*math.sin(t*5);tail.keyframe_insert('rotation_euler',frame=f)
 # A tracking three-quarter shot becomes a frontal portrait for the roar.
 blend=min(max((t-2.7)/1.2,0),1);dodge=1.35*math.sin(math.pi*(t-1)/1.8)**2 if 1<t<2.8 else 0;cam.location=(2.7*(1-blend)+.2*blend-dodge,travel-6.1,2.5+.15*blend)
 target=Vector((0,travel-.3,1.35+roar*.23));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
# Save the scene for reproducibility; previews and frames are outside the repo.
bpy.ops.wm.save_as_mainfile(filepath=str(out/'pulse_lion_scene.blend'))
if len(args)>1 and args[1]=='preview':
 s.frame_set(112);s.render.filepath=str(out/'preview.png');bpy.ops.render.render(write_still=True)
elif len(args)>1 and args[1]=='repair':
 s.frame_start=25;s.frame_end=68;bpy.ops.render.render(animation=True)
else:bpy.ops.render.render(animation=True)
