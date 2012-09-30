# Internal libs
fs    = require 'fs'
paths = require 'path'
http  = require 'http'

# External libs
async     = require 'async'
WebSocket = require 'ws'

# Shortcuts
log = console.log

# Chrome Agent API in Inspector.json
# http://svn.webkit.org/repository/webkit/trunk/Source/WebCore/inspector/Inspector.json

exports.connect = (chromeUrl, siteUrl) ->
	return new Configuration chromeUrl, siteUrl

class Configuration
	constructor: (@chromeUrl, @siteUrl) ->
		@pendingFiles = []
		
		@chrome = new Chrome @siteUrl
		
		@reset()
		@chrome.debugger.on 'scriptParsed', (script) =>
			if script.url and script.url.substr(0, @siteUrl.length) is @siteUrl
				path = script.url.substr(@siteUrl.length)
				log "Script #{path} was parsed"
				@parsedScripts[path] = script
		
		@cycle()

	reset: ->
		@ready = false
		@parsedScripts = {}

	cycle: ->
		log "Trying to connect to Chrome"
		repeat = => setTimeout((=> @cycle()), 2000)
	
		getJson @chromeUrl + "json", (err, tabs) =>
			return repeat() if err
			@findDebuggerForSite @siteUrl, tabs, (url) =>
				return repeat() unless url
				@connect url

	findDebuggerForSite: (url, tabs, callback) ->
		for tab in tabs
			continue unless tab.webSocketDebuggerUrl
			if tab.url.substr(0, url.length) is url
				callback tab.webSocketDebuggerUrl
				return
		
		callback null

	connect: (debuggerUrl) ->
		ws = new WebSocket debuggerUrl
		
		ws.once 'open', =>
			log '[Chrome] Connected'
			@chrome.setConnection ws
			@chrome.css.enable => @chrome.debugger.enable => @chrome.network.enable => @chrome.page.enable =>
				@ready = true
				@synchronize()
		
		ws.once 'close', =>
			log '[Chrome] Disconnected'
			@chrome.setConnection null
			@reset()
			@cycle()
		
		ws.on 'message', (data, flags) =>
			@chrome.onMessage JSON.parse(data)
		
		ws.on 'error', (err) =>
			log "[Chrome] Error: #{JSON.stringify err}"

	reload: ->
		@chrome.page.reload() if @ready

	refreshFile: (path, type) ->
		files = @pendingFiles[type + 's'] ?= {}
		files[path] = true
		@synchronize()

	refreshScript: (script) ->
		@refreshFile script, 'script'
	
	refreshStyle: (style) ->
		@refreshFile style, 'style'
	
	refreshImage: (image) ->
		@refreshFile image, 'image'
	
	synchronize: ->
		return unless @ready
		
		files = @pendingFiles
		@pendingFiles = {}
		
		updateFile = (path, strategy, done) ->
			log "Updating: #{path}"
			code = fs.readFileSync path, 'utf-8'
			strategy code, (err) ->
				return done err if err
				log "Finished: #{path}"
				done()
		
		updateAttribute = (nodeId, name, done) =>
			log "Updating: node #{nodeId}"
			@chrome.dom.getAttributes nodeId, (err, list) =>
				return done err if err
				
				list.shift() while list.length and list.shift() isnt name
				return done() unless value = list.shift()
				
				@chrome.dom.setAttributeValue nodeId, name, value, (err) =>
					log "Finished: node #{nodeId}"
					done err
		
		updateStyles = (done) =>
			return done() unless files.styles
			@chrome.css.getAllStyleSheets (err, headers) =>
				return done err if err
				async.forEach headers, (style, done) =>
					path = style.sourceURL.substr @siteUrl.length
					return done() unless files.styles[path]
					updateFile path, (code, callback) =>
						@chrome.css.setStyleSheetText style.styleSheetId, code, callback
					, done
				, done

		updateScripts = (done) =>
			return done() unless files.scripts
			@chrome.debugger.canSetScriptSource (err, available) =>
				return done err if err
				return done "Cannot set script source" unless available
				async.forEach Object.keys(files.scripts), (path, done) =>
					return done() unless script = @parsedScripts[path]
					updateFile path, (code, callback) =>
						@chrome.debugger.setScriptSource script.scriptId, code, callback
					, done
				, done

		# Update images
		updateImages = (done) =>
			return done() unless files.images
			async.parallel [
				# Update tags
				(done) =>
					@chrome.dom.getDocument (err, doc) =>
						return done err if err
						# Document node => HTML node => BODY node
						body = doc.children[1].children[1]
						async.forEach Object.keys(files.images), (path) =>
							escapedFile = paths.basename(path).replace("'", '\\')
							async.parallel [
								# Reapply src attributes that might refer to the current image
								(done) =>
									@chrome.dom.querySelectorAll body.nodeId, "*[src*='#{escapedFile}']", (err, nodeIds) =>
										return done err if err
										async.forEach nodeIds, (nodeId, done) =>
											updateAttribute nodeId, 'src', done
										, done
								# Reapply inline style attributes that might refer to the current image
								(done) =>
									@chrome.dom.querySelectorAll body.nodeId, "*[style*='#{escapedFile}']", (err, nodeIds) =>
										return done err if err
										async.forEach nodeIds, (nodeId, done) =>
											updateAttribute nodeId, 'style', done
										, done
							], done
						, done
				# Reapply all external style sheets
				(done) =>
					@chrome.css.getAllStyleSheets (err, headers) =>
						return done err if err
						async.forEach headers, (style, done) =>
							async.waterfall [
								(next)       => @chrome.css.getStyleSheetText style.styleSheetId, next
								(code, next) => @chrome.css.setStyleSheetText style.styleSheetId, code, next
							], done
						, done
			], done
		
		async.series [
			(next) => @chrome.network.setCacheDisabled true, next
			(next) => async.parallel [updateStyles, updateImages, updateScripts], next
			(next) => @chrome.network.setCacheDisabled false, next
		], (err) =>
			throw err if err
			log "DONE!"

class Chrome
	constructor: (@siteUrl) ->
		@installApi()
		@listeners = {}
		@setConnection null
		
	setConnection: (@ws) ->
		@nextId = 0
		@calls = {}

	installApi: ->
		call = (domainName, commandSpec, args) =>
			method   = domainName + '.' + commandSpec.name
			
			userCallback = if args.length > 0 and args[args.length-1].apply? then args.pop() else null
			
			callback = (err, result) ->
				return unless userCallback
				
				args = [err]
				unless err
					for paramSpec, i in commandSpec.returns ? []
						args.push result[paramSpec.name]
				userCallback.apply null, args
			
			params   = {}
			for paramSpec, i in commandSpec.parameters ? []
				unless i < args.length
					throw new Error "Missing parameter ##{i+1} (#{paramSpec.name}) for #{method}" unless paramSpec.optional
					break
				params[paramSpec.name] = args[i]
			
			@send method, params, callback
	
		api = JSON.parse fs.readFileSync __dirname + '/Inspector.json'
		api.domains.forEach (domainSpec) =>
			domainName = domainSpec.domain
			domainApi = @[domainName.toLowerCase()] = {}
			domainApi.on = (eventName, callback) => (@listeners[domainName + '.' + eventName] ?= []).push callback
			domainSpec.commands.forEach (commandSpec) =>
				domainApi[commandSpec.name] = (args...) => call domainName, commandSpec, args
	
	send: (method, params, callback) ->
		if params?.apply?
			callback = params
			params = {}
		
		id = @nextId++
		@calls[id] = { method, params, callback }
		
		data = JSON.stringify
			id: id
			method: method
			params: params

		@ws.send data, (err) -> throw err if err
	
	onMessage: (message) ->
		if message.id?
			call = @calls[message.id]
			if call
				delete @calls[message.id]
				
				# Convert the object into a throwable error
				if message.error
					filter = (key, value) ->
						return value.slice(0, 11) + "..." + value.slice(-11) if typeof value is 'string' and value.length > 25
						return value
					params = JSON.stringify call.params, filter, "  "
					
					text = message.error.message
					text += "\n" + message.data.join "\n" if message.data
					text += "\n" + call.method + "(" + params + ")"
					
					message.error = new Error text
				
				if callback = call.callback
					callback message.error, message.result
				else if message.error
					throw message.error
		else if message.method
			if listeners = @listeners[message.method]
				for listener in listeners
					listener message.params
		else
			log "Unhandled message:"
			log message
	

uniqueItems = (array) ->
	items = {}
	items[array[key]] = array[key] for key in [0...array.length]
	value for key, value of items
	
getJson = (url, callback) ->
	onSuccess = (res) ->
		res.setEncoding 'utf8'
		
		buffer = []
		res.on 'data', (chunk) ->
			buffer.push chunk
		res.on 'end', ->
			callback null, JSON.parse(buffer.join(''))
	
	onError = (err) ->
		callback err
	
	http.get(url, onSuccess).on('error', onError);