shader_type spatial;
uniform float max_quality = 1.0;
uniform vec2 wave_origin;
uniform vec4 wave_color : source_color = vec4(.4,.8,1.0,1.0);
uniform float wave_radius = -20.0;
uniform float wave_strength = 0.0;
varying vec3 wp;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float line(float d,float width){return 1.0-smoothstep(width,width+max(fwidth(d),.02),abs(d));}
float inset(float d){return 1.0-smoothstep(-max(fwidth(d),.025),max(fwidth(d),.025),d);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec2 p=wp.xz,q=abs(p);
 float row=floor(p.y/10.0);
 vec2 grid=vec2(p.x/14.0+mod(row,2.0)*.5,p.y/10.0);
 vec2 joint=abs(fract(grid)-.5);
 float grout=line(max(joint.x,joint.y)-.5,.008);
 float block=hash(floor(grid));
 float grain=noise(p*.6)*.06+noise(p*2.7)*.025;
 vec3 pale=mix(vec3(.46,.46,.38),vec3(.64,.63,.53),block*.6+grain);
 vec3 slate=mix(vec3(.16,.25,.25),vec3(.30,.37,.34),block*.7+grain);
 float border=max(max(q.x-90.0,q.y-76.0),q.x+q.y-139.0);
 vec3 color=mix(pale,slate,smoothstep(-.3,.3,border));
 float r=length(p);
 float angle=atan(p.y,p.x);
 // Fitted sea-green stone, rather than luminous paint, anchors the open stage.
 // Its segmented navigation band stays outside the six playable gate positions.
 float ring_band=inset(abs(r-60.1)-4.2);
 float segment=floor((angle+3.141593)/.1308997);
 vec3 ring_stone=mix(vec3(.15,.255,.25),vec3(.255,.34,.31),hash(vec2(segment,4.0))*.6+grain);
 float radial_joint=line(sin(angle*24.0)*r,.09);
 ring_stone*=1.0-radial_joint*.25;
 color=mix(color,ring_stone,ring_band);
 vec3 brass=vec3(.45,.39,.245);
 float ring=max(line(r-55.7,.15),line(r-64.7,.23));
 float graduation=line(sin(angle*24.0)*r,.16)*inset(abs(r-62.7)-1.25);
 float major=line(sin(angle*4.0)*r,.31)*inset(abs(r-60.1)-3.6);
 color=mix(color,brass,clamp(ring+graduation+major,0.0,1.0)*.9);
 // A small two-tone stone compass is readable from the normal tactical camera.
 // Eight tapered blades have different cardinal/intercardinal lengths.
 float compass=0.0;
 float compass_half=0.0;
 for(int i=0;i<8;i++){
  float a=float(i)*.78539816;
  vec2 v=vec2(p.x*cos(a)-p.y*sin(a),p.x*sin(a)+p.y*cos(a));
  float reach=mod(float(i),2.0)<.5?15.0:10.2;
  float d=max(abs(v.x)-(reach-v.y)*.19,max(-v.y,v.y-reach));
  float blade=inset(d);
  compass=max(compass,blade);
  compass_half=max(compass_half,blade*inset(v.x));
 }
 color=mix(color,vec3(.20,.31,.30),compass*.88);
 color=mix(color,vec3(.40,.43,.34),compass_half*.85);
 color=mix(color,brass,max(line(r-16.6,.16),line(r-2.0,.22))*.8);
 float edge=max(q.x,q.y)-140.0;
 float trim=max(max(line(border,.30),line(border+2.1,.17)),max(line(edge+4.0,.32),line(edge+6.0,.18)));
 color*=1.0-grout*.22;
 color=mix(color,vec3(.24,.30,.27),line(r-68.5,.12)*.45);
 color=mix(color,brass,trim*.72);
 float wave=exp(-pow((length(p-wave_origin)-wave_radius)/2.6,2.0))*wave_strength;
 ALBEDO=mix(color,wave_color.rgb,wave*.48);
 EMISSION=wave_color.rgb*wave*.64;
 ROUGHNESS=.91+noise(p*3.0)*.06;SPECULAR=.24;
 NORMAL_MAP=vec3(.5+(noise(p*3.0)-.5)*.08,.5+(noise(p*3.0+vec2(.3))-.5)*.08,1.0);
 NORMAL_MAP_DEPTH=.22;
}
