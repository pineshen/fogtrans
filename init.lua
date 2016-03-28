local _M = {}
local bit = require "bit"
local crc16 = require "crc16"
local cjson = require "cjson.safe"
local Json = cjson.encode

local insert = table.insert
local concat = table.concat

local strbyte = string.byte
local strchar = string.char

local cmds = {
    [0x00] = {[0]="READ",    			[1]=0,					[2]=0,				[3]=0,					[4]=0,					[5]=0},
    [0x01] = {[0]="STOP;DELAY=0000",	[1]="START;DELAY=0000", [2]=0, 				[3]=0,					[4]=0, 					[5]=1},
	[0x02] = {[0]="SLEEP;OPEN=0",		[1]="SLEEP;OPEN=1", 	[2]=0, 				[3]=0,					[4]=0, 					[5]=2},
    [0x03] = {[0]="XINFEN;OPEN=0",     	[1]="XINFEN;OPEN=1", 	[2]=0,				[3]=0,					[4]=0,					[5]=3},
    [0x04] = {[0]="AUTO;OPEN=0",		[1]="AUTO;OPEN=1",		[2]=0,				[3]=0,					[4]=0,					[5]=4},
    [0x05] = {[0]="DJIAREN;OPEN=0",		[1]="DJIAREN;OPEN=1",	[2]=0,				[3]=0,					[4]=0,					[5]=5},
    [0x06] = {							[1]="FJSET;LEVEL=1",	[2]="FJSET;LEVEL=2",[3]="FJSET;LEVEL=3",	[4]="FJSET;LEVEL=4",	[5]=6},
    [0x07] = {"START;DELAY=",0,0,0,7},
    [0x08] = {"STOP;DELAY=", 0,0,0,8},
--	[0x09] = {"SLEEP;DELAY=", 0,0,9},
}

--~ local r_cmds = {
--~     ["read"]       	= cmds[0x00],--读取状态
--~     ["power"]      	= cmds[0x01],--设备开关
--~ 	["sleep"]		= cmds[0x02],--睡眠
--~     ["xinf"]     	= cmds[0x03],--新风
--~     ["auto"]       	= cmds[0x04],--自动
--~     ["djiaren"]    	= cmds[0x05],--电加热
--~     ["fjset"]      	= cmds[0x06],--风机档位
--~     ["timing-on"]  	= cmds[0x07],--延时启动
--~     ["timing-off"] 	= cmds[0x08],--延时关闭
--~ 	["timing-sleep"]= cmds[0x09],--延时睡眠
--~ }

local r_cmds = {
    ["read"]       	= {[0]="READ",    			[1]=0,					[2]=0,				[3]=0,	[4]=0,	[5]=0},
    ["power"]      	= {[0]="STOP;DELAY=0000",	[1]="START;DELAY=0000", [2]=0, 				[3]=0,	[4]=0, 	[5]=1},
	["sleep"]		= {[0]="SLEEP;OPEN=1",		[1]="SLEEP;OPEN=0", 	[2]=0, 				[3]=0,	[4]=0, 	[5]=2},
    ["xinf"]     	= {[0]="XINFEN;OPEN=0",     [1]="XINFEN;OPEN=1",	[2]=0,				[3]=0,	[4]=0,	[5]=3},
    ["auto"]       	= {[0]="AUTO;OPEN=0",		[1]="AUTO;OPEN=1",		[2]=0,				[3]=0,	[4]=0,	[5]=4},
    ["djiaren"]    	= {[0]="JIARE;OPEN=0",		[1]="JIARE;OPEN=1",		[2]=0,				[3]=0,	[4]=0,	[5]=5},
    ["fjset"]      	= {[1]="FJSET;LEVEL=1",		[2]="FJSET;LEVEL=2",	[3]="FJSET;LEVEL=3",[4]="FJSET;LEVEL=4",	[5]=6},
	["uv"]      	= {[0]="UV;OPEN=0",			[1]="UV;OPEN=1",		[2]=0,				[3]=0,	[4]=0,	[5]=7},
    ["timing-on"]  	= {"START;DELAY=",			0,						0,					0,					8},
    ["timing-off"] 	= {"STOP;DELAY=", 			0,						0,					0,					9},
--	["timing-sleep"]= {"SLEEP;DELAY=", 			0,						0,					9},
}

local limit_value = {
    ["PM25"]       	= {"0",		"999"	},
    ["PMJB"]      	= {"0",		"9"		},
	["CO2"]			= {"0",		"9999"	},
    ["CO2JB"]     	= {"0",		"9"		},
    ["WD1"]       	= {"-99",	"+99"	},
    ["WD2"]    		= {"-99",	"+99"	},
    ["FJ"]      	= {"1",		"4"		},
    ["XINF"]  		= {"0",		"1"		},
    ["JIARE"] 		= {"0",		"1"		},
	["POWER"]		= {"0",		"1"		},
	["SLEEP"]      	= {"0",		"1"		},
    ["AUTO"]  		= {"0",		"1"		},
    ["UV"]  		= {"0",		"1"		},
}

function string.fromhex(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

function string.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end

function math.mod(num, div)
    return math.floor(num/div), math.fmod(num,div)
end

local function printx(x)
  print("0x"..bit.tohex(x))
end

bit.range = function (number, i, j)
    local res = ''
    for v = i, j do
        res = bit.get(number, v) .. res
    end
    return res
end

bit.get = function (number, i)
    return (bit.band(number, 2^i) == 0 and 0) or 1
end

local function _pack(cmd, data, msg_id)
    local packet = {}
    local cmd = r_cmds[cmd]
	local minutes = 0;
    if cmd == nil then
        error("cmd error: [".. cmd .."] is not existed!")
    end
    if cmd[5] <= 7 then
 		insert(packet, "CMD=")
		insert(packet, cmd[tonumber(data)])
	else
		insert(packet, "CMD=")
		insert(packet, cmd[1])
		minutes = tonumber(string.sub(data,1,2))*60 + tonumber(string.sub(data,3,4))
		insert(packet, string.format("%04d",minutes))
	end
	insert(packet,string.char(0x0D))
	insert(packet,string.char(0x0A))
    return concat(packet, "")
end

local function _unpack(data)
    local packet = {}
    local cmd_i  = strbyte(data, 4)

    packet['cmd'] = cmds[cmd_i][2]
    packet['value'] = tonumber(string.tohex(string.sub(data, 5, 6)), 16)
    return packet
end

function _M.encode(payload)
    local obj, err = cjson.decode(payload)
    if obj == nil then
        error("json_decode error:"..err)
    end
    for cmd, data in pairs(obj) do
        return _pack(cmd, data)
    end
end

function _M.decode(payload)
	local packet = {}
	if string.match(payload,"CMD=READ;") == "CMD=READ;" then
		local i,j = string.find(payload,"CMD=READ;")
		payload = string.sub(payload,j+1)
		for k,v in string.gmatch(payload, "(%w+)=([+-]?%w+)") do
			if( tonumber(v) < tonumber(limit_value[k][1]) ) then
				v = limit_value[k][1]
			end
			if(tonumber(v) > tonumber(limit_value[k][2]) ) then
				v = limit_value[k][2]
			end
			packet[string.lower(k)] = v
		end
	end
	return Json(packet)
end

return _M
