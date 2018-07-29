#!/usr/bin/env lua
-- TODO: Create a lockfile while we work

local lfs = require "lfs"
local parse_markdown = require "discount"

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
	outfile:write(infile:read("*all"))
	infile:close()
	outfile:close()
end

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
-- workingdir should be "" when first called (it's used in recursive calls)
local function loaddir(rootdir, out_table, workingdir)
	workingdir = workingdir or ""
	local table_cursor = out_table
	if workingdir:sub(-1,-1) ~= "/" then workingdir = workingdir .. "/" end
	-- For each chunk of string split at `/`, eg. alice & bob in /alice/bob/
	for dir in workingdir:gmatch("(.-)/") do
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
				local _, _, file_extension = filename:find("(%..-)$")
				if file_extension == ".md" or file_extension == ".MD" then
					-- Convert markdown to html
					table_cursor[name] = parse_markdown(table_cursor[name])
				end
			end
		end
	end
end

-- Converts md to html and assembles templates
local function render(template_used, content_used)
	local cursor = 0
	content['auto'] = content_used
	repeat
		-- find and run {{ template blocks }}
		local blockstart, blockend = template_used:find("{{.-}}", cursor)
		if not blockstart then return template_used end -- Reached EOF
		cursor = blockstart
		local block_string = template_used:sub(blockstart + 2, blockend - 2)
		local block = loadstring("return "..block_string)
		-- Allow the block access to local tables
		setfenv(block, {content=content, templates=templates})

		-- TODO: Catch & warn on errors in template code

		local starttext = template_used:sub(1, blockstart-1)
		local blocktext = block()
		local endtext = template_used:sub(blockend+1, -1)

		template_used = starttext .. blocktext .. endtext

	until cursor == nil or cursor > #template_used
end

local function recursive_render(content_table, cursor)
	cursor = cursor or {}
	for k, v in pairs(content_table) do
		if k ~= "auto" then
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

-- Load all the content .md files into the content table
loaddir(rootpath.."/content", content)
-- Load all the .html templates into the template table
loaddir(rootpath.."/templates", templates)

-- Copy over the `static` directory
copydir(rootpath.."/static", rootpath.."/public")

-- Render all content & save output
recursive_render(content)
