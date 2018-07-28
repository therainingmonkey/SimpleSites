# SimpleSites - A very simple static site generator

## Plan:
SimpleSites, when run in the root dir, assembles templates, inserts .md content
and saves the output to the `public` directory.


### How it works:

1. build a `templates` table and a `content` table, containing the processed output of each file
2. for each file in `content`:
	* open the corresponding file in `templates`
	* split the text at `{{ }}`, execute the lua inbetween and insert it's string output


### Proposed file structure:

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
