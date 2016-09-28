#!/usr/bin/env perl

#
# Render speech to text using Google's Cloud Speech API.
#
# Copyright (C) 2011 - 2016, Lefteris Zafiris <zaf@fastmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2. See the COPYING file
# at the top of the source tree.
#
# The script takes as input flac or wav files and returns the following values:
# transcript : The recognized text string.
# confidence : A value between 0 and 1 indicating how "confident" the recognition engine
#  feels about the result. Values bigger than 0.95 usually mean that the
#  resulted text is correct.
#

use strict;
use warnings;
use URI::Escape;
use File::Temp qw(tempfile);
use Getopt::Std;
use File::Basename;
use HTTP::Tiny;
use JSON::Tiny qw(decode_json encode_json);
use MIME::Base64;

my %options;
my $flac;
my $audio;
my $http;
my $key;
my $url        = "https://speech.googleapis.com/v1beta1/speech";
my $samplerate = 16000;
my $language   = "en-US";
my $output     = "detailed";
my $results    = 1;
my $pro_filter = "false";
my $error      = 0;

getopts('k:l:o:r:n:fhq', \%options);

VERSION_MESSAGE() if (defined $options{h} || !@ARGV);

parse_options();

my %config = (
	"encoding"         => "FLAC",
	"sample_rate"      => $samplerate,
	"language_code"    => $language,
	"profanity_filter" => $pro_filter,
	"max_alternatives" => $results,
);

$http = HTTP::Tiny->new(
	agent      => 'CLI speech recognition script',
	timeout    => 60,
	verify_SSL => 1,
);

# send each sound file to google and get the recognition results #
foreach my $file (@ARGV) {
	my ($filename, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
	if ($ext ne ".flac" && $ext ne ".wav") {
		say_msg("Unsupported file type: $ext");
		++$error;
		next;
	}
	if ($ext eq ".wav") {
		if (($file = encode_flac($file)) eq '-1') {
			++$error;
			next;
		}
	}
	print("Opening $filename\n") if (!defined $options{q});
	if (open(my $fh, "<", "$file")) {
		$audio = do { local $/; <$fh> };
		close($fh);
	} else {
		say_msg("Cant read file $file");
		++$error;
		next;
	}
	my %audio = ( "content" => encode_base64($audio, "") );
	my %json = (
		"config" => \%config,
		"audio"  => \%audio,
	);

	my %headers =('Content-Type' => "application/json");
	my %options = ('headers' => \%headers, 'content' => encode_json(\%json));
	my $response = $http->request('POST', "$url:syncrecognize?key=$key", \%options);
	if (!$response->{'success'}) {
		say_msg("Failed to get data for file: $file");
		++$error;
		next;
	}
	if ($output eq "raw") {
		print $response->{'content'};
		next;
	}
	my $jdata = decode_json($response->{'content'});
	if ($output eq "detailed") {
		foreach (@{$jdata->{"results"}[0]->{"alternatives"}}) {
			printf "%-10s : %s\n", "transcript", $_->{"transcript"};
			printf "%-10s : %s\n", "confidence", $_->{"confidence"} if $_->{"confidence"};
		}
	} elsif ($output eq "compact") {
		print $_->{"transcript"}."\n" foreach (@{$jdata->{"results"}[0]->{"alternatives"}});
	}
}

exit(($error) ? 1 : 0);

sub parse_options {
# Command line options parsing #
	if (defined $options{k}) {
	# check API key #
		$key = $options{k};
	} else {
		say_msg("Invalid or missing API key.\n");
		exit 1;
	}
	if (defined $options{l}) {
	# check if language setting is valid #
		if ($options{l} =~ /^[a-z]{2}(-[a-zA-Z]{2,6})?$/) {
			$language = $options{l};
		} else {
			say_msg("Invalid language setting. Using default.\n");
		}
	}
	if (defined $options{o}) {
	# check if output setting is valid #
		if ($options{o} =~ /^(detailed|compact|raw)$/) {
			$output = $options{o};
		} else {
			say_msg("Invalid output formatting setting. Using default.\n");
		}
	}
	if (defined $options{n}) {
	# set number or results #
		$results = $options{n} if ($options{n} =~ /\d+/);
	}
	if (defined $options{r}) {
	# set audio sampling rate #
		$samplerate = $options{r} if ($options{r} =~ /\d+/);
	}
	# set profanity filter #
	$pro_filter = "true" if (defined $options{f});

	return;
}

sub encode_flac {
# Encode file to flac and return the filename #
	my $file   = shift;
	my $tmpdir = "/tmp";
	if (!$flac) {
		$flac   = `/usr/bin/which flac`;
		if (!$flac) {
			say_msg("flac encoder is missing. Aborting.");
			return -1;
		}
		chomp($flac);
	}
	my ($fh, $tmpname) = tempfile(
		"recg_XXXXXX",
		DIR    => $tmpdir,
		SUFFIX => '.flac',
		UNLINK => 1,
	);
	if (system($flac, "-1", "-f", "--totally-silent", "-o", "$tmpname", "$file")) {
		say_msg("$flac failed to encode file");
		return -1;
	}
	return $tmpname;
}

sub say_msg {
# Print messages to user if 'quiet' flag is not set #
	my @message = @_;
	warn @message if (!defined $options{q});
	return;
}

sub VERSION_MESSAGE {
# Help message #
	print "Speech recognition using Google Cloud Speech API.\n\n",
		"Usage: $0 [options] [file(s)]\n\n",
		"Supported options:\n",
		" -k <key>       specify the Speech API key\n",
		" -l <lang>      specify the language to use (default 'en-US')\n",
		" -o <type>      specify the type of output formatting\n",
		"    detailed    print detailed output with info like confidence (default)\n",
		"    compact     print only the transcripted string\n",
		"    raw         raw JSON output\n",
		" -r <rate>      specify the audio sample rate in Hz (default 16000)\n",
		" -n <number>    specify the maximum number of results (default 1)\n",
		" -f             filter out profanities\n",
		" -q             don't print any error messages or warnings\n",
		" -h             this help message\n\n";
	exit(1);
}
