#!/usr/bin/env lua

--[[

	__Locco__ is a Lua port of [Docco](http://jashkenas.github.com/docco/), the
	quick-and-dirty, hundred-line-long, literate-programming-style documentation
	generator. It produces HTML that displays your comments alongside your code.
	Comments are passed through
	[Markdown](http://daringfireball.net/projects/markdown/), and code is syntax
	highlighted. This page is the result of running Locco against its own source
	file:

		locco.lua locco.lua

	For its syntax highlighting Locco relies on the help of [David
	Manura](http://lua-users.org/wiki/DavidManura)'s [Lua
	Balanced](https://github.com/davidm/lua-balanced) to split up the code. As a
	markdown engine it ships with [Niklas Frykholm](http://www.frykholm.se/)'s
	[markdown.lua](http://www.frykholm.se/files/markdown.lua) in the [Lua 5.2
	compatible version](https://github.com/speedata/luamarkdown) from [Patrick
	Gundlach](https://github.com/pgundlach). Locco also uses
	[Commander.lua](https://gitlab.com/axtel-sturnclaw/Commander) for
	command-line processing. Otherwise there are no external dependencies.

	The generated HTML documentation for the given source files is saved into a
	`docs` directory. If you have Locco on your path you can run it from the
	command-line:

		locco.lua project/*.lua

	Locco is monolingual, but there are many projects written in and with
	support for other languages, see the
	[Docco](http://jashkenas.github.com/docco/) page for a list.<br> The [source
	for Locco](https://github.com/rgieseke/locco) is available on GitHub, and
	released under the MIT license.

--]]

-- ### Setup & Helpers

-- Add script path to package path to find submodules.
local script_path = arg[0]:match('(.+)/.+')
package.path = table.concat({
	script_path..'/?.lua',
	package.path
}, ';')

-- Load markdown.lua.
local md = require 'markdown'
-- Load Lua Balanced.
local lb = require 'luabalanced'

-- Load Commander and process arguments.
local cmdr = require 'Commander' {
	usage = "locco.lua [FILE] [...]",
	summary = "Locco is a simple lua documentation generator, transforming markdown\n"
	.. "formatted source code comments into human-legible HTML pages."
}:param {
	'd', 'docs-dir', help_arg = "<dir>",
	help = "The output directory to create the documentation in.\n"
	.. "Defaults to [FILEPATH]/docs/"
}:param {
	'o', 'out', help_arg = "<file>",
	help = "If only one file is being processed, set the output name of the file."
}:param {
	'template', help_arg = "<template name>",
	help = "Set the name of the documentation template to use."
}

local args = cmdr:parse(arg)

local opts = {
	outDir = "docs",
	template = "templates.default"
}

-- Generate the output directory path for `source`
local function get_paths(source)
	local path, out_path = source:match('(.+)/.+$') or '.', opts.outDir
	if not opts.outDir:match("^%.?/") then
		out_path = path .. '/' .. opts.outDir
	end
	return path, out_path
end

--[[
	Ensure the output directory exists and return the _path_ of the source file.

	Parameters:<br>
	`source`: The source file for which documentation is generated.
--]]
local function ensure_out_dir(source)
	local path, out_path = get_paths(source)
	os.execute('mkdir -p ' .. out_path)
	return path, out_path
end

--[[
	Insert HTML entities in a string.

	Parameters:<br>
	`s`: String to escape.
--]]
local function escape(s)
	s = s:gsub('&', '&amp;')
	s = s:gsub('<', '&lt;')
	s = s:gsub('>', '&gt;')
	s = s:gsub('%%', '&#37;')
	return s
end

-- Define the Lua keywords, built-in functions and operators that should
-- be highlighted.
local keywords = {
	'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
	'function', 'if', 'in', 'local', 'nil', 'repeat', 'return',
	'then', 'true', 'until', 'while'
}
local functions = {
	'assert', 'collectgarbage', 'dofile', 'error', 'getfenv',
	'getmetatable', 'ipairs', 'load', 'loadfile', 'loadstring',
	'module', 'next', 'pairs', 'pcall', 'print', 'rawequal',
	'rawget', 'rawset', 'require', 'setfenv', 'setmetatable',
	'tonumber', 'tostring', 'type', 'unpack', 'xpcall'
}
local operators = { 'and', 'not', 'or' }

-- Wrap an item from a list of Lua keywords in a span template or return the
-- unchanged item.<br>
-- Parameters:<br>
-- `item`: An item of a code snippet.<br>
-- `item_list`: List of keywords or functions.<br>
-- `span_class`: Style sheet class.<br>
local function wrap_in_span(item, item_list, span_class)
	for i=1, #item_list do
		if item_list[i] == item then
			item = '<span class="'..span_class..'">'..item..'</span>'
			break
		end
	end
	return item
end

-- Quick and dirty source code highlighting. A chunk of code is split into
-- comments (at the end of a line), strings and code using the
-- [Lua Balanced](https://github.com/davidm/lua-balanced/blob/master/luabalanced.lua)
-- module. The code is then split again and matched against lists
-- of Lua keywords, functions or operators. All Lua items are wrapped into
-- a span having one of the classes defined in the Locco style sheet.<br>
--
-- Parameters:<br>
-- `code`: Chunk of code to highlight.<br>
local function highlight_lua(code)
	local out = lb.gsub(code,
		function(u, s)
			local sout
			if u == 'c' then -- Comments.
				sout = '<span class="c">'..escape(s)..'</span>'
			elseif u == 's' then -- Strings.
				sout = '<span class="s">'..escape(s)..'</span>'
			elseif u == 'e' then -- Code.
				s = escape(s)
				-- First highlight function names.
				s = s:gsub('function ([%w_:%.]+)', 'function <span class="nf">%1</span>')
				-- There might be a non-keyword at the beginning of the snippet.
				sout = s:match('^(%A+)') or ''
				-- Iterate through Lua items and try to wrap operators,
				-- keywords and built-in functions in span elements.
				-- If nothing was highlighted go to the next category.
				for item, sep in s:gmatch('([%a_]+)(%A+)') do
					local span, n = wrap_in_span(item, operators, 'o')
					if span == item then
						span, n = wrap_in_span(item, keywords, 'k')
					end
					if span == item then
						span, n = wrap_in_span(item, functions, 'nt')
					end
					sout = sout..span..sep
				end
			end
			return sout
		end)
		out = '<div class="highlight"><pre>'..out..'</pre></div>'
	return out
end


-- ### Main Documentation Generation Functions

-- Given a source text, read and parse the text into documentation
-- and comments.
--
-- Parameters:<br>
-- `text`: The file text to process.

local function parse(text)
	local sections, text_len = {}, #text
	local has_code = false
	local docs_text, code_text = '', ''

	--[[
		Given a string of source code, parse out each comment and the code that
		follows it, and create an individual section for it. Sections take the
		form:

			{
				docs_text = ...,
				docs_html = ...,
				code_text = ...,
				code_html = ...,
			}

		Line comments without a space, tab, newline (LF or CRLF) or `[` following the `--` are
		ignored and passed through into the code section. Useful for file
		headers and the like.
	--]]

	local pos = 1
	while pos < text_len do
		local comment_pos, comment = text:match("^[ \t]*()%-%-", pos)
		if comment_pos then
			local ok, comment_text, npos = pcall(lb.match_comment, text, comment_pos)
			if ok and comment_text and comment_text:sub(3, 3):match("[ \t\r\n%[]") then
				pos = npos; comment = comment_text
			end
		end

		if comment then
			if has_code then
				code_text = code_text:gsub('\n\n$', '\n') -- remove empty trailing line
				sections[#sections + 1] = {
					['docs_text'] = docs_text,
					['code_text'] = code_text:gsub("\t", string.rep(" ", 4))
				}
				has_code = false
				docs_text, code_text = '', ''
			end

			-- Given a long comment, remove the opening and closing delimiters,
			-- de-indent each line by the level of indentation of the first
			-- free-standing line, and add the resulting text to the docs
			-- section.
			local long, pos = comment:match("^%-%-%[(=*)%[%-*()")
			if long then
				comment = comment:sub(pos):gsub("%s*%-*%]"..long.."%][^\r\n]*$", "")
				local first_line, pos = comment:match("^[ \t]*(.-)\r?\n()")
				comment = comment:sub(pos):gsub("^%s*\n(%s-[^%s])", "%1")
				local ind, pos = comment:match("^([ \t]*)()")
				comment = comment:sub(pos):gsub("\n"..ind, "\n")
				docs_text = docs_text .. first_line .. '\n' .. comment .. '\n'


			-- Given a short comment, remove the comment delimiter and one space
			-- or tab from the beginning, and add the resulting text to the docs
			-- section.
			else
				docs_text = docs_text .. comment:gsub("^%-%-[ \t]?", '')
			end

		-- If it's not a comment, then treat the line like code.
		else
			local line, npos = text:match("(.-)\r?\n()", pos)
			if line then pos = npos else
				line, pos = text:sub(pos), text_len
			end

			if not line:match('^#!') then -- ignore shebangs.
				has_code = true
				code_text = code_text..line..'\n'
			end
		end
	end

	sections[#sections + 1] = {
		['docs_text'] = docs_text,
		['code_text'] = code_text
	}

	return sections
end

-- Loop through a table of split sections and convert the documentation
-- from Markdown to HTML and pass the code through Locco's syntax
-- highlighting. Add    _docs\_html_ and _code\_html_ elements to the sections
-- table.
--
-- Parameters:<br>
-- `sections`: A table with split sections.<br>
local function highlight(sections)
	for i=1, #sections do
		sections[i]['docs_html'] = md.markdown(sections[i]['docs_text'])
		sections[i]['code_html'] = highlight_lua(sections[i]['code_text'])
	end
	return sections
end

-- After the highlighting is done, the template is filled with the documentation
-- and code snippets and the HTML document is assembled.
--
-- Parameters:<br>
-- `title`: The title for the generated document.<br>
-- `sections`: A table with the original sections and rendered as HTML.<br>
-- `jump_to`: A HTML chunk with links to other documentation files.
local function generate_html(title, sections, jump_to)
	local out = ""

	local h = opts.template.header:gsub('%%title%%', title)
	h = h:gsub('%%jump%%', jump_to)
	out = out .. h

	for i=1, #sections do
		local t = opts.template.table_entry:gsub('%%index%%', i..'')
		t = t:gsub('%%(docs_html)%%', sections[i])
		t = t:gsub('%%(code_html)%%', sections[i])
		out = out .. t
	end

	out = out .. opts.template.footer
	return out
end

-- Generate the documentation for a source file by reading it in, splitting it
-- up into comment/code sections, highlighting and merging them into an HTML
-- template.
--
-- Parameters:<br>
-- `source`: The path to the source file to process.<br>
-- `filename`: The filename of the source file.<br>
-- `jump_to`: A HTML chunk with links to other documentation files.
-- Returns:<br>
-- `true` on success, false otherwise.
local function generate_documentation(source, filename, jump_to)
	local path, out_path = get_paths(source)

	local file, err = io.open(source, 'r')
	if not file then
		print("Error opening source '"..source.."' for reading.  Skipping file.")
		print("Error Message: " .. err)
		return
	end

	local text, err = file:read("a")
	file:close()

	if not text then
		print("Error reading source '"..source.."'. Skipping file.")
		print("Error Message: " .. err)
		return
	end

	local sections = parse(text)
	local sections = highlight(sections)
	local html = generate_html(source, sections, jump_to)

	local out_file = out_path .. '/' .. filename

	local f, err = io.open(out_file, 'wb')
	if err then
		print("Error opening '" .. out_file .. "' for writing.  Skipping file.")
		print(err)
		return
	end

	f:write(html)
	f:close()

	return true
end

--[[
	### CLI Functions

	Process arguments and run the converter over each file passed to locco.

	If a file is unable to be converted, it is skipped, and a message is printed
	on the command line.
--]]
local function main(args)
	opts.outName = #args == 1 and args:param('o', 'out')
	opts.outDir = args:param('d', 'docs-dir') or opts.outDir
	local template_name = args:param('template') or opts.template

	-- Load HTML templates.
	local ok, res = pcall(require, template_name)
	if ok and res then
		opts.template = res
	else
		print("Error loading template file '" .. template_name .. "'")
		if not res then
			print("did not return a template")
		else
			print(res)
		end

		-- If the template is unable to be loaded for whatever reason, fall back
		-- on the default.
		print("Using default template.")
		opts.template = require(opts.template)
	end

	-- Generate HTML links to other files in the documentation.
	local jump_to = ''
	if #args > 1 then
		jump_to = opts.template.jump_start
		for i=1, #args do
			local link = args[i]:gsub('lua$', 'html')
			link = link:match('.+/(.+)$') or link
			local t = opts.template.jump:gsub('%%jump_html%%', link)
			t = t:gsub('%%jump_lua%%', args[i])
			jump_to = jump_to..t
		end
		jump_to = jump_to..opts.template.jump_end
	end

	-- Make sure the output directory exists, generate the HTML files for each
	-- source file, print what's happening, and write the style sheet.
	local path, out_path = ensure_out_dir(args[1])
	for i=1, #args do
		local filename = opts.outName or args[i]:match('.+/(.+)$') or args[i]
		local html = generate_documentation(args[i], filename:gsub('%.lua$', '.html'), jump_to)
		local out_path = out_path .. '/' .. filename:gsub("lua$", "html")
		if ok then
			print(args[i] .. ' --> ' .. out_path)
		end
	end

	-- Generate the CSS stylesheet in the output directory.
	local f, err = io.open(out_path..'/locco.css', 'wb')
	if err then print(err) end
	f:write(opts.template.css)
	f:close()
end

-- If there are no files to process or the user wants to see the help, print the
-- help text and return.
if not args[1] or args:switch('h', 'help') then
	print(cmdr:help()) return
end

-- Run the script.
main(args)
