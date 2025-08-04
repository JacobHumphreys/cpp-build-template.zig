# Zig Build System Template For C/C++
## Description
This is a [zig build system](https://ziglang.org/) template for c/cpp. It includes some easily toggleable strict default flags
for your c/cpp project intended to encourage safer code.

### features
By default, the build.Zig is configured to recursively search the src/cpp directory for .cpp files and compiles them using the following warnings and sanitizers.  
**See windows section for notes on windows support.**

<details>
<summary>⚠️ <strong>Warnings</strong></summary>
<br>

- Wall
- Wextra
- Wnull-dereference
- Wuninitialized
- Wshadow
- Wpointer-arith              # warns on potentially unsafe pointer arithmetic
- Wstrict-aliasing            # warns on violations of strict aliasing rules
- Wstrict-overflow=5          # warns on compiler assumptions about overflow (level 5 = most strict)
- Wcast-align                 # warns on casts that may result in misaligned memory access
- Wconversion                 # warns on implicit type conversions that may change values
- Wsign-conversion            # warns on implicit signed/unsigned conversions
- Wfloat-equal                # warns on comparisons between floating-point values
- Wformat=2                   # enables full format string checks
- Wswitch-enum                # warns when not all enum values are handled in a switch
- Wmissing-declarations       # warns if functions are defined without prior declarations
- Wunused
- Wundef                      # warns when undefined macros are used in `#if`
- Werror                      # treats all warnings as errors
</details>

<details>
<summary>⚠️ <strong>Sanitizers</strong></summary>
<br>

- fsanitize=address
- fsanitize=array-bounds      # detects out-of-bounds array accesses
- fsanitize=null              # detects null pointer dereferencing
- fsanitize=alignment         # detects misaligned memory access
- fsanitize=leak              # detects memory leaks
- fsanitize=unreachable       # detects execution of code marked as unreachable
- fstack-protector-strong     # adds stack canaries to detect buffer overflows
- fno-omit-frame-pointer      # keeps frame pointers for better stack traces

</details>

Because Zig does not natively package certain sanitizers such ASan, **Clang is required in addition to Zig to build this project**.  

The template's `build.zig` uses a Clang command to locate ASan libraries for linking in `Debug` mode.

### Setup
To use compile this template after cloning it, you must first build the dynamic and static libraries it relies on. This is simple as all you need to do is run the following command.  

```
zig build -Dbuild-static -Dbuild-dynamic
```
**Note:** you can use any regular build steps with these flags (eg: zig build run)

After they are built you can avoid having to rebuild them by moving them to the ./lib/ directory. You can do this with the following.
```
mv ./zig-out/lib/libexample_* ./lib/
```

---
## Project structure
```
./
  ./lib/ # Includes source code for dynamic and static library examples and
         # is the location you can store the built library files in for automatic linking

  ./include/ # Place header files here

  ./src/
    ./c # Unused in this template, but here to demonstrate a reccomended structure
    ./cpp # All files here will be compiled and linked automatically
    ./zig # Files here are compiled and linked as a library

  build.zig
  build.zig.zon
```

---
## For use with language servers
The template has a dependency on [the-argus/zig-compile-commands](https://github.com/the-argus/zig-compile-commands) for automating the creation of a **compile_commands.json** because the zig build system has no native way to do this. This file hints to language servers and IDEs how to analyze your project.

In order to use it, run the following build step after configuring the project to your preference.

```
zig build cmds
```

---
## For use with Jetbrains IDEs (eg: Clion)
### Prerequisites
In the IDE, install the [zigbrains](https://plugins.jetbrains.com/plugin/22456-zigbrains) extension. Then add your build toolchain in the extensions settings. Once done, open the template in the ide, and **select compilation database project** in the popup.  
**Note:** the IDE **will not** see your compile_commands.json if you do not select this option properly. This will result in issues. The IDE will also not give warnings based off compile_commands.json 

### Setting up the project
Once open, no build configuration will be provided by default. This  means in order to run your project, either regularly or with the debugger, you must first add a run configuration. Luckily this is fairly simple.

First click the **Add Configuration** Button in the IDE top bar, then select the **edit configurations** drop down. Click the **plus button** on the sub window and scroll down until you see the **Zig buiild** option.

In the newly created Unnamed Configuration Menu, set the following:
- Build steps &rarr; run
- Debug Build steps &rarr; debug
- Debug output executable created by build  &rarr; **/path/to/project**/zig-out/bin/debug
  **Note:** if you change the name property of the debug executable in the build.zig you will need to change the name in the debug output path

If, when you run the project, you get an error stating the following:

```
Zig project toolchain not set, cannot execute program!
Please configure it in [Settings | Languages & Frameworks | Zig]
```

You can fix it by going to settings -> Languages & Frameworks -> Zig then selecting the toolchain installed on your system.

---
## Windows
For windows, both setup and use are complicated because of inconsistant support of various sanitizers and bugs within the current version of zig. 

### Setup
---
#### Installing Clang
Just like on Linux and Mac, you must install clang in order to use supported sanitizers. This is because **the MSVC sanitizers are not compatible with zig**.

This can be done with the following command in powershell
```ps1
winget install LLVM.LLVM
```

Once LLVM is installed you can use clang by adding the following to the *Path* environment variable.
- C:\Program Files\LLVM\bin
- C:\Program Files\LLVM\lib\clang\20\ #or whatever version you have installed
---
#### Configuring build.zig
On Windows, the leak sanitizer is currently unsupported. So in order for Zig to build properly, **you must remove the leak tag from the *runtime_check_flags* constant in build.zig

Before
```zig
#168
const runtime_check_flags: []const []const u8 = &.{
    "-fsanitize=array-bounds,null,alignment,unreachable,address,leak", // asan and leak are linux/macos only in 0.14.1
    "-fstack-protector-strong",
    "-fno-omit-frame-pointer",
};
#174
```

After
```zig
#168
const runtime_check_flags: []const []const u8 = &.{
    "-fsanitize=array-bounds,null,alignment,unreachable,address", //leak", // asan and leak are linux/macos only in 0.14.1
    "-fstack-protector-strong",
    "-fno-omit-frame-pointer",
};
#174
```

After making this change building the project should result in success, but you will lose leak-detection.

**Special Note for Zig 0.14**
In the 0.14 zig release for windows, there is ~~a bug for which a [fix has been merged](https://github.com/ziglang/zig/pull/23140)~~ a bug with [asan](https://github.com/ziglang/zig/issues/24643).  

In order to avoid running into this bug, disable either the *-Werror* in *warning_flags* or the *address* flag in *runtime_check_flags* (reccomended for general use).
