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
	Gundlach](https://github.com/pgundlach). Otherwise there are no external
	dependencies.

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
-- Load HTML templates.
local template = require 'template'

-- Load Commander.lua and process arguments.
local Commander = require 'Commander'
local args = Commander(arg)

--[[
	Ensure the `docs` directory exists and return the _path_ of the source file.<br>
	Parameters:<br>
	`source`: The source file for which documentation is generated.
--]]
local function ensure_directory(source)
	local path = source:match('(.+)/.+$')
	if not path then path = '.' end
	os.execute('mkdir -p '..path..'/docs')
	return path
end

-- Insert HTML entities in a string.
--
-- Parameters:<br>
-- `s`: String to escape.
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

-- Given a filename, read and parse the file into documentation
-- and comments.
--
-- Parameters:<br>
-- `source`: The source file to process.

local function parse(source)
	local sections, text, text_len = {}, "", 0
	local has_code = false
	local docs_text, code_text = '', ''

	source = assert(io.open(source, "rb"))
	text = source:read("a")
	text_len = #text
	source:close()

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

		Line comments without a space, tab, or `[` following the `--` are
		ignored and passed through into the code section. Useful for file
		headers and the like.

	--]]

	local pos = 1
	while pos <= text_len do
		local comment_pos, comment = text:match("^[ \t]*()%-%-", pos)
		if comment_pos then
			local ok, comment_text, npos = pcall(lb.match_comment, text, comment_pos)
			if ok and comment_text and comment_text:sub(3, 3):match("[ \t\n%[]") then
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
			local line
			line, pos = text:match("(.-)\r?\n()", pos)
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
-- and code snippets and an HTML file is written.
--
-- Parameters:<br>
-- `source`: The source file.<br>
-- `path`: Path of the source file.<br>
-- `filename`: The filename of the source file.<br>
-- `sections`: A table with the original sections and rendered as HTML.<br>
-- `jump_to`: A HTML chunk with links to other documentation files.
local function generate_html(source, path, filename, sections, jump_to)
	local f, err = io.open(path..'/'..'docs/'..filename:gsub('lua$', 'html'), 'wb')
	if err then print(err) end
	local h = template.header:gsub('%%title%%', source)
	h = h:gsub('%%jump%%', jump_to)
	f:write(h)
	for i=1, #sections do
		local t = template.table_entry:gsub('%%index%%', i..'')
		t = t:gsub('%%(docs_html)%%', sections[i])
		t = t:gsub('%%(code_html)%%', sections[i])
		f:write(t)
	end
	f:write(template.footer)
	f:close()
end

-- Generate the documentation for a source file by reading it in,
-- splitting it up into comment/code sections, highlighting and merging
-- them into an HTML template.
--
-- Parameters:<br>
-- `source`: The source file to process.<br>
-- `path`: Path of the source file.<br>
-- `filename`: The filename of the source file.<br>
-- `jump_to`: A HTML chunk with links to other documentation files.
local function generate_documentation(source, path, filename, jump_to)
	local sections = parse(source)
	local sections = highlight(sections)
	generate_html(source, path, filename, sections, jump_to)
end

-- If there are no files to process or the user wants to see the help, print the
-- help text and return.
if not args[1] or args:switch('h', 'help') then
	print 'Locco.lua - A Lua documentation generator'
	print 'Usage: locco.lua FILE [...]'
	print ''
	print 'Options:'
	print '    -h  --help'
	print '            Show this message'
	return
end

-- Run the script.
--
-- Generate HTML links to other files in the documentation.
local jump_to = ''
if #args > 1 then
	jump_to = template.jump_start
	for i=1, #args do
		local link = args[i]:gsub('lua$', 'html')
		link = link:match('.+/(.+)$') or link
		local t = template.jump:gsub('%%jump_html%%', link)
		t = t:gsub('%%jump_lua%%', args[i])
		jump_to = jump_to..t
	end
	jump_to = jump_to..template.jump_end
end

-- Make sure the output directory exists, generate the HTML files for each
-- source file, print what's happening and write the style sheet.
local path = ensure_directory(args[1])
for i=1, #args do
	local filename = args[i]:match('.+/(.+)$') or args[i]
	generate_documentation(args[i], path, filename, jump_to)
	print(args[i]..' --> '..path..'/docs/'..filename:gsub('lua$', 'html'))
end

local f, err = io.open(path..'/'..'docs/locco.css', 'wb')
if err then print(err) end
f:write(template.css)
f:close()
