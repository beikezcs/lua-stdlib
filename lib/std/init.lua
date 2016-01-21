--[[--
 Enhanced Lua core functions, and others.

 After requiring this module, simply referencing symbols in the
 submodule hierarchy will load the necessary modules on demand.

 By default there are no changes to any global symbols, or monkey
 patching of core module tables and metatables.  However, sometimes it's
 still convenient to do that: For example, when using stdlib from the
 REPL, or in a prototype where you want to throw caution to the wind and
 compatibility with other modules be damned. In that case, you can give
 stdlib permission to scribble all over your namespaces by using the
 various `monkey_patch` calls in the library.

 @todo Write a style guide (indenting/wrapping, capitalisation,
   function and variable names); library functions should call
   error, not die; OO vs non-OO (a thorny problem).
 @todo pre-compile.
 @corefunction std
]]


local _ENV		= _ENV
local _G		= _G
local error		= error
local ipairs		= ipairs
local pairs		= pairs
local pcall		= pcall
local rawset		= rawset
local require		= require
local setmetatable	= setmetatable
local tostring		= tostring
local type		= type

local string_format	= string.format
local string_match	= string.match


local deprecated	= require "std.delete-after.a-year"

local _ = {
  debug_init		= require "std.debug_init",
  std			= require "std.base",
  typing		= require "std.typing",
}

local _DEBUG		= _.debug_init._DEBUG
local _ipairs		= _.std.ipairs
local _pairs		= _.std.pairs
local _tostring		= _.std.tostring
local argscheck		= _.typing.argscheck
local compare		= _.std.list.compare
local copy		= _.std.base.copy
local eval		= _.std.eval
local getmetamethod	= _.std.getmetamethod
local ielems		= _.std.ielems
local maxn		= _.std.table.maxn
local merge		= _.std.base.merge
local ripairs		= _.std.ripairs
local split		= _.std.string.split


if _DEBUG.strict then
  local ok, strict	= pcall (require, "strict")
  if ok then
    _ENV = strict {}
  end
end

_ = nil




--[[ =============== ]]--
--[[ Implementation. ]]--
--[[ =============== ]]--


local M, monkeys


local function monkey_patch (namespace)
  copy (namespace or _G, monkeys)
  return M
end


local function _assert (expect, fmt, arg1, ...)
  local msg = (arg1 ~= nil) and string_format (fmt, arg1, ...) or fmt or ""
  return expect or error (msg, 2)
end


local function barrel (namespace)
  namespace = namespace or _G

  -- Older releases installed the following into _G by default.
  for _, name in pairs {
    "functional.bind", "functional.collect", "functional.compose",
    "functional.curry", "functional.filter", "functional.id",
    "functional.map",

    "io.die", "io.warn",

    "string.pickle", "string.prettytostring", "string.render",

    "table.pack",

    "tree.ileaves", "tree.inodes", "tree.leaves", "tree.nodes",
  } do
    local module, method = name:match "^(.*)%.(.-)$"
    namespace[method] = M[module][method]
  end

  -- Support old api names, for backwards compatibility.
  namespace.fold = M.functional.fold
  namespace.metamethod = M.getmetamethod
  namespace.op = M.operator
  namespace.require_version = M.require

  require "std.io".monkey_patch (namespace)
  require "std.math".monkey_patch (namespace)
  require "std.string".monkey_patch (namespace)
  require "std.table".monkey_patch (namespace)

  return monkey_patch (namespace)
end


local function elems (t)
  -- capture _pairs iterator initial state
  local fn, istate, ctrl = _pairs (t)
  return function (state, _)
    local v
    ctrl, v = fn (state, ctrl)
    if ctrl then return v end
  end, istate, true -- wrapped initial state
end


local function npairs (t)
  local m = getmetamethod (t, "__len")
  local i, n = 0, m and m(t) or maxn (t)
  return function (t)
    i = i + 1
    if i <= n then return i, t[i] end
   end,
  t, i
end


local function rnpairs (t)
  local m = getmetamethod (t, "__len")
  local oob = (m and m (t) or maxn (t)) + 1

  return function (t, n)
    n = n - 1
    if n > 0 then
      return n, t[n]
    end
  end, t, oob
end


local function vcompare (a, b)
  return compare (split (a, "%."), split (b, "%."))
end


local function _require (module, min, too_big, pattern)
  pattern = pattern or "([%.%d]+)%D*$"

  local s, m = "", require (module)
  if type (m) == "table" then s = tostring (m.version or m._VERSION or "") end
  local v = string_match (s, pattern)
  if min then
    _assert (vcompare (v, min) >= 0, "require '" .. module ..
            "' with at least version " .. min .. ", but found version " .. v)
  end
  if too_big then
    _assert (vcompare (v, too_big) < 0, "require '" .. module ..
            "' with version less than " .. too_big .. ", but found version " .. v)
  end
  return m
end



--[[ ================= ]]--
--[[ Public Interface. ]]--
--[[ ================= ]]--


local function X (decl, fn)
  return argscheck ("std." .. decl, fn)
end

M = {
  --- Release version string.
  -- @field version


  --- Core Functions
  -- @section corefuncs

  --- Enhance core `assert` to also allow formatted arguments.
  -- @function assert
  -- @param expect expression, expected to be *truthy*
  -- @string[opt=""] f format string
  -- @param[opt] ... arguments to format
  -- @return value of *expect*, if *truthy*
  -- @usage
  -- std.assert (expect == nil, "100% unexpected!")
  -- std.assert (expect == "expect", "%s the unexpected!", expect)
  assert = X ("assert (?any, ?string, [any...])", _assert),

  --- Evaluate a string as Lua code.
  -- @function eval
  -- @string s string of Lua code
  -- @return result of evaluating `s`
  -- @usage
  -- --> 2
  -- std.eval "math.min (2, 10)"
  eval = X ("eval (string)", eval),

  --- Return named metamethod, if any, otherwise `nil`.
  -- The value found at the given key in the metatable of *x* must be a
  -- function or have its own `__call` metamethod to qualify as a
  -- callable. Any other value found at key *n* will cause this function
  -- to return `nil`.
  -- @function getmetamethod
  -- @param x item to act on
  -- @string n name of metamethod to lookup
  -- @treturn callable|nil callable metamethod, or `nil` if no metamethod
  -- @usage
  -- clone = std.getmetamethod (std.object.prototype, "__call")
  getmetamethod = X ("getmetamethod (?any, string)", getmetamethod),

  --- Enhance core `tostring` to render table contents as a string.
  -- @function tostring
  -- @param x object to convert to string
  -- @treturn string compact string rendering of *x*
  -- @usage
  -- -- {1=baz,foo=bar}
  -- print (std.tostring {foo="bar","baz"})
  tostring = X ("tostring (?any)", _tostring),


  --- Module Functions
  -- @section modulefuncs

  --- A [barrel of monkey_patches](http://dictionary.reference.com/browse/barrel+of+monkeys).
  --
  -- Apply **all** of stdlib's `monkey_patch` functions to *namespace*.
  --
  -- Additionally, for backwards compatibility only, write an historical
  -- selection of stdlib submodule functions into the given namespace too
  -- (at least until the next major release).
  -- @function barrel
  -- @tparam[opt=_G] table namespace where to install global functions
  -- @treturn table module table
  -- @usage local std = require "std".barrel ()
  barrel = X ("barrel (?table)", barrel),

  --- Overwrite core methods and metamethods with `std` enhanced versions.
  --
  -- Write all functions from this module, except `std.barrel` and
  -- `std.monkey_patch`, into *namespace*.
  -- @function monkey_patch
  -- @tparam[opt=_G] table namespace where to install global functions
  -- @treturn table the module table
  -- @usage local std = require "std".monkey_patch ()
  monkey_patch = X ("monkey_patch (?table)", monkey_patch),

  --- Enhance core `require` to assert version number compatibility.
  -- By default match against the last substring of (dot-delimited)
  -- digits in the module version string.
  -- @function require
  -- @string module module to require
  -- @string[opt] min lowest acceptable version
  -- @string[opt] too_big lowest version that is too big
  -- @string[opt] pattern to match version in `module.version` or
  --  `module._VERSION` (default: `"([%.%d]+)%D*$"`)
  -- @usage
  -- -- posix.version == "posix library for Lua 5.2 / 32"
  -- posix = require ("posix", "29")
  require = X ("require (string, ?string, ?string, ?string)", _require),

  --- Iterator Functions
  -- @section iteratorfuncs

  --- An iterator over all values of a table.
  -- If *t* has a `__pairs` metamethod, use that to iterate.
  -- @function elems
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table *t*, the table being iterated over
  -- @return *key*, the previous iteration key
  -- @see ielems
  -- @see pairs
  -- @usage
  -- --> foo
  -- --> bar
  -- --> baz
  -- --> 5
  -- std.functional.map (print, std.ielems, {"foo", "bar", [4]="baz", d=5})
  elems = X ("elems (table)", elems),

  --- An iterator over the integer keyed elements of a table.
  --
  -- If *t* has a `__len` metamethod, iterate up to the index it
  -- returns, otherwise up to the first `nil`.
  --
  -- This function does **not** support the Lua 5.2 `__ipairs` metamethod.
  -- @function ielems
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table *t*, the table being iterated over
  -- @treturn int *index*, the previous iteration index
  -- @see elems
  -- @see ipairs
  -- @usage
  -- --> foo
  -- --> bar
  -- std.functional.map (print, std.ielems, {"foo", "bar", [4]="baz", d=5})
  ielems = X ("ielems (table)", ielems),

  --- An iterator over integer keyed pairs of a sequence.
  --
  -- Like Lua 5.1 and 5.3, this iterator returns successive key-value
  -- pairs with integer keys starting at 1, up to the first `nil` valued
  -- pair.
  --
  -- If there is a `_len` metamethod, keep iterating up to and including
  -- that element, regardless of any intervening `nil` values.
  --
  -- This function does **not** support the Lua 5.2 `__ipairs` metamethod.
  -- @function ipairs
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table *t*, the table being iterated over
  -- @treturn int *index*, the previous iteration index
  -- @see ielems
  -- @see npairs
  -- @see pairs
  -- @usage
  -- --> 1	foo
  -- --> 2	bar
  -- std.functional.map (print, std.ipairs, {"foo", "bar", [4]="baz", d=5})
  ipairs = X ("ipairs (table)", _ipairs),

  --- Ordered iterator for integer keyed values.
  -- Like ipairs, but does not stop until the __len or maxn of *t*.
  -- @function npairs
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table t
  -- @see ipairs
  -- @see rnpairs
  -- @usage
  -- --> 1	foo
  -- --> 2	bar
  -- --> 3	nil
  -- --> 4	baz
  -- std.functional.map (print, std.npairs, {"foo", "bar", [4]="baz", d=5})
  npairs = X ("npairs (table)", npairs),

  --- Enhance core `pairs` to respect `__pairs` even in Lua 5.1.
  -- @function pairs
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table *t*, the table being iterated over
  -- @return *key*, the previous iteration key
  -- @see elems
  -- @see ipairs
  -- @usage
  -- --> 1	foo
  -- --> 2	bar
  -- --> 4	baz
  -- --> d	5
  -- std.functional.map (print, std.pairs, {"foo", "bar", [4]="baz", d=5})
  pairs = X ("pairs (table)", _pairs),

  --- An iterator like ipairs, but in reverse.
  -- Apart from the order of the elements returned, this function follows
  -- the same rules as @{ipairs} for determining first and last elements.
  -- @function ripairs
  -- @tparam table t any table
  -- @treturn function iterator function
  -- @treturn table *t*
  -- @treturn number `#t + 1`
  -- @see ipairs
  -- @see rnpairs
  -- @usage
  -- --> 2	bar
  -- --> 1	foo
  -- std.functional.map (print, std.ripairs, {"foo", "bar", [4]="baz", d=5})
  ripairs = X ("ripairs (table)", ripairs),

  --- An iterator like npairs, but in reverse.
  -- Apart from the order of the elements returned, this function follows
  -- the same rules as @{npairs} for determining first and last elements.
  -- @function rnpairs
  -- @tparam table t a table
  -- @treturn function iterator function
  -- @treturn table t
  -- @see npairs
  -- @see ripairs
  -- @usage
  -- --> 4	baz
  -- --> 3	nil
  -- --> 2	bar
  -- --> 1	foo
  -- std.functional.map (print, std.rnpairs, {"foo", "bar", [4]="baz", d=5})
  rnpairs = X ("rnpairs (table)", rnpairs),
}


monkeys = copy ({}, M)

-- Don't monkey_patch these apis into _G!
for _, api in ipairs {"barrel", "monkey_patch", "version"} do
  monkeys[api] = nil
end


if deprecated then
  M = merge (M, deprecated.std)
end



--- Metamethods
-- @section Metamethods

return setmetatable (M, {
  --- Lazy loading of stdlib modules.
  -- Don't load everything on initial startup, wait until first attempt
  -- to access a submodule, and then load it on demand.
  -- @function __index
  -- @string name submodule name
  -- @treturn table|nil the submodule that was loaded to satisfy the missing
  --   `name`, otherwise `nil` if nothing was found
  -- @usage
  -- local std = require "std"
  -- local Object = std.object.prototype
  __index = function (self, name)
              local ok, t = pcall (require, "std." .. name)
              if ok then
		rawset (self, name, t)
		return t
	      end
	    end,
})