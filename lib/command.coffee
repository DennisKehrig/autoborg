# Coffee-Script friendly error messages
process.on 'uncaughtException', require 'ansinception'

# Config
configFile = 'autoborg.json'

# Internal libs
fs            = require 'fs'
paths         = require 'path'
child_process = require 'child_process'

# External libs
coffee = require 'coffee-script'
jade   = require 'jade'
stylus = require 'stylus' 
uglify = require 'uglify-js'

# Local libs
chrome = require './clients/chrome'

# Shortcuts
log = console.log

actions =
	reload_clients: (path, response) ->
		response.reload()

	update_style: (path, response) ->
		response.refreshStyle path

	update_script: (path, response) ->
		response.refreshScript path

	update_image: (path, response) ->
		response.refreshImage path

	# Compile Coffee-Script to JavaScript
	convert_coffee_to_js: (path, response) ->
		coffeeCode = fs.readFileSync path, 'ascii'
		jsCode = coffee.compile coffeeCode
		
		response.writeFile setExtension(path, 'js'), jsCode

	# Compile Coffee-Script to JavaScript including a source map
	convert_coffee_to_js_with_sourcemap: (path, response) ->
		coffeeCode = fs.readFileSync path, 'ascii'

		fileName = paths.basename path
		result = coffee.compile coffeeCode,
			sourceMap:     true
			sourceFiles:   [fileName]
			filename:      fileName
			generatedFile: setExtension(fileName, 'js')

		result.js += "\n/*\n//@ sourceMappingURL=" + setExtension(paths.basename(path), 'map') + "\n*/\n"
		
		response.writeFile setExtension(path, 'js'), result.js
		response.writeFile setExtension(path, 'map'), result.v3SourceMap

	# Compile Jade to a require.js module
	convert_jade_to_js_module: (path, response) ->
		jadeCodeBuffer = fs.readFileSync path
		jsFunc = jade.compile jadeCodeBuffer, client: true, filename: path, compileDebug: true
		jsCode = 'define(function() { return ' + jsFunc.toString() + '; });'
		
		response.writeFile setExtension(path, 'js'), jsCode

	# Compile Jade to HTML
	convert_jade_to_html: (path, response) ->
		jadeCodeBuffer = fs.readFileSync path
		jsFunc = jade.compile jadeCodeBuffer, filename: path
		htmlCode = jsFunc()
		
		response.writeFile setExtension(path, 'html'), htmlCode

	# Compile Stylus to CSS
	convert_stylus_to_css: (path, response) ->
		stylCode = fs.readFileSync path, 'utf8'
		cssCode = ''
		stylus(stylCode).set('filename', path).set('compress', true).render (err, output) ->
			throw err if err
			cssCode = output
		
		response.writeFile setExtension(path, 'css'), cssCode

	merge_and_minify_scripts: (path, response) ->
		mergeAssets path, response, (code, filePath, directory) ->
			return code if filePath.substr(-7) is '.min.js'
			# Add a trailing semicolon to avoid syntax errors
			return minify(code) + ';'
	
	merge_and_minify_styles: (path, response) ->
		mergeAssets path, response, (code, filePath, directory) ->
			# Adjust paths in CSS rules, like background-image: url(...);
			move = paths.relative(directory, paths.dirname(filePath)).replace('\\', '/')
			code = code.replace(/url\((["']?)([^)]+)\1\)/g, 'url($1' + move + '/$2$1)')

# Like preg_escape (PHP)
escapeRegExp = (text) ->
	return text.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&")

# '/foo/bar.abc' => '/foo/bar.<extension>'
setExtension = (path, extension) ->
	return path.replace /\.[^\.]+$/, '.' + extension

# Minify JavaScript code
minify = (js) ->
	ast = uglify.parser.parse js
	ast = uglify.uglify.ast_mangle ast
	ast = uglify.uglify.ast_squeeze ast
	jsCode = uglify.uglify.gen_code ast
	
	return jsCode

# Merge multiple files into a big minified one
mergeAssets = (configPath, response, strategy) ->
	# Get file list
	files = JSON.parse fs.readFileSync(configPath)
	
	# Remember this directory
	directory = paths.dirname configPath
	# Remove .json extension
	mergedPath = configPath.substr 0, configPath.length - 5
	
	# Add all source files to the buffer
	buffer = []
	for relativePath in files
		try
			# Ignore entries that start with // (The JSON format doesn't allow comments)
			continue if relativePath.substr(0, 2) is '//'
			path = directory + '/' + relativePath
			
			code = fs.readFileSync path, 'utf-8'
			code = strategy code, path, directory
			
			buffer.push "/* #{relativePath} */\n" + code
		catch err
			log "mergeAssets: Error while adding #{relativePath}: #{err.stack}"
	
	# Merge the result and write it to disk
	response.writeFile mergedPath, buffer.join("\n\n")

onRuleMatched = (rules, clients, rule, path, memory) ->
	info = memory[path]
	
	try
		stats = fs.statSync path
	catch err
		throw err unless err.code is 'ENOENT'
		
		# File not found
		if info
			# File was renamed or deleted => delete previously generated files
			log "#{path} was renamed or deleted"
			for derivedPath in info.files
				log "Deleting #{derivedPath}"
				fs.unlinkSync derivedPath
			
			# Forgot about this file
			delete memory[path]
		
		# Nothing else to do
		return
	
	mtime = stats.mtime.getTime()
	return if info?.mtime is mtime
	
	info = memory[path] = mtime: mtime, files: []
	
	log "Processing #{path}"
	compile = rules[rule]
	response =
		writeFile: (derivedPath, contents) ->
			info.files.push derivedPath
			if derivedPath is path
				throw new Error 'Denied request to overwrite the source file'
			fs.writeFileSync derivedPath, contents
		
		reload: ->
			for name, client of clients
				client.reload()
		
		refreshStyle: (path) ->
			for name, client of clients
				client.refreshStyle path
		
		refreshScript: (path) ->
			for name, client of clients
				client.refreshScript path
		
		refreshImage: (path) ->
			for name, client of clients
				client.refreshImage path

	try
		compile path, response
	catch err
		log "Error while running compiler for rule #{rule}:"
		log err.stack
	
start = (config) ->
	log "Starting auto compilation"
	
	rules = {}
	for rule, id of config.actions
		unless actions[id]
			log "Unknown action #{id}"
			continue
		rules[rule] = actions[id]
	
	clients = {}
	for id, url of config.clients
		if id is 'chrome'
			clients[id] = chrome.connect url, config.url
		else
			log "Unknown client #{id}"

	watchers = makeWatchers rules
	memory = {}
	
	do ->
		#process.stdout.write '.'
		
		for watcher in watchers
			if watcher.type is 'file'
				onRuleMatched rules, clients, watcher.rule, watcher.path, memory
			if watcher.type is 'directory'
				directory = watcher.directory
				try
					files = fs.readdirSync directory
				catch err
					continue if err.code is 'ENOENT'
					throw err
			
				matcher = watcher.matcher
				for file in files
					continue unless matcher.test file
					onRuleMatched rules, clients, watcher.rule, directory + file, memory
		
		setTimeout arguments.callee, 100
	
makeMatcher = (rule) ->
	matcher = escapeRegExp rule
	matcher = matcher.replace '\\*', '[^\\/]+'
	matcher = new RegExp matcher
	
	return matcher

makeWatchers = (rules) ->
	matcher = /^(\/?(?:[^\/]+\/)*)([^\/]+)$/
	watchers = []

	for rule, compile of rules
		throw new Error "Failed to split #{rule} into directory and file name" unless matcher.test rule
		[directory, file] = [RegExp.$1, RegExp.$2]
		directory = './' if directory is ''
		
		if file.indexOf('*') is -1
			watchers.push rule: rule, type: 'file', path: rule, 
		else
			watchers.push rule: rule, type: 'directory', directory: directory, matcher: makeMatcher(file)

	return watchers

readConfig = (done) ->
	try
		# Read the config file
		config = fs.readFileSync configFile
		config = JSON.parse config
		done null, config
	catch err
		log "Error while reading #{configFile}: #{err.message}"
		done err
	
exports.run = ->
	readConfig (err, config) ->
		return process.exit() if err
		start config
