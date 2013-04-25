#!/usr/bin/perl -w
#
# AS AT 08Mar2012
#
# Submit solar production data to pvoutput.org per http://pvoutput.org/help.html#api
#
# Setup your pvoutput settings per http://pvoutput.org/help.html#api
# Set all values in @PVOUTPUT in this script to match those in your pvoutput settings
#       - API_KEY & SYSTEM_ID to your settings from pvoutput.org
#       - SERIAL_NUM to your inverter's serial number
#       - add another record (in curly braces) if you have more than 1 inverter
#
# V1: Initial release
#
# Copyright Eric Sandeen <sandeen@sandeen.net> 2010
# released under GNU GPL v3 or later
#
# + editions by mmcdon23:
#          + removed enphase envoy lines
#          + added 4 arguments
#
# + editions by shell_l_d:
#          + added serial_num argument so works for multiple inverters
#          + replaced variables with @PVOUTPUT array of hashes
#          + removed die if $current_watts = 0
#
# + editions by trollkarlen:
#          + add support for r2 of api
#
# Usage examples:
#       perl pvoutput.pl 5500 1813 20110307 12:15 1234567890
#
# Arguments:
#  $ARGV[0] = (ETODAY) watt hrs exported so far today
#  $ARGV[1] = (PAC) current watts
#  $ARGV[2] = date (YYYYMMDD)
#  $ARGV[3] = time (HH:MM)
#  $ARGV[4] = inverter serial number - in case of multiple inverters
#  $ARGV[5] = pv voltage
#  $ARGV[6] = temp
#
#######################################################################

use HTTP::Request::Common qw(POST GET);
use LWP::UserAgent;				# Web User Agent
use strict;

my $daily_watthrs = $ARGV[0];
my $current_watts = $ARGV[1];
my $log_date      = $ARGV[2];
my $log_time      = $ARGV[3];
my $serial_num    = $ARGV[4];
my $pv_volt       = $ARGV[5];
my $temp          = $ARGV[6];

use constant {
   DEBUG_SCRIPT         => 0,   	# 0 = NO, 1 = YES
   LIVE_DATA_URL        => "http://pvoutput.org/service/r2/addstatus.jsp",
};

#
# Array of Hashes of pvoutput information for each inverter - add more as required (in extra curly braces)
#
my @PVOUTPUT = (
	{
		SERIAL_NUM    => "S441218059",
		API_KEY       => "ce3e40776d259a48dc717a652d19a665be0c5157",
		SYSTEM_ID     => "18661",
	},
);


#######################################################################


#
# Display arguments if $debug turned on
#
if ( DEBUG_SCRIPT ) {
   print "Serial: $serial_num as at: $log_date $log_time\n";
   print "Now:   $current_watts W\n";
   print "Today: $daily_watthrs Wh\n";
}

#
# Prepare the web request
#
my $ua = LWP::UserAgent->new;

#
# Loop through the PVOUTPUT Array of Hashes to find the matching inverter serial number
#
my $i;
for $i ( 0 .. $#PVOUTPUT ) {
   if ( $PVOUTPUT[$i]{SERIAL_NUM} eq $serial_num ) {
      if ( DEBUG_SCRIPT ) {
         print $PVOUTPUT[$i]{SERIAL_NUM} . " serial match found at index $i\n";
      }
      $ua->default_header(
         "X-Pvoutput-Apikey"   => $PVOUTPUT[$i]{API_KEY},
         "X-Pvoutput-SystemId" => $PVOUTPUT[$i]{SYSTEM_ID},
         "Content-Type"        => "application/x-www-form-urlencoded"
      );
              
      #
      # Prepare request string
      #
      print "Sending to PVOUTPUT [ d => $log_date, t => $log_time, v1 => $daily_watthrs, v2 => $current_watts, v5 => $temp, v6 => $pv_volt ]\n";
      my $request = POST LIVE_DATA_URL, [ d => $log_date, t => $log_time, v1 => $daily_watthrs, v2 => $current_watts, v5 => $temp, v6 => $pv_volt ];

      #
      # Send request to pvoutput to add/update live output status
      #
      my $res = $ua->request($request);

      #
      # Display any errors
      #
      if (! $res->is_success) {
         die "Error via pvoutput.org: " . $res->content . "\n";
         #die "Couldn't submit data to pvoutput.org: " . $res->status_line . "\n";
      }
              
   }
}

exit;
