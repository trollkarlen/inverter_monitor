#!/usr/bin/perl -w
#
# AS AT 27Mar2011
#
# This creates the rrd file using rrdtool (Round Robin Database Tool)
# Download & install rrdtool for your platform (unix/linux/windows)
# - http://oss.oetiker.ch/rrdtool/download.en.html
# - http://www.mywebhostingblog.net/window-hosting/install-rrdtool-on-windows-server/]
#
# CREATED BY:  slampt with help from JinbaIttai
#
# + editions by shell_l_d:
#          + converted to perl script
#
# Usage examples:
#       perl create_rrd.pl "c:/solar/inverter.rrd" "c:/rrdtool/rrdtool"
#       perl create_rrd.pl "/tmp/inverter.rrd" "/usr/bin/rrdtool"
#
# Arguments:
#  $ARGV[0] = path & name for the new rrd file
#  $ARGV[1] = path to rrdtool
#
#######################################################################

my $rrdfile = $ARGV[0];
my $rrdexe = $ARGV[1];

#
# Info:     http://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html
# --step  = base interval in secs with which data will be fed into the RRD.
# --start = time in secs since EPOCH when first value should be added to the RRD
# DS      = Data Source
#           DS:ds-name:GAUGE|COUNTER|DERIVE|ABSOLUTE:heartbeat:min:max
# RRA     = Round Robin Archive
#           RRA:AVERAGE|MIN|MAX|LAST:xff:steps:rows
#
my $rrdCreateLine = "--step 60 "    .
#        "--start 1300774440 "       .
	"DS:TEMP:GAUGE:120:U:U "    .
	"DS:VPV:GAUGE:120:U:U "     .
	"DS:IAC:GAUGE:120:U:U "     .
	"DS:VAC:GAUGE:120:U:U "     .
	"DS:FAC:GAUGE:120:U:U "     .
	"DS:PAC:GAUGE:120:0:U "     .
	"DS:ETOTAL:GAUGE:120:0:U "  .
	"DS:HTOTAL:GAUGE:120:0:U "  .
	"DS:MODE:GAUGE:120:0:U "    .
	"DS:ETODAY:GAUGE:120:0:U "  .
	"RRA:AVERAGE:0.5:1:576 "    .   #  1*60secs=  1min ,  576*  1min  =    9.6hrs =   0.4days
	"RRA:AVERAGE:0.5:6:672 "    .   #  6*60secs=  6mins,  672*  6mins =   67.2hrs =   2.8days
	"RRA:AVERAGE:0.5:24:732 "   .   # 24*60secs= 24mins,  732* 24mins =  292.8hrs =  12.2days
	"RRA:AVERAGE:0.5:144:1460";     #144*60secs=144mins, 1460*144mins = 3504.0hrs = 146.0days

system( "$rrdexe create $rrdfile $rrdCreateLine" );