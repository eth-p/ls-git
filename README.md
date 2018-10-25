# ls-git
Do you find it annoying/verbose to figure out the status of files in your git repositories when using a terminal?
If so, then `ls-git` is here to come to your rescue!

Designed to be a **fast** and effective union of `ls` and `git status`, this script allows you to see the status
of files and directories in your repository in way that is both familiar and useful.

<p align="center">
    <img src="https://media.githubusercontent.com/media/eth-p/ls-git/a56c69119cdd4051d73629aaef9e0bb5d07b78f5/docs/demo.svg">
</p>

### 

| Symbol | For Files                         | For Directories                                              |
| ------ | --------------------------------- | ------------------------------------------------------------ |
| `[ ]`  | The file is up-to-date.           | Files in the directory are up-to-date.                       |
| `[~]`  | The file was modified or renamed. | The directory has one or more modified, added, or renamed files. |
| `[+]`  | The file was added.               | N/A                                                          |
| `[i]`  | The file is ignored.              | All files in the directory are ignored.                      |
| `[?]`  | The file is untracked.            | The directory has one or more untracked files.               |




## Warnings
- **This software is pre-alpha.**  
  As much as I would like to, *I unfortunately cannot guarantee it will work for you*.  
  If you come across a bug or issue, please help out and report it.
  
- **This software does not automatically update.**  
  If something is broken, please try and re-install `ls-git` to see if it was fixed in the latest version.

## Compatibility
Due to the complexity of `ls`, not all command-line switches are supported.

See [here](https://github.com/eth-p/ls-git/issues/1) for a full compatibility list.

## Requirements

In order to use `ls-git`, the following requirements must be met:

Programs:
- git
- tput
- perl

Perl Modules:
- Time::Moment
- Math::Round

## Installation

```bash
git clone 'https://github.com/eth-p/ls-git.git'
cd ls-git
./install --deps --to ~/.bin
```

This will install all required Perl modules, and save `ls-git` to `~/.bin/ls-git`.
