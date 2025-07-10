# oarc
## Oberon `.Arc` Archive Utility

**oarc** is a command-line tool written in Oberon using the [Vishap Oberon Compiler (VOC)](https://github.com/vishapoberon/compiler) that allows you to manipulate `.Arc` archive files originally used in Oberon System 3.

These archives are based on LZ77 compression and were used in the classical Oberon system to bundle and distribute sources. This tool enables modern systems to interact with those `.Arc` files: listing contents, extracting, adding, or deleting files, all in a native Oberon implementation that runs outside the original OS environment.

This tool was developed to support preservation and access to historical Oberon System 3 archives using modern tooling.

## Features

- List archive contents (with optional detail)
- Extract specific files or the entire archive
- Add files to an archive
- Delete files from an archive

## Design Goals

- Faithful reproduction of Oberon S3 archive behavior.
- Minimal dependencies: currently the only dependency outside of libraries distributed with VOC is [Unix File System Utils](https://github.com/norayr/unixFileSystem) module.
- Command-line tool written entirely in Oberon for use on modern systems via VOC

## Limitations

- Windows is not supported, I used my UnixFS.Mod which is not portable.

## Source Modules

- `ArcTool.Mod`: Implements core `.Arc` parsing, compression, and file handling
- `FileUtil.Mod`: List of files structure. Depends on standard `Files.Mod` and abovementioned `UnixFS.Mod` and abstracts some file operations.
- `oarc.Mod`: Main command-line interface with argument parsing and dispatch

## Building

There is a supplied GNUmakefile which downloads dependencies (in this case: UnixFS.Mod) then builds dependencies and the tool source.

Compile all modules with VOC:

```bash
make
```

This will produce an executable named `oarc` in the `build` directory.

## Usage

```bash
./oarc <command> <archive> [options/files...]
```

### Commands

#### List archive contents

```bash
./oarc list archive.arc
```

Add `-d` to see detailed output with file sizes and offsets:

```bash
./oarc list archive.arc -d
```

Example output with `-d`:

```
 $ ./oarc list pr3fonts.arc -d
Oberon8.Pr3.Fnt  Size: 4183  Ratio: 6.38919E+01%
Oberon8b.Pr3.Fnt  Size: 4223  Ratio: 6.48495E+01%
Oberon8i.Pr3.Fnt  Size: 4633  Ratio: 6.69896E+01%
Oberon10.Pr3.Fnt  Size: 5305  Ratio: 6.02704E+01%
```

#### Extract specific files

```bash
./oarc extract archive.arc file1.Mod file2.Text
```

#### Extract all files

```bash
./oarc extractall archive.arc
```

#### Add files to archive

```bash
./oarc add archive.arc file1.Mod file2.Text
```

- Files are compressed using the same LZ77-based method used in the original Oberon system.
- If a file with the same name already exists, it is not replaced and a warning is printed.

#### Delete files from archive

```bash
./oarc delete archive.arc file1.Mod file2.Text
```

## Notes

- Archives are modified in-place.

## Example

```bash
# List files
./oarc list WebNavBeta4.Arc

# Add a new module
./oarc add WebNavBeta4.Arc New.Mod

# Remove an old module
./oarc delete WebNavBeta4.Arc Old.Mod

# Extract all contents
./oarc extractall WebNavBeta4.Arc
```

## License

GPL-3


---


