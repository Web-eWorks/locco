--[[

	Commander is a fully-featured command-line parser library for Lua, implemented in
	less than 70 lines of code.

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

--- Commander.lua - Version 1.1

--- Commander is free software under the terms of the MIT License.
--- Copyright (c) 2017 Webster Sheets <webster@web-eworks.com>.

local mt, Commander = {}
mt.__index = mt

--[[
	## Commander() <a id="Commander"><a/>

	Takes a table containing commandline input (pre-split on all non-quoted
	whitespace), and an optional table of parameter definitions.

	Commander then parses the input and returns a table of [arguments](#args).

	Parameters:
		inargs: a table of command-line arguments, split on non-escaped spaces.
		params: a sequence of argument names to consider parameters.
	Returns:
		args: a table containing the parsed directives, parameters, and switches.
--]]
function Commander(inargs, params)
	local out, i = setmetatable({params={}}, mt), 1
	params = type(params) == "table" and params or {}
	for k,v in ipairs(params) do params[v] = true end
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
				if params[m] then local t = out.params[m] or {}
					if n == #v and #inargs > i and inargs[i+1]:sub(1,1) ~= "-" then
						table.insert(t, inargs[i+1]); i = i + 1
					else table.insert(t, false) end
					out.params[m] = t
				end
				out[m] = true
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
				local t = out.params[m] or {}
				if v:sub(1,1) == "=" then
					table.insert(t, #v:sub(2) > 0 and v:sub(2) or false)
				elseif #inargs > i then
					local nx = inargs[i+1]
					if #nx > 0 and nx:sub(1,1) ~= "-" then
						table.insert(t, nx); i = i + 1
					else table.insert(t, false) end
				end
				out.params[m] = t
			end
			out[m] = true

		-- If it's not a switch or parameter in short or long form, Commander
		-- assumes it's a directive.
		else table.insert(out, v) end
		i = i + 1
	end

	--[[
	## args <a id="args"></a>

	The table returned by a call to [Commander()](#Commander). This table is
	comprised of three logical components: Arguments, Switches, and Parameters.

	Use [args:switch()](#args:switch) to query the presence of a switch, and
	[args:param()](#args:param) for a parameter.

	Arguments are queryable via `args[n]`, where `n` is a positive integer.
	--]]
	return out
end

--[[
	### args:switch() <a id="args:switch"></a>

	Query the presence of a switch in equivalent short or long format

	If the switch is present, returns true.  Otherwise, returns false.

	Parameters:
		short: the shorter name of the switch.
		long: the longer name of the switch.
	Returns:
		present: Whether the switch was present.
--]]
function mt:switch(short, long)
	short = type(short) == "string" and short or ""
	long = type(long) == "string" and long or ""
	short = short:sub(1,1) == "-" and short:sub(2) or short
	long = long:sub(1,2) == "--" and long:sub(3) or long
	return not not (self[short or 0] or self[long or 0])
end

--[[
	### args:param() <a id="args:param"></a>

	Query a parameter in equivalent short or long format. If the
	parameter is defined multiple times, index selects the specific
	occurence.

	If the parameter is present, returns the parameter.
	Otherwise, if the name was given as a switch, returns `false`;
	if the name is not present at all, returns `nil`.

	Parameters:

		short: A parameter name to look up. Can be any length, but is
		traditionally the one-letter form.

		long: An alternative parameter name to look up. Can be any length, but
		is traditionally the multi-letter form.

		idx: An optional numerical index specifing the n-th occurence of the
		parameter to retrieve.  Defaults to 1.

	Returns:
		val: The value of the parameter
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
