# Zig Build System Template For C/C++
## Description
This is a [zig build system](https://ziglang.org/) template for c/cpp. It includes some easily toggleable strict default flags
for your c/cpp project intended to encourage safer code.

### features
By default, the build.Zig is configured to recursively search the src/cpp directory for .cpp files and compiles them using the following warnings and sanitizers.

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

Because Zig does not natively package sanitizers such as UBSan and ASan, **Clang is required in addition to Zig to build this project**.  
The template's `build.zig` uses a Clang command to locate UBSan and ASan libraries for linking in `ReleaseSafe` and `Debug` modes.

</details>

## Project structure
```
./
  ./include/ #place header files here
  ./src/
    ./cpp # All files here will be compiled and linked automatically
    ./zig # Files here are compiled and linked as a library
  build.zig
  build.zig.zon
```
## For use with language servers
The template has a dependency on [the-argus/zig-compile-commands](https://github.com/the-argus/zig-compile-commands) for automating the creation of a **compile_commands.json** because the zig build system has no native way to do this. This file hints to language servers and IDEs how to analyze your project.

In order to use it, run the following build step after configuring the project to your preference.

```
zig build cmds
```

## For use with Jetbrains IDEs (eg: Clion)
### Prerequisites
In the IDE, install the [zigbrains](https://plugins.jetbrains.com/plugin/22456-zigbrains) extension. Then add your build toolchain in the extensions settings. Once done, open the template in the ide, and **select compilation database project** in the popup.  
**Note:** the IDE **will not** see your compile_commands.json if you do not select this option properly.

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