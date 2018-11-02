pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
local hmap={}
local track
local mouse={drag=false,hand=false,x=0,y=0,lmb_t=0,lmb=false,rmb=false}
local cam
local tool
local menu
local time_t=0
-- edit mode
local tool
local track_sel

function make_cam()
	local c={
	 scale=1,
	 pan={0,0},
		project=function(self,x,y)
			return self.scale*x+self.pan[1],self.scale*y+menu.height+self.pan[2],self.scale
		end,
		zoom=function(self,factor)
			self.scale=mid(self.scale+factor,1,4)
		end,
		unproject=function(self,i,j)
			return flr((i-self.pan[1])/self.scale),flr((j-menu.height-self.pan[2])/self.scale)
		end
	}
	return c
end

function safe_index(i,j)
	return band(i,0x3f)+64*band(j,0x3f)+1
end

function raise_terrain(x,y,scale)
	local radius=4
	for i=-radius,radius do
		for j=-radius,radius do
			local d=i*i+j*j
			if d<radius*radius then
				local h=hmap[safe_index(x+i,y+j)]
				local dh=scale*flr(7*(1-sqrt(d)/radius))
			 hmap[safe_index(x+i,y+j)]=mid(h+dh,0,7)
			end
		end
	end
end

function clear_map()
	-- fill map
	hmap={}
	for j=0,63 do
	 for i=0,63 do
	 	add(hmap,0)
	 end
	end
	track=make_track()
end

function save_map()
	local mem=0x2000
	for i=1,#hmap-1,2 do
		local h0,h1=hmap[i],hmap[i+1]
		poke(mem,bor(h0,shl(h1,4)))
		mem+=1
	end
	track:save(mem)
	cstore()
end

function load_map()
	hmap={}
	local mem=0x2000
	for i=0,32*64-1 do
		local h=peek(mem)
		add(hmap,band(0xf,h))
		add(hmap,band(0xf,shr(h,4)))
		mem+=1
	end
	track=make_track()
	track:load(mem)
end

function _init()
 	-- mouse support
	poke(0x5f2d,1)
	
	cam=make_cam()
	
	menu=make_menu({
	 -- selection
	 {
	 	spr=42,
 		click=function()
 	 end,
 	 move=function(self,x,y)
 			local dummy
 			x,y=cam:unproject(x,y)
 			dummy,track_sel=track:nearest_segment(x,y) 
 	 end,
 		drag=function(self,x,y)
				local dx,dy=-mouse.x+x,-mouse.y+y
 			if track_sel!=-1 then
 				track:move(track_sel,dx/cam.scale,dy/cam.scale)
 			else
 				cam.pan[1]+=dx
					cam.pan[2]+=dy
 			end	
 	 end
	 },
	 -- raise/dig mode
	 {
	 	spr=34,
		 click=function(self,x,y)
				x,y=cam:unproject(x,y)
	 		raise_terrain(x,y,1)
	 	end,
	 	drag=function(self,x,y)
				x,y=cam:unproject(x,y)
	 		raise_terrain(x,y,1)
	 	end
	 },
	 {
	 	spr=35,
		 click=function(self,x,y)
				x,y=cam:unproject(x,y)
	 		raise_terrain(x,y,-1)
	 	end,
	 	drag=function(self,x,y)
				x,y=cam:unproject(x,y)
	 		raise_terrain(x,y,-1)
	 	end
	 },
	 -- flag
	 {
	 	spr=32,
	 	cursor=16,
		 click=function(self,x,y)
				x,y=cam:unproject(x,y)
				track:insert({pos={x,y}},self.ni)
	 	end,
	 	move=function(self,x,y)
				x,y=cam:unproject(x,y)
				self.np,self.ni=nil,nil
				-- find nearest intersection
				local np,nd,ni=track:nearest_point(x,y)
				-- close enough?
				if np and nd<4 then
					self.np,self.ni=np,ni
				end
			end,
			draw=function(self)
				if self.np then
					local x,y=cam:project(self.np[1],self.np[2])
					circ(x,y,3,8)
				end
			end
	 },
	 -- chrono
	 {
	 	spr=33,
	 	cursor=17,
		 click=function(self,x,y)
				x,y=cam:unproject(x,y)
				track:insert({pos={x,y},chrono=true})
	 	end
	 },
	 -- kill marker
	 {
	 	spr=39,
	 	cursor=18,
		 click=function(self,x,y)
				x,y=cam:unproject(x,y)
	 		local t,i=track:nearest_segment(x,y)
	 		track:del(t)
	 	end
	 },
	 -- save
	 {
	 	spr=40,
	 	action=function()
	 		save_map()
	 	end
	 },
	 -- trash
	 {
	 	spr=41,
	 	action=function()
	 		clear_map()
	 	end
	 },
	 -- export
	 {
	 	spr=43,
	 	action=function()
	 		export_map()
	 	end
	 }
	},function(item)
		tool=item
	end)

	load_map()
end

function _update()
	time_t+=1
	local mx,my=stat(32),stat(33)
	local lmb,rmb=stat(34)==1,stat(34)==2

	local px,py=0,0
	if(btn(0)) px=1
	if(btn(1)) px=-1
	if(btn(2)) py=1
	if(btn(3)) py=-1
	cam.pan[1]+=cam.scale*px
	cam.pan[2]+=cam.scale*py
	
	cam:zoom(stat(36))

	mouse.hand=false
 -- mouse drag?
	mouse.drag=false
	if lmb then
		mouse.drag=(mx==mouse.x and my==mouse.y)==true and false or true
	end 

	-- frame click?
	local lmbb=lmb and lmb!=mouse.lmb 
	
	menu:update()
 if mouse.y<menu.height then
  if lmbb then
			menu:click(mx,my)
		else
			menu:move(mx,my)
		end
	-- not captured by menu?
	elseif tool then
		if tool.drag and mouse.drag then
			tool:drag(mx,my)
		elseif tool.click and lmbb then
			tool:click(mx,my)
		elseif tool.move then
			tool:move(mx,my)
		end
	end
 
	mouse.x,mouse.y=mx,my
	mouse.lmb,mouse.rmb=lmb,rmb
end

function _draw()
	cls(0)
	fillp(0xa5a5)
	local x0,y0=cam:project(0,0)
	local x1,y1=cam:project(63,63)
	rect(x0,y0,x1,y1,7)
	fillp()
	
	for j=0,63 do
	 for i=0,63 do
	 	local x,y,w=cam:project(i,j)
	  local h=hmap[i+j*64+1]
	  if x<127 then
	 	 if(y>127) break
	 	 local c=sget(8+h,0)
	 	 if(c!=0) rectfill(x,y,x+w-1,y+w-1,c)
	 	end
	 end
	end
	track:draw()
	
	if tool and tool.draw then
		tool:draw()
	end
	
	menu:draw()
	
	if mouse.hand or track_sel!=-1 then
		spr(2,mouse.x-4,mouse.y)
	elseif tool and tool.cursor then
		spr(tool.cursor,mouse.x,mouse.y)
	else
		spr(0,mouse.x,mouse.y)
	end
end

-->8
-- binary export helpers
local int={}
function int:tostr(v)
	return sub(tostr(v,true),3,6)
end
local byte={}
function byte:tostr(v)
	return sub(tostr(v,true),5,6)
end
local nible={}
function nible:tostr(v)
	return sub(tostr(v,true),6,6)
end
-->8
-- menu
function make_menu(items,cb)
	local m={
		height=8,
		selected=-1,
		over=-1,
		update=function(self)
			self.over=-1
		end,
		move=function(self,x,y)
			local i=x-2
			i=flr(i/8)+1
			if i>=1 and i<=#items then
				mouse.hand=true
				self.over=i
			end
		end,
		click=function(self,x,y)
			local i=x-2
			i=flr(i/8)+1
			if i>=1 and i<=#items then
				-- item
				local item=items[i]
				-- single click?
				if item.action then
					item:action()
					cb()
				else
					cb(item)
					self.selected=i
				end
			end
		end,
		draw=function(self)
			rectfill(0,0,127,self.height,8)
			local x=2
			for i=1,#items do
				local item=items[i]
				if self.selected==i then
					pal(1,15)
				end
				if self.over==i then
					pal(1,7)
				end
				spr(item.spr,x,0)
				pal()
				x+=8
			end
		end
	}
	return m
end
-->8
-- vector functions
function make_v(a,b)
	return {b[1]-a[1],b[2]-a[2]}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]
end
function v_sqrlen(a)
	return a[1]*a[1]+a[2]*a[2]
end
function v_normz(v)
	local d=sqrt(v_sqrlen(v))
	if d>0 then
		v[1]/=d
		v[2]/=d
	end
end
function v_normal(v)
	v[1],v[2]=-v[2],v[1]
end
function v_add(a,b,scale)
	scale=scale or 1
	a[1]+=scale*b[1]
	a[2]+=scale*b[2]
end
function v_clone(a)
	return {a[1],a[2]}
end
function v_scale(v,scale)
	v[1]*=scale
	v[2]*=scale
end

-- trifill by @p01
function p01_trapeze_h(l,r,lt,rt,y0,y1)
 lt,rt=(lt-l)/(y1-y0),(rt-r)/(y1-y0)
 if(y0<0)l,r,y0=l-y0*lt,r-y0*rt,0 
	for y0=y0,min(y1,128) do
  rectfill(l,y0,r,y0)
  l+=lt
  r+=rt
 end
end
function p01_trapeze_w(t,b,tt,bt,x0,x1)
 tt,bt=(tt-t)/(x1-x0),(bt-b)/(x1-x0)
 if(x0<0)t,b,x0=t-x0*tt,b-x0*bt,0 
 for x0=x0,min(x1,128) do
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
-- array functions
function insert(a,elt,i)
	-- move 
	for j=#a,i,-1 do
		a[j+1]=a[j]
	end
	a[i]=elt
end

-->8
-- track functions
function is_near_capsule(x,y,x0,y0,x1,y1,r)
	local dx,dy=x1-x0,y1-y0
	local ax,ay=x-x0,y-y0
	local t,d=ax*dx+ay*dy,dx*dx+dy*dy
	if d==0 then
		t=0
	else
		t=mid(t,0,d)
		t/=d
	end
	local ix,iy=x0+t*dx-x,y0+t*dy-y
	return ix*ix+iy*iy<r*r
end
function draw_capsule(x0,y0,x1,y1,r,c)
	circfill(x0,y0,r,c)
	circfill(x1,y1,r,c)
	-- draw rectangle
	local v=make_v({x0,y0},{x1,y1})
 v_normz(v)
 v_normal(v)
 v_scale(v,r)
 trifill(x0-v[1],y0-v[2],x0+v[1],y0+v[2],x1-v[1],y1-v[2],c)
 trifill(x1-v[1],y1-v[2],x1+v[1],y1+v[2],x0+v[1],y0+v[2],c)
end

function make_track()
	local track={}
	return {
		is_near=function(self,x,y,dist)
		 local t0=track[#track]
		 for i=1,#track do
		 	local t1=track[i]
		 	if(is_near_capsule(x,y,t0.pos[1],t0.pos[2],t1.pos[1],t1.pos[2],dist)) return true
		 	t0=t1
		 end
		 return false
		end,
		nearest_segment=function(self,x,y)
 		local t,t_i
 		for i=1,#track do
 			local v=track[i]
 	 	local dx,dy=x-v.pos[1],y-v.pos[2]
 			if dx*dx+dy*dy<2 then
 	 		return v,i
 			end
 		end
 		return nil,-1
 	end,
  nearest_point=function(self,x,y)
  	if(#track==0) return
  	local x0,y0=track[#track].pos[1],track[#track].pos[2]
   local mindist,mini=32000,-1
   local minp
   for i=1,#track do
  		local t=track[i]
  		local x1,y1=t.pos[1],t.pos[2]	
  		-- project point on segment
  		local a,b=make_v({x0,y0},{x,y}),make_v({x0,y0},{x1,y1})
  		local d=v_dot(a,b)/v_dot(b,b)
  		if d>=0 and d<=1 then
  			local np=v_clone({x0,y0})
  			v_add(np,b,d)
  			local dist=v_sqrlen(make_v(np,{x,y}))
  			if dist<mindist then
  				mindist,minp,mini=dist,np,i
  			end
  		end
  	 x0,y0=x1,y1
  	end
  	return minp,mindist,mini
  end,
		draw=function(self)
  	local xmin,ymin=cam:project(0,0)	
  	local xmax,ymax=cam:project(64,64)	
			clip(xmin,ymin,xmax-xmin,ymax-ymin)
   fillp(0xa5a5.f)
   -- road border
   local draw_segments=function(r,c)
    local t0=track[#track]
 			local x0,y0=cam:project(t0.pos[1],t0.pos[2])	
  	 
  	 for i=1,#track do
 		 	local t1=track[i]
 				local x1,y1=cam:project(t1.pos[1],t1.pos[2])	
  			draw_capsule(x0,y0,x1,y1,2.5,c)
  			x0,y0=x1,y1	 	
 		 end
 		end
 		draw_segments(2.5*cam.scale,9)
		 draw_segments(2*cam.scale,4)
		 
  	fillp()
  	clip()
   -- track
  	if #track>0 then
  	 --fillp(0xa5a5)
   	local prevx,prevy=cam:project(track[#track].pos[1],track[#track].pos[2])
   	for i=1,#track do
   		local v=track[i]
   		local x,y,w=cam:project(v.pos[1],v.pos[2])	
   		line(prevx,prevy,x,y,12)
   		prevx,prevy=x,y
   	end
   	--fillp()
   end
  	
  	for i=1,#track do
  		local v=track[i]
  		local x,y,w=cam:project(v.pos[1],v.pos[2])
  		local s=v.chrono and 17 or 16
  		if track_sel==i then
  		 s=20
  		elseif i==1 then
  		 s=19
  		end
  		spr(s,x-1,y-5)
  	end
		end,
		insert=function(self,t,i)
			if i then
				insert(track,t,i)
			else
			 add(track,t)
			end
		end,
		move=function(self,i,dx,dy)
			local t=track[i]
 		t.pos[1]+=dx
 		t.pos[2]+=dy
		end,
		del=function(t)
			del(track,t)
		end,
		save=function(self,mem)
  -- track
  	poke(mem,#track)
  	mem+=1
  	for i=1,#track do
  		local t=track[i]
  		poke(mem,t.pos[1])
  		mem+=1
  		poke(mem,t.pos[2])
  		mem+=1
  	end
  	return mem
  end,
		load=function(self,mem)
			local n=peek(mem)
  	mem+=1
  	for i=1,n do
  		local x=peek(mem)
  		mem+=1
  		local y=peek(mem)
  		mem+=1
  		add(track,{pos={x,y}})
  	end
  	return mem
  end,
  tostr=function(self)
  	local s=byte:tostr(#track)
  	for i=1,#track do
  		local t=track[i]
  		s=s..byte:tostr(t.pos[1])
  		s=s..byte:tostr(t.pos[2])
  	end
  	return s
  end
	}
end
-->8
-- export map
local tohex={}
for i=0,15 do
	tohex[i]=sub(tostr(i,true),6,6)
end

function log(s)
 printh(s)
	rectfill(0,120,127,127,15)
	print(s,2,121,0)
	flip()
end

function export_map()
 local idx_offsets={0,1,128,129}
	local q_codes={
		{0,0,0,0},
		{0,0,1,0},
		{0,0,0,2},
		{0,0,5,5},
		{0,4,0,0},
		{2,0,0,8},
		{0,5,0,5},
		{2,5,5,5},
		{8,0,0,0},
		{5,0,5,0},
		{5,1,4,5},
		{5,1,5,5},
		{5,5,0,0},
		{5,5,5,8},
		{5,5,4,5},
		{5,5,5,5}}
	
	-- returns whether value is above a given level
	local is_solid=function(i,j,dist)
		return track:is_near(i,j,dist) and 1 or 0
	end
	-- converts four corners into a single lookup index
	-- cf: https://en.wikipedia.org/wiki/marching_squares
	local marching_code=function(i,j,level,margin)
		return
		8*is_solid(i,j,level,margin)+
		4*is_solid(i+1,j,level,margin)+
		2*is_solid(i+1,j+1,level,margin)+
		is_solid(i,j+1,level,margin)
	end
	-- layout
	-- 0x0f: q
	-- 0x0.ff00: hi
	-- 0x0.00ff: lo
	local get_q_colors=function(q)
		return shl(band(0x0.ff00,q),8),shl(band(0x0.00ff,q),16)
	end

	local set_q_colors=function(q,lo,hi)
		return bor(q,bor(shr(hi,8),shr(lo,16)))
	end
	
	local qmap={}
	
	-- create multiple layers
	-- color range: 0-7
	local layers={
		{dist=2.5,hi=1,lo=0},
		{dist=2,hi=2}}

	for l=1,#layers do
		local layer=layers[l]
		log("generating qmap:"..l.."/"..#layers)
		for j=0,63 do
			for i=0,63 do
				local q=marching_code(i,j,layer.dist)				
				local idx=2*i+2*128*j
				local code=q_codes[q+1]
				for k=1,4 do
					local q,k=code[k],idx+idx_offsets[k]
					-- hi/lo colors
					local hi,lo=layer.hi,layer.lo
					-- previous tile
					local prev_q=qmap[k]
					if prev_q then
						prev_hi,prev_lo=get_q_colors(prev_q)
						-- replace lo color
						lo=prev_lo
					end
					-- replace only full hi tiles
					prev_q=band(0xff,prev_q or 5)
					if prev_q==5 then
						if q==0 then
							hi,lo=lo,lo
						elseif band(0xf,q)==5 then
							hi,lo=hi,hi
						elseif q==1 or q==8 then
							hi,lo=hi,lo
						elseif q==4 or q==2 then
							hi,lo=lo,hi
						end
						q=set_q_colors(q,hi,lo)
						qmap[k]=q
					end
				end
			end
		end
	end
	--[[
	cls()
	for j=0,127 do
		for i=0,127 do
			local idx=i+128*j
		 local hi,lo=get_q_colors(qmap[idx])
			pset(i,j,hi)
		end
	end
	flip()
	while(btn(4)==false) do
	end
	]]
	
	local dump=""
	local run_values={}
	local commit=function()
		if #run_values>0 then
			-- bit layout:
			-- rle
			-- length x7
			-- or:
			-- q
			-- hi/lo
			-- hi/lo
			local s=""
			if #run_values>=2 then
				-- rle mode
				-- set rle bit
				s=s..byte:tostr(bor(0x80,#run_values))
				run_values={run_values[1]}
			end
			-- values
			for i=1,#run_values do
				s=s..byte:tostr(run_values[i])
			end
			dump=dump..s
			run_values={}			
		end
	end
	for idx=0,128*128-1 do
		--if(idx%128==0) log("exporting:"..flr(idx/128).."/127")
		local q=qmap[idx] or 0
		-- hi/lo colors
		local hi,lo=get_q_colors(q or 0)
		q=band(0xf,q)
		if q==1 or q==4 then
			hi,lo=lo,hi
		end
		-- convert to bit
		q=(q==1 or q==4) and 0x40 or 0
		q=bor(q,bor(shl(hi,3),lo))
		-- new run?
		if run_values[1]!=q or #run_values>=127 then
			commit()
		end
		add(run_values,q)
	end
	-- trailing data?
	commit()
	-- number of items + track
	dump=dump..track:tostr()
	-- clipboard
	printh(dump,"@clip")
	log("copied to clipboard")
end


__gfx__
01000000015d6fa70001000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
17100000000000000017100000171000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
17710000000000000017111001777100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
17771000000000000117777117717710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
17711000000000001717777101777100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11171000000000000177777100171000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00010000000000000017771000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000001110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb00000bbb0000080080000eee00000777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
33300000373000000880000088800000777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
33300000377000000880000088800000777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
13100000131000008008000018100000f7f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010000000100000000000000010000000f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000111110000010000000000000000000000000000000000000000000000000000
00011100000111000001100001111110000010000001110000011100001001000101111001111100001000000101101000000000000000000000000000000000
000111000001d1000011110000000000000110000000010000010000000110000111111000000000001100000101101000000000000000000000000000000000
000111000001dd000111111001111110000010000000110000011100000110000100001001111100001110000000000000000000000000000000000000000000
00011100000111000000000000111100000010000000010000000100001001000100001001010100001110000110101000000000000000000000000000000000
00001000000010000111111000011000000111000001110000011100000000000111111000111000001000000110101000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000020404040101010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000020404040201010100000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000010404040202020200000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000020404040201000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000020303030000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000020404040300000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000001010101040404020100000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000102020202040402020100000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000202020303040401010000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000010303040404040301010000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000001010303040404040301010000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000102020404040404040301010000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000020203030404040404040303010000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001020203030304040404040302020000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001020203030304040404040302020100000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001020202030304040404040303030202010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001020202020203040303040303030201000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001010202020203030303040303030101010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000010101010101020303040303020101010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000020202030302020101010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000101020202010101010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000101010101000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b0f2009160c09180b2408301a3222302c2a2e202d14270318041b051f072209250b290f2c142e182f232f27302c2f302e342c332832262f242b24272423241f221d1f1b1c171c141d131b1118151619141b101a0c392f382a3223453c0000000000000000000000000000000000000000000000000000000000000000000000
0000000001010303030404040404040404040404030302010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001020303040404040404040404040404040403030201010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001020303040404040404040404040404040403030101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001020303040404040404040404040404040102020101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000020203040404040404040404040404040101030202020100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000010101040404040404040404040404040304030403030101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000102040404040404040404040404040404040303020201000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001030303040404040404040404040404030202020201000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001020303030404040304040404040404030202020201000000000000000000000201010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001010202020303020304040404040404030202020201000000000000000000010202030202010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001010101010102020204040404040404030202020200000000000000000000010102020303010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000010101010100000102030404030303010101010000000000000000000000010102030302010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000001010101010101000000000000000000000000000000010204040403020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000010101010100000000000000000000000000000000010304040403020201000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000304040403010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000