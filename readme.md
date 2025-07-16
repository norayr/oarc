# 📜 oarc

## Oberon `.Arc` Archive Utility

**oarc** is a command-line tool written in Oberon using the [Vishap Oberon Compiler (VOC)](https://github.com/vishapoberon/compiler) that allows you to manipulate `.Arc` archive files originally used in Oberon System 3.

These archives are based on LZ77 compression and were used in the classical Oberon system to bundle and distribute sources. This tool enables modern systems to interact with those `.Arc` files: listing contents, extracting, adding, or deleting files — all in a native Oberon implementation that runs outside the original OS environment.

This tool was developed to support preservation and access to historical Oberon System 3 archives using modern tooling.

## Features

* List archive contents (with optional detail)
* Extract specific files or the entire archive
* Add files to an archive (with optional encryption)
* Delete files from an archive
* Support for several compatible encryption methods

## Design Goals

* Faithful reproduction of Oberon S3 archive behavior.
* Minimal dependencies: currently the only dependency outside of libraries distributed with VOC is [Unix File System Utils](https://github.com/norayr/unixFileSystem).
* Command-line tool written entirely in Oberon for use on modern systems via VOC.

## Limitations

* Windows is not supported due to reliance on `UnixFS.Mod`.

## Source Modules

* `ArcTool.Mod`: Core `.Arc` parsing, compression, and file handling
* `FileUtil.Mod`: Lists files and abstracts file operations. Depends on standard `Files.Mod` and `UnixFS.Mod`
* `oarc.Mod`: Main command-line interface with argument parsing and dispatch
* `Crypt0.Mod`: Encryption methods

## Building

A GNUmakefile is provided which fetches dependencies (in this case: UnixFS.Mod), builds them, and compiles the tool using VOC.

To build:

```bash
make
```

This will produce the executable `oarc` in the `build` directory.

## Usage

```bash
./oarc <command> <archive> [options/files...]
```

### Commands

| Command                                          | Description                                         |
| ------------------------------------------------ | --------------------------------------------------- |
| `list <archive> [-d]`                            | List contents of the archive (add `-d` for details) |
| `add <archive> [-c cipher] [-e key] <files>`     | Add files to archive (optionally encrypted)         |
| `extract <archive> [-c cipher] [-e key] [files]` | Extract specific files (with optional decryption)   |
| `extractall <archive> [-c cipher] [-e key]`      | Extract all files (with optional decryption)        |
| `delete <archive> <files>`                       | Remove specific files from archive                  |

### Options

* `-d`          Show detailed listing (for `list`)
* `-c cipher`   Select encryption cipher (default: `mod`)
* `-e key`      Use specified key to enable encryption/decryption

### Available Ciphers

* `mod`: Parks-Miller PRNG with modular arithmetic (default)

  * Uses: `ciphertext = (plaintext + keystream) MOD 256`

* `heidelberg`: Voyager project cipher from `Crypt0.Mod` (has a bug with 1-char keys!)

  * Same as `mod` but uses `Length(key) - 1` as length
  * **Warning**: crashes with single-character passwords — use only for legacy compatibility

* `xor`: Simple XOR stream cipher

  * Uses: `ciphertext = plaintext XOR keystream`

* `s3`: Cipher from ETH Oberon System 3 `CompressCrypt.Mod`

  * Uses: `ciphertext = plaintext +/- key[i MOD keylen]`

## Examples

```bash
# List files
./oarc list WebNavBeta4.Arc

# List with details
./oarc list WebNavBeta4.Arc -d

# Add new files (with encryption)
./oarc add WebNavBeta4.Arc -e mypassword New.Mod More.Text

# Extract files (with cipher and password)
./oarc extract WebNavBeta4.Arc -c heidelberg -e oldkey New.Mod

# Extract all files
./oarc extractall WebNavBeta4.Arc

# Delete files
./oarc delete WebNavBeta4.Arc Old.Mod
```

## Notes

* Archives are modified in-place
* Encrypted files are compatible with original Oberon S3 formats (where applicable)

## How to create/extract encrypted archives in Oberon operating system?

You have to install one of the encryption methods. In Oberon S3 there's `CompressCrypt` module.

```
Compress.Add \C CompressCrypt.Install "key" archive.Arc file0.txt file1.txt ~
```

or

```
Compress.Extract \C CompressCrypt.Install "key" archive.Arc file0.txt file1.txt ~
```

Otherwise, if you use [compress system](https://web.archive.org/web/20140314210953/http://statlab.uni-heidelberg.de/projects/oberon/util/system3/Compress.Arc) from [Voyager project](https://web.archive.org/web/20140314210953/http://statlab.uni-heidelberg.de/projects/voyager/) then its Crypt0.Mod file encryption should be used.

```
Compress.Extract \C Crypt0.Install "key" archive.Arc file0.txt file1.txt ~
```

## License

GPL-3
