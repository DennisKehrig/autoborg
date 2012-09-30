# Autoborg

I am Autoborg of the browser collective.

Your semantic and syntactic distinctiveness will be added to our own. Your code will be assimilated.

Your life as it has been is over. Your [Coffee-Script](http://coffeescript.org/), [Jade](http://jade-lang.com/) and [Stylus](http://learnboost.github.com/stylus/) will adapt to service us.

### Resistance is futile

Install Autoborg. Why do you resist? You must comply.

	npm install -g autoborg

Create an __autoborg.json__ and surrender your file system.

	{
		"actions": {
			"index.jade"  : "convert_jade_to_html",
			"css/*.styl"  : "convert_stylus_to_css",
			"js/*.coffee" : "convert_coffee_to_js"
		}
	}

From this time forward, run:

	$ autoborg

### Reloading is irrelevant

Start Chrome with remote debugging:

	$ chrome --remote-debugging-port=9222

__autoborg.json__
	
	{
		"url": "http://localhost/project/",
		"clients": {
			"chrome": "http://localhost:9222/" 
		},
		"actions": {
			"index.html" : "reload_clients",
			"css/*.css"  : "update_style",
			"img/*.png"  : "update_image",
			"js/*.js"    : "update_script"
		}
	}

### Modularization is irrelevant

__autoborg.json__

	{
		"actions": {
			"vendor/merged.css.json" : "merge_and_minify_styles",
			"vendor/merged.js.json"  : "merge_and_minify_scripts"
		}
	}

__vendor/merged.css.json__

	[
		"bootstrap/css/bootstrap.min.css",
		"bootstrap/css/bootstrap-responsive.min.css"
	] 

__vendor/merged.js.json__

	[
		"jade-runtime.js",
		"jquery.min.js",
		"jquery.serializeObject.js",
		"bootstrap/js/bootstrap.min.js",
		"require.min.js"
	]

### Perfection is irrelevant

* Only tested on Windows XP SP3 with node.js 0.8.11
* The compiled files are always in the same directory as the source files
* Changes to files merged with `merge_and_minify_*` are not detected
* No wildcards for directories
* Compiles everything on startup instead of checking timestamps
* Reporting of compilation errors is not obvious enough
* Restarts its whole process when autoborg.json changes instead of just starting over
* For automatic reloading/updating, the url field has to be present even for local files
* Chrome is the only supported browser
* Coffee-Script, Jade and Stylus are the only supported languages (for compilation)
* Clients and actions are not yet easily extendable
* Polls the file system (watching is unstable, but should be used, too)
* Polling interval is not configurable
* Depends on Coffee-Script

### Copyright is relevant

The MIT License (MIT) Copyright (c) 2012 Dennis Kehrig. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.