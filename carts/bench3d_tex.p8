pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- 3d textured bench
-- by freds72

-- time
local time_t=0
-- globals
local cam_angle,cam_dist=0.45,7
local actors,cam,light={}
function nop() return true end

-- zbuffer (kind of)
local drawables
function zbuf_clear()
	drawables={}
end
function zbuf_draw()
	local objs={}
	for _,d in pairs(drawables) do
		local p=d.pos
		local x,y,z,w=cam:project(p[1],p[2],p[3])
		if z>0 then
			add(objs,{obj=d,key=z,x,y,z,w})
		end
	end
	-- z-sorting
	sort(objs)
	-- actual draw
	for i=1,#objs do
		local d=objs[i]
		d.obj:draw(d[1],d[2],d[3],d[4])
	end
end

function zbuf_filter(array)
	for _,a in pairs(array) do
		if not a:update() then
			del(array,a)
		else
			add(drawables,a)
		end
	end
end

function clone(src,dst)
	-- safety checks
	if(src==dst) assert()
	if(type(src)!="table") assert()
	dst=dst or {}
	for k,v in pairs(src) do
		if(not dst[k]) dst[k]=v
	end
	-- randomize selected values
	if src.rnd then
		for k,v in pairs(src.rnd) do
			-- don't overwrite values
			if not dst[k] then
				dst[k]=v[3] and rndarray(v) or rndlerp(v[1],v[2])
			end
		end
	end
	return dst
end

function lerp(a,b,t)
	return a*(1-t)+b*t
end
function rndlerp(a,b)
	return lerp(b,a,1-rnd())
end
function smoothstep(t)
	t=mid(t,0,1)
	return t*t*(3-2*t)
end
function rndrng(ab)
	return flr(rndlerp(ab[1],ab[2]))
end
function rndarray(a)
	return a[flr(rnd(#a))+1]
end

-- https://github.com/morgan3d/misc/tree/master/p8sort
function sort(data)
 for num_sorted=1,#data-1 do 
  local new_val=data[num_sorted+1]
  local new_val_key=new_val.key
  local i=num_sorted+1

  while i>1 and new_val_key>data[i-1].key do
   data[i]=data[i-1]   
   i-=1
  end
  data[i]=new_val
 end
end


function sqr_dist(a,b)
	local dx,dy,dz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
	if abs(dx)>128 or abs(dy)>128 or abs(dz)>128 then
		return 32000
	end

	return dx*dx+dy*dy+dz*dz
end

-- world axis
local v_fwd,v_right,v_up={0,0,1},{1,0,0},{0,1,0}

function v_clone(v)
	return {v[1],v[2],v[3]}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end
function v_normz(v)
	local d=v_dot(v,v)
	if d>0.001 then
		d=sqrt(d)
		v[1]/=d
		v[2]/=d
		v[3]/=d
	end
	return d
end

-- matrix functions
function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
end
-- 3x3 matrix mul (orientation only)
function o_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z,m[2]*x+m[6]*y+m[10]*z,m[3]*x+m[7]*y+m[11]*z
end
function m_x_xyz(m,x,y,z)
	return {
		m[1]*x+m[5]*y+m[9]*z+m[13],
		m[2]*x+m[6]*y+m[10]*z+m[14],
		m[3]*x+m[7]*y+m[11]*z+m[15]}
end
function make_m(v)
	return {
		1,0,0,v[1],
		0,1,0,v[2],
		0,0,1,v[3],
		0,0,0,1
	}
end

-- quaternion
function make_q(v,angle)
	angle/=2
	-- fix pico sin
	local s=-sin(angle)
	return {v[1]*s,
	        v[2]*s,
	        v[3]*s,
	        cos(angle)}
end
function q_clone(q)
	return {q[1],q[2],q[3],q[4]}
end
function m_from_q(q)
	local x,y,z,w=q[1],q[2],q[3],q[4]
	local x2,y2,z2=x+x,y+y,z+z
	local xx,xy,xz=x*x2,x*y2,x*z2
	local yy,yz,zz=y*y2,y*z2,z*z2
	local wx,wy,wz=w*x2,w*y2,w*z2

	return {
		1-(yy+zz),xy+wz,xz-wy,0,
		xy-wz,1-(xx+zz),yz+wx,0,
		xz+wy,yz-wx,1-(xx+yy),0,
		0,0,0,1
	}
end

function make_m(v,scale)
	return {
		1,0,0,scale*v[1],
		0,1,0,scale*v[2],
		0,0,1,scale*v[3],
		0,0,0,scale*1
	}
end
-- only invert 3x3 part
function m_inv(m)
	m[2],m[5]=m[5],m[2]
	m[3],m[9]=m[9],m[3]
	m[7],m[10]=m[10],m[7]
end
-- inline matrix invert
-- inc. position
function m_inv_x_v(m,v)
	local x,y,z=v[1]-m[13],v[2]-m[14],v[3]-m[15]
	v[1],v[2],v[3]=m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z
end
function m_set_pos(m,v)
	m[13],m[14],m[15]=v[1],v[2],v[3]
end
-- returns foward vector from matrix
function m_fwd(m)
	return {m[9],m[10],m[11]}
end
-- returns up vector from matrix
function m_up(m)
	return {m[5],m[6],m[7]}
end

function m_x_m(a,b)
 local a11,a12,a13,a14=a[1],a[5],a[9],a[13]
	local a21,a22,a23,a24=a[2],a[6],a[10],a[14]
	local a31,a32,a33,a34=a[3],a[7],a[11],a[15]
	local a41,a42,a43,a44=a[4],a[8],a[12],a[16]

 local b11,b12,b13,b14=b[1],b[5],b[9],b[13]
 local b21,b22,b23,b24=b[2],b[6],b[10],b[14]
	local b31,b32,b33,b34=b[3],b[7],b[11],b[15]
	local b41,b42,b43,b44=b[4],b[8],b[12],b[16]

 return {
		a11*b11+a12*b21+a13*b31+a14*b41,a21*b11+a22*b21+a23*b31+a24*b41,a31*b11+a32*b21+a33*b31+a34*b41,a41*b11+a42*b21+a43*b31+a44*b41,
		a11*b12+a12*b22+a13*b32+a14*b42,a21*b12+a22*b22+a23*b32+a24*b42,a31*b12+a32*b22+a33*b32+a34*b42,a41*b12+a42*b22+a43*b32+a44*b42,
		a11*b13+a12*b23+a13*b33+a14*b43,a21*b13+a22*b23+a23*b33+a24*b43,a31*b13+a32*b23+a33*b33+a34*b43,a41*b13+a42*b23+a43*b33+a44*b43,
		a11*b14+a12*b24+a13*b34+a14*b44,21*b14+a22*b24+a23*b34+a24*b44,a31*b14+a32*b24+a33*b34+a34*b44,a41*b14+a42*b24+a43*b34+a44*b44
  }
end

-- models
local all_models={
		["205gti"]={c=1}
	}

function draw_actor(self,x,y,z,w)
	-- distance culling
	if w>1 then
		draw_model(self.model,self.m,x,y,z,w)
	else
		circfill(x,y,1,self.model.c)
	end
end

local color_lo={1,1,13,6,7}
local color_hi={0x11,0xd0,0x60,0x70,0x70}
local dither_pat={0b1111111111111111,0b0111111111111111,0b0111111111011111,0b0101111111011111,0b0101111101011111,0b0101101101011111,0b0101101101011110,0b0101101001011110,0b0101101001011010,0b0001101001011010,0b0001101001001010,0b0000101001001010,0b0000101000001010,0b0000001000001010,0b0000001000001000,0b0000000000000000}

function draw_model(model,m,x,y,z,w)
	-- cam pos in object space
	local cam_pos=v_clone(cam.pos)
	m_inv_x_v(m,cam_pos)

	-- object to world
	-- world to cam
	-- inv cam
	local cam_m=m_x_m(cam.m,m)
	m_set_pos(cam_m,{0,-2,cam_dist-1})

	-- faces
	local faces,p={},{}
	for i=1,#model.f do
		local f,n=model.f[i],model.n[i]
		-- viz calculation
		local d=n[1]*cam_pos[1]+n[2]*cam_pos[2]+n[3]*cam_pos[3]
		if d>=model.cp[i] then
			-- project vertices
			for _,vi in pairs(f.vi) do
				if not p[vi] then
					local v=model.v[vi]
					local x,y,z=cam_m[1]*v[1]+cam_m[5]*v[2]+cam_m[9]*v[3]+cam_m[13],cam_m[2]*v[1]+cam_m[6]*v[2]+cam_m[10]*v[3]+cam_m[14],cam_m[3]*v[1]+cam_m[7]*v[2]+cam_m[11]*v[3]+cam_m[15]
				 local w=64/z
				 -- avoid rehash
					p[vi]={64+x*w,64-y*w,w,0,0}
				end
			end
			-- distance to camera (in object space)
			local d=sqr_dist(f.center,cam_pos)

			-- register faces
			add(faces,{key=d,face=f})
		end
	end
	-- sort faces
	sort(faces)

	-- draw faces using projected points
	for _,f in pairs(faces) do
		f=f.face
		local c=max(v_dot(model.n[f.ni],light.u))
		local p0,uv0=p[f.vi[1]],f.uv[1]
		p0[4],p0[5]=uv0[1],uv0[2]
		for i=2,#f.vi-1 do
	 		local p1,p2=p[f.vi[i]],p[f.vi[i+1]]
	 		local uv1,uv2=f.uv[i],f.uv[i+1]
			p1[4],p1[5]=uv1[1],uv1[2]
			p2[4],p2[5]=uv2[1],uv2[2]
	 		tritex(p0,p1,p2)
	 		--trifill(p0[1],p0[2],p1[1],p1[2],p2[1],p2[2],11)
		end
	end
end

local all_actors={
	car={
		model="205gti",
		update=nop}
	}

function make_npc(p,v,src)
	-- instance
	local a=clone(all_actors[src],{
		pos=v_clone(p),
		q=make_q(v,0),
		draw=draw_actor
	})
	a.model=all_models[a.model]

	-- init orientation
	local m=m_from_q(a.q)
	m_set_pos(m,p)
	a.m=m
	return add(actors,a)
end

function make_light_actor(r)
	local a={
		pos={r,0,0},
		u={-1,0,0},
		update=function(self)
			local t=time_t/128
			self.pos={
				r*cos(t),
				0,
				-r*sin(t)
			}
			self.u={
				cos(t),
				0,
				-sin(t)
			}
			return true
		end,
		draw=function(self,x,y,z,w)
			circfill(x,y,max(1,0.2*w),7)
		end
	}
	return add(actors,a)
end

function make_cam(f,x0,y0)
	x0,y0=x0 or 64,y0 or 64
	local c={
		pos={0,0,3},
		q=make_q(v_up,0),
		focal=f,
		update=function(self)
			self.m=m_from_q(self.q)
			m_inv(self.m)
			self.m=m_x_m(self.m,make_m(self.pos,-1))
		end,
		track=function(self,pos,q)
			self.pos=v_clone(pos)
			self.q=q
		end,
		project=function(self,x,y,z)
			-- world to view
			x-=self.pos[1]
			y-=self.pos[2]
			z-=self.pos[3]
			local v=m_x_xyz(self.m,x,y,z)
			-- distance to camera plane
			v[3]-=1
			if(v[3]<0.001) return nil,nil,-1,nil
			-- view to screen
 			local w=self.focal/v[3]
 			return x0+v[1]*w,y0-v[2]*w,v[3],w
		end
	}
	return c
end

local model_catalog={"205gti"}
local cur_model=1
local actor
function _update()
	time_t+=1
	
	zbuf_clear()

	actor.model=all_models[model_catalog[cur_model]]
	
	zbuf_filter(actors)
	
	-- move cam
	if(btn(0)) cam_angle+=0.01
	if(btn(1)) cam_angle-=0.01
	if(btn(2)) cam_dist+=0.1
	if(btn(3)) cam_dist-=0.1
	cam_dist=mid(cam_dist,2,32)
	
	local q=make_q(v_up,cam_angle)
	local m=m_from_q(q)
	cam:track(m_x_xyz(m,0,2,-cam_dist),q)
	cam:update()
end

function _draw()
	cls(0)

	zbuf_draw()

	if(draw_stats) draw_stats()
	
	print("⬇️⬆️: zoom / ⬅️➡️: rotate",16,120,14)
end


function _init()
	-- read models from map data
	unpack_models()
	
	cam=make_cam(64)
	
	light=make_light_actor(5)

	actor=make_npc({0,0,0},v_up,"car")
end

-->8
-- stats
local cpu_stats={}

function draw_stats()
	-- 
	fillp(0b1000100010001111)
	rectfill(0,0,127,9,0x10)
	fillp()
	local cpu,mem=flr(1000*stat(1))/10,flr(100*(stat(0)/2048))
	cpu_stats[time_t%128+1]={cpu,mem}
	for i=1,128 do
		local s=cpu_stats[(time_t+i)%128+1]
		if s then
			-- cpu
			local c,sy=11,s[1]
			if(sy>100) c=8 sy=100
			pset(i-1,9-9*sy/100,c)
		 -- mem
			c,sy=12,s[2]
			if(sy>90) c=8 sy=100
			pset(i-1,9-9*sy/100,c)
		end
	end
	if time_t%120>60 then
		print("cpu:"..cpu.."%",2,2,7)
	else
		print("mem:"..mem.."%",2,2,7)
	end
end

-->8
-- trifill by @p01
function p01_trapeze_h(l,r,lt,rt,y0,y1)
 lt,rt=(lt-l)/(y1-y0),(rt-r)/(y1-y0)
 if(y0<0)l,r,y0=l-y0*lt,r-y0*rt,0 
	y1=min(y1,128)
	for y0=y0,y1 do
  rectfill(l,y0,r,y0)
  l+=lt
  r+=rt
 end
end
function p01_trapeze_w(t,b,tt,bt,x0,x1)
 tt,bt=(tt-t)/(x1-x0),(bt-b)/(x1-x0)
 if(x0<0)t,b,x0=t-x0*tt,b-x0*bt,0 
 x1=min(x1,128)
 for x0=x0,x1 do
  rectfill(x0,t,x0,b)
  t+=tt
  b+=bt
 end
end
function trifill(x0,y0,x1,y1,x2,y2,col)
 color(col)
 if(y1<y0)x0,x1,y0,y1=x1,x0,y1,y0
 if(y2<y0)x0,x2,y0,y2=x2,x0,y2,y0
 if(y2<y1)x1,x2,y1,y2=x2,x1,y2,y1
 if max(x2,max(x1,x0))-min(x2,min(x1,x0)) > y2-y0 then
  col=x0+(x2-x0)/(y2-y0)*(y1-y0)
  p01_trapeze_h(x0,x0,x1,col,y0,y1)
  p01_trapeze_h(x1,col,x2,x2,y1,y2)
 else
  if(x1<x0)x0,x1,y0,y1=x1,x0,y1,y0
  if(x2<x0)x0,x2,y0,y2=x2,x0,y2,y0
  if(x2<x1)x1,x2,y1,y2=x2,x1,y2,y1
  col=y0+(y2-y0)/(x2-x0)*(x1-x0)
  p01_trapeze_w(y0,y0,y1,col,x0,x1)
  p01_trapeze_w(y1,col,y2,y2,x1,x2)
 end
end
-->8
-- unpack models
local mem=0x1000
function unpack_int()
	local i=peek(mem)
	mem+=1
	return i
end
function unpack_float(scale)
	local f=(unpack_int()-128)/32	
	return f*(scale or 1)
end
-- valid chars for model names
local itoa='_0123456789abcdefghijklmnopqrstuvwxyz'
function unpack_string()
	local s=""
	for i=1,unpack_int() do
		local c=unpack_int()
		s=s..sub(itoa,c,c)
	end
	return s
end
function unpack_models()
	-- for all models
	for m=1,unpack_int() do
		local model,name,scale={},unpack_string(),unpack_int()
		flip()
		-- vertices
		model.v={}
		for i=1,unpack_int() do
			add(model.v,{unpack_float(scale),unpack_float(scale),unpack_float(scale)})
		end
		
		-- faces
		model.f={}
		for i=1,unpack_int() do
			local f={ni=i,vi={},uv={}}
			-- vertex indices
			for i=1,unpack_int() do
				add(f.vi,unpack_int())
			end
			-- uv coords (if any)
			for i=1,unpack_int() do
				add(f.uv,{unpack_int(),unpack_int()})
			end
			-- center point
			f.center={unpack_float(scale),unpack_float(scale),unpack_float(scale)}
			add(model.f,f)
		end

		-- normals
		model.n={}
		for i=1,unpack_int() do
			add(model.n,{unpack_float(),unpack_float(),unpack_float()})
		end
		
		-- n.p cache	
		model.cp={}
		for i=1,#model.f do
			local f,n=model.f[i],model.n[i]
			add(model.cp,v_dot(n,model.v[f.vi[1]]))
		end

		-- merge with existing model
		all_models[name]=clone(model,all_models[name])
	end
end

-->8
-- tritex
function trapezefill(l,dl,r,dr,start,finish)
	local l,dl={l[1],l[4],l[5],r[1],r[4],r[5]},{dl[1],dl[4],dl[5],dr[1],dr[4],dr[5]}
	local dt=1/(finish-start)
	for k,v in pairs(dl) do
		dl[k]=(v-l[k])*dt
	end

	-- cliping
	if start<0 then
		for k,v in pairs(dl) do
			l[k]-=start*v
		end
		start=0
	end

	-- rasterization
	for j=start,min(finish,127) do
		--rectfill(l[1],j,r[1],j,11)
		local len=l[4]-l[1]
		if len>0 then
			local u0,v0=l[2],l[3]
			local du,dv=(l[5]-u0)/len,(l[6]-v0)/len
			for i=l[1],l[4] do
				local c=sget(u0,v0)
				if(c!=11) pset(i,j,c)
				u0+=du
				v0+=dv
			end
  end 
		for k,v in pairs(dl) do
			l[k]+=v
		end
	end
end
function tritex(v0,v1,v2)
	local x0,x1,x2=v0[1],v1[1],v2[1]
	local y0,y1,y2=v0[2],v1[2],v2[2]
if(y1<y0)v0,v1,x0,x1,y0,y1=v1,v0,x1,x0,y1,y0
if(y2<y0)v0,v2,x0,x2,y0,y2=v2,v0,x2,x0,y2,y0
if(y2<y1)v1,v2,x1,x2,y1,y2=v2,v1,x2,x1,y2,y1

	-- mid point
	local v02,mt={},1/(y2-y0)*(y1-y0)
	for k,v in pairs(v0) do
		v02[k]=v+(v2[k]-v)*mt
	end
	if(x1>v02[1])v1,v02=v02,v1

	-- upper trapeze
	-- x u v
	trapezefill(v0,v1,v0,v02,y0,y1)
	-- lower trapeze
	trapezefill(v1,v2,v02,v2,y1,y2)

end
__gfx__
bb88856599777777777777777777777777777777777777788756566bb00000000000000000000000000000000000000000000000000000000000000000000000
b888856599766666777777777711666667666677777777788756666bb00000000000000000000000000000000000000000000000000000000000000000000000
b8888565657666667777777777116666677777666666667aa756776bb00000000000000000000000000000000000000000000000000000000000000000000000
b8888565657666667777777777116666677777777777776aa756776bb00000000000000000000000000000000000000000000000000000000000000000000000
bb0555656586666677777777771166666777777e87667765a756776bb00000000000000000000000000000000000000000000000000000000000000000000000
bb0555656c8666667777777777116666657777e8877766656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb505565cc866666777777777711666665777780877777656756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb055565cc866666777777777711666665777787877777656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb505565ca7666667777777777116666657777e8877777656756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb056565aa76666677777777771166666577777e877777656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb566565a1766666777777777711666665777777777777765756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb506565117666667777777777116666657777777e8877567756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb566565117666667777777777116666657777e8888877656756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb05656518766666777777777711666665777788111177656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb5055658876666677777777771166666577778111aa77656756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb0555658578e666777777777711666665777781aacc77656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb50556565788e66777777777711666665777781acc777656756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb05556565780866777777777711666665777781ac7766656756556bb00000000000000000000000000000000000000000000000000000000000000000000000
bb05556565787866777777777711666667777781a7667765a756776bb00000000000000000000000000000000000000000000000000000000000000000000000
b888856565788e667777777777116666677777777777776aa756776bb00000000000000000000000000000000000000000000000000000000000000000000000
b88885656578e6667777777777116666677777666666667aa756776bb00000000000000000000000000000000000000000000000000000000000000000000000
b888856599766666777777777711666667666677777777788756666bb00000000000000000000000000000000000000000000000000000000000000000000000
bb88856599777777777777777777777777777777777777788756566bb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbb7777777777777777777777777bbbbbbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbb777777666666676666666666667bbbbbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbbb777887666666667666666666666676bbbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbb7778aa86666666676677777666666676bbbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbb77778aa866666666766766666666666676bbbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbb777777887666666667667777766666666676bbbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
bb77777777776666666676666666666666666776bbbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
b77777777777777777777777777777777777777777777777777bbbbbb00000000000000000000000000000000000000000000000000000000000000000000000
777888888888888888777777777777777777888888888888888777bbb00000000000000000000000000000000000000000000000000000000000000000000000
77888811111111111117777557555555557771111111111188887777700000000000000000000000000000000000000000000000000000000000000000000000
558881111aaaaaaaaaaa77755575755757777aaaaaaaa11118888788800000000000000000000000000000000000000000000000000000000000000000000000
86688111aaaccccc6656677575757575557777ccccccaa111188878a800000000000000000000000000000000000000000000000000000000000000000000000
86660055500ccccc66566777777777777777777cccccca0055500778700000000000000000000000000000000000000000000000000000000000000000000000
556055555550ccccc66566777777777777777777ccccc05555555077700000000000000000000000000000000000000000000000000000000000000000000000
6605555555550cccc66566777878777787877777cccc055555555505500000000000000000000000000000000000000000000000000000000000000000000000
6655555755555cccccccccc778888888878777777ccc555557555556600000000000000000000000000000000000000000000000000000000000000000000000
6655556665555cccccccccc777777777777777777ccc555566655556600000000000000000000000000000000000000000000000000000000000000000000000
6655576667555ccccccccccc777777777777777777cc555766675556500000000000000000000000000000000000000000000000000000000000000000000000
b655556665555ccccccccccc111111111111111111cc555566655556600000000000000000000000000000000000000000000000000000000000000000000000
bb55555755555cccccccccccc111111111111111111c555557555556600000000000000000000000000000000000000000000000000000000000000000000000
bbb555555555055555555555555555555555555555550555555555bbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbb5555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb5555555bbbb00000000000000000000000000000000000000000000000000000000000000000000000
bbbbb55555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb55555bbbbb00000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
206040207021f141100156f67456d874b9f674b9d87456f69956d899b9f699b9d89956f6fb5698fbb9f6fbb998fbb6b9e559b9e5b6b97859b978d04010206050
4000030002720272035607e74030402010400071a071a00000000874e7406080c0a04012001271e271e20008cab84030708040400003720372020002b907e740
90a0c0b0409300e200e271937108fbc7405060a09040720372029322930356cad7408070b0c0407202720393039322b9cad7401090b03040b1b282b282d2b1d2
0838f640d0e001f04011001171917191000837b940d02040e0401100a000a071117108354940e0408001409091000272020291891749408060f0014012711200
9100917108094940d0f06020409091029172020002861749d0060808080806080a380a080808080a0608080a0808080608080a0808b9f6e9c80808994926c808
b040207021f14110d0d0a132108056f674b9f674b9b97456b97456f6fbb9f6fbb9b9fb56b9fb60401040805000563858406070302000b9385840508070600008
fb584010506020000838f64040307080000838b9402030401000087458600608080a080808080a080608080a0808080600000000000000000000000000000000
__sfx__
00020000085500d650086500955009550086500955008550086500955008650085500865008550076500855008550076500855007650085500865008650075500765007650076500755008650096500855009550
010f00002c060350503b0403e0403365029060216501e0501665015040116400d0400b6300a030076300803007630060300463004030036300263002640016400164001640016300163001630016300163001620
000100003c5503755034550315502f5502b5502565024550206501f5301b620185201161010550096500655004650036500265004550036500b50008500065000350001500015000000000000000000000000000
00020000026500a650146501765019650196501765015650126500e6500d6500b6500a65007650036400565004650026500165001650016500165001650026500265002650036500365003650036500265002650
0004000032450334602c4603235033460333602e3502e3502b450343402d4302c320333203a3203d330363302033025330224302f4302e33021350243402644026330284202632035430203301c320364201b320
000200081f5501f5501f5501d5501b550195501c5500f5500f55032450344501445022450224502c4502c4502c4502c4502c4502c4502c4502b4502b4502b4502b4502b4502b4502b4502b450000000000000000
000200081b560160501f540120401f550140601e550180502325015040116400d0400b6300a030076300803007630060300463004030036300263002640016400164001640016300163001630016300163001620
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200081f6301f7301f6301e7301f6301f7301f630207301f2001f3001f2001e3001f2001f3001f200203001f2001f3001f2001e3001f2001f3001f200203000000000000000000000000000000000000000000
000200080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000

