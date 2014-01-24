#!/usr/bin/env coffee

##
# coffee-distiller
# https://github.com/yi/node-coffee-distiller
#
# Copyright (c) 2014 yi
# Licensed under the MIT license.
##

pkg = require "../package"
p = require "commander"
## cli parameters
p.version(pkg.version)
  .option('-o, --output [VALUE]', 'output directory')
  .option('-m, --main [VALUE]', 'main entrance coffee file')
  .parse(process.argv)

# {{{ AMD 模版
AMD_TMPL = '''
## Module dependencies
nativePath = require "path"
# NativeModule = require "native_module"

# A hack to fix requiring external module issue
nativeRequire = require
m = require "module"
hackRequire = (id) -> m._load id, module
# A hack to make cluster work
# cluster = NativeModule.require 'cluster'
nativeCluster = require 'cluster'
nativeCluster.settings.exec = "_third_party_main"
if process.env.NODE_UNIQUE_ID
  nativeCluster._setupWorker()
  # Make sure it's not accidentally inherited by child processes.
  delete process.env.NODE_UNIQUE_ID

# A cache object contains all modules with their ids
_MODULES_BY_ID = {}

# Internal module class holding module id, dependencies and exports
class Module

  constructor: (@id, @factory) ->
    # Append module to cache
    _MODULES_BY_ID[@id] = this

  # Initialize exports
  initialize: ->
    @exports = {}
    # Imports a module
    @require or= (id) =>
      # If this is a relative path
      if id.charAt(0) == "."
        # Resolve id to absolute path
        id = nativePath.normalize(nativePath.join(nativePath.dirname(@id), id))
        mod = _MODULES_BY_ID[id]
        throw new Error("module #{id} is not found") unless mod
        return mod.exports if mod.exports?
        mod.initialize()
      else
        hackRequire id
    @factory.call this, @require, @exports, this
    @exports

# Define a module.
define = (id, factory) ->
  throw new Error("id must be specifed") unless id
  throw new Error("module #{id} is already defined") if id of _MODULES_BY_ID
  new Module(id, factory)

# Start a module
exec = (id) ->
  module = _MODULES_BY_ID[id]
  module.initialize()
'''
# }}}

path = require "path"
fs = require "fs"
mkdirp = require "mkdirp"
_ = require "underscore"
#async = require "async"
child_process = require 'child_process'
debug = require('debug')('distill')

DEFINE_HEAD = "\ndefine '%s', (require, exports, module) ->\n"

EXEC_TAIL = "\nexec '%s'"

RE_REQUIRE = /^.*require[\(\ ][\'"]([a-zA-Z0-9\.\_\/\-]+)[\'"]/mg

RE_HEAD = /^/mg

OUTPUT_JS_FILE = ""

OUTPUT_MINIFIED_JS_FILE = ""

OUTPUT_COFFEE_FILE = ""

MODULES = {}

quitWithError = (msg)->
  console.error "ERROR: #{msg}"
  process.exit 1

scan = (filename, isMain=false, source) ->
  # 扫描文件中所有 require() 方法

  debug "scan: #{filename} (required by: #{source or 'Root'})"

  if not fs.existsSync(filename) and path.basename(filename) isnt "index.coffee"
    # in case node require "/path/to/dir"
    oldFilename = filename
    filename = filename.replace(".coffee", "/index.coffee")
    console.warn "WARNING: missing coffee file at #{oldFilename}, try #{filename} (required by: #{source or 'Root'})"

  unless fs.existsSync(filename)
    quitWithError "missing coffee file at #{filename} (required by: #{source or 'Root'})"

  code = fs.readFileSync filename,
    encoding : 'utf8'

  MODULES[filename] =
    id : filename
    code : code
    isMain : isMain

  requires = []

  code.replace RE_REQUIRE, ($0, $1)->
    requires.push $1 if $1? and (!~$0.indexOf('#') and  $0.indexOf('#') < $0.indexOf('require'))
    arguments[arguments.length - 1] = null
    #console.dir arguments

  #requires = code.match(RE_REQUIRE) || []

  #console.dir requires

  for module in requires

    # ignore module require
    continue unless module.charAt(0) is "."

    module = resolve(filename, module)

    # ignore included modules
    continue if MODULES[module ]

    # run recesively
    scan module, false, filename

  return

# 将相对路径解析成决定路径
resolve = (base, relative) ->
  return path.normalize(path.join(path.dirname(base), relative)) + ".coffee"

# 合并成一个文件
merge = ->
  debug "do merge"

  result = "#{AMD_TMPL}\n\n"

  for id, module of MODULES
    #console.dir module
    id = id.replace('.coffee', '')
    result  += DEFINE_HEAD.replace('%s', id)
    result  += module.code.replace(RE_HEAD, '  ')
    result  += " \n"

  result  += EXEC_TAIL.replace('%s', p.main.replace('.coffee', ''))
  fs.writeFileSync(OUTPUT_COFFEE_FILE, result)

## validate input parameters
unless p.main?
  quitWithError "missing main entrance coffee file (-m), use -h for help."

p.main = path.resolve process.cwd(), (p.main || '')

unless fs.existsSync(p.main) and path.extname(p.main) is '.coffee'
  quitWithError "bad main entrance file: #{p.main}, #{path.extname(p.main)}."

p.output = path.resolve(process.cwd(), p.output || '')
outputBasename = if path.extname(p.output) is ".js" then path.basename(p.output, '.js') else path.basename(p.main, 'coffee')
OUTPUT_JS_FILE = path.join path.dirname(p.output), "#{outputBasename}.js"
OUTPUT_MINIFIED_JS_FILE = path.join path.dirname(p.output), "#{outputBasename}.min.js"
OUTPUT_COFFEE_FILE = path.join path.dirname(p.output), "#{outputBasename}.coffee"
mkdirp.sync(path.dirname(OUTPUT_JS_FILE))

## scan modules
console.log "[coffee-distiller] scanning..."
scan(p.main)

console.log "[coffee-distiller] merging #{_.keys(MODULES).length} coffee files..."
merge()

console.log "[coffee-distiller] compile coffer to js..."
child_process.exec "coffee -c #{OUTPUT_COFFEE_FILE}", (err, stdout, stderr)->
  if err?
    quitWithError "coffee compiler failed. error:#{err}, stdout:#{stdout}, stderr:#{stderr}"
    return

  console.log "[coffee-distiller] merging complete! #{path.relative(process.cwd(), OUTPUT_JS_FILE)}"

  console.log "[coffee-distiller] minifying js..."
  child_process.exec "java -jar #{__dirname}/compiler.jar --js #{OUTPUT_JS_FILE} --js_output_file #{OUTPUT_MINIFIED_JS_FILE} --compilation_level SIMPLE_OPTIMIZATIONS ", (err, stdout, stderr)->
    if err?
      quitWithError "minify js failed. error:#{err}, stdout:#{stdout}, stderr:#{stderr}"
      return

    console.log "[coffee-distiller] minifying complete! #{path.relative(process.cwd(), OUTPUT_MINIFIED_JS_FILE)}"


