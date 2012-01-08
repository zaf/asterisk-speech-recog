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
# The script takes as input flac files at 8kHz and returns the following values:
# status     : Return status. 0 means success, non zero values indicating different errors.
# id         : Some id string that googles engine returns, not very useful(?).
# utterance  : The generated text string.
# confidence : A value between 0 and 1 indicating how 'confident' the recognition engine
#  feels about the result. Values bigger than 0.95 usually mean that the
#  resulted text is correct.
#

use strict;
use warnings;
use LWP::UserAgent;

if (!@ARGV || $ARGV[0] eq '-h' || $ARGV[0] eq '--help') {
	print "Speech recognition using google voice.\n\n";
	print "Usage: $0 [FILES]\n\n";
	exit;
}

my $url        = "http://www.google.com/speech-api/v1/recognize?xjerr=1&client=chromium";
my $samplerate = 8000;
#my $filetype   = "x-speex-with-header-byte";
my $filetype   = "x-flac";
my $language   = "en-US";
my $results    = 1;
my @file_list  = @ARGV;

foreach my $file (@file_list) {
	print "Openning $file\n";
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
		if ($response{status} == 5) {
			print "Error reading audio file\n";
		}
		if ($3 =~ /^\{"utterance":"(.*)","confidence":(.*)\}/) {
			$response{utterance}  = "$1";
			$response{confidence} = "$2";
		}
	}
	printf "%-10s : %s\n", $_, $response{$_} foreach (keys %response);
	#print $response->content;
}
exit;
