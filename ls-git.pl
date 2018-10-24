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
use strict;
use warnings;
use feature qw(say);

use Cwd;
use Cwd 'abs_path';
use Cwd 'realpath';
use File::Basename;
use File::Spec::Functions 'catfile';
use Fcntl ':mode';
use Getopt::Long;
use List::Util qw(reduce max);
use Scalar::Util qw(reftype);

use Data::Dumper; # Debug
# ----------------------------------------------------------------------------------------------------------------------
# Globals:
# ----------------------------------------------------------------------------------------------------------------------

my %args        = ();
my $color       = 1;
my $status      = 0;

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
    return "usage: @{[basename($0, '.pl')]} [-ahls] [file ...]";
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
            push \@results, $args{$key};
        } else {
            push \@results, (%$arg)[1]
        }
    }

    return @results;
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
        'path'           => abs_path($file),
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
        'stat_ino'       => $stat[1],
        'stat_mode'      => $stat[2],
        'stat_nlink'     => $stat[3],
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
        return -1;
    }

    @entries_raw = readdir($directory_handle);
    closedir($directory_handle);

    # Clean the entries.
    my $entry;
    foreach $entry (@entries_raw) {
        next if (substr($entry, 0, 1) eq '.') && !$opt_hidden;
        push \@entries, catfile($directory, $entry);
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

    my @rendered = ({'text' => $info->{'path_basename'}});
    if ($_[3] && $info->{'kind'}->{'kind'} eq 'symlink') {
        push \@rendered, {'text' => ' -> '};
        push \@rendered, {'text' => readlink($info->{'file'})};
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
## The block count component.
sub render_component_size_blocks {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text'   => ' ',
        'margin' => 1 # bool, not a value
    },{
        'text' => $info->{'io_blocks'}
    }];
}

## RENDER COMPONENT:
## The file owner.
sub render_component_owner {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text'     => get_user_name($info->{'user'}),
    }];
}

## RENDER COMPONENT:
## The file group.
sub render_component_group {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text'   => ' ',
        'margin' => 1 # bool, not a value
    },{
        'text' => get_group_name($info->{'group'}),
    }];
}

## RENDER COMPONENT:
## The file size.
sub render_component_size {
    my $render = $_[0];
    my $colnum = $_[1];
    my $info   = $_[2];

    @$render[$colnum] = [{
        'text'   => '   ',
        'margin' => 1 # bool, not a value
    },{
        'text' => $info->{'size'}
    }];
}

## RENDER COMPONENT:
## The file date.
sub render_component_date {
    my $render    = $_[0];
    my $colnum    = $_[1];
    my $info      = $_[2];

    my $date_kind  = $_[3];
    my $date_stamp = $info->{'time_' . $date_kind};

    @$render[$colnum] = [{
        'text' => $date_stamp
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
        push $widths, component_width($component);
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

    foreach $segment (@{$_[0]}) {
        $padding -= length $segment->{'text'};
        $buffer  .= $segment->{'ansi_prefix'} if exists $segment->{'ansi_prefix'};
        $buffer  .= $segment->{'text'};
        $buffer  .= $segment->{'ansi_suffix'} if exists $segment->{'ansi_suffix'};
    }

    $buffer = (sprintf "%-${padding}s", '') . $buffer if $_[2] eq 'L';
    $buffer = $buffer . (sprintf "%-${padding}s", '') if $_[2] eq 'R';

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
        $component_size_blocks,
        $component_owner,
        $component_group,
        $component_size,
        $componentopt_size_human,
        $component_date,
        $componentopt_date_kind,
        $component_file,
        $componentopt_file_dest
    ) = desarg $_[1],
        {'quiet'                   => 0},
        {'sort'                    => 'filename'},
        {'single_column'           => 0},
        {'show_total'              => 0},
        {'component_permissions'   => 0},
        {'component_size_blocks'   => 0},
        {'component_owner'         => 0},
        {'component_group'         => 0},
        {'component_size'          => 0},
        {'componentopt_size_human' => 0},
        {'component_date'          => 0},
        {'componentopt_date_kind', => 'modified'},
        {'component_file'          => 1},
        {'componentopt_file_dest'  => 0};


    my @entries = map {file_info $_->{'path'}, {'quiet' => $opt_quiet}} @{$_[0]};
    my @renders = ();

    # Render components.
    my $file;
    foreach $file (@entries) {
        my $column  = 0;
        my $render  = [];
        my $renhash = {
            'info'   => $file,
            'render' => $render
        };

        render_component_permissions ($render, $column++, $file)                          if $component_permissions;
        render_component_size_blocks ($render, $column++, $file)                          if $component_size_blocks;
        render_component_owner       ($render, $column++, $file)                          if $component_owner;
        render_component_group       ($render, $column++, $file)                          if $component_group;
        render_component_size        ($render, $column++, $file)                          if $component_size;
        render_component_date        ($render, $column++, $file, $componentopt_date_kind) if $component_date;
        render_component_file        ($render, $column++, $file, $componentopt_file_dest) if $component_file;

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
            for (my $i = 0; $i < @columns; $i++) {
                print " " if $i != 0;
                print component_string($render->{'render'}[$i], $columns[$i], ($i == @columns - 1) ? '-' : 'L');
            }

            print "\n";
        }

    } else {
        # Calculate column width.
        my $width = max (map {reduce {$a + $b} @{component_widths($_->{'render'})}} @renders);

        # TODO: Short format.
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
## @param
sub print_listing {
    my $directory = $_[0];
    my $files     = files($_[0], {'hidden' => $args{'a'}}) or return -1;

    for (my $i = 0; $i < @$files; $i++) {
        @$files[$i] = {
            'path'   => @$files[$i],
            'follow' => 0
        };
    }

    print_entries($files, { %{$_[1]}, 'show_total' => 1 }) or return -1;

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

    Getopt::Long::Configure('bundling', 'bundling_override', 'gnu_compat');
    Getopt::Long::GetOptions(\%args,
        "1",      # One output per line.
        "a",      # Display all files.
        "l",      # Display long listing.
        "G",      # Enable colors.
        "h",      # Display human readable units.
    );

    $SIG{__WARN__} = undef;
}

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

    # Determine if symlink should be followed.
    my $follow = S_ISLNK($stat[2]) || (substr($file, -1, 1) eq '/') || basename($file) =~ /^\.{1,2}$/;
    if ($follow && !(S_ISDIR($stat[2]) || S_ISLNK($stat[2]))) {
        say STDERR prog_error("$file: Not a directory");
        $status = 1;
        next;
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

# Sort.
@files = sort {$a->{'path'} cmp $b->{'path'}} @files;
@dirs  = sort {$a->{'path'} cmp $b->{'path'}} @dirs;

# ----------------------------------------------------------------------------------------------------------------------
# Main: Print things!
# ----------------------------------------------------------------------------------------------------------------------

my $printopts = {
    'component_permissions' => 1,
    'component_size_blocks' => 1,
    'component_owner'       => 1,
    'component_group'       => 1,
    'component_size'        => 1,
    'component_date'        => 1,
    'componentopt_file_dest' => 1,
    'single_column'         => 1,
};

# Entries.
print_entries(\@files, $printopts) or $status = 1;

# Directories.
my $node;
foreach $node (@dirs) {
    print_header($node->{'path'}) unless $no_header;
    print_listing($node->{'path'}, $printopts) or $status = 1;
}

# Done!
exit $status;
