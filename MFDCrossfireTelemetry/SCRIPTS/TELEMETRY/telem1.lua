-- MyFlyDream <-> TBS Crossfire Telemetry script
-- by Hélio Teixeira <helio.b.teixeira@gmail.com>
--
-- Use at your own risk!
-- Modify and distribute as you want but an attribution would be nice.

local last_time		= 0			--- TEMP for changing speed
local last_state	= 0			--- TEMP for blinking image
local blink_time	= 0			--- TEMP for blinking GPS icon
local volts_time	= 0			--- TEMP for volts average
local avg_volts		= {0,0,0,0,0}	-- TEMP for moving average calc
local avg_up_SNR    = {0,0,0,0,0,0,0,0,0,0}--- TEMP for moving average up_SNR must init with same size as avg_size
local avg_dw_SNR    = {0,0,0,0,0,0,0,0,0,0}--- TEMP for moving average dw_SNR must init with same size as avg_size

local avg_size = 5              -- size of samples for moving average
local height = 12				-- line height including spacing
local max_speed = 40			-- maximum speed (mk/t) in the bar
local max_alt = 500				-- maximum altitude (m) in the bar
local num_rows = 6				-- maximum number of visible rows
local mid_pos = 29				-- position of target value
local alt_padding = 6			-- extra width for the altitude bar
local txt_height = 6			-- height of the text
local curr_speed_offset = -3	-- offset of the current speed to align the text vertically
local num_x_offset = 12			-- additional x offset for numbers, since these are right-aligned
local padding = 2				-- padding between lines and number bar
local box_height = 14			-- height of current speed box
local box_width = 25			-- width of current speed box

local boxW = 70
local boxH = 43
local boxOffX = 151
local boxOffY = 32
local P1X = boxOffX - boxW/2
local P1Y = boxOffY + 0
local P2X = boxOffX + boxW/2
local P2Y = boxOffY + 0
local alphaTransit = math.atan(boxH/boxW)

local attitude = 0
local pitch = 0
local pitchInc = 0.01
local pitchOrAttitude = 0

local headOffX = boxOffX
local headOffY = 63
local headW = boxW

local RX

local heading = 0
local alt = 0
local speed = 0
local percent = 1
local percentInc =1
local dB = -130
local dBInc =1

	--- Uplink:
local RSS1
local RSS2
local RQly
local RSNR
local RFMD
local TPWR
	
	-- Downlink
local TRSS
local TQly
local TSNR
local GPS
local Alt
local Sats
local Ptch
local Roll
local Yaw

local function round(num) 
	if num >= 0 then return math.floor(num+.5) 
	else return math.ceil(num-.5) end
end

function arraySize(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function movAvgArrayPush(array, value, size)
  local sum=0
  for i=2,size do
    array[i-1]=array[i]
    sum=sum+array[i]
  end
  array[size]=value
  sum=sum+value
  return sum/size
end

local function drawCenteredText(x, y, name, attr)
	local textsize=4.9425*string.len(name)
	
	lcd.drawText( x-textsize/2, y, name, attr  )
end

local function drawMode( mode )
	local y = 15
	local x = 0
	local name = "FLIGHT MODE"
	local attr = 0
	
	if mode == 0 then 
		name,attr = "Stabilize", 0
	elseif mode == 1 then 
		name,attr = 89, "Acro", 0
	elseif mode == 2 then
		name,attr = "Altitude hold", 0
	elseif mode == 3 then
		name,attr = "Auto", 0
	elseif mode == 4 then
		name,attr = "Guided", 0
	elseif mode == 5 then
		name,attr = "Loiter", 0
	elseif mode == 6 then
		name,attr = "Return to launch", INVERS+BLINK
	elseif mode == 7 then
		name,attr = "Circle", 0
	elseif mode == 8 then
		name,attr = "Position hold", 0
	elseif mode == 9 then
		name,attr = "Land", INVERS+BLINK
	elseif mode == 10 then
		name,attr = "OF Loiter", 0
	elseif mode == 11 then
		name,attr = "Drift", 0
	elseif mode == 13 then
		name,attr = "Sport", 0
	elseif mode == 14 then
		name,attr = "Flip", BLINK
	elseif mode == 15 then
		name,attr = "Autotune", BLINK
	elseif mode == 16 then
		name,attr = "Position hold", 0
	end
	
	
	
	lcd.drawText(23, 1, name, 0  )
	--drawCenteredText( 100, y, name, 0 + attr  )
	
end

local function drawRSSI(rssi, x, y, minrssi, maxrssi)
	local height = 7
	local count = 7
	lcd.drawFilledRectangle(x,y,2*count+1, height, ERASE)
	lcd.drawRectangle(x,y,2*count+1, height, 0)
	
	-- 100 - count-2
	---rssi- x
	local rssibars = math.max(0,round(((rssi-minrssi)*(count-1)/(maxrssi-minrssi))))
	for i=1,rssibars do
		lcd.drawLine(x+i*2,y+2,x+i*2,y+height-3, SOLID, FORCE)
	end
	
end

local function drawTopBar(rssi, flightmode)

	--lcd.drawFilledRectangle(17, 0, 173, 10, GREY_DEFAULT)
	drawMode(flightmode)
	
	local timer = model.getTimer( 1 )
	lcd.drawTimer( 166, 1, timer.value,1 )
	
	lcd.drawText(120,2,"RSSI: ", SMLSIZE)
	lcd.drawFilledRectangle(17, 0, 173, 9, GREY_DEFAULT)
	drawRSSI(rssi, 145,1, 30, 100)
	--drawMode(flightmode)

end

local function drawArtificalHorizon(roll, pitch)
	local pitchOffset = pitch*boxH/math.pi
	local oriRad = roll
	-- Simplify Angle
	roll = (roll % (2*math.pi)) 
	
	if (roll>3*math.pi/2) then
		roll = roll - 2*math.pi
    elseif (roll>math.pi/2) then
        roll=roll-math.pi
    elseif (roll<-3*math.pi/2) then
        roll=roll+2*math.pi
	elseif (roll<-math.pi/2) then
        roll=roll+math.pi
    end
    
    pitch = (pitch % (2*math.pi))
    pitch = -pitch 					--- Invert angle for horizon
	
	if (pitch>3*math.pi/2) then
		pitch = pitch - 2*math.pi
    elseif (pitch>math.pi/2) then
        pitch=pitch-math.pi
    elseif (pitch<-3*math.pi/2) then
        pitch=pitch+2*math.pi
	elseif (pitch<-math.pi/2) then
        pitch=pitch+math.pi
    end
    
    local pitchOffset = pitch*boxH/math.pi
    
    if (math.abs(roll)==math.pi/2)
    then
        P1X = 0
        P1Y = -boxH/2
		P2X = 0
        P2Y = boxH/2
    else
    	local absRadians=math.abs(roll)
		
		if(roll>0) then
			-- P1 Calculations
			P1X = -boxW/2
			P1Y = math.tan(absRadians)*P1X + pitchOffset
		
			if (P1Y<-boxH/2) then
				-- Recalculate P1:
				P1Y = -boxH/2
				P1X = (P1Y - pitchOffset)/math.tan(absRadians)
			end
			
			-- P2 Calculations
			P2X = boxW/2
			P2Y = math.tan(absRadians)*P2X + pitchOffset
			
			if (P2Y>boxH/2) then
				-- Recalculate P1:
				P2Y = boxH/2
				P2X = (P2Y - pitchOffset)/math.tan(absRadians)
			end
			
			--lcd.drawText( boxOffX, boxOffY, math.floor(math.deg(pitch)), SMLSIZE )
			
			lcd.drawLine( P1X+boxOffX,  -P1Y+boxOffY,  P2X+boxOffX,  -P2Y+boxOffY, SOLID, 0 )
			--lcd.drawLine( P1X+boxOffX,  P1Y+boxOffY,  P2X+boxOffX,  P2Y+boxOffY, SOLID, 0 )
		else -- roll<0
			-- P1 Calculations
			P1X = -boxW/2
			P1Y = math.tan(-absRadians)*P1X + pitchOffset
		
			if (P1Y>boxH/2) then
				-- Recalculate P1:
				P1Y = boxH/2
				P1X = (P1Y - pitchOffset)/math.tan(-absRadians)
			end
			
			-- P2 Calculations
			P2X = boxW/2
			P2Y = math.tan(-absRadians)*P2X + pitchOffset
			
			if (P2Y<-boxH/2) then
				-- Recalculate P1:
				P2Y = -boxH/2
				P2X = (P2Y - pitchOffset)/math.tan(-absRadians)
			end
			
			lcd.drawLine( P1X+boxOffX,  -P1Y+boxOffY,  P2X+boxOffX,  -P2Y+boxOffY, SOLID, 0 )
			
		end
		
		
    end

	local crossW = 15
	local crossH = 5
	local crossV = 4
	
	-- Draw center align cross
	lcd.drawPoint(boxOffX, boxOffY)
	lcd.drawLine(boxOffX-crossW/2, boxOffY, math.floor(boxOffX-crossV)-1, boxOffY, SOLID, FORCE )
	lcd.drawLine(math.floor(boxOffX-crossV), boxOffY, boxOffX, boxOffY+crossV, SOLID, FORCE )
	lcd.drawLine(boxOffX, boxOffY+crossV, math.floor(boxOffX+crossV), boxOffY, SOLID, FORCE )
	lcd.drawLine(boxOffX+crossW/2, boxOffY, math.floor(boxOffX+crossV)+1, boxOffY, SOLID, FORCE )
	
	-- Draw horizonal dotted lines
	lcd.drawLine(boxOffX-boxW/2, boxOffY, boxOffX-crossW/2, boxOffY, DOTTED, FORCE)
	lcd.drawLine(boxOffX+boxW/2, boxOffY, boxOffX+crossW/2, boxOffY, DOTTED, FORCE)
	
	
	lcd.drawRectangle(boxOffX-boxW/2, boxOffY-boxH/2, boxW+1, boxH+1) -- Need to inc 1px due to roundings...i guess
	--lcd.drawText( boxOffX-boxW/2, boxOffY+boxH/2-7, math.floor(math.deg(oriRad)) , SMLSIZE )
	--lcd.drawText( boxOffX-boxW/2, boxOffY+boxH/2,math.floor(math.deg(pitch)) , SMLSIZE )
	
end

local function drawHorizonLine(rolls, pitch)
	local deltaX = 0
	local deltaY = 0
	local truncDeltaX = 0
	local truncDeltaY = 0
	
    roll = (roll % (2*math.pi))
	
	if (roll>3*math.pi/2) then
		roll = roll - 2*math.pi
    elseif (roll>math.pi/2) then
        roll=roll-math.pi
    elseif (roll<-3*math.pi/2) then
        roll=roll+2*math.pi
	elseif (roll<-math.pi/2) then
        roll=roll+math.pi
    end
    
    pitch = (pitch % (2*math.pi))
    
    if (pitch>3*math.pi/2) then
		pitch = pitch - 2*math.pi
    elseif (pitch>math.pi/2) then
        pitch=pitch-math.pi
    elseif (pitch<-3*math.pi/2) then
        pitch=pitch+2*math.pi
	elseif (pitch<-math.pi/2) then
        pitch=pitch+math.pi
    end
    
    local pitchOffset = pitch*boxH/math.pi --scale to box height
    
    if (math.abs(roll)==math.pi/2)
    then
        deltaX = 0
		deltaY = boxH/2
    else
		deltaX = boxW/2
		deltaY = math.abs(math.tan(roll)*(boxW/2))
    end
	
	if ( math.abs(deltaY) - boxH/2 > 0) then -- Line exceeds box	
		-- Line Y Length beyond box
		truncDeltaY = math.abs(deltaY) - boxH/2
		truncDeltaX = math.abs(truncDeltaY/math.tan(roll))
	end
	
	deltaX = deltaX-truncDeltaX
	deltaY = deltaY-truncDeltaY

	if(roll>0) then
		P1X = boxOffX - deltaX
		P1Y = boxOffY + deltaY
		P2X = boxOffX + deltaX
		P2Y = boxOffY - deltaY
	else
		P1X = boxOffX - deltaX
		P1Y = boxOffY - deltaY
		P2X = boxOffX + deltaX
		P2Y = boxOffY + deltaY
	end

    --print("Alpha Trans:", math.deg(alphaTransit) )
    lcd.drawLine( math.floor(P1X),  math.floor(P1Y),  math.floor(P2X),  math.floor(P2Y), SOLID, 0 )
	--lcd.drawText( boxOffX, boxOffY, deltaX, SMLSIZE )
	--lcd.drawText( boxOffX, boxOffY+10, deltaY, SMLSIZE )
end

-- Draw heading indicator
-- **********************
local parmHeading = {
  {0, 2, "N"}, {30, 5}, {60, 5},
  {90, 2, "E"}, {120, 5}, {150, 5},
  {180, 2, "S"}, {210, 5}, {240, 5},
  {270, 2, "O"}, {300, 5}, {330, 5}
}

local wrkHeading = 0

local function drawHeading(heading)
	
	local colHeading = headOffX
	local rowHeading = headOffY
	--local rowDistance = rowAH + radAH + 3
	
	lcd.drawLine(colHeading - headW/2, rowHeading, colHeading + headW/2, rowHeading, SOLID, FORCE)
	for index, point in pairs(parmHeading) do
		wrkHeading = point[1] - math.deg(heading)
		if wrkHeading > 180 then wrkHeading = wrkHeading - 360 end
		if wrkHeading < -180 then wrkHeading = wrkHeading + 360 end
		delatX = math.floor(wrkHeading / 3.3 + 0.5) - 1

		if delatX >= -headW/2+2 and delatX <= headW/2-2 then
			if point[3] then
				lcd.drawText(colHeading + delatX - 1, rowHeading - 8, point[3], SMLSIZE + BOLD)
			end
			if point[2] > 0 then
				lcd.drawLine(colHeading + delatX, rowHeading - point[2], colHeading + delatX, rowHeading, SOLID, FORCE)
			end
		end
	end
	lcd.drawFilledRectangle(colHeading - headW/2, rowHeading - 9, 3, 10, ERASE)
	lcd.drawFilledRectangle(colHeading + headW/2-2, rowHeading - 9, 3, 10, ERASE)

  --deltaX = (distance_3D < 10 and 6) or (distance_3D < 100 and 8 or (distance_3D < 1000 and 10 or 12))
  --lcd.drawNumber(colHeading - deltaX, rowDistance , distance_3D, LEFT+SMLSIZE)
  --lcd.drawNumber(60, 60, heading, SMLSIZE)

end

local function drawSpeed( speed )

	speed = speed/10
	-- left and right lines
	local right_edge = num_x_offset + 2 * padding
	lcd.drawLine( right_edge, 0, right_edge, 63, SOLID, 0 )

	-- limit speed to min/max
	local limited_speed = speed
	if limited_speed > max_speed+1 then
		limited_speed = max_speed+1
	end
	if limited_speed < -1 then
		limited_speed = -1	
	end
	
	local rounded_speed = math.floor( limited_speed + 0.5 )
	local topnum = rounded_speed + num_rows/2
	local topnum_pos = mid_pos - (topnum-limited_speed) * height - txt_height/2

	for s=0,num_rows do
		local current_num = topnum-s
		if current_num <= max_speed and current_num >= 0 then
			lcd.drawNumber( num_x_offset + padding, s*height + topnum_pos, topnum-s, SMLSIZE+RIGHT )
		end
		
		-- draw + or - to indicate above/below max/min limits
		if current_num == max_speed+1 and speed > max_speed then
			lcd.drawText( padding, s*height + topnum_pos, "++", SMLSIZE )
		end
		if current_num == -1 and speed  < 0 then
			lcd.drawText( padding, s*height + topnum_pos, "--", SMLSIZE )
		end
	end
	
	-- Draw box and display current speed (unrounded)
	lcd.drawPixmap( -2, mid_pos - box_height/2, "/SCRIPTS/BMP/spd_boxXL.bmp" )
	lcd.drawNumber( 0 + box_width - 2 * padding-7, mid_pos + curr_speed_offset, round(speed), 0+RIGHT )
	
	-- Draw legend text
	--lcd.drawText( right_edge + 16, mid_pos + curr_speed_offset, "SPD", 0 )
	--lcd.drawText( right_edge + padding, 56, "Spd", SMLSIZE)
	lcd.drawText( 1, 35, "Km/h", SMLSIZE)
end

local function drawAlt( altitude )
	-- left and right lines
	altitude = altitude/10
	local left_edge = 212 - (num_x_offset + 2 * padding) - alt_padding
	lcd.drawLine( left_edge, 0, left_edge, 63, SOLID, 0 )


	-- limit to min/max
	local limited_alt = altitude
	if limited_alt > max_alt+1 then
		limited_alt = max_alt+1
	end
	if limited_alt < -1 then
		limited_alt = -1	
	end
	
	local rounded_alt = math.floor( limited_alt + 0.5 )
	local topnum = rounded_alt + num_rows/2
	local topnum_pos = mid_pos - (topnum-limited_alt) * height - txt_height/2

	for s=0,num_rows do
		local current_num = topnum-s
		if current_num <= max_alt and current_num >= 0 then
			lcd.drawNumber( 212 - padding, s*height + topnum_pos, topnum-s, SMLSIZE+RIGHT )
		end
		
		-- draw + or - to indicate above/below max/min limits
		if current_num == max_alt+1 and altitude > max_alt then
			lcd.drawText( 212 - num_x_offset - padding, s*height + topnum_pos, "++", SMLSIZE )
		end
		if current_num == -1 and altitude  < 0 then
			lcd.drawText( 212 - num_x_offset - padding, s*height + topnum_pos, "--", SMLSIZE )
		end
	end
	
	-- Draw box and display current speed (unrounded)
	lcd.drawPixmap( 188, mid_pos - box_height/2, "/SCRIPTS/BMP/alt_box.bmp" )
	lcd.drawNumber( 212 - padding, mid_pos + curr_speed_offset, round(altitude), 0+RIGHT )

	-- Draw legend text
	--lcd.drawText( left_edge - 14, 56, "Alt", SMLSIZE)
	lcd.drawText( left_edge +16 , 35, "m", SMLSIZE)
end

local function drawSats( value )
	-- Sats and fix type are stored in T2 as sats*10
	local sats = value / 10
	local fixtype = value % 10
	local left_edge = 212 - (num_x_offset + 2 * padding) - alt_padding
	if fixtype ~= 3 then
		-- If not 3D fix, blink image
		time = getTime()
		if time > blink_time + 60 then
			blink_time = time
			if last_state == 0 then
				last_state = 1
			else 
				last_state = 0
			end
		end
	else
		last_state = 1
	end
	if last_state == 0 then
		lcd.drawPixmap( left_edge - 55, 16, "/SCRIPTS/BMP/3d_off.bmp" )
	else 
		lcd.drawPixmap( left_edge - 55, 16, "/SCRIPTS/BMP/3d.bmp" )
	end

	--lcd.drawText( left_edge - 22 , 42, "Sats", mode + SMLSIZE )
	lcd.drawNumber( left_edge - 55, 17, sats, SMLSIZE  )
end					

local function drawHeading_( heading )
	lcd.drawPixmap( 72, 30, "/SCRIPTS/BMP/hdg_circ.bmp" )
	
	local r = 35
	local x,y = 106,59
	
	-- Convert compass direction to unit circle degrees (reverse direction and 90° CW offset)
	local offset_dir = ((heading) + 90) % 360
	
	local dir_N = offset_dir/180 * math.pi
	-- NB: E, S, W offsets are - instead of plus because the direction has already been reversed
	local dir_NNE = ((offset_dir - 22.5) % 360)/180 * math.pi
	local dir_NE = ((offset_dir - 45) % 360)/180 * math.pi
	local dir_ENE = ((offset_dir - 67.5) % 360)/180 * math.pi
	local dir_E = ((offset_dir - 90) % 360)/180 * math.pi
	local dir_ESE = ((offset_dir - 112.5) % 360)/180 * math.pi
	local dir_SE = ((offset_dir - 135) % 360)/180 * math.pi
	local dir_SSE = ((offset_dir - 157.5) % 360)/180 * math.pi
	local dir_S = ((offset_dir - 180) % 360)/180 * math.pi
	local dir_SSW = ((offset_dir - 202.5) % 360)/180 * math.pi
	local dir_SW = ((offset_dir - 225) % 360)/180 * math.pi
	local dir_WSW = ((offset_dir - 247.5) % 360)/180 * math.pi
	local dir_W = ((offset_dir - 270) % 360)/180 * math.pi
	local dir_WNW = ((offset_dir - 292.5) % 360)/180 * math.pi
	local dir_NW = ((offset_dir - 315) % 360)/180 * math.pi
	local dir_NNW = ((offset_dir - 337.5) % 360)/180 * math.pi
	
	-- Draw compass points
	local dx = math.cos( dir_N ) * r
	local dy = math.sin( dir_N ) * r
	lcd.drawText( x-2+dx, y-2-dy, "N", SMLSIZE )

	dx = math.cos( dir_E ) * r
	dy = math.sin( dir_E ) * r
	lcd.drawText( x-2+dx, y-2-dy, "E", SMLSIZE )

	dx = math.cos( dir_S ) * r
	dy = math.sin( dir_S ) * r
	lcd.drawText( x-2+dx, y-2-dy, "S", SMLSIZE )

	dx = math.cos( dir_W ) * r
	dy = math.sin( dir_W ) * r
	lcd.drawText( x-2+dx, y-2-dy, "W", SMLSIZE )
	
	-- Points at half-direction directions
	dx = math.cos( dir_NNE ) * r
	dy = math.sin( dir_NNE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_NE ) * r
	dy = math.sin( dir_NE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_ENE ) * r
	dy = math.sin( dir_ENE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_ESE ) * r
	dy = math.sin( dir_ESE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_SE ) * r
	dy = math.sin( dir_SE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_SSE ) * r
	dy = math.sin( dir_SSE ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_SSW ) * r
	dy = math.sin( dir_SSW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_SW ) * r
	dy = math.sin( dir_SW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_WSW ) * r
	dy = math.sin( dir_WSW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_WNW ) * r
	dy = math.sin( dir_WNW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_NW ) * r
	dy = math.sin( dir_NW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	dx = math.cos( dir_NNW ) * r
	dy = math.sin( dir_NNW ) * r
	lcd.drawPoint( x+dx, y-dy )
	
	-- Heading line
	lcd.drawLine( x, 52, x, 32, DOTTED, 0 )
	
	-- Box
	lcd.drawLine( 92, 64, 92, 52, SOLID, 0 )
	lcd.drawLine( 120, 64, 120, 52, SOLID, 0 )
	lcd.drawLine( 92, 52, 120, 52, SOLID, 0 )
	
	-- Heading
	lcd.drawNumber( 114, 56, heading, 0 )
end

local function drawBattery( volts, amps, percent )
    local right_edge = num_x_offset + 2 * padding
	local time = getTime()
	
	if time > volts_time + 40 then
		volts_time = time
		avg_volts[1] = avg_volts[2]
		avg_volts[2] = avg_volts[3]
		avg_volts[3] = avg_volts[4]
		avg_volts[4] = avg_volts[5]
		avg_volts[5] = volts
	end
	
	volts = ((avg_volts[1] + avg_volts[2] + avg_volts[3] + avg_volts[4] + avg_volts[5])/5)
	
	-- Voltage
	lcd.drawNumber( right_edge + 48, 18, volts, SMLSIZE + PREC1 )
	lcd.drawText( right_edge + 48, 18, "V", SMLSIZE )

	-- Amperage
	lcd.drawNumber( right_edge + 48, 28, amps, SMLSIZE + PREC1 )
	lcd.drawText( right_edge + 48, 28, "A", SMLSIZE )
	
	local cells = 1

	if volts >= 6.4 and volts <= 9.4 then
		cells = 2
	elseif volts >= 9.5 and volts <= 12.6 then
		cells = 3
	elseif volts >= 12.7 and volts <= 16.8 then
		cells = 4
	elseif volts >= 16.9 and volts <= 21 then
		cells = 5
	elseif volts >= 21.1 and volts <= 26 then
		cells = 6
	end

	lcd.drawPixmap( right_edge + 16, 13, "/SCRIPTS/BMP/bat_"..math.ceil(percent*0.1)..".bmp" )
	lcd.drawNumber( right_edge + 27, 48, percent, SMLSIZE )
	lcd.drawText( right_edge + 27, 48, "%", SMLSIZE )
	
end

local function drawRSSI_ (rssi)
	
	if rssi < 20 then
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_0.bmp" )
	elseif rssi < 30 then
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_1.bmp" )
	elseif rssi < 45 then
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_2.bmp" )
	elseif rssi < 65 then
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_3.bmp" )
	elseif rssi < 80 then
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_4.bmp" )
	else
		lcd.drawPixmap( 155, 15, "/SCRIPTS/BMP/rssi_5.bmp" )
	end
	
	lcd.drawText( 163, 50, rssi, SMLSIZE )

end

local function drawXFTelemetry(offX, offY, UP_RSS1dB, UP_RSS2dB, UP_LQ, UP_SNR, DW_TRSS, DW_LQ, DW_SNR, CM_TPWR, CM_RFMD)
	-- RSS min: -130dB bad , max: -1dB Good
	
	local RSSmin = -130
	local RSSmax = -1
	
	-- Labels
	lcd.drawText(offX+3, offY, "RSSI", SMLSIZE)
	lcd.drawText(offX+31, offY, "Qly", SMLSIZE)
	lcd.drawPixmap(offX+60, offY, "/SCRIPTS/BMP/noise.bmp" )

	-- Uplink
	lcd.drawPixmap( offX+79, offY+12, "/SCRIPTS/BMP/uparrow.bmp" )
	
	local RSS1Prop = round((UP_RSS1dB-RSSmin)*100/(RSSmax-RSSmin))
	local RSS2Prop = round((UP_RSS2dB-RSSmin)*100/(RSSmax-RSSmin))
	--lcd.drawNumber(25, 20, RSS1Prop, SMLSIZE)
	lcd.drawGauge(offX+8, offY+8, 15, 7, RSS1Prop, 110) -- Using 110 as maxfill since 100 overfills gauge (bug?)
	lcd.drawGauge(offX+8, offY+16, 15, 7, RSS2Prop, 110) -- Using 110 as maxfill since 100 overfills gauge (bug?)

	lcd.drawPixmap( offX, offY+8, "/SCRIPTS/BMP/ant_1.bmp" )
	lcd.drawPixmap( offX, offY+16, "/SCRIPTS/BMP/ant_2.bmp" )
	
	--lcd.drawText(offX+30, offY, "Qly:", SMLSIZE)
	lcd.drawNumber(offX+43, offY+12, UP_LQ, SMLSIZE+RIGHT)
	lcd.drawText(offX+43, offY+12, "%", SMLSIZE)
	
	lcd.drawNumber(offX+68, offY+12, UP_SNR, SMLSIZE+RIGHT)
	lcd.drawText(offX+68, offY+12, "dB", SMLSIZE)
	
	-- Downlink
	lcd.drawPixmap( offX+79, offY+26, "/SCRIPTS/BMP/downarrow.bmp" )
	
	local TRSSProp = round((DW_TRSS-RSSmin)*100/(RSSmax-RSSmin))
	--lcd.drawNumber(25, 20, RSS1Prop, SMLSIZE)
	lcd.drawGauge(offX+8, offY+26, 15, 7, TRSSProp, 110) -- Using 110 as maxfill since 100 overfills gauge (bug?)
	lcd.drawPixmap( offX, offY+26, "/SCRIPTS/BMP/ant.bmp" )
	
	lcd.drawNumber(offX+43, offY+26, DW_LQ, SMLSIZE+RIGHT)
	lcd.drawText(offX+43, offY+26, "%", SMLSIZE)
	
	lcd.drawNumber(offX+68, offY+26, DW_SNR, SMLSIZE+RIGHT)
	lcd.drawText(offX+68, offY+26, "dB", SMLSIZE)
	
	-- Bars
	lcd.drawFilledRectangle(offX-1, offY+7, 88, 17, GREY_DEFAULT)
	lcd.drawFilledRectangle(offX-1, offY+25, 88, 9, GREY_DEFAULT)
	
	-- CommonLink
	lcd.drawPixmap( offX-5, offY+40, "/SCRIPTS/BMP/power.bmp" )
	lcd.drawNumber(offX+21, offY+40, CM_TPWR, SMLSIZE+RIGHT)
	lcd.drawText(offX+21, offY+40, "mW", SMLSIZE)
	
	lcd.drawRectangle(offX+39, offY+38, 40, 10)
	
	--lcd.drawFilledRectangle(offX+40, offY+39, 14, 8, GREY_DEFAULT)
	lcd.drawText(offX+44, offY+40, "H", SMLSIZE)
	lcd.drawText(offX+57, offY+40, "N", SMLSIZE)
	lcd.drawText(offX+70, offY+40, "L", SMLSIZE)
	if(CM_RFMD==2)then
		lcd.drawFilledRectangle(offX+40, offY+39, 12, 8, GREY_DEFAULT)
	elseif(CM_RFMD==1)then
		lcd.drawFilledRectangle(offX+52, offY+39, 13, 8, GREY_DEFAULT)
	elseif(CM_RFMD==0) then
		lcd.drawFilledRectangle(offX+65, offY+39, 13, 8, GREY_DEFAULT)
	end
end



local function run( event )
	
	-- Read telemetry values
	--- Uplink:
	RSS1 = getValue( "1RSS" ) -- Antenna 1 Signal Strength (dB)
	RSS2 = getValue( "2RSS" ) -- Antenna 2 Signal Strength (dB)
	RQly = getValue( "RQly" ) -- RX Link Quality (0-300%)
	RSNR = movAvgArrayPush(avg_up_SNR, getValue( "RSNR" ), avg_size) -- Rx SNR  (dB)
	
	
	--- Downlink
	TRSS = getValue( "TRSS" ) -- Downlink Radio Signal Strength (dB)
	TQly = getValue( "TQly" ) -- Downlink Link Quality (0-300%)
	TSNR = movAvgArrayPush(avg_dw_SNR, getValue( "TSNR" ), avg_size) -- TX SNR (dB)
	
	--- Commonlink
	RFMD = getValue( "RFMD" ) -- RF profile (2-HighUpdate; 1-NormalUpdate; 0-LowUpdate)
	TPWR = getValue( "TPWR" ) -- Transmitter Power (0-2000mW)
	
	-- MyFlyDream
	GPS  = getValue( "GPS" )  -- GPS Coordinates (0¼00'E 0¼00'N)
	Alt  = getValue( "Alt" )  -- Altitude (m)
	Sats = getValue( "Sats" ) -- # of Satellites
	Ptch = getValue( "Ptch" ) -- Pitch angle of MFD (0-?rad)
	Roll = getValue( "Roll" ) -- Roll angle of MFD (0-?rad)
	Yaw  = getValue( "Yaw" )  -- Yaw angle of MFD (relative to north) (0-?rad)
	speed = 0 -- TODO
	
	-- Others
	local rssi = getValue( "RSSI" )
	
	
	--local voltage = getValue( "VFAS" )
	--local amps = getValue( "Curr" )
	--local pct = getValue( "Fuel" )
	--local speed = getValue( "GSpd" )
	
	--local alt = getValue( "Alt" )
	
	--local sats_and_fix = getValue( "Tmp2" )
	--local mode = getValue( "Tmp1" )
	
	
	
	--[[ DEBUG 
	local mode = -1
	speed = speed + 0.1
	alt = alt + 0.5
	attitude = attitude + 0.01
	heading = heading - 0.005
	
	if (pitch>math.pi/2) then
		pitchInc=-0.03
	end
	if (pitch<-math.pi/2) then
		pitchInc =0.03
	end
	
	if (percent>=100) then
		percentInc=-1
	end
	if (percent<=0) then
		percentInc =1
	end
	
	if (dB>=-1) then
		dBInc=-1
	end
	if (dB<=-130) then
		dBInc =1
	end
	
	pitch = pitch +pitchInc
	
	percent=percent+percentInc
	rssi=percent
	RQly=percent
	TQly=percent
	
	dB=dB+dBInc
	RSS1=dB
	RSS2=dB
	RSNR=dB
	TRSS=dB
	TSNR=dB
	
	if (dB>-20)then
		RFMD=2
		TPWR=10
	elseif(dB>-60)then
		RFMD=1
		TPWR=500
	else
		RFMD=0
		TPWR=2000
	end
	
	]]--
	
	lcd.clear()
	
	drawTopBar(rssi, mode) --RSSI fica a zero??? qual RSSI?
	drawSpeed(speed)
	drawAlt( Alt )
	drawArtificalHorizon( Roll, Ptch )
	drawHeading(Yaw)
	drawXFTelemetry(27,12, RSS1, RSS2, RQly, RSNR, TRSS, TQly, TSNR, TPWR, RFMD) -- dB estao mt rapido...media movel
	--drawSats( sats_and_fix )
	--drawBattery ( voltage, amps, pct )
	--drawMode( mode )
	--drawHeading_( hdg )
	--drawRSSI ( rssi )
end

return { run=run }
