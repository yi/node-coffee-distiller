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
_ = require "underscore"
#async = require "async"
child_process = require 'child_process'
debug = require('debug')('distill')

RE_REQUIRE = /require[\(\ ][\'"]([a-zA-Z0-9\.\_\/\-]+)[\'"]/g

MODULES = {}

quitWithError = (msg)->
  console.error "ERROR: #{msg}"
  process.exit 1

scanModules = (filename, isMain=false) ->
  # 扫描文件中所有 require() 方法

  debug "scanModules filename:#{filename}, isMain:#{isMain}"

  if not fs.existsSync(filename) and path.basename(filename) isnt "index.coffee"
    # in case node require "/path/to/dir"
    oldFilename = filename
    filename = filename.replace(".coffee", "/index.coffee")
    console.warn "WARNING: try #{filename} instead of #{oldFilename}"

  unless fs.existsSync(filename)
    quitWithError "missing coffee file at #{filename}"

  code = fs.readFileSync filename,
    encoding : 'utf8'

  MODULES[filename] =
    id : filename
    code : code
    isMain : isMain

  requires = code.match(RE_REQUIRE) || []

  for module in requires

    # ignore module require
    continue unless module.charAt(0) is "."

    module = resolve(filename, module)

    # ignore included modules
    continue if MODULES[module ]

    # run recesively
    scanModules module

  return

# 将相对路径解析成决定路径
resolve = (base, relative) ->
  return path.normalize(path.join(path.dirname(base), relative)) + ".coffee"

# 合并成一个文件
#def merge_modules(filename, modules={}):
    #file = open(filename, 'w')
    #file.write(AMD_TMPL + '\n')
    #main_id = None
    #for id, module in modules.items():
        #id, code, is_main = module
        ## 加入 AMD define 方法
        #id = id.replace('.coffee', '')
        #head = DEFINE_HEAD % id
        ## 增加缩进
        #head += RE_HEAD.sub('  ', code)
        #head += '\n'
        #file.write(head)
        #if is_main:
            #main_id = id
    #assert main_id
    ## 加入执行命令
    #file.write(EXEC_TAIL % main_id)
    #file.close()
    #return filename

p.main = path.resolve __dirname, (p.main || '')

unless fs.existsSync(p.main) and path.extname(p.main) is '.coffee'
  quitWithError "bad main entrance file: #{p.main}, #{path.extname(p.main)}"

scanModules p.main

debug "distillation complete!"


