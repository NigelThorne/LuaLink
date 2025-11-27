# AutoBackup Async - BROKEN VERSION

This is a demonstration of Java method resolution failures we encounter when trying to run backup operations in async threads with LuaLink.

## The Problem

We're trying to create an async backup system that:
1. Saves all worlds (works fine on main thread)
2. Copies world files in the background (fails in async thread)
3. Compresses the backup (fails in async thread)

**Everything works perfectly when run synchronously via `scheduler:run()`, but fails with various errors when using `scheduler:runAsync()`.**

## Specific Errors We Encounter

### Error 1: Java NIO Files.copy()
```lua
Files.copy(sourcePath, destPath, StandardCopyOption.REPLACE_EXISTING)
```
**Error:** `bad argument #1 to 'copy' (__jclass__ expected, got userdata)`

The `sourcePath` and `destPath` are valid Path objects created with `file:toPath()`, but the static method `Files.copy()` doesn't recognize them in async threads.

### Error 2: Java byte array creation
```lua
local buffer = java.new("byte[]", 8192)
```
**Error:** `bad argument #1 to 'java.new': __jclass__ or __jobject__ expected`

Creating byte arrays with `java.new()` fails in async threads.

### Error 3: Files.walk()
```lua
local stream = Files.walk(sourcePath)
```
**Error:** `bad argument #1 to 'walk' (__jclass__ expected, got userdata)`

Again, the Path object is valid but the static method doesn't recognize it in async.

### Error 4: Traditional File methods
```lua
if not dest:exists() then
    dest:mkdirs()
end
local files = source:listFiles()
```
**Error:** `no matching method found`

Sometimes works, sometimes fails with "no matching method found" on basic File operations like `:exists()` or `:listFiles()`.

## What We've Tried

1. **Using `java.luaify()` on arrays** - We do this for the file lists, it works
2. **Wrapping in `synchronized()`** - Doesn't help, still fails
3. **Using Java NIO instead of traditional File I/O** - Same errors
4. **Different Java stream approaches** - All fail with similar errors
5. **Writing bytes individually to ZipOutputStream** - Produces corrupt archives

## What Works

- **Everything works in sync threads** - Exact same code in `scheduler:run()` works perfectly
- **Lua native I/O** - `io.open()`, `io.read()`, `io.write()` work fine in async
- **Pure Lua operations** - String manipulation, table operations, math, etc.

## Our Current Workaround

We run everything synchronously:
- For hourly backups, the brief pause is acceptable
- We skip compression and use Lua I/O to copy files
- Everything works, just not async

## Questions for LuaLink Experts

1. **Is async supposed to work with Java method calls?** The scheduler wrapper docs suggest it should synchronize automatically.

2. **Are we doing something wrong?** Are there specific patterns we should use for Java objects in async?

3. **Compression examples?** Someone mentioned doing `.tar.xz` compression - how did you create compressed archives from Lua?

4. **Any suggestions?** We're open to trying different approaches!

## How to Test

1. Load this plugin: `/lualink load autobackup-async-broken`
2. Run the command: `/backup-async-test`
3. Check console for errors

The same code works perfectly if you change `scheduler:runAsync()` to `scheduler:run()` on line 155.

## Environment

- LuaLink 1.21.10-SNAPSHOT
- Paper 1.21.10-115
- macOS (but same issues reported on Windows)

## Thanks!

Any help figuring this out would be greatly appreciated! Either we're doing something wrong, or there's a limitation we should document for other users.