# SimpleSites - A very simple static site generator

SimpleSites, when run in the root dir, assembles templates, inserts .md content
and saves the output to the `public` directory.

Templates can contain lua code which will be run inside {{ double curly brackets}}

The tables `content` and `templates` are accessible within code blocks,

++TODO++
* Generate empty file structure / default templates
* Copy `static` dir



### Example file structure:

	root
	| -- public
	|		|--[final output .html]
	|
	| -- content
	|		| -- index.md
	|		| -- posts
	|		|		| -- post1.md
	|		|		| -- post2.md
	|		| -- about.md
	|
	| -- templates
	|		| -- index.html
	|		| -- default.html
	|		| -- posts.html
	|		| -- posts
	|		|		| -- default.html
	|
	| -- static
	|		| -- style.css
	|		| -- images
	|		|		| -- catpic.jpg


### imaginary index.html template
``` html
{{ templates.head }}
{{ templates.menubar }}
<h1>Title!</h1>
{{ content.auto --finds the matching .md based on filesystem, or passed as arg to ss:render() }}
{{
	local output = ""
	for _, post in pairs(content.posts) do
			output = output .. ss:render(templates.posts, post)
	end
	return output
}}
{{ templates.footer }}
```

### imaginary templates/posts.html template
``` html
{{ content.auto:sub(1, 144) -- Only the first 144 chars of content }}
```
