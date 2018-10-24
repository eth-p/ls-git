# ls-git
Do you find it annoying/verbose to figure out the state of your git repositories when using a terminal?
If so, then `ls-git` is here to come to your rescue!

Designed to be a **fast** and effective union of `ls` and `git status`, this script allows you to see the state
of files and directories in your repository in way that is both familiar and useful.

<p align="center">
    <img src="https://media.githubusercontent.com/media/eth-p/ls-git/a56c69119cdd4051d73629aaef9e0bb5d07b78f5/docs/demo.svg">
</p>

## Compatibility
Due to the complexity of `ls`, not all command-line switches are supported.

See [here](https://github.com/eth-p/ls-git/issues/1) for a full compatibility list.

## Requirements

- git
- tput
- perl

## Installation

```bash
git clone 'https://github.com/eth-p/ls-git.git'
cd ls-git
./install
```
