#!/usr/bin/env lua

local lfs = require "lfs"
local parse_markdown = require "markdown"


-- The default files for a new project
local DEFAULT_CONTENT = 
[[# Welcome!
This is where you can write the content for your front page.

The text here will be formatted according to markdown syntax and inserted into
a template, which you can find at `/templates/_default.html`.

### Templates
If there is a template with the same name as the `.md` file in the `content`
directory, then that template will be used to render that content.

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

If no other matching template is found, it'll use `templates/_default.html`.

### Code blocks
Double curly brackets in the template file can contain Lua code which will be
run. eg. `{ { "hello, " .. NAME .. "!" } }` (with no spaces between
the brackets) will be evaluated before it's inserted into the template. Don't
put code blocks in your content `.md` files, it causes horrible, subtle and
intermittent bugs.

One HTML page is rendered for every `.md` file in the `content` directory and
its subdirectories. Within whichever template is chosen to render the `.md`
file, the `.md` file is available inside code blocks as `content.auto`.

The text of the `.md` file is `content.auto.text`. `content.auto` has a few
other useful fields, like `content.auto.modified_time` or `content.auto.title`
(which is guessed either from the first #markdown header or else from the 
filename). Read the code to see all available fields, it should be Simple
enough.

Code blocks are evaluated and templates merged before markdown is parsed into
HTML. This means that you can include markdown in your templates, but you
shouldn't indent any HTML in your templates or it'll be treated as a code block.

### Styling
To change the style of your site, edit `static/style.css`.

## Markdown
You can use [Markdown](https://en.wikipedia.org/wiki/Markdown) to add formatting.
Look at the difference between `index.md` and `index.html` to see how markdown
renders into HTML.

Here's a quick overview of markdown:

# Headers start with a "#"

## Subheadings start with multiple "#"s

Leave one empty line to start a new paragraph, otherwise lines will run
together.

This is _italicised_, so is *this*.
**This** will be bold, so will __this__.
These will all be part of the same paragraph.

->This text will be centred.<-

[This](www.example.com) will be a link to example.com
So will [this][link1]. Look at the bottom of the markdown to see the
footnote-style link it references.

Images are very similar, but prefixed with a !
![My image text](static/image.png)
You can use inline _or_ reference style.

> This will be displayed in 
> blockquote style.


	This will be displayed in 'code' style, ie. with the exact formatting
	written here and displayed in a monospace font.
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
You can use regular <abbr title="Hypertext Markup Language">HTML</abbr> in
markup wherever you like.


[link1]: www.example.com "On hover, this text will be displayed!"
]]

local DEFAULT_TEMPLATE = [[<html>
<head>
<link rel="stylesheet" type="text/css" href="static/style.css">
<title> {{ return content.auto.title }} </title>
<body>

{{ return content.auto.text }}

</body>
</html>
]]

local DEFAULT_STYLESHEET = [[
body {
	margin: auto;
	width: 80%;
	font-family: Arial, sans-serif;
}
]]

-- Back to the code -------------------

-- If we're passed a dir as an argument, chdir there
if arg[1] then
	lfs.chdir(arg[1])
end
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

-- Loads the `content` or `templates` dirs into tables
local function loaddir(dir)
	if dir:sub(-1, -1) ~= '/' then
		dir = dir .. '/'
	end
	
	local out_table = {}
	for filename in lfs.dir(dir) do
		if filename ~= '.' and filename ~= '..' then
			local filepath = dir .. filename
			local attributes = lfs.attributes(filepath)
			if attributes.mode == 'directory' then
				out_table[filename] = loaddir(filepath)
			else
				local content = {_is_page=true}
				--`filename:find("(.+)%.")` matches everything up to the final `.`
				-- eg. `first_post` from `first_post.md`.
				local _, _, name = filename:find("(.+)%.")
				content.name = name
				
				local handle = io.open(filepath)
				content.text = handle:read('*all') or '\nSimpleSites: Error reading file!\n'
				handle:close()
				
				content.accessed_time = attributes.access
				content.changed_time = attributes.change
				content.modified_time = attributes.modification
				
				content.title = content.text:match("#(.-)\n") or content.name
				
				out_table[name] = content
			end
		end
	end
	
	return out_table
end

-- Evaluate code blocks & assemble templates; then render markdown to HTML
local function render(content, template, content_table, templates_table)
    
    local cursor = 0
	local_content_table = deepcopy(content_table)
	local_content_table['auto'] = content
	local text = template.text
	repeat
		-- find and run {{ template blocks }}
		local blockstart, blockend = text:find("{{.-}}", cursor)
		if not blockstart then break end -- Reached EOF
		cursor = blockstart
		local block_string = text:sub(blockstart + 2, blockend - 2)
		local block, err = loadstring(block_string)
		
		if block then
			-- Allow the block access to local tables
			setfenv(block, {
				content=local_content_table,
				templates=templates_table,
				pairs=pairs,
				ipairs=ipairs,
				string=string,
				tostring=tostring,
				print=print,
				tonumber=tonumber,
				math=math,
				table=table,
				error=error,
			})
			
			local success, output = pcall(block)
			if success then
                output = output or ""
				local starttext = text:sub(1, blockstart-1)
				local endtext = text:sub(blockend+1, -1)
				text = starttext .. output .. endtext
			else
				cursor = blockend
				print("Error running code block: "..output.."\n"..block_string)
			end
		else -- Bad lua in the code block, don't evaluate & leave as is.
			cursor = blockend
			print("Error loading code block: "..err.."\n"..block_string)
		end
	
	until cursor == nil or cursor > #text
	
	return parse_markdown(text)
end

-- Navigate the filesystem to match content to templates,
-- using the nearest template in the tree; render templates with content
local function recursive_render(content_table, templates_table, cursor, content_root)
	cursor = cursor or {} -- cursor keeps track of which subdir we're in
	content_root = content_root or content_table -- Store the top level of the tree
	
	for k, content in pairs(content_table) do
		if k ~= "auto" then -- "auto" changes depending which file we're rendering
			if content._is_page == nil then
				local newcursor = deepcopy(cursor)
				table.insert(newcursor, k)
				recursive_render(content, templates_table, newcursor, content_root)
			else
				-- Choose the nearest template in the tree
				local t_table = deepcopy(templates_table)
				local default = templates_table._default
				for _, i in pairs(cursor) do
					if t_table[i] then
						t_table = t_table[i]
						if t_table._default then
							default = t_table._default
						end
					end
				end
				local template = t_table[k] or default
				
-- If there's a folder with the same name as our content.md, don't try to use the folder as a template
				if not template._is_page then
					template = default
				end
				local rendered = render(content, template, content_root, templates_table)
				
				-- Write the rendered page to a file
				local path = ""
				for _, dir in pairs(cursor) do
					path = path .. "/" .. dir
					lfs.mkdir(rootpath.."/public"..path)
				end
				
				local outpath = rootpath.."/public"..path.."/" .. k ..".html"
				local handle = io.open(outpath, "w")
				print("Writing ", "/public"..path.."/" .. k ..".html")
				handle:write(rendered)
				handle:close()
			end
		end
	end
end

-- Check if we're in an initialised SimpleSites project dir
local function check_filesystem()
	for _, dir in pairs({"/content", "/templates", "/static", "/public"}) do
		local attr = lfs.attributes(rootpath..dir)
		if attr == nil or attr.mode ~= "directory" then
			return false
		end
	end
	return true
end

-- Ask to create the file tree for a default project
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
local content = loaddir(rootpath.."/content")

-- Load all the .html templates into the template table
local templates = loaddir(rootpath.."/templates")

-- Copy over the `static` directory
lfs.mkdir(rootpath..'/public/static')
copydir(rootpath.."/static", rootpath.."/public/static")

-- Render all content & save output
recursive_render(content, templates)
