--[[

	Commander is a fully-featured command-line parser library for Lua.

	Commander can parse this:

		> ./prog.lua Test.test -abC "More Test" Other Test --continue \
			--extra=Scones,"Other Stuff"

	Into this:

		Directives:		{"Test.test", "Other", "Test"}
		Switches:		{"a", "b", "continue"}
		Parameters:		{C = "More Test", extra = "Scones,Other Stuff"}

	Commander supports a Unix-like commandline syntax:

	**Short arguments:**

		> -acS Something -d -B

	**Long arguments:**

		> --test=Test --two

	**Directives:**

		> run Something in /home/test/.config

	*'Argument'* is a catch-all term.    Commander supports two ways to
	pass annotated data:

	**Switches:**

		> -abC --compile --continue

	**Parameters:**

		> -T Test --extra Stuff --plus=Test,2 --additionally="More Test"

--]]

--- Commander.lua - Version 2.0

--- Commander is free software under the terms of the MIT License.
--- Copyright (c) 2017 Webster Sheets <webster@web-eworks.com>.

local cmdr, mt = {}
cmdr.__index = cmdr

--[[
	## Commander() <a id="cmdr"></a>

	Creates and returns a new Commander instance.
	This function is passed a table containing options to control
	the behavior of Commander.

		Commander {
			usage = "appname [ARGS]"
			summary = "Some summary text relating to the application."
		}

	Recognized fields in the `opts` table:

	-	`usage`: help text on command-line invocation. Usually takes the form:
		`"yourappname [-abcdefg] [ARGS] [--hijk] [--lmnop=<qrstuv>] [XYZ]"`
			
	-	`summary`: a short multiline summary of the program.

	-	`help_handler`: if not explicitly false, will print the output of
		[Commander:help()](#cmdr:help) and call `os.exit(0)` if the user passes
		the `-h` or `--help` switches.
		
		If a function value is provided, Commander will call that function instead.
		
	-	`warn_extra`: if true, the program will print an informational message
		if the user passes extra switches or parameters.
--]]
local function Commander(opts)
	opts = type(opts) == "table" and opts or {}
	local new = {}

	new.usage = type(opts.usage) == "string" and opts.usage or nil
	new.summary = type(opts.summary) == "string" and opts.summary or nil
	new.help_handler = opts.help_handler
	new.warn_extra = opts.warn_extra
	
	new.switches = {}
	new.params = {}
	new._help = {}

	setmetatable(new, cmdr)
	if new.help_handler ~= false then
		new:switch{'h', 'help', help = "Show this help text"}
	end
	
	return new
end

--[[
	## Commander:switch() <a id="cmdr:switch"></a>

	Registers a switch with the Commander instance.
	This function is passed a single table containing the format of the switch.

		cmdr:switch {
			'a', 'apples',
			help = "An apple a day keeps the doctor away..."
		}

	Format table:

	-	`[1, 2]`: The short and long names for the switch.
		Either may be omitted entirely, but at least one must be present.
		
	-	`help`: A summary string describing the switch.

	Returns the self object.
--]]
function cmdr:switch(switch)
	if type(switch) ~= "table" then
		error("Switch definitions must be a table", 2)
	end

	local sw = {
		switch[1] and tostring(switch[1]),
		switch[2] and tostring(switch[2]),
		help = switch.help and tostring(switch.help)
	}

	if not sw[1] then
		error("Switch definitions must have at least one name", 2)
	end

	table.insert(self.switches, sw)
	table.insert(self._help, sw)
	self.switches[sw[1]] = sw
	if sw[2] then self.switches[sw[2]] = sw end
	
	return self
end

--[[
	## Commander:param() <a id="cmdr:param"></a>

	Registers a parameter argument with the Commander instance.
	This function is passed a single table containing the format of the parameter.

		cmdr:param {
			'b', 'baker',
			help = "Mmm...  Tasty apple pie."
			help_arg = "[lane]"
		}

	Format table:

	-	`[1, 2]`: The short and long names for the parameter.
		Either may be omitted entirely, but at least one must be present.

	-	`[help]`: A summary string describing the param.

	-	`[help_arg]`: The help string to print as the parameter's argument.
		Defaults to `'[arg]'`.

	Returns the self object.
--]]
function cmdr:param(param)
	if type(param) ~= "table" then
		error("Parameter definitions must be a table", 2)
	end

	local pm = {
		param[1] and tostring(param[1]),
		param[2] and tostring(param[2]),
		help = param.help and tostring(param.help),
		help_arg = param.help_arg and tostring(param.help_arg) or "[arg]"
	}
	if not pm[1] then
		error("Parameter definitions must have at least one name", 2)
	end

	table.insert(self.params, pm)
	table.insert(self._help, pm)
	self.params[pm[1]] = pm
	if pm[2] then self.params[pm[2]] = pm end

	return self
end

--[[
	## Commander:parse() <a id="cmdr:parse"></a>

	Takes a table containing commandline input pre-split on all non-quoted
	whitespace and parses it into a table of [arguments](#args).
	
	Parameters:

	-	`inargs`: a table of command-line arguments, split on non-escaped spaces.

	Returns a table containing the parsed directives, parameters, and switches.
--]]
function cmdr:parse(inargs)
	local out, i = setmetatable({switches={}, params={}}, mt), 1
	local params, switches, extra = self.params, self.switches, {}
	for k, v in ipairs(params) do
		local t = {}
		for _, k in ipairs(v) do out.params[k] = t end
	end
	--for k,v in ipairs(params) do params[v] = true end
	if inargs[0] then out[0] = inargs[0] end

	while i <= #inargs do local v = inargs[i]
		--[[
			**Process short arguments**

			Short arguments can be given in group form:
				-someArg
			which is equivalent to passing them individually:
				-s -o -m -e -A -r -g

			Commander assumes all short arguments are switches unless explicitly
			told otherwise.
		--]]
		if v:sub(1,1) == "-" and v:sub(2,2) ~= "-" then v = v:sub(2)
			for n, m in v:gmatch("()(%w)") do
				if params[m] then local t = out.params[m]
					if n == #v and #inargs > i and inargs[i+1]:sub(1,1) ~= "-" then
						table.insert(t, inargs[i+1]); i = i + 1
					else
						table.insert(t, false)
					end
				elseif not switches[m] and not extra[m] then
					extra[m] = true
				end
				out.switches[m] = true
			end

		--[[
			**Process long arguments**

			Commander assumes long arguments in the form

				--arg-name=arg-val

			are parameters.  Arguments in the form

				--arg-name arg-val

			are interpreted as a switch and a directive, respectively, unless
			Commander is explicitly told that `arg-name` is a parameter.
		--]]
		elseif v:sub(1,2) == "--" and #v > 2 then v = v:sub(3)
			local s,e,m = v:find("([^=]+)"); v = v:sub(e+1)
			
			if v:sub(1,1) == "=" or params[m] then
				local t = out.params[m] or (type(extra[m]) == "table" and extra[m]) or {}
						
				if v:sub(1,1) == "=" then
					table.insert(t, #v:sub(2) > 0 and v:sub(2) or false)
				elseif #inargs > i then
					local nx = inargs[i+1]
					if #nx > 0 and nx:sub(1,1) ~= "-" then
						table.insert(t, nx); i = i + 1
					else table.insert(t, false) end
				end
			
				if not params[m] then
					extra[m] = t
				end
			elseif not switches[m] and not extra[m] then
				extra[m] = true
			end
			out.switches[m] = true

		-- If it's not a switch or parameter in short or long form, Commander
		-- assumes it's a directive.
		else table.insert(out, v) end
		i = i + 1
	end

	-- **Cleanup**

	-- Automatically handle the user passing the `-h` or `--help` switches.
	if self.help_handler ~= false and out:switch('h', 'help') then
		if type(self.help_handler) == 'function' then
			self.help_handler(out)
		else
			print(self:help())
			os.exit()
		end
	end

	-- Print messages to the user regarding unrecognized arguments.
	if self.warn_extra then
		local prints = {}
		for k, v in pairs(extra) do
			if v == true then
				table.insert(prints, {k, "Warning: Unrecognized switch "})
			else
				out.params[k] = v
				table.insert(prints, {k, "Warning: Unrecognized parameter "})
			end
		end

		-- We sort the parameters by name for pretty printing.
		table.sort(prints, function (a, b) return a[1] < b[1] end)
		
		for _, v in ipairs(prints) do
			io.stderr:write(v[2] .. "'" .. (#v[1]>1 and "--" or "-") .. v[1] .. "'" .. '\n')
		end
		
	-- If we are not warning about unrecognized arguments, replace them in the output.
	else	
		for k, v in pairs(extra) do
			if type(v) == "table" then out.params[k] = v end
		end
	end

	return out
end

--[[
	## Commander:help() <a id="cmdr:help"></a>

	Returns a generated help listing suitable for printing on the console
	as output from `yourapp --help`.

	The output takes the form:

		USAGE: appname [args]
		Some summary text related to the application.

		OPTIONS:
			-a  --apples
				An apple a day keeps the doctor away...

			-b  --baker  [lane]
				Mmm...  Tasty apple pie.

	The specifics for what is printed are controlled by the `usage` and `summary`
	fields passed to [Commander()](#cmdr), and the `help` fields passed to
	[Commander:switch()](#cmdr:switch) and [Commander:param()](#cmdr:param).
--]]
function cmdr:help()
	local frag = ""

	if self.usage then frag = "USAGE: " .. self.usage .. "\n" end
	if self.summary then frag = frag .. self.summary .. "\n" end
	frag = frag .. "\nOPTIONS:\n"

	for i, v in ipairs(self._help) do
		local n, s = "\t", v.help and "\t\t" .. v.help or ""
		for _, v in ipairs(v) do
			if v then n = n .. (#v>1 and "--" or "-") .. v .. "  " end
		end
		n = n .. (v.help_arg or "") .. "\n"
		frag = frag .. n .. s:gsub("\n", "\n\t\t") .. "\n"
	end
	
	return frag
end

--[[
	## args <a id="args"></a>

	The table returned by a call to [Commander:parse()](#cmdr:parse). This table is
	comprised of three logical components: Arguments, Switches, and Parameters.

	Use [args:switch()](#args:switch) to query the presence of a switch, and
	[args:param()](#args:param) for a parameter.

	Arguments are queryable via `args[n]`, where `n` is a positive integer.
--]]
mt = {}
mt.__index = mt

--[[
	### args:switch() <a id="args:switch"></a>

	Query the presence of a switch in equivalent short or long format:

		args:switch('a', 'apples')

	If the switch is present, returns true.  Otherwise, returns false.

	Parameters:
	
	-	`short`: the shorter name of the switch.
	
	-	`long`: the longer name of the switch.

	Returns `true` if the switch is present.
--]]
function mt:switch(short, long)
	short = type(short) == "string" and short or ""
	long = type(long) == "string" and long or ""
	short = short:sub(1,1) == "-" and short:sub(2) or short
	long = long:sub(1,2) == "--" and long:sub(3) or long
	return self.switches[short] or self.switches[long]
end

--[[
	### args:param() <a id="args:param"></a>

	Query a parameter in equivalent short or long format. If the
	parameter is defined multiple times, index selects the specific
	occurence.

		args:param('b', 'baker', 1)

	Parameters:

	-	`short`: A parameter name to look up. Can be any length, but is
		traditionally the one-letter form.

	-	`long`: An alternative parameter name to look up. Can be any length, but
		is traditionally the multi-letter form.

	-	`idx`: An optional numerical index specifing the n-th occurence of the
		parameter to retrieve.  Defaults to 1.

	If the parameter is present, returns the parameter.
	Otherwise, if the name was given as a switch, returns `false`;
	if the name is not present at all, returns `nil`.
--]]
function mt:param(short, long, idx)
	short = type(short) == "string" and short or ""
	long = type(long) == "string" and long or ""
	short = short:sub(1,1) == "-" and short:sub(2) or short
	long = long:sub(1,2) == "--" and long:sub(3) or long
	idx = tonumber(idx)
	local param = self.params[short] or self.params[long]
	if param and #param > 0 then
		local n = math.min(idx or #param, #param)
		while n > 1 and not param[n] do
			n = n - 1
		end
		return param[n]
	else
		return nil
	end
end

--[[

### Credits

Commander is created and maintained by [Webster
Sheets](mailto:webster@web-eworks.com), a fine fellow at [Web eWorks,
LTD](http://web-eworks.com).

--]]

return Commander
