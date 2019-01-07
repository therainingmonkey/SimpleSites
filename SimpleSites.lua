#!/usr/bin/env lua
-- TODO: Create a lockfile while we work

local lfs = require "lfs"
local parse_markdown = require "discount"

-- The default files for a new project
local DEFAULT_CONTENT = [[# Welcome!
This is where you can write the content for your front page.

The text here will be formatted according to markdown syntax and inserted into
a template, which you can find at `/templates/_default.html`.

### Templates
If there is a template with the same name as the `.md` file in the `content`
directory, then that template will be used to render that content. Otherwise,
the `_default.html` template will be used.

If your content `.md` file is in a subdirectory of the `content` directory,
SimpleSites will look for a subdirectory with the same name in the `templates`
directory. If it finds one, it will look for a template there with the same
name as the content `.md` file. If there isn't one, it'll look for a
`_default.html` file in that subdirectory. If it finds neither, it'll look in
the directory above.

You can use this to have specific templates for different pages or different
sections of your site. For instance, you could have a `content/posts` directory
conaining blog posts, and a `templates/posts/_default.html` template which would
be applied to them.

### Code blocks
Double curly brackets in the template file can contain Lua code which will be
run. eg. `{ { "hello, " .. NAME .. "!" } }` (with no spaces between
the brackets) will be evaluated before it's inserted into the template. Don't
put code blocks in your content `.md` files, it causes horrible, subtle and
intermittent bugs.

One HTML page is rendered for every `.md` file in the `content` directory and its subdirectories. Within whichever template is chosen to render the `.md` file,
the contents of the `.md` file are available inside code blocks as
`content.auto`.

Code blocks are evaluated and templates merged before markdown is parsed into HTML. This means that you can include markdown in your templates, but you can't indent any HTML in your templates or it'll be treated as a code block.

### Styling
To change the style of your site, edit `static/style.css`.

## Markdown
You can use [Discount](http://www.pell.portland.or.us/~orc/Code/markdown/) flavoured [markdown](https://en.wikipedia.org/wiki/Markdown) to add formatting. Discount uses [Smartypants](https://daringfireball.net/projects/smartypants/) substitutions. [Here](http://tedwise.com/markdown/) is a full guide to Discount markdown's syntax.

Here's a quick overview of markdown:

# Headers start with a "#"

## Subheadings start with multiple "#"s

Leave one empty line to start a new paragraph, otherwise lines will run together.

This is _italicised_, so is *this*.
**This** will be bold, so will __this__.
These will all be part of the same paragraph.

->This text will be centred.<-

[This](www.example.com) will be a link to example.com
So will [this][link1]. Look at the bottom to see the footnote-style link it references.

Images are very similar, but prefixed with a !
![My image text](static/image.png)
You can use inline _or_ reference style.

> This will be displayed in 
> blockquote style.


	This will be displayed in 'code' style, ie. with the exact formatting written
	here and displayed in a monospace font.
	That's because it's been indented by 1 tab.
    You can also start a code block by indenting 4 spaces.

`This is an inline code block. It's between backticks (not 'single quotes').`

* This
* Is
* A 
* Bullet
* List

1. This is a 
2. Numbered list

### HTML
You can use regular <abbr title="Hypertext Markup Language">HTML</abbr> in markup wherever you like.


[link1]: www.example.com "On hover, this text will be displayed!"
]]

local DEFAULT_TEMPLATE = [[<html>
<head>
<link rel="stylesheet" type="text/css" href="style.css">
<title> {{ return content.auto:match("#(.-)\n")  }} </title>
<body>

{{ return content.auto }}

</body>
</html>
]]

local DEFAULT_STYLESHEET = [[
body {
	font-family: Arial, sans-serif;
}
]]

-- Back to the code -------------------

-- If we're passed a dir as an argument, chdir there
if arg[1] then
	lfs.chdir(arg[1])
end

local content, templates = {["auto"]=""}, {}
local rootpath = lfs.currentdir()

local function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

-- Copies a file from `inpath` to `outpath`
-- Holds whole file in memory, not good for huge files.
local function copyfile(inpath, outpath)
	local infile = io.open(inpath)
	local outfile = io.open(outpath, "w")
	-- If file doesn't exist or is empty,we skip it.
	if infile ~= nil and outfile ~= nil then
		outfile:write(infile:read("*all"))
		infile:close()
		outfile:close()
	end
end

-- Copies an entire directory, including nested subdirectories
local function copydir(inpath, outpath)
	for filename in lfs.dir(inpath) do
		if filename ~= "." and filename ~= ".." then
			if lfs.attributes(inpath.."/"..filename).mode == "directory" then
				lfs.mkdir(outpath.."/"..filename)
				copydir(inpath.."/"..filename, outpath.."/"..filename)
			else
				copyfile(inpath.."/"..filename, outpath.."/"..filename)
			end
		end
	end
end

-- Reads files recursively from a folder and stores their contents in a table
-- rootdir should be the base dir to be loaded, out_table is the table to use
-- workingdir should be empty when first called (it's used in recursive calls)
local function loaddir(rootdir, out_table, workingdir)
	workingdir = workingdir or ""
	local table_cursor = out_table
	if workingdir:sub(-1,-1) ~= "/" then workingdir = workingdir .. "/" end
	-- For each chunk of string split at `/`, eg. alice & bob in /alice/bob/
	for dir in workingdir:gmatch("(.-)/") do
		-- Build a list of dirs above the current one
		if dir ~= "" and dir ~= "." and dir ~= ".." then
			if not table_cursor[dir] then
				table_cursor[dir] = {}
			end
			table_cursor = table_cursor[dir]
		end
	end
	for filename in lfs.dir(rootdir .. workingdir) do
		if filename ~= "." and filename ~= ".." then
			local filepath = rootdir .. workingdir .. "/" .. filename
			if lfs.attributes(filepath).mode == "directory" then
				loaddir(rootdir, out_table, workingdir .. filename)
			else
				local handle = io.open(rootdir..workingdir.."/"..filename)
			-- `filename:find("(.+)%.")` matches everything up to the final `.`
			-- eg. `first_post` from `first_post.md`.
			-- var `name` holds the key for the table element we're using.
				local _, _, name = filename:find("(.+)%.")
				table_cursor[name] = handle:read("*all")
				handle:close()
			end
		end
	end
end

-- Evaluate code blocks & assemble templates; then render markdown to HTML
local function render(template_used, content_used)
    
    local cursor = 0
	content['auto'] = content_used
	repeat
		-- find and run {{ template blocks }}
		local blockstart, blockend = template_used:find("{{.-}}", cursor)
		if not blockstart then break end -- Reached EOF
		cursor = blockstart
		local block_string = template_used:sub(blockstart + 2, blockend - 2)
		local block, err = loadstring(block_string)
		
		if block then
			-- Allow the block access to local tables
			setfenv(block, {content=content, templates=templates, pairs=pairs})
			
			local success, output = pcall(block)
			if success then
                output = output or ""
				local starttext = template_used:sub(1, blockstart-1)
				local endtext = template_used:sub(blockend+1, -1)
				template_used = starttext .. output .. endtext
			else
				cursor = blockend
				print("Error running code block: "..output.."\n"..block_string)
			end
		else -- Bad lua in the code block, don't evaluate & leave as is.
			cursor = blockend
			print("Error loading code block: "..err.."\n"..block_string)
		end
	
	until cursor == nil or cursor > #template_used
	return parse_markdown(template_used)
end

-- Navigate the filesystem to match content to templates,
-- using the nearest template in the tree; render templates with content
local function recursive_render(content_table, cursor)
	cursor = cursor or {}
	for k, v in pairs(content_table) do
        if k ~= "auto" then -- "auto" changes depending which file we're rendering
			if type(v) == "table" then
				local newcursor = deepcopy(cursor)
				table.insert(newcursor, k)
				recursive_render(v, newcursor)
			else
				local t_table = deepcopy(templates)
				local default = templates._default
				for _, i in pairs(cursor) do
					if t_table[i] then
						t_table = t_table[i]
					end
					if t_table["_default"] then
						default = t_table["_default"]
					end
				end
				local template = t_table[k] or default
-- If there's a folder with the same name as our content.md, don't try to use the folder as a template
                if type(template) == "table" then
                    template = default
                end
				local rendered = render(template, v)

				-- Write the rendered page to a file
				local path = ""
				for _, dir in pairs(cursor) do
					path = path .. "/" .. dir
					lfs.mkdir(rootpath.."/public"..path)
				end

				local outpath = rootpath.."/public"..path.."/" .. k ..".html"
				local handle = io.open(outpath, "w")
				print("Writing ", "/public"..path.."/" .. k ..".html") -- DEBUG
				handle:write(rendered)
				handle:close()
			end
		end
	end
end

local function check_filesystem()
	for _, dir in pairs({"/content", "/templates", "/static", "/public"}) do
		local attr = lfs.attributes(rootpath..dir)
		if attr == nil or attr.mode ~= "directory" then
			return false
		end
	end
	return true
end

local function build_default_filesystem()
	print("Couldn't find the right directory structure. Would you like to create it in this dir:\n'"..rootpath.."'?\t(y/n)")
	local answer = io.read()
	if answer == "y" or answer == "Y" then
		print("Generating new project...")
		-- Create the directories
		lfs.mkdir(rootpath.."/content")
		lfs.mkdir(rootpath.."/templates")
		lfs.mkdir(rootpath.."/static")
		lfs.mkdir(rootpath.."/public")
		-- Create default files
		local f = io.open(rootpath.."/content/index.md", "w")
		f:write(DEFAULT_CONTENT)
		f:close()
		f = io.open(rootpath.."/templates/_default.html", "w")
		f:write(DEFAULT_TEMPLATE)
		f:close()
		f = io.open(rootpath.."/static/style.css", "w")
		f:write(DEFAULT_STYLESHEET)
		f:close()
		print("Done! Open content/index.md to get started.")
	else
		print("Exiting..")
		os.exit()
	end
end

-- Main section -----------------------

if check_filesystem() ~= true then
	build_default_filesystem()
	os.exit()
end

-- Load all the content .md files into the content table
loaddir(rootpath.."/content", content)
-- Load all the .html templates into the template table
loaddir(rootpath.."/templates", templates)

-- Copy over the `static` directory
copydir(rootpath.."/static", rootpath.."/public")

-- Render all content & save output
recursive_render(content)
