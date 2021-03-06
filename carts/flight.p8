pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- airshow
-- by freds72
local good_side,bad_side,any_side=0x1,0x2,0x0
-- register json context here
local _tok={
 ['true']=true,
 ['false']=false}
function nop() end
local _g={
	good_side=good_side,
	bad_side=bad_side,
	any_side=any_side,
	nop=nop}

-- json parser
-- from: https://gist.github.com/tylerneylon/59f4bcf316be525b30ab
local table_delims={['{']="}",['[']="]"}
local function match(s,tokens)
	for i=1,#tokens do
		if(s==sub(tokens,i,i)) return true
	end
	return false
end
local function skip_delim(str,pos,delim,err_if_missing)
 if sub(str,pos,pos)!=delim then
  if(err_if_missing) assert('delimiter missing')
  return pos,false
 end
 return pos+1,true
end
local function parse_str_val(str,pos,val)
	val=val or ''
	if pos>#str then
		assert('end of input found while parsing string.')
	end
	local c=sub(str,pos,pos)
	if(c=='"') return _g[val] or val,pos+1
	return parse_str_val(str,pos+1,val..c)
end
local function parse_num_val(str,pos,val)
	val=val or ''
	if pos>#str then
		assert('end of input found while parsing string.')
	end
	local c=sub(str,pos,pos)
	-- support base 10,16 and 2 numbers
	if(not match(c,"-xb0123456789abcdef.")) return tonum(val),pos
	return parse_num_val(str,pos+1,val..c)
end
-- public values and functions.

function json_parse(str,pos,end_delim)
	pos=pos or 1
	if(pos>#str) assert('reached unexpected end of input.')
	local first=sub(str,pos,pos)
	if match(first,"{[") then
		local obj,key,delim_found={},true,true
		pos+=1
		while true do
			key,pos=json_parse(str,pos,table_delims[first])
			if(key==nil) return obj,pos
			if not delim_found then assert('comma missing between table items.') end
			if first=="{" then
				pos=skip_delim(str,pos,':',true)  -- true -> error if missing.
				obj[key],pos=json_parse(str,pos)
			else
				add(obj,key)
			end
			pos,delim_found=skip_delim(str,pos,',')
	end
	elseif first=='"' then
		-- parse a string (or a global object)
		return parse_str_val(str,pos+1)
	elseif match(first,"-0123456789") then
		-- parse a number.
		return parse_num_val(str,pos)
	elseif first==end_delim then  -- end of an object or array.
		return nil,pos+1
	else  -- parse true,false
		for lit_str,lit_val in pairs(_tok) do
			local lit_end=pos+#lit_str-1
			if sub(str,pos,lit_end)==lit_str then return lit_val,lit_end+1 end
		end
		assert('invalid json token')
	end
end

-- cloud generator
function noise_get(n,i,j)
	-- wrap around
	i%=128
	j%=128
	return n[i+128*j+1]>0.7 and 1 or 0
end
function noise_set(n,i,j)
	i,j=(i%128+128)%128,(j%128+128)%128
	n[i+j*128]+=0.5
end

function noise_flags(n,i,j)
	return
		bor(noise_get(n,i,j),
		bor(shl(noise_get(n,i+1,j),1),
		bor(shl(noise_get(n,i,j+1),2),
		shl(noise_get(n,i+1,j+1),3))))
end

function make_clouds()
	local noisemap={}
	for i=0,127 do
		for j=0,127 do
			add(noisemap,0)
		end
	end
  for n=1,16 do
  	local i0,j0=flr(rnd(128)),flr(rnd(128))
  	-- mixes multiple clouds into one
  	for k=1,1+rnd(3) do
  		i0+=flr(rnd(4)-2)
  		j0+=flr(rnd(4)-2)
  		-- todo adjust cloud style per level
	  	local sx,sy=24+8*flr(rnd(3)),0
	  	for i=i0,i0+15 do
	  		sy=0
	  		for j=j0,j0+15 do
	  			local s=sget(sx,7-sy)
	  			if s!=0 then
	  				noise_set(noisemap,j,i)
	  			end
	  			sy+=0.5
	  		end
	  		sx+=0.5
	  	end
	  end
  end
  
  local clouds={}
  for x=0,127 do
  	for y=0,127 do
  		add(clouds,noise_flags(noisemap,x,y))
  	end
 	end
 	return clouds
end

-- screen mgt
local cur_screen
--
local time_t,time_dt=0,0
local dither_pat=json_parse('[0b1111111111111111,0b0111111111111111,0b0111111111011111,0b0101111111011111,0b0101111101011111,0b0101101101011111,0b0101101101011110,0b0101101001011110,0b0101101001011010,0b0001101001011010,0b0001101001001010,0b0000101001001010,0b0000101000001010,0b0000001000001010,0b0000001000001000,0b0000000000000000]')

-- fog
-- local colors={0,13,6,7}
-- sunset
-- local colors={0,9,10,7}
-- sea
local colors={0,1,12,7}
-- night
-- local colors={0,1,5,7}

-- futures
function futures_update(futures)
	futures=futures or before_update
	for _,f in pairs(futures) do
		if not coresume(f) then
			del(futures,f)
		end
	end
end
function futures_add(fn,futures)
	return add(futures or before_update,cocreate(fn))
end
function wait_async(t,fn)
	local i=1
	while i<=t do
		if fn then
			if not fn(i) then
				return
			end
		end
		i+=time_dt
		yield()
	end
end
-- print text helper
local txt_offsets={{-1,0},{0,-1},{0,1},{-1,-1},{1,1},{-1,1},{1,-1}}
local txt_center,txt_shade,txt_border=false,-1,false
function txt_options(c,s,b)
	txt_center=c or false
	txt_shade=s or -1
	txt_border=b or false
end
function txt_print(str,x,y,col)
	if txt_center then
		x-=flr((4*#str)/2+0.5)
	end
	if txt_shade!=-1 then	
		print(str,x+1,y,txt_shade)
		if txt_border then
			for _,v in pairs(txt_offsets) do
				print(str,x+v[1],y+v[2],txt_shade)
			end
		end
	end
	print(str,x,y,col)
end

-- helpers
function pop(a)
	if #a>0 then
		local p=a[#a]
		a[#a]=nil
		return p
	end
end

-- calls 'fn' method on all elements of a[]
-- pairs allows add/remove while iterating
function filter(a,fn)
	for _,v in pairs(a) do
		if not v[fn](v) then
			del(a,v)
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
function amortize(x,dx)
	x*=dx
	return abs(x)<0.001 and 0 or x
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
function smoothstep(t)
	t=mid(t,0,1)
	return t*t*(3-2*t)
end

function sqr_dist(x0,y0,x1,y1)
	local dx,dy=x1-x0,y1-y0
	if abs(dx)>128 or abs(dy)>128 then
		return 32000
	end
	return dx*dx+dy*dy
end

function dot(a,b,u,v)
	return a*u+b*v
end
function normalize(u,v,scale)
	scale=scale or 1
	local d=sqrt(u*u+v*v)
	if (d>0) u/=d v/=d
	return u*scale,v*scale
end

-- collision map
-- provides o(1) lookup for proximity checks
local cmap={}
local cmap_cells=json_parse('[0,1,197,196,195,-1,-197,-196,-195]')
function cmap_op(obj,fn)
	if(bor(obj.w,obj.h)==0) return
	for x=flr(obj.x-obj.w),flr(obj.x+obj.w) do
		for y=flr(obj.y-obj.h),flr(obj.y+obj.h) do
			fn(obj,cmap,x+196*y)
		end
	end
end
function cmap_add(obj,cmap,h)
	cmap[h]=cmap[h] or {}
	add(cmap[h],obj)
end
function cmap_del(obj,cmap,h)
	if cmap[h] then
		del(cmap[h],obj)
		-- remove empty sets
		if #cmap[h]==0 then
			cmap[h]=nil
		end
	end
end
local cmap_session,cmap_i,cmap_cell,cmap_h,cmap_side=0
-- creates a nearby iterator
-- filters by side
-- warning: not reentrant
function cmap_iterator(x,y,side)
	cmap_i,cmap_cell,cmap_side=1,1,side or any_side
	cmap_h=flr(x)+196*flr(y)
	cmap_session+=1
end
function cmap_next()
	while(cmap_cell<=9) do
		local h=cmap_h+cmap_cells[cmap_cell]
		local objs=cmap[h]
		if objs and cmap_i<=#objs then
			local obj=objs[cmap_i]
			cmap_i+=1
			if obj.cmap_session!=cmap_session and band(obj.side,cmap_side)==0 then
				return obj
			end
			obj.cmap_session=cmap_session
		end
		cmap_i=1
		cmap_cell+=1
	end
	return nil
end

-- camera
local cam_x,cam_y,cam_z=0,0,0
local shkx,shky=0,0
function cam_shake(u,v,pow)
	shkx=min(4,shkx+pow*u)
	shky=min(4,shky+pow*v)
end
function cam_update()
	shkx*=-0.7-rnd(0.2)
	shky*=-0.7-rnd(0.2)
	if abs(shkx)<0.5 and abs(shky)<0.5 then
		shkx,shky=0,0
	end
	camera(shkx,shky)
end
function cam_track(x,y,z)
	cam_x,cam_y,cam_z=8*x,8*y,8*z
end
function cam_project(x,y,z)
	local w=32/(32+cam_z-8*z)
	return 64-(cam_x-8*x)*w,64+(cam_y-8*y)*w,w
end

-- zbuffer
local zbuf={}
function zbuf_clear()
	zbuf[1]={}
	zbuf[2]={}
	zbuf[3]={}
end
function zbuf_write(obj)
	local zi=obj.zorder or 2
	add(zbuf[zi],{obj=obj})
end
function zbuf_draw()
	local xe,ye
	for _,v in pairs(zbuf[1]) do
		xe,ye,w=cam_project(v.obj.x,v.obj.y,1)
		v.obj:draw(xe,ye,w)
	end
	for _,v in pairs(zbuf[2]) do
		xe,ye,w=cam_project(v.obj.x,v.obj.y,0)
		v.obj:draw(xe,ye,w)
	end
end

function rspr(s,x,y,ca,sa,w)
	local sx,sy=band(s*8,127),8*flr(s/16)
 local srcx,srcy
 local ddx0,ddy0=ca,sa
 local mask=shl(0xfff8,(w-1))
 w*=4
 ca*=w-0.5
 sa*=w-0.5
 local dx0,dy0=sa-ca+w,-ca-sa+w
 w=2*w-1
 for ix=0,w do
  srcx,srcy=dx0,dy0
  for iy=0,w do
   if band(bor(srcx,srcy),mask)==0 then
   	local c=sget(sx+srcx,sy+srcy)
   	sset(x+ix,y+iy,c)
  	end
   srcx-=ddy0
  	srcy+=ddx0
  end
  dx0+=ddx0
  dy0+=ddy0
 end
end

-- particles (inc. bullets)
local parts={}
_g.update_emitter=function(self)
	if _g.update_part(self) then
		if self.emit_t<time_t then
			make_part(self.x,self.y,self.emit_cls)
			self.emit_t=time_t+self.emit_dly
		end
		return true
	end
	return false
end
_g.update_part=function(p)
	if(p.t<time_t or p.r<=0) return false
	p.x+=p.dx
	p.y+=p.dy
	if p.y<0 then
		p.y=0
		-- simulate friction
		p.dy*=-0.9
	end
	p.r+=p.dr
	p.dx*=p.inertia
	p.dy*=p.inertia
	-- gravity
	if p.g then
		p.dy-=0.01
	end
	zbuf_write(p)
	return true
end

_g.draw_pixel_part=function(self,x,y)
	pset(x,y,self.c or 13)
end
_g.draw_circ_part=function(self,x,y)
	local f=smoothstep((self.t-time_t)/self.ttl)
	fillp(dither_pat[flr(#dither_pat*f)+1])
	circfill(x,y,8*self.r,self.c)
end

_g.draw_spr_part=function(self,x,y)
	spr(self.spr,x,y)
end

_g.draw_cached_rspr_part=function(self,x,y)
	-- blit sprite
	local src,dst=self.rspr_mem,0x0
	local angle=((self.angle%1)+1)%1
	src+=flr(angle*32)*32
	for i=0,7 do
		poke4(dst,peek4(src))
		src+=4
		dst+=64
	end
	palt(14,true)
	spr(0,x-4,y-4)
end

_g.update_blt=function(self)
	if(self.t<time_t) return false
	local x0,y0=self.x,self.y
	self.x+=self.dx
	self.y+=self.dy
	self.prevx,self.prevy=x0,y0
	
	local hit=false
	if(self.y<0) then
		self.y=0
		hit=true
	else
 	cmap_iterator(self.x,self.y,self.side)
 	local a=cmap_next()
 	while a do
 		local x,y=self.x-a.x,self.y-a.y
 		if abs(x)<(a.w+0.4)/2 and
       abs(y)<(a.h+0.4)/2 and a:hit(self) then
				hit=true
				break
 		end
 		a=cmap_next()
 	end
	end
	
	if hit then
		make_part(self.x,self.y,"flash")
		return false
	end
	
 zbuf_write(self)
 return true
end

local all_weapons=json_parse('{"gun":{"sfx":63,"spread":0.01,"dmg":1,"v":0.4,"ttl":[32,48],"dly":5,"ammo":75,"shk_pow":2,"spr":2},"gun_turret":{"id":0,"sfx":63,"spread":0.04,"dmg":1,"v":0.4,"ttl":[32,48],"dly":10,"los":16,"los_angle":0.5,"draw":"draw_cached_rspr_part","rspr_mem":0,"spr":1,"ammo":5,"reload_dly":45}}')
local all_parts=json_parse('{"flash":{"dly":8,"r":0.9,"c":7,"dr":-0.1,"draw":"draw_circ_part"},"part_cls":{"update":"update_part","draw":"draw_pixel_part","inertia":0.98,"r":1,"dr":0,"ttl":30},"trail":{"c":13,"rnd":{"ttl":[24,32]}},"smoke":{"draw":"draw_circ_part","c":0xd7,"rnd":{"dr":[0.002,0.005],"ttl":[30,60]},"dy":0.08},"blast":{"shk":5,"draw":"draw_circ_part","dr":-0.09,"r":1,"rnd":{"debris":[8,12]},"ttl":16,"c":0x77},"miniblast":{"shk":2,"draw":"draw_circ_part","dr":-0.09,"r":0.5,"rnd":{"debris":[1,2]},"ttl":16,"c":0x77},"debris":{"g":true,"update":"update_emitter","rnd":{"emit_dly":[2,8]},"emit_t":0,"emit_cls":"smoke"},"thruster":{"rnd":{"r":[0.3,0.4],"dly":[8,12]},"c":0x77,"dr":-0.02,"draw":"draw_circ_part"}}')
function make_part(x,y,src,dx,dy)
	src=all_parts[src]
	local p=clone(all_parts[src.base_cls or "part_cls"],
		clone(src,{
			x=x,
			y=y,
			dx=dx or 0,
			dy=dy or 0}))
 if(not p.update) assert()
	if(p.sfx) sfx(p.sfx)
	p.t=time_t+p.ttl
	return add(parts,p)
end
function make_blt(a,x,y,angle,wp)
	local n=wp.blts or 1
	local ang,da
	if n==1 then
		ang,da=angle+wp.spread*(rnd(2)-1),0
	else
		ang,da=angle-wp.spread/n,wp.spread/n
	end
	for i=1,n do
		--[[
		if anchor.ammo then
			if a==plyr and anchor.ammo<=0 then
				sfx(57)
				return
			end
			anchor.ammo-=1
		end
		]]
		if wp.sfx then
			sfx(wp.sfx)
		end
		local u,v=cos(ang),sin(ang)
		-- absolute position
		local b={
			u=u,v=v,
			dx=wp.v*u,dy=wp.v*v,
			side=a.side,
			angle=ang%1
		}
		clone({
			x=x,y=y,
			wp=wp,
			side=a.side,
			-- weapon ttl is a range
			t=time_t+lerp(wp.ttl[1],wp.ttl[2],rnd()),
			-- for fast collision
			prevx=b.x,prevy=b.y,
			spr=wp.spr,
			-- if using rspr mem cache
			rspr_mem=wp.rspr_mem,
			update=wp.update or _g.update_blt,
			draw=wp.draw or _g.draw_spr_part},b)
		add(parts,b)
		-- muzzle flash
		if(i==1) make_part(x,y,"flash")
		ang+=da
	end
end

-- actors
local plyr,lead
local actors={}

function make_blast(x,y,dx,dy,src)
	dx=dx or 0
	dy=dy or 0
	local p=make_part(x,y,src or "blast")
	for i=1,p.debris do
		local angle=rnd()
		local c,s=cos(angle),sin(angle)
		local px,py=x+rnd(2)*c,y+rnd(2)*s
		local pdx,pdy=dx+c/4,dy+s/4
		if py<0 then
			pdy=abs(0.8*pdy)
			py=0
		end
		make_part(px,py,"debris",pdx,pdy)
	end
	cam_shake(rnd(),rnd(),p.shk)
end


local clouds={}
function draw_clouds(x,y,fp,scale)
 local dx,dy=x%scale,y%scale
 local i0,j0=flr(x/scale),flr(y/scale)
	local i=i0
	local x0=-dx-24
	fillp(fp)
	color(colors[2])
 while x0<127+24 do
 	local j=j0
 	local y0=-dy-24
 	local cx=(i%128+128)%128
 	while y0<127+24 do
 		local cy=(j%128+128)%128
			local f=clouds[cx+128*cy+1]
			local sx,sy=128-x0,128-y0
			if f==1 then
				circfill(sx,sy+1,scale)
			elseif f==2 then
				circfill(sx,sy-scale,scale)
			elseif f==4 then
				circfill(sx-scale,sy,scale)
			elseif f==8 then
				circfill(sx-scale,sy-scale,scale)
			elseif f>0 and f<=15 then
				rectfill(sx,sy,sx-scale+1,sy-scale+1)
			end
			j+=1
			y0+=scale
		end
		i+=1
		x0+=scale
 end
end
function draw_ground(self,x,y,w)
	if(y>127) return
	pal()
	fillp()
	rectfill(0,y,127,127,colors[2])
	for j=-0.5,0.5,0.1 do
		x,y,w=cam_project(0,0,j)
		local dx=w*(cam_x%16)
		x=-dx
		while x<64 do
			pset(64+x,y,colors[3])
			pset(64-x-2*dx,y,colors[3])
			x+=w*16
		end
	end
end

-- actors
function draw_actor(self,x,y,w)
	local s=self.frames[flr(self.frame)]
	rspr(s,32,16,self.u,self.v,2)
	
	palt(14,true)
	palt(0,false)
	pal(6,self.in_sight and 8 or 0)
	palt(14,true)
	local we=16*w
	sspr(32,16,16,16,x-we/2,y-we/2,we,we)

--	circ(x,y,	sqrt(256),7)
	for _,f in pairs(self.f) do
		local x1,y1=x+f[2],y-f[3]
		line(x,y,x1,y1,11)
		print(f[1],x1,y1-6,7)
	end
end

function draw_actor_shadow(self,x,y,w)
	if time_t%2==0 then
		spr(78,x-8,y-8,2,2)
	end
end

function get_turn_rate(self,b)
	local tr
	if(b==2) tr=0.002
	if(b==3) tr=-0.005
	if(self.inverted) tr=-tr
	return tr
end

function arrive(self,pos)
end
function follow(self,other,dist)
	-- target point
	local x,y=other.x-dist*other.u,other.y-dist*other.v
	--return normalize(x-self.x,y-self.y)
	return x-self.x,y-self.y
end
function evade(self,other,dist)
	self.in_sight=false

	local dx,dy=other.x-self.x,other.y-self.y
	local d=dx*dx+dy*dy
	if d<dist*dist then
		d=sqrt(d)
		if abs(d)>0.001 then
			dx/=d
			dy/=d
		end
		local angle=dot(other.u,other.v,dx,dy)
		-- in cone?
		if angle<-0.9 then
			self.in_sight=true
			return -self.v,self.u
		end
	end
	return 0,0
end
function avoid(self,dist)
	local dx,dy=0,0
	for _,other in pairs(actors) do
		if other!=self then
			local ddx,ddy=other.x-self.x,other.y-self.y
			local d=ddx*ddx+ddy*ddy
			local scale=1-smoothstep(d/dist*dist)
			--[[
			d=sqrt(d)
			if abs(d)>0.001 then
				ddx/=d
				ddy/=d
			end
			]]
			dx-=scale*ddx
			dy-=scale*ddy
		end
	end
	-- avoid ground
	if self.y<2 then
		--dy+=-self.y/2
		dy+=abs(self.y)
	end
	return dx,dy
end

function control_npc(self)
	local fx,fy,dx,dy=0,0,0,0
	self.f={}
	fx,fy=evade(self,plyr,4)
	dx+=fx
	dy+=fy
	add(self.f,{"evade",fx,fy})
	fx,fy=avoid(self,4)
	dx+=fx
	dy+=fy
	add(self.f,{"avoid",fx,fy})
	fx,fy=follow(self,plyr,4)
	dx+=fx
	dy+=fy
	add(self.f,{"follow",fx,fy})
	
	-- project force into thrust normal
	-- pull/push based on sign
	dx,dy=normalize(dx,dy)
	local d=-self.v*dx+self.u*dy
	self.da=lerp(0.005,-0.01,smoothstep((d+1)/2))
end

function control_plyr(self)
	if not self.rolling then
		if(btn(2)) self.da=get_turn_rate(self,2)
		if(btn(3)) self.da=get_turn_rate(self,3)
		if btnp(0) or btnp(1) then
			self.rolling=true
			if self.inverted then
				self.df=-0.1
				self.target_frame=1
			else
				self.df=0.1
				self.target_frame=#self.frames
			end
		end
	end

	if btn(4) and self.fire_t<time_t then
		if self.ammo>0 then
			self.fire_t=time_t+self.wp.dly
			local x,y=self.x+1.2*self.u,self.y+1.2*self.v
			make_blt(self,x,y,self.angle,self.wp)
		end
	end
	
	if btnp(5) and self.boost_t<time_t then
		self.boost=0.2
		self.boost_t=time_t+self.boost_dly
	end

	if self.boost_t>time_t then
		local x,y=self.x-0.8*self.u,self.y-0.8*self.v
		make_part(x,y,"thruster")
	end
end

function hit(self)
	local dx,dy=normalize(self.dx,self.dy)
	make_blast(self.x,self.y,dx*self.acc,dy*self.acc)
	self.disable=true
end

function move_actor(a)
	a.angle+=a.da
	-- rotation damping
	a.da*=0.96
	
	-- simulate air friction
	a.dx*=0.95
	a.dy*=0.95
	-- apply thrust force
	local u,v=cos(a.angle),sin(a.angle)
	a.dx+=u
	a.dy+=v
	local dx,dy=normalize(a.dx,a.dy)

	local acc=a.acc
	if a.boost then
		acc+=a.boost
		a.boost*=0.98
	end
	a.x+=dx*acc
	a.y+=dy*acc

	if a.rolling then
		if flr(a.frame)!=a.target_frame then
			a.frame+=a.df
		else
			a.frame=a.target_frame
			a.rolling=false
			a.inverted=not a.inverted
		end
	end
	a.u=u
	a.v=v
	
	return u,v,dx,dy
end

function update_actor(a)
	if (a.disable) return false
	
	a:input()
	
	cmap_op(a,cmap_del)
	local u,v,dx,dy=move_actor(a)
	cmap_op(a,cmap_add)
	
	-- collision?
	local hit=false
	if a.y<0.5 then
		hit=true
	end
	for _,other in pairs(actors) do
		if other!=a and sqr_dist(a.x,a.y,other.x,other.y)<1 then
			--other:hit()
			
			--hit=true
		end
	end
	if hit then
		--a:hit()
		cmap_op(a,cmap_del)
		return false
	end
	
	-- calculate drift force
	if abs(dx*u+dy*v)<0.90 then
		make_part(a.x+rnd()-1-u,a.y+rnd()-1-v,"trail")
	end
	
	zbuf_write(a)
	zbuf_write({
		x=a.x,y=0,
		draw=draw_actor_shadow
	})
	return true
end

local actor_cls={
 	dx=0,dy=0,
 	acc=0.1,
 	u=1,
 	v=0,
 	angle=0,
 	da=0,
 	update=update_actor,
 	draw=draw_actor
}
_g.draw_map_actor=function(self,x,y,w)
	palt(14,true)
	pal(8,time_t%2==0 and 14 or 6)
	
	x-=4*self.cw
	y-=4*self.ch
	map(self.cx,self.cy,x,y,self.cw,self.ch)

	for _,anchor in pairs(self.anchors) do
		local x,y=self.x+anchor.x,self.y+anchor.y
		x,y=cam_project(x,y,0)
		--line(x,y,x+8*anchor.u,y-8*anchor.v,8)
		print(anchor.hp,x+8*anchor.u,y-8*anchor.v,8)
	end

end
_g.hit_map_actor=function(self,blt)
	for _,b in pairs(self.cmap) do
		local x,y=self.x+b.x,self.y+b.y
		if sqr_dist(x,y,blt.x,blt.y)<0.25 then
			if b.hit then
				b.hit(b,x,y,blt.wp.dmg)
			end
			return true
		end
	end
end
_g.update_b29=function(self)
	-- destroyed?
	if #self.anchors==0 then
		futures_add(function()
			self.dy=0.1
			wait_async(90,function()
				return self.y>1
			end)
			make_blast(self.x,self.y,self.dx,self.dy)
			self.disable=true
		end)
	end
	cmap_op(self,cmap_del)
	if(self.disable) return false
	
	-- basic pos update
	self.x+=self.dx
	self.y+=self.dy
	cmap_op(self,cmap_add)
	
	filter(self.anchors,"update")

	zbuf_write(self)
	return true
end

_g.hit_plane_actor=function(self,blt)
	for i=-1,1 do
		local x,y=self.x+i*self.u/2,self.y+i*self.v/2
		if sqr_dist(x,y,blt.x,blt.y)<0.25 then
			-- todo: damage+feedback
			return true
		end
	end
end
_g.update_anchor=function(self)
	if(self.disable) return false
	-- time to reload?
	if self.reload_t<time_t then
		self.ammo=self.wp.ammo
	end
	if self.ammo<=0 or self.fire_t>time_t then
		return true
	end
	local x,y=self.actor.x+self.x,self.actor.y+self.y
	local dx,dy=plyr.x-x,plyr.y-y
	local d=dx*dx+dy*dy
	
	-- todo: fix overflow risk
	local wp=self.wp
	if d<wp.los*wp.los then
	
		if(d>0.001) d=sqrt(d) dx/=d dy/=d
		if dot(dx,dy,self.u,self.v)>wp.los_angle then
			self.fire_t=time_t+self.wp.dly
			local angle=atan2(dx,dy)
			make_blt(self.actor,x,y,angle,wp)
			self.ammo-=1
			if self.ammo<=0 then
				self.reload_t=time_t+self.wp.reload_dly
			end
		end
	end
	return true
end
_g.hit_anchor=function(self,x,y,dmg)
	if(self.disable) return
	self.hp-=dmg
	if self.hp<=0 then
		self.disable=true
		make_blast(x,y,0.1*self.u,0.1*self.v,"miniblast")
		
		del(self.actor.cmap,self)
	end
end
local all_actors=json_parse('{"b29":{"draw":"draw_map_actor","update":"update_b29","hit":"hit_map_actor","w":4.4,"h":1.4,"cx":0,"cy":0,"dx":0,"dy":0,"is_map":true},"f14":{"w":0.9,"h":0.4,"frames":[64,66,68,70,72,74,76],"frame":1,"df":0,"rolling":false,"inverted":false,"hit":"hit_plane_actor","wp":"gun","fire_t":0},"anchor":{"update":"update_anchor","hit":"hit_anchor","hp":3,"reload_t":32000}}')
function make_actor(x,y,src)
	src=all_actors[src]
	local a=clone(actor_cls,clone(src,{x=x,y=y,f={}}))
	-- scan map for anchors
	if a.is_map then
		a.anchors={}
		a.cmap={}
		a.cw,a.ch=max(1,flr(2*a.w+0.5)),max(1,flr(2*a.h+0.5))
		for i=0,a.cw-1 do
			for j=0,a.ch-1 do
				local s=mget(a.cx+i,a.cy+j)
				if s!=0 then
					local anchor=make_anchor(a,i,j,s)
					if anchor then
						add(a.anchors,anchor)
						add(a.cmap,anchor)
					else
						add(a.cmap,{
							x=i-a.cw/2+0.5,
							y=-j+a.ch/2-0.5,
						})
					end
				end
			end
		end
	end
	return add(actors,a)
end
function make_anchor(a,i,j,s)
	local flags=fget(s)

	-- anchor point?
	if(band(flags,0x1)==0) return

	-- orientation (2 bits)
	flags=shr(flags,1)
	local angle=band(0b11,flags)/4

	-- weapon type (7 bits)
	flags=band(15,shr(flags,2))

	for _,wp in pairs(all_weapons) do
		if wp.id==flags then
			return clone(all_actors["anchor"],{
				actor=a,
				x=i-a.cw/2+0.5,
				y=-j+a.ch/2-0.5,
				angle=angle,
				u=cos(angle),
				v=-sin(angle),
				-- fire delay after spawn
				fire_t=time_t+90,
				ammo=wp.ammo,-- can be nil
				wp=wp})
		end
	end
	assert("unknown wp:"..flags)
end

local game_screen={}
function game_screen:update()
	time_t+=1
	
	zbuf_clear()

	cam_track(plyr.x+4*plyr.u,plyr.y+4*plyr.v,8*plyr.boost)
	
	filter(actors,"update")
	filter(parts,"update")

	cam_update()
end

function game_screen:draw()
	cls(colors[3])

	--ground
	local x,y,w=cam_project(0,0,0.8)
	draw_clouds(x,y,nil,8)
	draw_ground({},x,y,w)

	zbuf_draw()
	x,y,w=cam_project(0,0,-0.8)
	draw_clouds(x,y,0b1010010110100101.1,16)
	-- draw hud
	if lead and not lead.visible then
		x,y=cam_project(lead.x,lead.y,0)
		x-=plyr.x
		y-=plyr.y
		x,y=normalize(x,y)
		line(64+8*x,64+8*y,64+10*x,64+10*y,13)
	end
	
	--[[
	for i=0,195 do
		for j=0,16 do
			local h=i+196*j
			if cmap[h] then
				x,y=cam_project(i,j,0)
				print(#cmap[h],x-4,y-4,7)
			end
		end
	end
	]]
	
	fillp()
	rectfill(0,0,127,8,1)
	print((flr(1000*stat(1))/10).."%",2,2,7)
end

function game_screen:init()
 -- noise clouds (marching squares)
 clouds=make_clouds()
 	
	lead=make_actor(32,3,"f14")
	lead.input=control_npc
	lead.npc=true
	lead.side=bad_side
	
	lead=make_actor(30,4,"f14")
	lead.input=control_npc
	lead.npc=true
	lead.side=bad_side
	
	local a=make_actor(24,8,"b29")
	a.side=bad_side
	
	plyr=make_actor(30,3,"f14")
	plyr.input=control_plyr
	plyr.score=0
	plyr.side=good_side
	plyr.ammo=100
	plyr.wp=all_weapons[plyr.wp]
	plyr.boost=0
	plyr.boost_t=0
	plyr.boost_dly=90
end

cur_screen=game_screen
function _draw()
	cur_screen:draw()
	time_dt=0
end
function _update60()
	time_dt+=1
	cur_screen:update()
end
function _init()
	-- sprite cache
	local dst=0x4300
	for _,wp in pairs(all_weapons) do
		if wp.rspr_mem then
  	wp.rspr_mem=dst
 		-- using spr 36
   local src=0x0+16+16*64
   for i=0,31 do	
		rspr(wp.spr,32,16,cos(i/32),sin(i/32),1)
  		-- copy image to user data
  		for k=0,7 do
  			poke4(dst,peek4(src+k*64))
  			dst+=4
  		end
  	end
		end
	end

	if cur_screen.init then
		cur_screen:init()
	end
end

__gfx__
00000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700e777777eeee77eee00000000000000000000777000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000e777777eee7777ee07777000000000000077777000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000e777777eee7777ee77777777000777007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700e777777eeee77eee00000000007777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000eeeeeeeeeeeeeeee00000000000077700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eee666eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeee6e6666eeeeeeeeee6e66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eee6666eeeeeeeeeeee666eeeeeeeeeeeee6e66666eeeeeeeee66e66666eeeeeeee6666666eeeeeeeeeee66eeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeee
eeee66666677eeeeeeee66666677eeeeeee6666666776eeeeeee666666666eeeeeee666666666eeeeee6666666666eeeeee6666666666eeeeeeee666666eeeee
eee66666666666eeeee66666666666eeeee66666667766eeeee66666667766eeeee66666667766eeeee66666666666eeeee66666666666eeeee6666666666eee
eee6666666666eeeeee6666666666eeeeeee666666666eeeeeee666666666eeeeee6666666776eeeeeee66666677eeeeeeee66666677eeeeeeee66666666eeee
eeeee66eeeeeeeeeeeeee66eeeeeeeeeeee6666666eeeeeeeee66e66666eeeeeeee6e66666eeeeeeeee666eeeeeeeeeeeee6666eeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee6e66eeeeeeeeeeee6e6666eeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeeeeee666eeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eee66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeee666eeeeeeeeeeeee666eeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeee0000000000000000
eee666ee77eeeeeeeee66eee66eeeeeeeee66ee666eeeeeeeee66ee666eeeeeeeeeeeee666eeeeeeeeeeeee666eeeeeeeeeeeee666eeeeee0000000000000000
ee66666677666eeeee66666677666eeeee66666666666eeeeee6666666666eeeeee66e6666666eeeeeeeee6666666eeeeeeeee6666666eee0000000000000000
eeee6666666666eeeee66666776666eeeee66666776666eeee666666776666eeeee66666776666eeeee66666666666eeeeee6666666666ee0000000000000000
eeeeee6666666eeeeeeeee6666666eeeeee66e6666666eeeeee6666677666eeeee66666677666eeeee66666677666eeeee66666677666eee0000000000000000
eeeeeee666eeeeeeeeeeeee666eeeeeeeeeeeee666eeeeeeeee66ee666eeeeeeeee66ee666eeeeeeeee66eee77eeeeeeeee666ee77eeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeee666eeeeeeeeeeeee666eeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee66eeeeeeeeeeeeee66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000
eeeeee0000eeeeee000000ee00000000eeeeee00eeeeeeeee000000ee0000000000000000000000000000000eeeeeeee00000000000000000000000000000000
eeee0000000eeeee0000000000000000eeeee777eeeeeeeee000000ee8e000000000000000000eee00000000eeeeeeee00000000000000000000000000000000
eee00000000eeeee0000000000000000eeee7777eeeeeeeeee0000eee8e00000000000000000eeee00000000eeeeeeee00000000000000000000000000000000
eee00000000eeeee000000ee00000000e0000000eeeeeeeeeeeeeeeee8ee00000000000000eeeeee00000000eeeeeeee00000000000000000000000000000000
eee000000000eeee000eeeee0000000000000000eeeeeeeeeeeeeeeee8eeeeee0000eeeeeeeeeeee00000000eeeeeeee00000000000000000000000000000000
ee0000000000eeeeeeeeeeee0000000000000000ee0000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000eeeeeeee00000000000000000000000000000000
ee0000000000eeeeeeeeeeee00000eee00000000e000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000eeeeeeee00000000000000000000000000000000
ee0000000000eeeeeeeeeeee00eeeeeee0000000e000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000eeeeeeee00000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000010005030700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
8b8b858b8b858b80810000000404020201010504040301010105040403010403050401010405030403010405040404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
848a8a8a8a8a8a83820000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8b8b8788898b868b8b0000040202020405010101010504040401050301010504040404040301010504040405030101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0404040404040105040404040403050101010504040401040504040404040403050101050404040501000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
