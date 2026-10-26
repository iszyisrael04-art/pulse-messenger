"""Pulse's original gift stories, rendered in Blender 4.5 LTS.
blender -b --threads 3 --python scripts/render_cinema_gifts.py -- SKU OUT [preview]
Downloaded CC0 source models stay editable under art/gift_sources. Cameras,
lighting, environments, staging, extra rigs and stories are original Pulse work.
No TikTok clips, logos, models or audio are included.
"""
import bpy, math, random, sys
from mathutils import Vector, Matrix
from pathlib import Path
random.seed(451)
args=sys.argv[sys.argv.index('--')+1:];sku=args[0];out=Path(args[1]);out.mkdir(parents=True,exist_ok=True)
repo=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=4;s.cycles.use_denoising=True
s.cycles.max_bounces=3;s.cycles.diffuse_bounces=1;s.cycles.glossy_bounces=2
s.render.resolution_x=360;s.render.resolution_y=640;s.render.resolution_percentage=100
s.render.fps=18;s.frame_start=1;s.frame_end=108;s.render.image_settings.file_format='PNG'
s.render.filepath=str(out/'frame_');s.world.use_nodes=True
s.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.012,.018,.045,1)
s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.22
s.view_settings.view_transform='AgX'
s.use_nodes=True;ns=s.node_tree.nodes;ns.clear();rl=ns.new('CompositorNodeRLayers');gl=ns.new('CompositorNodeGlare');gl.glare_type='FOG_GLOW';gl.threshold=1.8;gl.quality='MEDIUM';co=ns.new('CompositorNodeComposite');s.node_tree.links.new(rl.outputs['Image'],gl.inputs['Image']);s.node_tree.links.new(gl.outputs['Image'],co.inputs['Image'])
def mat(name,c,metal=0,rough=.4,glow=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if glow:p.inputs['Emission Color'].default_value=(*c,1);p.inputs['Emission Strength'].default_value=glow
 return m
gold=mat('Champagne gold',(.83,.49,.09),.85,.23);black=mat('Graphite',(.012,.018,.03),.5,.28);white=mat('Pearl ceramic',(.76,.83,.91),.35,.24);cyan=mat('Pulse cyan',(.025,.66,.87),.4,.22,2);purple=mat('Pulse violet',(.32,.025,.8),.35,.2,2);fire=mat('Solar fire',(1,.16,.012),.2,.28,4);starlight=mat('Starlight',(.4,.7,1),.1,.3,5)
def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o
def sphere(name,loc,scale,m,parent=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12);o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=scale;o.data.materials.append(m)
 for f in o.data.polygons:f.use_smooth=True
 return o
def cube(name,loc,scale,m,parent=None,bevel=.08):
 bpy.ops.mesh.primitive_cube_add();o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
 if bevel:mod=o.modifiers.new('Soft manufactured edges','BEVEL');mod.width=bevel;mod.segments=3;o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
 return o
def line(name,points,r,m,parent=None):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=2;sp=c.splines.new('POLY');sp.points.add(len(points)-1)
 for p,co in zip(sp.points,points):p.co=(*co,1)
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.parent=parent;o.data.materials.append(m);return o
def torus(name,loc,major,minor,m,parent=None,rot=(0,0,0)):
 bpy.ops.mesh.primitive_torus_add(major_segments=56,minor_segments=10,major_radius=major,minor_radius=minor);o=bpy.context.object;o.name=name;o.location=loc;o.parent=parent;o.rotation_euler=rot;o.data.materials.append(m);return o
def text(body,loc,size,m,parent=None):
 c=bpy.data.curves.new(body,'FONT');c.body=body;c.align_x='CENTER';c.size=size;c.extrude=.035;c.bevel_depth=.012;c.bevel_resolution=3;o=bpy.data.objects.new(body,c);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;o.rotation_euler=(math.pi/2,0,0);o.data.materials.append(m);return o
def area(name,loc,power,c,size=5,target=(0,0,1.4)):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=c;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm key',(3,-5,6),1600,(1,.72,.4));area('Cool rim',(-4,2,5),2200,(.18,.55,1));area('Face fill',(-1,-6,3),500,(.6,.8,1))
bpy.ops.object.camera_add(location=(5,-10,4.2));cam=bpy.context.object;s.camera=cam;cam.data.lens=42
cam.data.dof.use_dof=False

def point_camera(loc,target):cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
def starfield():
 for i in range(85):sphere('Distant star',(random.uniform(-11,11),random.uniform(2,10),random.uniform(-1,13)),(.012,)*3,starlight)
def ground(m=black):
 bpy.ops.mesh.primitive_plane_add(size=120);bpy.context.object.data.materials.append(m)
def imported(name,height):
 before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(repo/'art/gift_sources'/f'{name}.glb'))
 objs=set(bpy.context.scene.objects)-before
 # The CC0 rig templates include an unrelated reference sphere, not character geometry.
 for o in list(objs):
  if o.type=='MESH' and name in ['dragon','bird'] and not any(x.type=='ARMATURE' for x in o.modifiers):objs.remove(o);bpy.data.objects.remove(o,do_unlink=True)
 root=empty(name+' cinematic travel')
 for o in objs:
  if o.parent not in objs:
   world=o.matrix_world.copy();o.parent=root;o.matrix_world=world
 bpy.context.view_layer.update();points=[o.matrix_world@Vector(v) for o in objs if o.type=='MESH' for v in o.bound_box]
 low=Vector(tuple(min(p[i] for p in points) for i in range(3)));high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
 factor=height/(high.z-low.z);root.scale=(factor,)*3;root.location=(-((low.x+high.x)/2)*factor,-((low.y+high.y)/2)*factor,-low.z*factor)
 base=root.location.copy();arm=next((o for o in objs if o.type=='ARMATURE'),None)
 if arm:
  arm.animation_data_clear();arm.animation_data_create()
 for o in objs:
  if o.type=='MESH':
   for p in o.data.polygons:p.use_smooth=True
 return root,base,arm,objs

def jungle():
 ground(mat('Forest moss',(.018,.055,.025),rough=.85))
 bark=mat('Bark',(.065,.035,.015),rough=.85);leaf=mat('Jade leaves',(.018,.16,.055),rough=.5)
 for i in range(24):
  x=random.choice([-1,1])*random.uniform(2.5,7);y=random.uniform(-2,15);h=random.uniform(5,10)
  cube('Tree trunk',(x,y,h/2),(.13,.15,h/2),bark,bevel=.12)
  sphere('Canopy',(x,y,h),(2.3,2,1.2),leaf)
  for j in range(4):
   a=j*math.tau/4
   o=sphere('Broad tropical leaf',(x+math.cos(a),y+math.sin(a),.4),(.8,.15,.04),leaf);o.rotation_euler.z=a
 for i in range(28):sphere('Jungle dust',(random.uniform(-3,3),random.uniform(-2,6),random.uniform(.3,4)),(.014,)*3,gold)

# Authored armatures drive rigid detailed parts. These are editable bones, not
# an animation baked into a 2D screenshot. Skinned imported rigs keep weights.
def make_rig(name):
 root=empty(name+' travel');a=bpy.data.armatures.new(name+' skeleton');o=bpy.data.objects.new(name+' armature',a);bpy.context.collection.objects.link(o);o.parent=root;bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 bones={}
 def bone(n,h,t,parent=None):
  b=a.edit_bones.new(n);b.head=h;b.tail=t
  if parent:b.parent=a.edit_bones[parent]
  bones[n]=tuple(h);return b
 bone('body',(0,0,0),(0,0,1));bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
 return root,o,bones

def add_bone(arm,bones,n,h,t,parent='body'):
 bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT');b=arm.data.edit_bones.new(n);b.head=h;b.tail=t;b.parent=arm.data.edit_bones[parent];bones[n]=h;bpy.ops.object.mode_set(mode='OBJECT');arm.select_set(False)
def attach(obj,arm,bone):
 # One rigid weight per part keeps faces/jewelry crisp while joints articulate.
 vg=obj.vertex_groups.new(name=bone);vg.add(list(range(len(obj.data.vertices))),1,'REPLACE');mod=obj.modifiers.new('Gift bone skin','ARMATURE');mod.object=arm;obj.parent=arm

# Downloaded detailed CC0 wildlife has no skeleton: bake scene transforms, then
# add named head/jaw/limb bones and region weights in normalized world space.
def wildlife(model,height):
 old,base,_,objs=imported(model,height)
 old.rotation_euler.z=math.pi if model=='astronaut' else -math.pi/2
 bpy.context.view_layer.update()
 pts=[o.matrix_world@Vector(v) for o in objs if o.type=='MESH' for v in o.bound_box]
 low=Vector(tuple(min(p[i] for p in pts) for i in range(3)));high=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
 old.location-=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z));bpy.context.view_layer.update()
 baked=[]
 for ob in objs:
  if ob.type!='MESH':continue
  world=ob.matrix_world.copy();ob.data=ob.data.copy();ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.data.transform(world);baked.append(ob)
 root,arm,bones=make_rig(model+' articulated')
 if model=='astronaut':
  add_bone(arm,bones,'head',(0,0,height*.78),(0,0,height*.98))
  for side in [-1,1]:
   add_bone(arm,bones,f'arm{side}',(side*height*.2,0,height*.7),(side*height*.4,0,height*.5))
   add_bone(arm,bones,f'leg{side}',(side*height*.1,0,height*.44),(side*height*.1,0,height*.05))
 elif model=='gorilla':
  add_bone(arm,bones,'head',(0,-.42,height*.72),(0,-.46,height*.95))
  for side in [-1,1]:
   add_bone(arm,bones,f'arm{side}',(side*height*.24,-.04,height*.72),(side*height*.34,-.15,height*.48))
   add_bone(arm,bones,f'forearm{side}',(side*height*.34,-.15,height*.48),(side*height*.35,-.25,height*.14),f'arm{side}')
   add_bone(arm,bones,f'leg{side}',(side*height*.12,.15,height*.40),(side*height*.15,.05,height*.05))
 else:
  add_bone(arm,bones,'head',(0,-height*.48,height*.70),(0,-height*.7,height*.96))
  for side in [-1,1]:
   for front in [True,False]:
    y=-height*.30 if front else height*.37
    add_bone(arm,bones,f'leg{side}{front}',(side*height*.17,y,height*.53),(side*height*.17,y,height*.06))
 add_bone(arm,bones,'jaw',(0,-height*.61,height*.75),(0,-height*.69,height*.68),'head')
 for ob in baked:
  for m in ob.data.materials:
   if m and m.use_nodes:
    p=m.node_tree.nodes.get('Principled BSDF')
    if p:
     noise=m.node_tree.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=90;noise.inputs['Detail'].default_value=3
     bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.35;bump.inputs['Distance'].default_value=.012;m.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],p.inputs['Normal']);p.inputs['Roughness'].default_value=.74
  groups={n:ob.vertex_groups.new(name=n) for n in bones}
  n=ob.name.lower()
  for v in ob.data.vertices:
   x,y,z=v.co;side=1 if x>=0 else -1
   smooth=lambda a:max(0,min(1,a))**2*(3-2*max(0,min(1,a)))
   weights={}
   if model=='gorilla':
    head=smooth((z/height-.66)/.19)*smooth((.20-y/height)/.25)
    armw=(1-head)*smooth((abs(x)/height-.20)/.15)
    lower=smooth((.62-z/height)/.25)
    legw=(1-head-armw)*smooth((.44-z/height)/.25)*smooth((abs(x)/height-.04)/.10)
    weights={'head':head,f'arm{side}':armw*(1-lower),f'forearm{side}':armw*lower,f'leg{side}':legw}
   elif model=='astronaut':
    head=smooth((z/height-.72)/.15)
    armw=(1-head)*smooth((abs(x)/height-.16)/.15)
    legw=(1-head-armw)*smooth((.45-z/height)/.20)
    weights={'head':head,f'arm{side}':armw,f'leg{side}':legw}
   else:
    head=smooth((-.26-y/height)/.30)*smooth((z/height-.47)/.19)
    legw=(1-head)*smooth((.57-z/height)/.31)*smooth((abs(x)/height-.05)/.13)
    front=smooth((.12-y/height)/.28)
    weights={'head':head,f'leg{side}True':legw*front,f'leg{side}False':legw*(1-front)}
   weights['body']=max(0,1-sum(weights.values()))
   if any(term in n for term in ['lower lip','jaw and chin','lower jaw']):weights={'jaw':1}
   for bone,w in weights.items():
    if w>.0001:groups[bone].add([v.index],w,'REPLACE')
  mod=ob.modifiers.new('Pulse articulated gift skeleton','ARMATURE');mod.object=arm;ob.parent=arm
 bpy.data.objects.remove(old,do_unlink=True)
 return root,arm

models=[];fx=[];rigs=[];base=None
if sku in ['dragon','phoenix','thunder_falcon']:
 root,base,arm,objs=imported('dragon' if sku=='dragon' else 'bird',2.8 if sku=='dragon' else 2.4)
 anim='Fly Flap' if sku=='dragon' else 'Flap';action=next((a for a in bpy.data.actions if a.name==anim),None)
 if action is None:action=next(iter(bpy.data.actions),None)
 if action:arm.animation_data.action=action
 # Make the template's surface tangible under cinematic lights.
 for ob in objs:
  if ob.type=='MESH':
   for m in ob.data.materials:
    if m and m.use_nodes:
     p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Metallic'].default_value=.22;p.inputs['Roughness'].default_value=.36
 if sku in ['phoenix','thunder_falcon']:
  plumage=mat('Phoenix amber feathers' if sku=='phoenix' else 'Storm silver feathers',
    (.8,.22,.015) if sku=='phoenix' else (.18,.38,.65), .45,.3,.15)
  p=plumage.node_tree.nodes.get('Principled BSDF');n=plumage.node_tree.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=45
  bump=plumage.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.3;bump.inputs['Distance'].default_value=.025;plumage.node_tree.links.new(n.outputs['Fac'],bump.inputs['Height']);plumage.node_tree.links.new(bump.outputs['Normal'],p.inputs['Normal'])
  for ob in objs:
   if ob.type=='MESH':ob.data.materials.clear();ob.data.materials.append(plumage)
 if sku=='dragon':
  ground(mat('Obsidian lava',(.025,.012,.009),.25,.4))
  for i in range(14):
   y=random.uniform(-2,12);x=random.choice([-1,1])*random.uniform(1.5,5)
   sphere('Volcanic spire',(x,y,.9),(.7,.7,2),black)
   line('Lava seam',[(x,y,.02),(x+.4,y+1,.02),(x-.3,y+2,.02)],.04,fire)
 else:
  starfield()
  torus('Celestial flight portal',(0,1,2.6),2.5,.045,fire if sku=='phoenix' else cyan,rot=(math.pi/2,0,0))
 for i in range(24):
  ob=sphere('Ember' if sku=='phoenix' else 'Atmosphere spark',(random.uniform(-3,3),random.uniform(-2,4),random.uniform(.3,6)),(.025,)*3,fire if sku!='thunder_falcon' else cyan);fx.append(ob)
elif sku=='sports_car':
 root,base,arm,objs=imported('car',1.4);root.rotation_euler.z=-math.pi/2;ground()
 for ob in objs:
  if ob.type=='MESH':
   for m in ob.data.materials:
    if m and m.use_nodes:
     p=m.node_tree.nodes.get('Principled BSDF')
     if p:p.inputs['Metallic'].default_value=.8;p.inputs['Roughness'].default_value=.22
 for side in [-1,1]:
  line('Neon road',[(side*1.7,-30,.03),(side*1.7,30,.03)],.035,cyan)
  for i in range(16):cube('City tower',(side*random.uniform(4,8),i*2-5,random.uniform(1,4)),(.4,.6,random.uniform(2,6)),black)
 for y in range(-25,30,2):cube('Road mark',(0,y,.015),(.035,.5,.015),white,bevel=0)
 # Body panel accent follows the car travel rig, without third-party branding.
 for ob in objs:
  if ob.type=='MESH':
   for m in ob.data.materials:
    if 'paint' in m.name.lower() or 'body' in m.name.lower():
     p=m.node_tree.nodes.get('Principled BSDF')
     for link in list(p.inputs['Base Color'].links):m.node_tree.links.remove(link)
     p.inputs['Base Color'].default_value=(.9,.55,.08,1)
 models=[root]
elif sku in ['gorilla','lion','royal_lions','pulse_stars']:
 jungle()
 if sku=='gorilla':root,arm=wildlife('gorilla',2.9);rigs=[arm]
 else:
  root,arm=wildlife('lion',2.3);rigs=[arm]
  if sku in ['royal_lions','pulse_stars']:
   cub,ca=wildlife('gorilla' if sku=='pulse_stars' else 'lion',2.3);cub.scale=((.75,)*3 if sku=='pulse_stars' else (.5,)*3);cub.location=(-1.5,-.25,0);models.append(cub);rigs.append(ca)
   crown=empty('Royal crown',(0,-1.35,2.25),root)
   torus('Gold crown',(0,0,0),.30,.05,gold,crown)
   for i in range(7):sphere('Royal ruby',(.28*math.cos(i*math.tau/7),.28*math.sin(i*math.tau/7),.20),(.07,.07,.13),purple,crown)
 if sku=='pulse_stars':
  text('PULSE STARS',(0,.4,3.3),.38,gold)
  for i in range(18):fx.append(sphere('Star fountain',(random.uniform(-2,2),random.uniform(-1,2),random.uniform(.2,3.8)),(.035,)*3,starlight))
elif sku in ['dream','galaxy']:
 starfield();earth=mat('Ocean sapphire',(.014,.095,.32),.45,.24)
 planet=sphere('Blue world',(0,3,1.2),(2.4,)*3,earth)
 # Authored land masses and rings give depth and changing parallax.
 for i in range(20):
  a=random.uniform(0,math.tau);z=random.uniform(-.9,.9);r=math.sqrt(1-z*z)*2.4
  sphere('Continents',(r*math.cos(a),3+r*math.sin(a),1.2+2.4*z),(.20,.12,.07),mat('Land'+str(i),(.04,.20,.15),.2,.55))
 torus('Orbital light',(0,3,1.2),3.0,.035,cyan,rot=(.35,.3,0))
 root=empty('Cosmic travel')
 if sku=='dream':
  astronaut,arm=wildlife('astronaut',2.4);astronaut.parent=root;astronaut.location=(0,-1.3,1)
  rigs=[arm];text('PULSE DREAM',(0,0,4.2),.34,white)
 else:
  # The existing galaxy SKU keeps its price/earnings, branded as Pulse Universe.
  text('PULSE',(0,-.5,3.35),.64,white,root);text('UNIVERSE',(0,-.55,2.8),.33,gold,root)
  emblem=sphere('Pulse portal',(0,-.1,1.6),(1.15,1.15,1.15),mat('Universe violet',(.14,.012,.4),.55,.18,.15),root)
  torus('Halo',(0,0,1.6),1.55,.04,gold,root,rot=(math.pi/2,.3,0))
  text('P',(0,-1.27,1.15),1.35,white,root)
  for i in range(5):
   orbit=empty('Planet orbit '+str(i));angle=i*math.tau/5
   sphere('Orbiting planet',(math.cos(angle)*2.5,math.sin(angle)*1.5+1,2+math.sin(angle)*.7),(.22+i*.04,)*3,gold if i%2 else cyan,orbit);models.append(orbit)
else:raise ValueError(sku)

breath=[];lightning=[]
if sku=='dragon':
 for i in range(14):
  ob=sphere('Dragon breath flame',(0,0,0),(.12+i*.015,.20,.12+i*.015),fire)
  ob.parent=arm;ob.parent_type='BONE';ob.parent_bone='mouth_upper_tip'
  ob.location=(math.sin(i*2)*.05,.12+i*.16,0);breath.append(ob)
if sku=='thunder_falcon':
 for side in [-1,1]:
  points=[(side*(1.9+random.uniform(-.3,.3)),1,z*.6) for z in range(10)]
  lightning.append(line('Storm lightning',points,.022,cyan))

for f in range(1,109):
 t=(f-1)/18;u=(f-1)/107
 for i,ob in enumerate(breath):
  k=max(0,math.sin(min(max((t-3)/2.5,0),1)*math.pi));ob.scale=(k*(.10+i*.013),k*.20,k*(.10+i*.013));ob.keyframe_insert('scale',frame=f)
 for ob in lightning:
  ob.hide_render=(f%14>3);ob.keyframe_insert('hide_render',frame=f)
 if sku in ['dragon','phoenix','thunder_falcon']:
  # Imported skeletal flight loops remain bound to their original weighted mesh.
  if action:
   # Keyed action frames already loop through an NLA strip with repeat.
   if f==1:
    arm.animation_data.action=None;track=arm.animation_data.nla_tracks.new();strip=track.strips.new('Wing beats',1,action);strip.repeat=20
  root.location=base+Vector((math.sin(t*.7)*.5,1.5-2.2*u,1.0+.22*math.sin(t*2)))
  root.rotation_euler.z=.15*math.sin(t*.8)
  root.keyframe_insert('location',frame=f);root.keyframe_insert('rotation_euler',frame=f)
  point_camera((5-3*u,-9+1.0*u,3.5),(0,0,2.4))
  for i,o in enumerate(fx):o.location.z=.2+(i*.29+t*.8)%5.5;o.keyframe_insert('location',frame=f)
 elif sku=='sports_car':
  root.location=base+Vector((0,-3*u,0));root.rotation_euler.z=-math.pi/2-.15+.5*u;root.keyframe_insert('location',frame=f);root.keyframe_insert('rotation_euler',frame=f)
  point_camera((5.5-2*u,-8-3*u,3.0-.8*u),(0,-3*u,.65))
 elif sku in ['gorilla','lion','royal_lions','pulse_stars']:
  moving=max(0,1-min(t/3,1));root.location=(0,3*(1-min(t/3,1)),0);root.keyframe_insert('location',frame=f)
  for a in rigs:
   for b in a.pose.bones:
    if b.name.startswith('leg'):b.rotation_mode='XYZ';b.rotation_euler.x=math.sin(t*8+(0 if '-1' in b.name else math.pi))*.35*moving;b.keyframe_insert('rotation_euler',frame=f)
    if b.name.startswith('arm') and sku=='gorilla':b.rotation_mode='XYZ';b.rotation_euler.y=math.sin(t*6)*.10*moving; b.rotation_euler.x=0; b.keyframe_insert('rotation_euler',frame=f)
    if b.name=='head':b.rotation_mode='XYZ';b.rotation_euler.x=-.12*math.sin(max(0,t-3));b.keyframe_insert('rotation_euler',frame=f)
    if b.name=='jaw':b.rotation_mode='XYZ';b.rotation_euler.x=max(0,math.sin(min(max((t-3.1)/2.5,0),1)*math.pi))*.25;b.keyframe_insert('rotation_euler',frame=f)
  blend=min(max((t-2.4)/3.3,0),1);point_camera((2.5*(1-blend)+.15*blend,-9+4.2*blend,3-.6*blend),(0,root.location.y-.45,1.7))
 elif sku in ['dream','galaxy']:
  root.rotation_euler.z=.05*math.sin(t);root.location.z=.12*math.sin(t*1.4);root.keyframe_insert('rotation_euler',frame=f);root.keyframe_insert('location',frame=f)
  for i,o in enumerate(models):o.rotation_euler.z=t*.2*(1 if i%2 else -1);o.keyframe_insert('rotation_euler',frame=f)
  if sku=='dream':
   for b in rigs[0].pose.bones:
    if b.name=='arm-1':b.rotation_mode='XYZ';b.rotation_euler.y=-.8-.25*math.sin(t*5);b.keyframe_insert('rotation_euler',frame=f)
  point_camera((3.4-2.8*u,-9.5+1.2*u,3.6),(0,.3,2.0))
# Save an editable master including armatures and named clips outside the app.
bpy.ops.wm.save_as_mainfile(filepath=str(out/(sku+'.blend')))
if len(args)>2 and args[2]=='preview':
 s.frame_set(76);s.render.filepath=str(out/'preview.png');bpy.ops.render.render(write_still=True)
else:bpy.ops.render.render(animation=True)
