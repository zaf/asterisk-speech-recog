#!/usr/bin/env perl

#
# Render speech to text using Google's speech recognition engine.
#
# Copyright (C) 2011 - 2012, Lefteris Zafiris <zaf.000@gmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2. See the COPYING file
# at the top of the source tree.
#
# The script takes as input flac, speex or wav files at 8kHz and returns the following values:
# status     : Return status. 0 means success, non zero values indicating different errors.
# id         : Some id string that googles engine returns, not very useful(?).
# utterance  : The generated text string.
# confidence : A value between 0 and 1 indicating how 'confident' the recognition engine
#  feels about the result. Values bigger than 0.95 usually mean that the
#  resulted text is correct.
#

use strict;
use warnings;
use File::Temp qw(tempfile);
use Getopt::Std;
use File::Basename;
use LWP::UserAgent;

my %options;
my $filetype;
my $url        = "http://www.google.com/speech-api/v1/recognize?xjerr=1&client=chromium";
my $samplerate = 8000;
my $language   = "en-US";
my $results    = 1;

getopts('l:r:hq', \%options);

VERSION_MESSAGE() if (defined $options{h} || !@ARGV);

if (defined $options{l}) {
# check if language setting is valid #
	if ($options{l} =~ /^[a-z]{2}(-[a-zA-Z]{2,6})?$/) {
		$language = $options{l};
	} else {
		say_msg("Invalid language setting. Using default.");
	}
}

if (defined $options{r}) {
# set number or results #
	$results = $options{r} if ($options{r} =~ /%d+/);
}

my @file_list  = @ARGV;

foreach my $file (@file_list) {
	my($filename, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
	if ($ext ne ".flac" && $ext ne ".spx" && $ext ne ".wav") {
		say_msg("Unsupported filetype: $ext");
		exit 1;
	}

	if ($ext eq ".flac") {
		$filetype   = "x-flac";
	} elsif ($ext eq ".spx") {
		$filetype   = "x-speex-with-header-byte";
	} elsif ($ext eq ".wav") {
		$filetype   = "x-flac";
		$file = encode_flac($file);
	}

	say_msg("Openning $file");
	open(my $fh, "<", "$file") or die "Cant read file: $!";
	my $audio = do { local $/; <$fh> };
	close($fh);
	my $ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/5.0 (X11; Linux) AppleWebKit/535.2 (KHTML, like Gecko)");
	$ua->timeout(20);
	my $response = $ua->post(
		"$url&lang=$language&maxresults=$results",
		Content_Type => "audio/$filetype; rate=$samplerate",
		Content      => "$audio",
	);
	last if (!$response->is_success);
	my %response;
	if ($response->content =~ /^\{"status":(\d*),"id":"(.*)","hypotheses":\[(.*)\]\}$/) {
		$response{status} = "$1";
		$response{id}     = "$2";
		if ($response{status} != 0) {
			say_msg("Error reading audio file");
			exit 1;
		}
		if ($3 =~ /^\{"utterance":"(.*)","confidence":(.*)\}/) {
			$response{utterance}  = "$1";
			$response{confidence} = "$2";
		}
	}
	if (!defined $options{q}) {
		printf "%-10s : %s\n", $_, $response{$_} foreach (keys %response);
	} else {
		print "$response{utterance}\n";
	}
	#print $response->content;
}
exit 0;

sub encode_flac {
# Encode file to flac and return the filename #
	my $file   = shift;
	my $tmpdir = "/tmp";
	my $flac   = `/usr/bin/which flac`;

	if (!$flac) {
		say_msg("flac encoder is missing. Aborting.");
		exit 1;
	}
	chomp($flac);

	my ($fh, $tmpname) = tempfile("recg_XXXXXX",
		DIR => $tmpdir,
		SUFFIX => '.flac',
		UNLINK => 1,
	);
	if (system($flac, "-8", "-f", "--totally-silent", "-o", "$tmpname", "$file")) {
		say_msg("$flac failed to encode file.");
		exit 1;
	}
	return $tmpname;
}

sub say_msg {
# Print messages to user if 'quiet' flag is not set #
	print @_, "\n" if (!defined $options{q});
}

sub VERSION_MESSAGE {
# Help message #
	print "Speech recognition using google voice API.\n\n",
		 "Usage: $0 [options] [file(s)]\n\n",
		 "Supported options:\n",
		 " -l <lang>      specify the language to use, defaults to 'en-US' (English)\n",
		 " -r <number>    specify the number of results\n",
		 " -q             Return only recognised utterance. Don't print any messages or warnings\n",
		 " -h             this help message\n\n";
	exit 1;
}
