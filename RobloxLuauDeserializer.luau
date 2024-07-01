-- // Environment changes in the VM are not supposed to alter the behaviour of the VM so we localise globals beforehand
local type = type
local pcall = pcall
local error = error
local tonumber = tonumber
local assert = assert
local setmetatable = setmetatable

local string_format = string.format

local table_move = table.move
local table_pack = table.pack
local table_unpack = table.unpack
local table_create = table.create
local table_insert = table.insert
local table_remove = table.remove

local coroutine_create = coroutine.create
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local coroutine_close = coroutine.close

local buffer_fromstring = buffer.fromstring
local buffer_len = buffer.len
local buffer_readu8 = buffer.readu8
local buffer_readu32 = buffer.readu32
local buffer_readstring = buffer.readstring
local buffer_readf32 = buffer.readf32
local buffer_readf64 = buffer.readf64

local bit32_bor = bit32.bor
local bit32_band = bit32.band
local bit32_btest = bit32.btest
local bit32_rshift = bit32.rshift
local bit32_lshift = bit32.lshift
local bit32_extract = bit32.extract

local ttisnumber = function(v) return type(v) == "number" end
local ttisstring = function(v) return type(v) == "string" end
local ttisboolean = function(v) return type(v) == "boolean" end
local ttisfunction = function(v) return type(v) == "function" end

-- // opList contains information about the instruction, each instruction is defined in this format:
-- // {OP_NAME, OP_MODE, K_MODE, HAS_AUX}
-- // OP_MODE specifies what type of registers the instruction uses if any
--		0 = NONE
--		1 = A
--		2 = AB
--		3 = ABC
--		4 = AD
--		5 = AE
-- // K_MODE specifies if the instruction has a register that holds a constant table index, which will be directly converted to the constant in the 2nd pass
--		0 = NONE
--		1 = AUX
--		2 = C
--		3 = D
--		4 = AUX import
--		5 = AUX boolean low 1 bit
--		6 = AUX number low 24 bits
-- // HAS_AUX boolean specifies whether the instruction is followed up with an AUX word, which may be used to execute the instruction.

local opList = {
	[164] = { "PREPVARARGS", 1, 0, false },
	[222] = { "GETVARARGS", 2, 0, false },
	[131] = { "RETURN", 2, 0, false },
	[218] = { "NEWCLOSURE", 4, 0, false },
	[54] = { "GETGLOBAL", 1, 1, true },
	[160] = { "CALL", 3, 0, false },
	[112] = { "LOADK", 4, 3, false },
	[141] = { "LOADN", 4, 0, false },
	[169] = { "FORNPREP", 4, 0, false },
	[140] = { "FORNLOOP", 4, 0, false },
	[256] = { "NEWTABLE", 2, 0, true },
	[29] = { "LENGTH", 2, 0, false },
	[15] = { "JUMPIFNOT", 4, 0, false },
	[252] = { "GETUPVAL", 2, 0, false },
	[83] = { "MOVE", 2, 0, false },
	[107] = { "SETTABLE", 3, 0, false },
	[19] = { "CAPTURE", 2, 0, false },
	[49] = { "SETTABLEKS", 3, 1, true },
	[242] = { "JUMPIFEQ", 4, 0, true },
	[208] = { "MOD", 3, 0, false },
	[136] = { "GETTABLE", 3, 0, false },
	[10] = { "MUL", 3, 0, false },
	[68] = { "ADD", 3, 0, false },
	[39] = { "SUB", 3, 0, false },
	[237] = { "DIV", 3, 0, false },
	[73] = { "JUMPBACK", 4, 0, false },
	[179] = { "POW", 3, 0, false },
	[78] = { "GETTABLEKS", 3, 1, true },
	[44] = { "JUMPIF", 4, 0, false },
	[199] = { "LOADNIL", 1, 0, false },
	[58] = { "MINUS", 2, 0, false },
	[97] = { "JUMPIFNOTLT", 4, 0, true },
	[184] = { "JUMPIFLT", 4, 0, true },
	[116] = { "CONCAT", 3, 0, false },
	[170] = { "LOADB", 3, 0, false },
	[198] = { "SETLIST", 3, 0, true },
	[155] = { "JUMPIFNOTEQ", 4, 0, true },
	[189] = { "NAMECALL", 3, 1, true },
	[101] = { "FORGPREP", 4, 0, false },
	[111] = { "FORGLOOP", 4, 8, true },
	[102] = { "JUMP", 4, 0, false },
	[227] = { "DUPTABLE", 4, 3, false },
	[223] = { "SETUPVAL", 2, 0, false },
	[194] = { "CLOSEUPVALS", 1, 0, false },
	[213] = { "JUMPIFLE", 4, 0, true },
	[87] = { "NOT", 2, 0, false },
	[25] = { "SETGLOBAL", 1, 1, true },
	[126] = { "JUMPIFNOTLE", 4, 0, true },
	[232] = { "AND", 3, 0, false },
	[165] = { "GETIMPORT", 4, 4, true },
	[77] = { "FASTCALL", 3, 0, false },
	[63] = { "DIVK", 3, 2, false },
	[188] = { "FASTCALL1", 3, 0, false },
	[246] = { "SUBRK", 3, 7, false },
	[34] = { "MODK", 3, 2, false },
	[14] = { "JUMPXEQKN", 4, 6, true },
	[121] = { "SUBK", 3, 2, false },
	[159] = { "FASTCALL2", 3, 0, true },
	[24] = { "FORGPREP_NEXT", 4, 0, false },
	[20] = { "GETTABLEN", 3, 0, false },
	[241] = { "JUMPXEQKS", 4, 6, true },
	[150] = { "ADDK", 3, 2, false },
	[72] = { "JUMPXEQKNIL", 4, 5, true },
	[43] = { "JUMPXEQKB", 4, 5, true },
	[145] = { "ORK", 3, 2, false },
	[247] = { "SETTABLEN", 3, 0, false },
	[92] = { "MULK", 3, 2, false },
	[174] = { "ANDK", 3, 2, false },
	[82] = { "FORGPREP_INEXT", 4, 0, false },
	[130] = { "FASTCALL2K", 3, 1, true },
	[5] = { "POWK", 3, 2, false },
	[193] = { "DUPCLOSURE", 4, 3, false },
	[217] = { "DIVRK", 3, 7, false },
	[212] = { "IDIV", 3, 0, false },
	[203] = { "OR", 3, 0, false },
	[183] = { "IDIVK", 3, 2, false },
	[106] = { "JUMPX", 5, 0, false },
}

local LUA_MULTRET = -1
local LUA_GENERALIZED_TERMINATOR = -2

local function luau_newsettings()
	return {
		vectorCtor = function() error("vectorCtor was not provided") end,
		vectorSize = 4,
		useNativeNamecall = false,
		namecallHandler = function() error("Native __namecall handler was not provided") end,
		extensions = {},
		callHooks = {},
		errorHandling = true,
		generalizedIteration = true,
		allowProxyErrors = false,
		useImportConstants = false,
		staticEnvironment = {},
	}
end

local function luau_validatesettings(luau_settings)
	assert(type(luau_settings) == "table", "luau_settings should be a table")
	assert(type(luau_settings.vectorCtor) == "function", "luau_settings.vectorCtor should be a function")
	assert(type(luau_settings.vectorSize) == "number", "luau_settings.vectorSize should be a number")
	assert(type(luau_settings.useNativeNamecall) == "boolean", "luau_settings.useNativeNamecall should be a boolean")
	assert(type(luau_settings.namecallHandler) == "function", "luau_settings.namecallHandler should be a function")
	assert(type(luau_settings.extensions) == "table", "luau_settings.extensions should be a table of functions")
	assert(type(luau_settings.callHooks) == "table", "luau_settings.callHooks should be a table of functions")
	assert(type(luau_settings.errorHandling) == "boolean", "luau_settings.errorHandling should be a boolean")
	assert(type(luau_settings.generalizedIteration) == "boolean", "luau_settings.generalizedIteration should be a boolean")
	assert(type(luau_settings.allowProxyErrors) == "boolean", "luau_settings.allowProxyErrors should be a boolean")
	assert(type(luau_settings.staticEnvironment) == "table", "luau_settings.staticEnvironment should be a table")
	assert(type(luau_settings.useImportConstants) == "boolean", "luau_settings.useImportConstants should be a boolean")
end

local function resolveImportConstant(static, count, k0, k1, k2)
	local res = static[k0]
	if count < 2 or res == nil then
		return res
	end
	res = res[k1]
	if count < 3 or res == nil then
		return res
	end
	res = res[k2]
	return res
end

local function luau_deserialize(bytecode, luau_settings)
	if luau_settings == nil then
		luau_settings = luau_newsettings()
	else 
		luau_validatesettings(luau_settings)
	end

	local stream = if type(bytecode) == "string" then buffer_fromstring(bytecode) else bytecode
	local cursor = 0

	local function readByte()
		local byte = buffer_readu8(stream, cursor)
		cursor = cursor + 1
		return byte
	end

	local function readWord()
		local word = buffer_readu32(stream, cursor)
		cursor = cursor + 4
		return word
	end

	local function readFloat()
		local float = buffer_readf32(stream, cursor)
		cursor = cursor + 4
		return float
	end

	local function readDouble()
		local double = buffer_readf64(stream, cursor)
		cursor = cursor + 8
		return double
	end

	local function readVarInt()
		local result = 0

		for i = 0, 4 do
			local value = readByte()
			result = bit32_bor(result, bit32_lshift(bit32_band(value, 0x7F), i * 7))
			if not bit32_btest(value, 0x80) then
				break
			end
		end

		return result
	end

	local function readString()
		local size = readVarInt()

		if size == 0 then
			return ""
		else
			local str = buffer_readstring(stream, cursor, size)
			cursor = cursor + size

			return str
		end
	end

	local luauVersion = readByte()
	local typesVersion = 0
	if luauVersion == 0 then
		error("the provided bytecode is an error message",0)
	elseif luauVersion < 3 or luauVersion > 5 then
		error("the version of the provided bytecode is unsupported",0)
	elseif luauVersion >= 4 then
		typesVersion = readByte()
	end

	local stringCount = readVarInt()
	local stringList = table_create(stringCount)

	for i = 1, stringCount do
		stringList[i] = readString()
	end

	local function readInstruction(codeList)
		local value = readWord()
		local opcode = bit32_band(value, 0xFF)

		local opinfo = opList[opcode + 1]
		local opname = opinfo[1]
		local opmode = opinfo[2]
		local kmode = opinfo[3]
		local usesAux = opinfo[4]

		local inst = {
			opcode = opcode;
			opname = opname;
			opmode = opmode;
			kmode = kmode;
			usesAux = usesAux;
		}

		table_insert(codeList, inst)

		if opmode == 1 then --[[ A ]]
			inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
		elseif opmode == 2 then --[[ AB ]]
			inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
			inst.B = bit32_band(bit32_rshift(value, 16), 0xFF)
		elseif opmode == 3 then --[[ ABC ]]
			inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
			inst.B = bit32_band(bit32_rshift(value, 16), 0xFF)
			inst.C = bit32_band(bit32_rshift(value, 24), 0xFF)
		elseif opmode == 4 then --[[ AD ]]
			inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
			local temp = bit32_band(bit32_rshift(value, 16), 0xFFFF)
			inst.D = if temp < 0x8000 then temp else temp - 0x10000
		elseif opmode == 5 then --[[ AE ]]
			local temp = bit32_band(bit32_rshift(value, 8), 0xFFFFFF)
			inst.E = if temp < 0x800000 then temp else temp - 0x1000000
		end

		if usesAux then 
			local aux = readWord()
			inst.aux = aux

			table_insert(codeList, {value = aux, opname = "auxvalue" })
		end

		return usesAux
	end

	local function checkkmode(inst, k)
		local kmode = inst.kmode

		if kmode == 1 then --// AUX
			inst.K = k[inst.aux +  1]
		elseif kmode == 2 then --// C
			inst.K = k[inst.C + 1]
		elseif kmode == 3 then--// D
			inst.K = k[inst.D + 1]
		elseif kmode == 4 then --// AUX import
			local extend = inst.aux
			local count = bit32_rshift(extend, 30)
			local id0 = bit32_band(bit32_rshift(extend, 20), 0x3FF)

			inst.K0 = k[id0 + 1]
			inst.KC = count
			if count == 2 then
				local id1 = bit32_band(bit32_rshift(extend, 10), 0x3FF)

				inst.K1 = k[id1 + 1]
			elseif count == 3 then
				local id1 = bit32_band(bit32_rshift(extend, 10), 0x3FF)
				local id2 = bit32_band(bit32_rshift(extend, 0), 0x3FF)

				inst.K1 = k[id1 + 1]
				inst.K2 = k[id2 + 1]
			end
			if luau_settings.useImportConstants then
				inst.K = resolveImportConstant(
					luau_settings.staticEnvironment,
					count, inst.K0, inst.K1, inst.K2
				)
			end
		elseif kmode == 5 then --// AUX boolean low 1 bit
			inst.K = bit32_extract(inst.aux, 0, 1) == 1
			inst.KN = bit32_extract(inst.aux, 31, 1) == 1
		elseif kmode == 6 then --// AUX number low 24 bits
			inst.K = k[bit32_extract(inst.aux, 0, 24) + 1]
			inst.KN = bit32_extract(inst.aux, 31, 1) == 1
		elseif kmode == 7 then --// B
			inst.K = k[inst.B + 1]
		elseif kmode == 8 then --// AUX number low 16 bits
			inst.K = bit32_band(inst.aux, 0xf)
		end
	end

	local function readProto(bytecodeid)
		local maxstacksize = readByte()
		local numparams = readByte()
		local nups = readByte()
		local isvararg = readByte() ~= 0

		if luauVersion >= 4 then
			readByte() --// flags 
			local typesize = readVarInt();
			cursor = cursor + typesize;
		end

		local sizecode = readVarInt()
		local codelist = table_create(sizecode)

		local skipnext = false 
		for i = 1, sizecode do
			if skipnext then 
				skipnext = false
				continue 
			end

			skipnext = readInstruction(codelist)
		end

		local sizek = readVarInt()
		local klist = table_create(sizek)

		for i = 1, sizek do
			local kt = readByte()
			local k

			if kt == 0 then --// Nil
				k = nil
			elseif kt == 1 then --// Bool
				k = readByte() ~= 0
			elseif kt == 2 then --// Number
				k = readDouble()
			elseif kt == 3 then --// String
				k = stringList[readVarInt()]
			elseif kt == 4 then --// Import
				k = readWord()
			elseif kt == 5 then --// Table
				local dataLength = readVarInt()
				k = table_create(dataLength)

				for i = 1, dataLength do
					k[i] = readVarInt()
				end
			elseif kt == 6 then --// Closure
				k = readVarInt()
			elseif kt == 7 then --// Vector
				local x,y,z,w = readFloat(), readFloat(), readFloat(), readFloat()

				if luau_settings.vectorSize == 4 then
					k = luau_settings.vectorCtor(x,y,z,w)
				else 
					k = luau_settings.vectorCtor(x,y,z)
				end
			end

			klist[i] = k
		end

		-- // 2nd pass to replace constant references in the instruction
		for i = 1, sizecode do
			checkkmode(codelist[i], klist)
		end

		local sizep = readVarInt()
		local protolist = table_create(sizep)

		for i = 1, sizep do
			protolist[i] = readVarInt() + 1
		end

		local linedefined = readVarInt()

		local debugnameindex = readVarInt()
		local debugname 

		if debugnameindex ~= 0 then
			debugname = stringList[debugnameindex]
		else 
			debugname = "(??)"
		end

		-- // lineinfo
		local lineinfoenabled = readByte() ~= 0

		if lineinfoenabled then
			local linegaplog2 = readByte()

			local intervals = bit32_rshift((sizecode - 1), linegaplog2) + 1

			local lineinfo = table_create(sizecode)
			local abslineinfo = table_create(intervals)

			local lastoffset = 0
			for j = 1, sizecode do
				lastoffset += readByte()
				lineinfo[j] = lastoffset
			end

			local lastline = 0
			for j = 1, intervals do
				lastline += readWord()
				abslineinfo[j] = lastline
			end
		end

		-- // debuginfo
		if readByte() ~= 0 then
			local sizel = readVarInt()
			for i = 1, sizel do
				readVarInt()
				readVarInt()
				readVarInt()
				readByte()
			end
			local sizeupvalues = readVarInt()
			for i = 1, sizeupvalues do
				readVarInt()
			end
		end

		return {
			maxstacksize = maxstacksize;
			numparams = numparams;
			nups = nups;
			isvararg = isvararg;
			linedefined = linedefined;
			debugname = debugname;

			sizecode = sizecode;
			code = codelist;

			sizek = sizek;
			k = klist;

			sizep = sizep;
			protos = protolist;

			lineinfoenabled = lineinfoenabled;

			bytecodeid = bytecodeid;
		}
	end

	local protoCount = readVarInt()
	local protoList = table_create(protoCount)

	for i = 1, protoCount do
		protoList[i] = readProto(i - 1)
	end

	local mainProto = protoList[readVarInt() + 1]

	assert(cursor == buffer_len(stream), "deserializer cursor position mismatch")

	mainProto.debugname = "(main)"

	return {
		stringList = stringList;
		protoList = protoList;

		mainProto = mainProto;

		typesVersion = typesVersion;
	}
end

return luau_deserialize
