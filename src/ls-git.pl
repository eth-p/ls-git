#!/usr/bin/env perl
# ----------------------------------------------------------------------------------------------------------------------
# ls-git - https://github.com/eth-p/ls-git/ | MIT License | Copyright (C) 2018 Ethan P. (eth-p)
# ----------------------------------------------------------------------------------------------------------------------
# Copyright (c) 2018 Ethan P. (eth-p)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ----------------------------------------------------------------------------------------------------------------------
use feature qw(say);
use strict;
use warnings;

use Cwd 'abs_path', 'realpath';
use Env qw($LANG);
use File::Basename;
use File::Spec::Functions 'catfile', 'rel2abs', 'abs2rel';
use Fcntl ':mode';
use Getopt::Long;
use List::Util qw(reduce max);
use Math::Round;
use Scalar::Util qw(reftype);
use Time::Moment;

use Data::Dumper; # Debug

# ----------------------------------------------------------------------------------------------------------------------
# Warnings:
# ----------------------------------------------------------------------------------------------------------------------

BEGIN {
    say "WARNING: @{[basename($0, '.pl')]} is not designed to be used in scripts!\n" unless (-t STDOUT);
}

# ----------------------------------------------------------------------------------------------------------------------
# Globals:
# ----------------------------------------------------------------------------------------------------------------------

my %args        = ();
my $color       = (-t STDOUT);
my $term_width  = `tput cols`;
my $status      = 0;
my $now         = Time::Moment->now();

my @argspec     = (
    "1",      # Output: One file per line.
    "a",      # Display all files.
    "A",      # Display all files, except for "."/"..".
    "f",      # Same as -a.
    "g",      # Do not display user.
    "G",      # Enable colors.
    "H",      # Follow symlink command-line arguments.
    "h",      # Display human readable units.
    "i",      # Print inode.
    "l",      # Output: long format.
    "n",      # Display owner and group using uid/gid.
    "o",      # Do not display owner.
    "P",      # Do not follow symlink command-line arguments. Opposite of H.
    "s",      # Print block count.
    #"@",     # TODO: Extended attribute support.
);

# ----------------------------------------------------------------------------------------------------------------------
# Localization:
# ----------------------------------------------------------------------------------------------------------------------

my $locale_date_patterns = {
    'recent'  => '%b %d',
    'distant' => '%b %d %Y',
    'align'   => 'L'
};

my $locale_time_patterns = {
    'recent'  => '%H:%M',
    'distant' => '%H:%M',
    'align'   => 'L'
};

# ----------------------------------------------------------------------------------------------------------------------
# Messages:
# ----------------------------------------------------------------------------------------------------------------------

## Returns a string describing a program error.
##
## @param   [string] The error message.
## @returns [string]
sub prog_error {
    return "@{[basename($0, '.pl')]}: $_[0]";
}

## Returns a string describing how to use the command.
## @returns [string]
sub prog_usage {
    my $argspec_str = reduce {$a . $b} @argspec;
    return "usage: @{[basename($0, '.pl')]} [-$argspec_str] [file ...]";
}

# ----------------------------------------------------------------------------------------------------------------------
# Util:
# ----------------------------------------------------------------------------------------------------------------------

## Trims a string.
##
## @param   [string] The string to trim.
## @returns [string] The trimmed string.
sub trim {
    return ($_[0] =~ /^\s*(.*)\s*$/)[0];
}

## Expands a path without canonicalizing it.
##
## @param   [string] The path to expand.
## @returns [string] The resulting path.
sub path_expand {
    my @components = split(/\//, $_[0]);

    expand:
    for (my $i = 0; $i < @components; $i++) {
        if ($components[$i] eq '.') {
            $components[$i] = undef;
        } elsif ($components[$i] eq '..') {
            for (my $j = $i - 1; $j >= 0; $j--) {
                if (defined $components[$j]) {
                    $components[$j] = undef;
                    $components[$i] = undef;
                    next expand;
                }
            }
        }
    }

    return join('/', grep {defined $_} @components);
}

## Destructures an arguments hash.
## Argument hashes work similarly to JavaScript options objects.
##
## @param   [\hash] The arguments hash.
## @param   [\hash] A {key => value> that represents the a destructured argument.
## @param   ...     ...
##
## @returns [array] An array of the destructured arguments.
##
## Example:
##     my ($a, $b) = desarg $_[1],
##                   {'a' => 'Hello'},
##                   {'b' => 'World'};
##
sub desarg {
    my %args = ();
    %args = %{$_[0]} if (defined $_[0]) && (reftype $_[0] eq reftype {});

    my $arg;
    my @results;

    shift @_;
    foreach $arg (@_) {
        my $key = (%$arg)[0];
        if (exists $args{$key}) {
            push @results, $args{$key};
        } else {
            push @results, (%$arg)[1]
        }
    }

    return @results;
}

# ----------------------------------------------------------------------------------------------------------------------
# Util: Formatting
# ----------------------------------------------------------------------------------------------------------------------

## Formats a number using the units of information suffixes.
## See: https://en.wikipedia.org/wiki/Units_of_information
##
## @param   [int]    The number to format.
## @returns [string] The formatted number.
sub format_size {
    my $size = $_[0];
    my $lim  = 1;
    return $size                             . 'B' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'K' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'M' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'G' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'T' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'P' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'E' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'Z' if $size < ($lim *= 1024);
    return nearest(1, $size / ($lim / 1024)) . 'Y';
}

# ----------------------------------------------------------------------------------------------------------------------
# Util: System Operations
# ----------------------------------------------------------------------------------------------------------------------

my %cache_get_user_name;
my %cache_get_group_name;

## Converts a UID number into a username.
##
## @param   [int]    The UID number.
## @returns [string] The corresponding username, or the UID if none found.
sub get_user_name {
    my $uid = $_[0];
    return $cache_get_user_name{$uid} if exists $cache_get_user_name{$uid};
    return $cache_get_user_name{$uid} = getpwuid($uid) || $uid;
}

## Converts a GID number into a group name.
##
## @param   [int]    The GID number.
## @returns [string] The corresponding group name, or the GID if none found.
sub get_group_name {
    my $gid = $_[0];
    return $cache_get_group_name{$gid} if exists $cache_get_group_name{$gid};
    return $cache_get_group_name{$gid} = getgrgid($gid) || $gid;
}


# ----------------------------------------------------------------------------------------------------------------------
# Util: Colors
# ----------------------------------------------------------------------------------------------------------------------

## Determines the display color for a file from its permissions, flags, and kind.
##
## @param   [\hash]  The file info.
## @returns [string] The color string.
sub file_color {
    my $info = $_[0];
    return "\x1B[34m" if ($info->{'kind'}->{'kind'} eq 'directory');
    return "\x1B[35m" if ($info->{'kind'}->{'kind'} eq 'symlink');
    return "\x1B[33m" if ($info->{'kind'}->{'kind'} eq 'pipe');
    return "\x1B[31m" if ($info->{'executable'});
    # TODO: More colors.
    return '';
}

## Determines the git status color for a file.
##
## @param   [\hash]  The file info.
## @returns [string] The color string.
sub status_color {
    my $info = $_[0];
    return ""           if ($info->{'git'}->{'status'} eq 'up-to-date');
    return "\x1B[34m"   if ($info->{'git'}->{'status'} eq 'modified');
    return "\x1B[33m"   if ($info->{'git'}->{'status'} eq 'untracked');
    return "\x1B[32m"   if ($info->{'git'}->{'status'} eq 'added');
    return "\x1B[31m"   if ($info->{'git'}->{'status'} eq 'removed');
    return "\x1B[34m"   if ($info->{'git'}->{'status'} eq 'renamed');
    return "\x1B[2;39m" if ($info->{'git'}->{'status'} eq 'ignored');
    return '';
}

## Determines the git status symbol for a file.
##
## @param   [\hash]  The file info.
## @returns [string] The color string.
sub status_symbol {
    my $info = $_[0];
    return " " if ($info->{'git'}->{'status'} eq 'up-to-date');
    return '~' if ($info->{'git'}->{'status'} eq 'modified');
    return '?' if ($info->{'git'}->{'status'} eq 'untracked');
    return '+' if ($info->{'git'}->{'status'} eq 'added');
    return '-' if ($info->{'git'}->{'status'} eq 'removed');
    return '~' if ($info->{'git'}->{'status'} eq 'renamed');
    return "i" if ($info->{'git'}->{'status'} eq 'ignored');
    return 'x';
}

# ----------------------------------------------------------------------------------------------------------------------
# Util: Git Operations
# ----------------------------------------------------------------------------------------------------------------------

## Uses git status --porcelain to retrieve information about the current state of files in a directory.
##
## @param  [string] The directory.
## @return [\array] The status of files in the directory. Everything not mentioned is up-to-date.
sub git_status {
    my $results = [];
    my $line;

    # git ls-tree
    my $lsfiles = `git -C "$_[0]" ls-tree --name-only HEAD 2>/dev/null`;
    return 0 if $? != 0;

    for $line (split(/\n/, $lsfiles)) {
        push @$results, {
            'file'   => $line,
            'status' => 'up-to-date'
        };
    }

    # git ls-files (ignored)
    $lsfiles = `git -C "$_[0]" ls-files --others -i --exclude-standard 2>/dev/null`;
    return 0 if $? != 0;

    for $line (split(/\n/, $lsfiles)) {
        push @$results, {
            'file'   => $line,
            'status' => 'ignored'
        };
    }

    # git status
    my $porcelain = `git -C "$_[0]" status --porcelain=2 2>/dev/null`;
    return 0 if $? != 0;

    # Parse status.
    for $line (split(/\n/, $porcelain)) {
        my @fields = split(/ /, $line, 9);
        my $status = {};

        if ($fields[0] eq '?') {
            $status->{'status'} = 'untracked';
            $status->{'file'}   = substr($line, 2);
        } elsif ($fields[0] eq '!') {
            $status->{'status'} = 'ignored';
            $status->{'file'}   = substr($line, 2);
        } elsif ($fields[0] eq '1') {
            $status->{'status'} = 'modified';
            $status->{'status'} = 'added'    if substr($fields[1], 0, 1) eq 'A';
            $status->{'status'} = 'removed'  if substr($fields[1], 0, 1) eq 'D';
            $status->{'file'}   = $fields[8];
        } elsif ($fields[0] eq '2') {
            my @files = split(/\t/, $fields[8]);
            $status->{'status'} = 'renamed';
            $status->{'file'}   = $files[0];
            $status->{'to'}     = $files[1];
        }

        push @$results, $status;
    }

    return $results;
}

sub get_versioning_for_files {
    my $dir = '';
    my $file;
    my $files = [sort {$a->{'path'} cmp $b->{'path'}} @{$_[0]}];
    my %githash;

    # Get file status.
    foreach $file (@$files) {
        # next if $file->{'kind'}->{'kind'} eq 'directory';

        my $filedir = dirname($file->{'file'});
        if ($filedir ne $dir) {
            $dir = $filedir;

            my $gitdir = trim(`git -C "$filedir" rev-parse --show-toplevel 2>/dev/null` || '');
            next unless $? == 0;

            my $git = git_status($filedir) or next;
            my $status_info;
            foreach $status_info (@$git) {
                my $status_file   = path_expand(rel2abs(catfile($filedir, $status_info->{'file'})));
                my $file_status = $status_info->{'status'};
                $githash{$status_file} = $status_info;

                # Bubble up to gitdir.
                while (($status_file = dirname($status_file)) ne $gitdir) {
                    my $dir_status = $githash{$status_file}->{'status'} || 'unknown';
                    if ($file_status eq 'ignored' && $dir_status =~ /unknown/) {
                        $githash{$status_file} = {
                            'status' => 'ignored'
                        };
                    } elsif ($file_status eq 'up-to-date' && $dir_status =~ /unknown|ignored/) {
                        $githash{$status_file} = {
                            'status' => 'up-to-date'
                        };
                    } elsif ($file_status eq 'untracked' && $dir_status =~ /unknown|ignored|up-to-date/) {
                        $githash{$status_file} = {
                            'status' => 'untracked'
                        };
                    } elsif (($file_status =~ /modified|added|removed|renamed/) ) {
                        $githash{$status_file} = {
                            'status' => 'modified'
                        };
                    }
                }
            }
        }
    }

    # Set git key on file objects.
    foreach $file (@$files) {
        if (exists $githash{$file->{'path'}}) {
            $file->{'git'} = $githash{$file->{'path'}};
        } else {
            my $file_parent = path_expand(rel2abs($file->{'path'}));
            while (($file_parent = dirname($file_parent)) ne '/') {
                if (exists $githash{$file_parent}) {
                    $file->{'git'} = $githash{$file_parent};
                    last;
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------------
# Util: Filesystem Operations
# ----------------------------------------------------------------------------------------------------------------------

## Determines file permissions from its stat mode.
##
## @param   [string] The permission type to check: USR, GRP, or OTH.
## @param   [int]    The file mode value.
## @returns [string] A "rwx"/"r--"/etc. string representing permissions.
sub file_mode_to_perm {
    no strict 'refs';
    my $buf   = '';
    $buf .= (&{'S_IR'.$_[0]} & $_[1]) ? 'r' : '-';
    $buf .= (&{'S_IW'.$_[0]} & $_[1]) ? 'w' : '-';
    $buf .= (&{'S_IX'.$_[0]} & $_[1]) ? 'x' : '-';
    return $buf;
}

## Determines file node kind from its stat mode.
##
## @param   [int]   The file mode value.
## @returns [\hash] The file kind.
sub file_mode_to_kind {
    return {'code' => '-', 'kind' => 'file'}             if (S_ISREG($_[0]));
    return {'code' => 'd', 'kind' => 'directory'}        if (S_ISDIR($_[0]));
    return {'code' => 'l', 'kind' => 'symlink'}          if (S_ISLNK($_[0]));
    return {'code' => 'b', 'kind' => 'block device'}     if (S_ISBLK($_[0]));
    return {'code' => 'c', 'kind' => 'character devuce'} if (S_ISCHR($_[0]));
    return {'code' => 'p', 'kind' => 'pipe'}             if (S_ISIFO($_[0]));
    return {'code' => 's', 'kind' => 'socket'}           if (S_ISSOCK($_[0]));
    return {'code' => ' ', 'kind' => 'whiteout'}         if (S_ISWHT($_[0]));  #TODO => Find code for whiteout.
    return {'code' => ' ', 'kind' => 'door'}             if (S_ISDOOR($_[0])); #TODO => Find code for door.
    return {'code' => ' ', 'kind' => 'port'}             if (S_ISPORT($_[0])); #TODO => Find code for port.
    return {'code' => '?', 'kind' => '[unknown]'};
}

## Gets detailed information about a file or directory.
## This pulls A TON of details about the file.
##
## @param   [string] The file to retrieve info about.
## @returns [hash]   A hash of file details.
##
## Details:
##
##     - 'file'            [string]    The file name, as provided to the function.
##     - 'kind'            [string]    The file kind. e.g. 'directory', 'file', 'symlink'.
##     - 'path'            [string]    The absolute file path.
##     - 'path_canonical'  [string]    The absolute, canonicalized file path.
##     - 'size'            [int]       The file size, in bytes.
##     - 'time_accessed'   [timestamp] The timestamp of when the file was last accessed.
##     - 'time_modified'   [timestamp] The timestamp of when the file was last modified.
##     - 'time_created'    [timestamp] The file creation timestamp.
##     - 'io_blocksize'    [int]       The block size of the file.
##     - 'io_blocks'       [int]       The number of blocks used by the file.
##     - 'user'            [int]       The ID of the file owner.
##     - 'user_perms'      [string]    The permissions of the file owner.
##     - 'group'           [int]       The ID of the file group.
##     - 'group_perms'     [string]    The permissions of the file group.
##     - 'other_perms'     [string]    The permissions of everybody else.
##     - 'stat_dev'        [int]       ???
##     - 'inode'           [int]       The inode of the file.
##     - 'stat_mode'       [int]       ???
##     - 'fields'          [int]       The number of hard links to this file.
##
sub file_info {
    my ($opt_quiet) = desarg $_[1], {'quiet' => 0};

    # Use stat to get file information.
    my $file = $_[0];
    my @stat = lstat($file);

    # Call to stat() failed.
    if (@stat < 1) {
        say STDERR prog_error("$file: $!") unless $opt_quiet;
        return {
            'file'  => $file,
            'error' => $!
        };
    }

    # Return.
    return {
        'file'           => $file,
        'kind'           => file_mode_to_kind($stat[2]),
        'size'           => $stat[7],
        'path'           => path_expand(rel2abs($file)),
        'path_canonical' => &realpath($file),
        'path_basename'  => basename($file),
        'user'           => $stat[4],
        'user_perms'     => file_mode_to_perm('USR', $stat[2]),
        'group'          => $stat[5],
        'group_perms'    => file_mode_to_perm('GRP', $stat[2]),
        'other_perms'    => file_mode_to_perm('OTH', $stat[2]),
        'time_accessed'  => $stat[8],
        'time_modified'  => $stat[9],
        'time_created'   => $stat[10],
        'io_blocksize'   => $stat[11],
        'io_blocks'      => $stat[12],
        'stat_dev'       => $stat[0],
        'inode'          => $stat[1],
        'stat_mode'      => $stat[2],
        'fields'         => $stat[3],
        'executable'     => $stat[2] & (S_IXUSR() | S_IXGRP() | S_IXOTH())
    }
}

## Gets a listing of entries in a directory.
##
## @param   [string]    The directory.
## @param   [\hash]     The arguments hash.
## @returns [array|int] The contents, or -1 if failed.
##
## Arguments:
##     - 'details' [bool] Return detailed file information.
##     - 'hidden'  [bool] Include files that begin with a period.
##     - 'quiet'   [bool] Do not display error messages.
##
sub files {
    my ($opt_quiet, $opt_hidden, $opt_details) = desarg $_[1],
        {'quiet'   => 0},
        {'hidden'  => 0},
        {'details' => 0};

    my $directory = $_[0];
    my $directory_handle;
    my @entries;
    my @entries_raw;

    # Read the directory.
    unless (opendir($directory_handle, $directory)) {
        say STDERR prog_error("$directory: $!") unless $opt_quiet;
        return 0;
    }

    @entries_raw = readdir($directory_handle);
    closedir($directory_handle);

    # Clean the entries.
    my $entry;
    foreach $entry (@entries_raw) {
        if (substr($entry, 0, 1) eq '.') {
            next unless $opt_hidden;
            next if ($entry =~ /^\.{1,2}$/ && $opt_hidden != 2);
        }

        push @entries, catfile($directory, $entry);
    }

    # Stat the entries.
    if ($opt_details) {
        for (my $i = 0; $i < @entries; $i++) {
            $entries[$i] = file_info($entries[$i], $_[1]);
        }
    }

    # Sort the entries.
    if ($opt_details) {
        @entries = sort {$a->{'path_basename'} cmp $b->{'path_basename'}} @entries;
    } else {
        @entries = sort {basename($a) cmp basename($b)} @entries;
    }

    # Return.
    return \@entries;
}

# ----------------------------------------------------------------------------------------------------------------------
# Components:
# ----------------------------------------------------------------------------------------------------------------------

## RENDER COMPONENT:
## The filename/path component.
sub render_component_file {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    my ($color, $show_link_dest) = desarg $_[3],
        {'color' => 0},
        {'componentopt_file_dest' => 0};

    my @rendered = ({
        'text'        => $info->{'path_basename'},
        'ansi_prefix' => $color ? file_color($info) : '',
        'ansi_suffix' => $color ? "\x1B[0m" : ''
    });

    if ($show_link_dest && $info->{'kind'}->{'kind'} eq 'symlink') {
        push @rendered, {'text' => ' -> '};
        push @rendered, {'text' => readlink($info->{'file'})};
    }

    @$render[$colnum] = \@rendered;
}

## RENDER COMPONENT:
## The permissions component.
sub render_component_permissions {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text' => $info->{'kind'}->{'code'}
    },{
        'text' => $info->{'user_perms'}
    },{
        'text' => $info->{'group_perms'}
    },{
        'text' => $info->{'other_perms'}
    }];
}

## RENDER COMPONENT:
## The fields (stat: nlink) component.
## This represents the number of links to or inside a filesystem node.
sub render_component_inode {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text' => $info->{'inode'}
    }];
}

## RENDER COMPONENT:
## The fields (stat: nlink) component.
## This represents the number of links to or inside a filesystem node.
sub render_component_fields {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text' => $info->{'fields'}
    }];
}

## RENDER COMPONENT:
## The block count component.
sub render_component_blocks {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text' => $info->{'io_blocks'}
    }];
}

## RENDER COMPONENT:
## The file owner.
sub render_component_owner {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    my ($names_human) = desarg $_[3], {'componentopt_names_human'  => 1};

    @$render[$colnum] = [{
        'text' => $names_human ? get_user_name($info->{'user'}) : $info->{'user'},
    }];
}

## RENDER COMPONENT:
## The file group.
sub render_component_group {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    my ($names_human) = desarg $_[3], {'componentopt_names_human'  => 1};

    @$render[$colnum] = [{
        'text' => $names_human ? get_group_name($info->{'group'}) : $info->{'group'},
    }];
}

## RENDER COMPONENT:
## The file size.
sub render_component_size {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    my ($size_human) = desarg $_[3], {'componentopt_size_human' => 0};

    @$render[$colnum] = [{
        'text' => ($size_human ? format_size($info->{'size'}) : $info->{'size'})
    }];
}

## RENDER COMPONENT:
## The file time.
sub render_component_time {
    my $render    = $_[0];
    my $colnum    = $_[1];
    my $info      = $_[2];

    my ($date_kind) = desarg $_[3], {'componentopt_date_kind', => 'modified'};
    my $timestamp   = $info->{'time_' . $date_kind};

    my $datetime         = Time::Moment->from_epoch($timestamp);
    my $pattern_style    = $datetime->delta_months($now) >= 6 ? 'distant' : 'recent';
    my $pattern          = $locale_time_patterns->{$pattern_style};

    @$render[$colnum] = [{
        'text'  => $datetime->strftime($pattern),
        'align' => $locale_time_patterns->{'align'} || 'L'
    }];
}

## RENDER COMPONENT:
## The file date.
sub render_component_date {
    my $render    = $_[0];
    my $colnum    = $_[1];
    my $info      = $_[2];

    my ($date_kind) = desarg $_[3], {'componentopt_date_kind', => 'modified'};
    my $timestamp   = $info->{'time_' . $date_kind};

    my $datetime         = Time::Moment->from_epoch($timestamp);
    my $pattern_style    = $datetime->delta_months($now) >= 6 ? 'distant' : 'recent';
    my $pattern          = $locale_date_patterns->{$pattern_style};

    @$render[$colnum] = [{
        'text'  => $datetime->strftime($pattern),
        'align' => $locale_date_patterns->{'align'} || 'L'
    }];
}

## RENDER COMPONENT:
## A git component.
sub render_component_git {
    my $render    = $_[0];
    my $colnum    = $_[1];
    my $info      = $_[2];

    # No git information.
    if (!(exists $info->{'git'}->{'status'}) || $info->{'git'}->{'status'} eq 'unknown') {
        @$render[$colnum] = [{'text' => '', 'minwidth_short' => 3}];
        return;
    }

    # Some git information.
    my ($color)   = desarg $_[3], {'color' => 0};
    @$render[$colnum] = [{
        'ansi_prefix' => $color ? "\x1B[2m" : '',
        'text' => '[',
        'ansi_suffix' => $color ? "\x1B[0m" : ''
    },{
        'text'        => status_symbol($info),
        'ansi_prefix' => $color ? status_color($info) : '',
        'ansi_suffix' => $color ? "\x1B[0m" : ''
    },{
        'ansi_prefix' => $color ? "\x1B[2m" : '',
        'text' => ']',
        'ansi_suffix' => $color ? "\x1B[0m" : ''
    }];
}

## RENDER COMPONENT:
## An empty space.
sub render_component_margin {
    my $render    = $_[0];
    my $colnum    = $_[1];

    @$render[$colnum] = [{
        'text'   => ' ' x ($_[4] || 1),
        'margin' => 1 # bool, not a value
    }];

}

# ----------------------------------------------------------------------------------------------------------------------
# Components: Util
# ----------------------------------------------------------------------------------------------------------------------

## Calculates the text width of a render component.
##
## @param   [\array] The render component.
## @returns [int]    The calculated width.
sub component_width {
    my $segment;
    my $width = 0;

    foreach $segment (@{$_[0]}) {
        $width += max ((length $segment->{'text'}), ((exists $segment->{'minwidth'}) ? $segment->{'minwidth'} : 0));
    }

    return $width;
}

## Calculates the widths of an array of components.
##
## @param   [\array] The array of render components.
## @returns [\array] The array of widths.
sub component_widths {
    my $widths = [];
    my $component;

    foreach $component (@{$_[0]}) {
        push @$widths, component_width($component);
    }

    return $widths;
}

## Generates a string from a render component.
##
## @param   [\array] The render component.
## @param   [int]    The minimum width.
## @param   [string] The padding direction: L, R
## @returns [string] The resulting string.
sub component_string {
    my $segment;
    my $buffer  = '';
    my $padding = $_[1];

    my $align = @{$_[0]}[0]->{'align'} || $_[2];

    foreach $segment (@{$_[0]}) {
        $padding -= length $segment->{'text'};
        $buffer  .= $segment->{'ansi_prefix'} if exists $segment->{'ansi_prefix'};
        $buffer  .= $segment->{'text'};
        $buffer  .= $segment->{'ansi_suffix'} if exists $segment->{'ansi_suffix'};
    }

    $buffer = (sprintf "%-${padding}s", '') . $buffer if ($padding > 0 && $align eq 'R');
    $buffer = $buffer . (sprintf "%-${padding}s", '') if ($padding > 0 && $align eq 'L');

    return $buffer;
}

# ----------------------------------------------------------------------------------------------------------------------
# Printer:
# ----------------------------------------------------------------------------------------------------------------------

## Prints file entries.
## The entry objects must be hashes that contain a 'path' and 'follow' key.
##
## @param   [\array] The entries to print.
## @param   [\hash]  The options.
## @returns [int]    The exit code.
sub print_entries {
    my (
        $opt_quiet,
        $opt_sort,
        $opt_single_column,
        $opt_total,
        $component_permissions,
        $component_fields,
        $component_owner,
        $component_group,
        $component_size,
        $component_date,
        $component_time,
        $component_file,
        $component_inode,
        $component_blocks,
    ) = desarg $_[1],
        {'quiet'                   => 0},
        {'sort'                    => 'filename'},
        {'single_column'           => 0},
        {'show_total'              => 0},
        {'component_permissions'   => 0},
        {'component_fields'        => 0},
        {'component_owner'         => 0},
        {'component_group'         => 0},
        {'component_size'          => 0},
        {'component_date'          => 0},
        {'component_time'          => 0},
        {'component_file'          => 1},
        {'component_inode'         => 1},
        {'component_blocks'        => 1};


    my @entries = map {file_info $_->{'path'}, {'quiet' => $opt_quiet}} @{$_[0]};
    my @renders = ();

    return 1 if @entries == 0;

    # Git things.
    get_versioning_for_files(\@entries);

    # Render components.
    my $file;
    foreach $file (@entries) {
        my $column  = 0;
        my $render  = [];
        my $renhash = {
            'info'   => $file,
            'render' => $render
        };

        render_component_inode       ($render, $column++, $file, $_[1])    if $component_inode;
        render_component_blocks      ($render, $column++, $file, $_[1])    if $component_blocks;
        render_component_permissions ($render, $column++, $file, $_[1])    if $component_permissions;
        render_component_margin      ($render, $column++, $file, $_[1])    if $component_permissions;

        render_component_fields      ($render, $column++, $file, $_[1])    if $component_fields;
        render_component_owner       ($render, $column++, $file, $_[1])    if $component_owner;
        render_component_margin      ($render, $column++, $file, $_[1])    if $component_owner && $component_group;

        render_component_group       ($render, $column++, $file, $_[1])    if $component_group;

        render_component_margin      ($render, $column++, $file, $_[1], 2) if $component_size;
        render_component_size        ($render, $column++, $file, $_[1])    if $component_size;
        render_component_date        ($render, $column++, $file, $_[1])    if $component_date;
        render_component_time        ($render, $column++, $file, $_[1])    if $component_time;

        render_component_git         ($render, $column++, $file, $_[1])    if $component_file;
        render_component_file        ($render, $column++, $file, $_[1])    if $component_file;

        push @renders, $renhash;
    }

    # Print total.
    say "total " . (reduce {$a + $b} (map {$_->{'io_blocks'}} @entries)) if $opt_total;

    # Print files.
    my $render;
    if ($opt_single_column) {
        # Calculate common widths.
        my @columns;
        foreach $render (@renders) {
            my $widths = component_widths($render->{'render'});
            for (my $i = 0; $i < @$widths; $i++) {
                $columns[$i] = @$widths[$i] if (! exists $columns[$i]) || (@$widths[$i] > $columns[$i]);
            }
        }

        # Print columns.
        foreach $render (@renders) {
            my $buffer = '';
            for (my $i = 0; $i < @columns; $i++) {
                $buffer .= " " if ($i != 0 && !$render->{'render'}[$i][0]->{'margin'});
                $buffer .= component_string($render->{'render'}[$i], $columns[$i], ($i == @columns - 1) ? '-' : 'R');
            }

            say $buffer;
        }

    } else {
        # Calculate max component width.
        my $width  = max (map {reduce {$a + $b} @{component_widths($_->{'render'})}} @renders);
        my $remain = $term_width;

        foreach $render (@renders) {
            if (($remain -= ($width + 1)) <= ($width + 1)) {
                $remain = $term_width - $width + 1;
                print "\n";
            }

            my $buffer = '';
            my $buffer_width = 0;
            my $count = @{$render->{'render'}};
            for (my $i = 0; $i < $count; $i++) {
                my $min_width = $render->{'render'}[$i][0]->{'minwidth_short'} || 0;

                $buffer .= " " if ($i != 0 && !$render->{'render'}[$i][0]->{'margin'});
                $buffer .= component_string($render->{'render'}[$i], $min_width, ($i == $count - 1) ? '-' : 'R');
                $buffer_width += component_width(${render}->{'render'}[$i]) + $min_width;
            }

            my $pad = ' ' x max(1, $width - $buffer_width);
            print $buffer . $pad . ' ';
        }

        print "\n";
    }

    return 1;
}

## Prints a directory header.
## @param [string] The directory path.
sub print_header {
    say "\n$_[0]:";
    return 1;
}

## Prints a directory listing.
## @param [string] The directory path.
## @param [\hash]  The print options.
## @param [\hash]  The listing options.
sub print_listing {
    my $directory = $_[0];
    my $files     = files($_[0], $_[2]) or return 0;

    for (my $i = 0; $i < @$files; $i++) {
        @$files[$i] = {
            'path'   => @$files[$i],
            'follow' => 0
        };
    }

    print_entries($files, $_[1]) or return 0;

    return 1;
}

# ----------------------------------------------------------------------------------------------------------------------
# Arguments:
# ----------------------------------------------------------------------------------------------------------------------

{
    $SIG{__WARN__} = sub {
        my ($option) = $_[0] =~ / ([^ ]+)$/;
        say STDERR prog_error("illegal option -- @{[trim($option)]}");
        say STDERR prog_usage();
        exit 1;
    };

    Getopt::Long::Configure('gnu_getopt');
    Getopt::Long::GetOptions(\%args, @argspec);

    $SIG{__WARN__} = undef;
}

$color = $color || $args{'G'} || 0;

$args{'a'} = 1 if !$args{'a'} && $args{'f'};

my $printopts = {
    'sort'                    => 'name', # TODO: Configurable
    'color'                   => $color,
    'single_column'           => $args{'1'} || $args{'l'} || 0,
    'show_total'              => $args{'l'},

    # Components
    'component_fields'        => $args{'l'} || 0,
    'component_permissions'   => $args{'l'} || 0,
    'component_owner'         => $args{'g'} ?  0 : ($args{'l'} || 0),
    'component_group'         => $args{'o'} ?  0 : ($args{'l'} || 0),
    'component_size'          => $args{'l'} || 0,
    'component_date'          => $args{'l'} || 0,
    'component_time'          => $args{'l'} || 0,
    'component_inode'         => $args{'i'} || 0,
    'component_blocks'        => $args{'s'} || 0,

    # Component Options
    'componentopt_file_dest'   => $args{'l'} || 0,
    'componentopt_size_human'  => $args{'h'} || 0,
    'componentopt_names_human' => $args{'n'} ? 0 : 1,
    'componentopt_date_kind',  => 'modified',
};

my $listingopts = {
    'hidden'   => $args{'a'} ? 2 : ($args{'A'} || 0),
    'symlinks' => $args{'P'} ? 'follow' : 'nofollow'
};

my $cliopts = {
    'symlinks' => ($args{'H'} ? 'follow' : 0) || ($args{'P'} ? 'nofollow' : 'default')
};

# ----------------------------------------------------------------------------------------------------------------------
# Main: Determine which filesystem nodes to display.
# ----------------------------------------------------------------------------------------------------------------------

if (@ARGV < 1) {
    unshift @ARGV, '.';
}

my $no_header = 1;
my @files;
my @dirs;

for (my $i = 0; $i < @ARGV; $i++) {

    # Get node information.
    my $file = $ARGV[$i];
    my @stat = lstat($file);
    if (@stat < 1) {
        say STDERR prog_error("$file: $!");
        $status = 1;
        next;
    }

    # Determine if a symlink argument should be followed.
    my $follow = S_ISDIR($stat[2]);

    if (substr($file, -1, 1) eq '/') {
        # If it ends with a '/', the user wants to follow it.
        # Throw an error if it's not a link or directory, though!
        if (!(S_ISDIR($stat[2]) || S_ISLNK($stat[2]))) {
            say STDERR prog_error("$file: Not a directory");
            $status = 1;
            next;
        }

        $follow = 1;
    }

    if (!$follow && S_ISLNK($stat[2])) {
        # If it's a symlink, we need to consider command line flags.
        $follow = ($cliopts->{'symlinks'} eq 'follow') || 0;
    }

    if ($follow ? (( -d $file ) ? 1 : 0) : 0) {
        $no_header = 0 if (@dirs > 0);
        push @dirs, {
            'path'   => $file,
            'follow' => $follow
        };
    } else {
        $no_header = 0;
        push @files, {
            'path'   => $file,
            'follow' => $follow
        }
    }
}

#
# # Sort.
# @files = sort {$a->{'path'} cmp $b->{'path'}} @files;
# @dirs  = sort {$a->{'path'} cmp $b->{'path'}} @dirs;

# ----------------------------------------------------------------------------------------------------------------------
# Main: Print things!
# ----------------------------------------------------------------------------------------------------------------------

# Entries.
if (@files > 0) {
    print_entries(\@files, $printopts) or $status = 1;
}

# Directories.
my $node;
foreach $node (@dirs) {
    print_header($node->{'path'}) unless $no_header;
    print_listing($node->{'path'}, $printopts, $listingopts) or $status = 1;
}

# Done!
exit $status;
