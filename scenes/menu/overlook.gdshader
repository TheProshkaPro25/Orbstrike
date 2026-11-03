shader_type spatial;
render_mode diffuse_burley;
uniform float night = 0.0;
varying vec3 p;
varying flat float part;
varying flat float tone;
float hash(vec2 q) { return fract(sin(dot(q,vec2(12.9898,78.233)))*43758.5453); }
void vertex() { p=VERTEX; part=floor(COLOR.r*10.0+.5); tone=COLOR.g; }
void fragment() {
	vec3 stone=vec3(.40,.34,.25);
	vec2 grid=vec2(p.x+mod(floor(p.y/1.2),2.0)*1.6,p.y)/vec2(3.2,1.2);
	vec2 tile=p.xz/vec2(2.4,3.6);
	float floor_face=step(.5,NORMAL.y);
	vec2 coord=mix(grid,tile,floor_face);
	vec2 edge=min(fract(coord),1.0-fract(coord));
	vec2 aa=fwidth(coord);
	float joint=1.0-smoothstep(.012,.012+max(aa.x,aa.y),min(edge.x,edge.y));
	float grain=hash(floor(p.xz*90.0));
	vec3 col=stone*(.88+.2*hash(floor(coord)));
	col=mix(col,col*.62,joint*.65);
	float rough=.91;
	float metal=0.0;
	vec3 glow=vec3(0.0);
	if(part>0.5 && part<1.5) col=vec3(.53,.46,.35)*(.94+grain*.09)*(1.0-joint*.22);
	if(part>1.5 && part<2.5) { col=vec3(.14,.19,.18); rough=.42; metal=.7; }
	if(part>2.5 && part<3.5) {
		float wood=sin(p.x*7.0+sin(p.z*31.0)*.7)*.5+.5;
		col=mix(vec3(.20,.10,.045),vec3(.40,.23,.10),wood*.45+grain*.12); rough=.74;
	}
	if(part>3.5 && part<4.5) {
		vec3 color=vec3(.64,.25,.11);
		if(tone>.1) color=vec3(.18,.46,.39);
		if(tone>.3) color=vec3(.67,.53,.20);
		if(tone>.5) color=vec3(.38,.31,.22);
		if(tone>.7) color=vec3(.37,.23,.48);
		if(tone>.9) color=vec3(.15,.34,.53);
		col=color*(.9+grain*.15); rough=.63;
	}
	if(part>4.5 && part<5.5) { col=vec3(.83,.65,.38); glow=vec3(1.0,.59,.23)*night*2.2; rough=.4; }
	if(part>5.5) { col=mix(vec3(.06,.12,.05),vec3(.14,.22,.08),tone); rough=.94; }
	// Мягкая тёплая засветка камня возле фонарей, без новых Light3D.
	float lamp=max(exp(-distance(p.xz,vec2(27,-10))*.35),exp(-distance(p.xz,vec2(27,15))*.35));
	if(part<1.5) glow+=col*vec3(.40,.24,.10)*lamp*night;
	// Холодный рассеянный свет оставляет читаемыми мощение и дерево ночью.
	glow+=col*vec3(.028,.037,.060)*night;
	ALBEDO=col; ROUGHNESS=rough; METALLIC=metal; EMISSION=glow;
}
