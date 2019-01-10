# SimpleSites - A very simple static site generator

## Requirements
SimpleSites depends on luafilesystem and markdown.lua
Both are available through luarocks:
`[sudo] luarocks install markdown`
`[sudo] luarocks install luafilesystem`


## About
SimpleSites, when run in the root dir, assembles templates, inserts .md content
and saves the output to the `public` directory.

Templates can contain lua code which will be run inside {{ double curly brackets }}

### Quickstart
```console
~/$ mkdir website
~/$ SimpleSites website/
Couldn't find the right directory structure. Would you like to create it in this dir:
'/media/casper/UltrabayWin/Casper/Documents/Code/SimpleSites/newsite'?  (y/n)
y
Generating new project...                                                                          
Done! Open content/index.md to get started.
~/$ nano website/content/index.md
~/$ SimpleSites website/
Writing         /public/index.html
# Your site has been built! You should be able to serve directly from the /public directory.
```

++TODO++
* Order the content table by file creation date
* Lots more testing



### Example file structure:

```
	root
	| -- public
	|	|--[final output .html]
	|
	| -- content
	|	| -- index.md
	|	| -- posts
	|	|	| -- post1.md
	|	|	| -- post2.md
	|	| -- about.md
	|
	| -- templates
	|	| -- index.html
	|	| -- _default.html
	|	| -- posts
	|	|	| -- _default.html
	|	| -- head.html
	|	| -- menubar.html
	|	| -- footer.html
	|
	| -- static
	|	| -- style.css
	|	| -- images
	|	|	| -- catpic.jpg
```


### Example index.html template
``` lua
{{ return templates.head }}
{{ return templates.menubar }}

{{ return content.auto --finds the matching .md based on filesystem }}

{{
	local output = ""
	
	for name, post in pairs(content.posts) do
	
	-- ### [<POST TITLE>](<URL>)\n<POST TEXT FOLLOWING POST TITLE UP TO 144 CHARS>
	
		output = output .. "### ["..post:match("#(.-)\n").."](".."./posts/"..name..".html)\n\t"..post:match("#.-\n(.*)"):sub(1, 144)
		
	end
	
	return output
}}

{{ return templates.footer }}
```
