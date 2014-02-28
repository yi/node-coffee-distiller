# coffee-distiller

This tool does three things:

1. combine multiple server side coffee-script file into one coffee file with fake CJS wrapper
2. compile the combiled coffee file into javascript file
3. uses google closure compiler or uglify-js2 to minify the javascritp file

## Why and Who need this tool

This tool is useful for developers who want to distribute a SERVER SIDE coffee-script app in the form of a single javascript file.

CommonJS module has its built-in module scope, thus developers can not simple combine server side coffee-script files like what they do on the client side.

This tool introduces a fake CJS module wrapper and merges coffee-script files, as well as keeps scopes of each module.

## Install

```bash
npm install coffee-script coffee-distiller  -g
```

## Usage

Use in command line

```bash
distill -i path/to/app.coffe -o dist/app.js

# this will generate 3 files in ./dist/ directory:
# - app.coffee : a merged coffee file
# - app.js : compiled javascript file from app.coffee
# - app.min.js : minified javascript file from app.js
```

## Command line options

* -h, --help            output usage information
* -V, --version         output the version number
* -o, --output [VALUE]  output directory
* -i, --input [VALUE]   path to main entrance coffee file
* -m, --minify [type]   minify merged javascript file. [closure(default)] use Closure Compiler, [uglify] use uglify-js2, [none] do not minify js code
* -n, --onlyKeepMinifiedFile  only keep minified js output file




