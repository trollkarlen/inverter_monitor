#!/usr/bin/perl -w
#
# AS AT 08Mar2012
#
# inverter.pl - polls data from the RS232 port on certain inverters and outputs data to a csv file
# & optionally to http://pvoutput.org, depending on the configuration file settings (config.ini).
#
# Usage examples:
#       perl inverter.pl
#       perl inverter.pl "COM1"
#       perl inverter.pl "/dev/ttyS0"
#
# Arguments:
#  $ARGV[0] = OPTIONAL port name (eg: "COM1") if have >1 inverter. See: config.ini for defaults.
#
# Output Filenames
# * inverter_[serial#]_YYYYMMDD.csv
# * inverter_err_[serial#]_YYYYMM.csv
# * inverter_[serial#].rrd
#
#######################################################################
#
# (c) 2010-2011 jinba @ jinba-ittai.net
# Licensed under the GNU GPL version 2
#
# + editions by shell_l_d:
#          + edited to work with ActivePerl (Windows) too
#          + added version/firmware checking & combined CMS2k & CMS10k (parseData) versions
#          + added data format checking (per findings from JinbaIttai & Ingmar)
#          + added %HoH, %HASH
#          + added writeToPort() & added warnings to readbuf()
#          + edited calc of sleep so dont have to keep DATAPOLL_FREQ_SECS set to 60.
#          + edited pvoutput code so dont have to keep DATAPOLL_FREQ_SECS set to 60.
#          + added DESCR to $HoH hash of hashes & used in parseDataFmt()
#          + added check if ( $seconds > 0 ) before 'sleep $seconds'
#          + added DESCR to parseData() & replaced die with warning in writeToFile()
#          + added %HoHparams, closeSerialPort(), parseParamFmt(), parseParam()
#          + renamed %HoH items: ETOTAL, HTOTAL, UNK1 through UNK9
#          + edited etotal & htotal calcs in WriteToFile()
#          + renamed DIVIDEBY to MULTIPLY & edited their values & replaced / with * in parseParam() & parseData()
#          + added rrdtool code
#          + edited REINIT_DEFAULT & writeReadBuffer()
#          + added warning to closeSerialPort() & edited REINIT_DEFAULT line in writeReadBuffer()
#          + added getDate_YYYYMM(), getErrFileName().
#          + edited parseData().
#          + implemented AppConfig & a configuration file (config.ini).
#          + edited parseVersData() - changed 'hex_serial_length > 0' check to hex_serial_index
#          + edited calcReqConfSerial() - added print hexSerial if flags_debug turned on & edited description.
#          + edited calcReqConfSerial() - added $HASH{SERIAL} = $hexSerial (so is set for KLNE inverters too)
#          + edited calcReqConfSerial() - fixed $HASH{SERIAL} = was hex not decimal (KLNE fix) & added print SERIAL.
#          + added isWindows(), getTime_HHMMSS(), setPollTimes(), setPvoutputTimes(), sleepTilNextPoll(), isValidPollTime(), isNextPvoutputDue(), main(), noTalks, reInits.
#          + edited initialiseSerialPort(), getLogFileName(), getErrFileName(), getRrdFileName(), writeToFile() - replaced if $^O with if isWindows()
#          + edited writeReadBuffer() - edited code for noTalks & reInits, added &isValidPollTime().
#          + edited all getDate & getTime subs - simplified them
#          + added new configs: time_start_poll, time_end_poll (script exits if time is outside this range).
#          + edited initialiseInverter(), main(): handle scenario if empty string returned by writeReadBuffer(...)
#          + edited parseData() - added $lastEtoday, edited $errLine.
#
# + editions by mmcdon23:
#          + added getDateTime_HHMM() & getDate_YYYYMMDD()
#          + added date & time strings to writeToFile()
#          + added "_YYYYMMDD.csv" to logfile name (suffix)
#          + edited parseData() by using 0 for ETODAY in morning if hasn't reset yet
#          + moved sleep from parseData() to main
#          + moved code from initialise, readbuf & main to writeReadBuffer()
#            & altered to continue reading until read pattern matched.
#          + added pvoutput code to main & only send to PVoutput every 5 or 10th min per PVOUTPUT_FREQ constant.
#          + added calc of sleep seconds to stop the script creeping away from the 00 minute mark.
#          + edited added if statement to parseParamFmt() & parseDataFmt() & around the calls to them
#
# + editions by nigol2:
#          + added optional port argument in case have more than 1 inverter
#          + added serial# to logfile name in case have more than 1 inverter
#
# + editions by slampt:
#          + uncommented & edited rrdtool (graphing) code in writeToFile() with help from JinbaIttai
#
#######################################################################
#
# Required to be installed:
# * perl
# * perl AppConfig module
# * perl Win32::SerialPort module  (Windows)
# * perl Device::SerialPort module (Unix/Linux/Other)
#
#######################################################################

#use strict;
use warnings;
use AppConfig;  # used to read from a config file

$| = 1;         # don't let Perl buffer I/O

#######################################################################
#
# Define constants & variables (most from config file)
#

# common
my $noTalks = 0;
my $reInits = 0;
my $lastPollTime = 0;
my $nextPollTime = 0;
my $lastPvoutputTime = 0;
my $nextPvoutputTime = 0;

# create a new AppConfig object & auto-define all variables
my $config = AppConfig->new();

# define new variables
$config->define( "flags_debug!"          );
$config->define( "flags_use_pvoutput!"   );
$config->define( "flags_use_rrdtool!"    );
$config->define( "secs_datapoll_freq=s"  );
$config->define( "secs_pvoutput_freq=s"  );
$config->define( "secs_timeout=s"        );
$config->define( "secs_reinit=s"         );
$config->define( "time_start_poll=s"     );
$config->define( "time_end_poll=s"       );
$config->define( "paths_windows=s"       );
$config->define( "paths_other=s"         );
$config->define( "scripts_pvoutput=s"    );
$config->define( "scripts_create_rrd=s"  );
$config->define( "scripts_rrdtool_exe_win=s" );
$config->define( "scripts_rrdtool_exe_oth=s" );
$config->define( "serial_baud=s"         );
$config->define( "serial_port_win=s"     );
$config->define( "serial_port_oth=s"     );
$config->define( "serial_parity=s"       );
$config->define( "serial_databits=s"     );
$config->define( "serial_stopbits=s"     );
$config->define( "serial_handshake=s"    );
$config->define( "serial_datatype=s"     );
$config->define( "hex_data_to_follow_index=s" );
$config->define( "hex_capacity_index=s"  );
$config->define( "hex_capacity_length=s" );
$config->define( "hex_firmware_index=s"  );
$config->define( "hex_firmware_length=s" );
$config->define( "hex_model_index=s"     );
$config->define( "hex_model_length=s"    );
$config->define( "hex_manuf_index=s"     );
$config->define( "hex_manuf_length=s"    );
$config->define( "hex_serial_index=s"    );
$config->define( "hex_serial_length=s"   );
$config->define( "hex_other_index=s"     );
$config->define( "hex_other_length=s"    );
$config->define( "hex_confserial_index=s" );
$config->define( "sendhex_initialise=s"   );
$config->define( "sendhex_serial=s"       );
$config->define( "sendhex_conf_serial1=s" );
$config->define( "sendhex_conf_serial2=s" );
$config->define( "sendhex_version=s"     );
$config->define( "sendhex_paramfmt=s"    );
$config->define( "sendhex_param=s"       );
$config->define( "sendhex_datafmt=s"     );
$config->define( "sendhex_data=s"        );
$config->define( "recvhex_serial=s"      );
$config->define( "recvhex_conf_serial=s" );
$config->define( "recvhex_version=s"     );
$config->define( "recvhex_paramfmt=s"    );
$config->define( "recvhex_param=s"       );
$config->define( "recvhex_datafmt=s"     );
$config->define( "recvhex_data=s"        );
$config->define( "param_vpvstart_hexcode=s"  );
$config->define( "param_vpvstart_multiply=s"  );
$config->define( "param_vpvstart_measure=s"  );
$config->define( "param_vpvstart_index=s"  );
$config->define( "param_vpvstart_descr=s"  );
$config->define( "param_tstart_hexcode=s"  );
$config->define( "param_tstart_multiply=s"  );
$config->define( "param_tstart_measure=s"  );
$config->define( "param_tstart_index=s"  );
$config->define( "param_tstart_descr=s"  );
$config->define( "param_vacmin_hexcode=s"  );
$config->define( "param_vacmin_multiply=s"  );
$config->define( "param_vacmin_measure=s"  );
$config->define( "param_vacmin_index=s"  );
$config->define( "param_vacmin_descr=s"  );
$config->define( "param_vacmax_hexcode=s"  );
$config->define( "param_vacmax_multiply=s"  );
$config->define( "param_vacmax_measure=s"  );
$config->define( "param_vacmax_index=s"  );
$config->define( "param_vacmax_descr=s"  );
$config->define( "param_facmin_hexcode=s"  );
$config->define( "param_facmin_multiply=s"  );
$config->define( "param_facmin_measure=s"  );
$config->define( "param_facmin_index=s"  );
$config->define( "param_facmin_descr=s"  );
$config->define( "param_facmax_hexcode=s"  );
$config->define( "param_facmax_multiply=s"  );
$config->define( "param_facmax_measure=s"  );
$config->define( "param_facmax_index=s"  );
$config->define( "param_facmax_descr=s"  );
$config->define( "param_zacmax_hexcode=s"  );
$config->define( "param_zacmax_multiply=s"  );
$config->define( "param_zacmax_measure=s"  );
$config->define( "param_zacmax_index=s"  );
$config->define( "param_zacmax_descr=s"  );
$config->define( "param_dzac_hexcode=s"  );
$config->define( "param_dzac_multiply=s"  );
$config->define( "param_dzac_measure=s"  );
$config->define( "param_dzac_index=s"  );
$config->define( "param_dzac_descr=s"  );
$config->define( "data_temp_hexcode=s"  );
$config->define( "data_temp_multiply=s"  );
$config->define( "data_temp_measure=s"  );
$config->define( "data_temp_index=s"  );
$config->define( "data_temp_descr=s"  );
$config->define( "data_vpv1_hexcode=s"  );
$config->define( "data_vpv1_multiply=s"  );
$config->define( "data_vpv1_measure=s"  );
$config->define( "data_vpv1_index=s"  );
$config->define( "data_vpv1_descr=s"  );
$config->define( "data_vpv2_hexcode=s"  );
$config->define( "data_vpv2_multiply=s"  );
$config->define( "data_vpv2_measure=s"  );
$config->define( "data_vpv2_index=s"  );
$config->define( "data_vpv2_descr=s"  );
$config->define( "data_vpv3_hexcode=s"  );
$config->define( "data_vpv3_multiply=s"  );
$config->define( "data_vpv3_measure=s"  );
$config->define( "data_vpv3_index=s"  );
$config->define( "data_vpv3_descr=s"  );
$config->define( "data_ipv1_hexcode=s"  );
$config->define( "data_ipv1_multiply=s"  );
$config->define( "data_ipv1_measure=s"  );
$config->define( "data_ipv1_index=s"  );
$config->define( "data_ipv1_descr=s"  );
$config->define( "data_ipv2_hexcode=s"  );
$config->define( "data_ipv2_multiply=s"  );
$config->define( "data_ipv2_measure=s"  );
$config->define( "data_ipv2_index=s"  );
$config->define( "data_ipv2_descr=s"  );
$config->define( "data_ipv3_hexcode=s"  );
$config->define( "data_ipv3_multiply=s"  );
$config->define( "data_ipv3_measure=s"  );
$config->define( "data_ipv3_index=s"  );
$config->define( "data_ipv3_descr=s"  );
$config->define( "data_etoday_hexcode=s"  );
$config->define( "data_etoday_multiply=s"  );
$config->define( "data_etoday_measure=s"  );
$config->define( "data_etoday_index=s"  );
$config->define( "data_etoday_descr=s"  );
$config->define( "data_vpv_hexcode=s"  );
$config->define( "data_vpv_multiply=s"  );
$config->define( "data_vpv_measure=s"  );
$config->define( "data_vpv_index=s"  );
$config->define( "data_vpv_descr=s"  );
$config->define( "data_ipv3_hexcode=s"  );
$config->define( "data_ipv3_multiply=s"  );
$config->define( "data_ipv3_measure=s"  );
$config->define( "data_ipv3_index=s"  );
$config->define( "data_ipv3_descr=s"  );
$config->define( "data_iac_hexcode=s"  );
$config->define( "data_iac_multiply=s"  );
$config->define( "data_iac_measure=s"  );
$config->define( "data_iac_index=s"  );
$config->define( "data_iac_descr=s"  );
$config->define( "data_vac_hexcode=s"  );
$config->define( "data_vac_multiply=s"  );
$config->define( "data_vac_measure=s"  );
$config->define( "data_vac_index=s"  );
$config->define( "data_vac_descr=s"  );
$config->define( "data_fac_hexcode=s"  );
$config->define( "data_fac_multiply=s"  );
$config->define( "data_fac_measure=s"  );
$config->define( "data_fac_index=s"  );
$config->define( "data_fac_descr=s"  );
$config->define( "data_pac_hexcode=s"  );
$config->define( "data_pac_multiply=s"  );
$config->define( "data_pac_measure=s"  );
$config->define( "data_pac_index=s"  );
$config->define( "data_pac_descr=s"  );
$config->define( "data_zac_hexcode=s"  );
$config->define( "data_zac_multiply=s"  );
$config->define( "data_zac_measure=s"  );
$config->define( "data_zac_index=s"  );
$config->define( "data_zac_descr=s"  );
$config->define( "data_etotalh_hexcode=s"  );
$config->define( "data_etotalh_multiply=s"  );
$config->define( "data_etotalh_measure=s"  );
$config->define( "data_etotalh_index=s"  );
$config->define( "data_etotalh_descr=s"  );
$config->define( "data_etotall_hexcode=s"  );
$config->define( "data_etotall_multiply=s"  );
$config->define( "data_etotall_measure=s"  );
$config->define( "data_etotall_index=s"  );
$config->define( "data_etotall_descr=s"  );
$config->define( "data_htotalh_hexcode=s"  );
$config->define( "data_htotalh_multiply=s"  );
$config->define( "data_htotalh_measure=s"  );
$config->define( "data_htotalh_index=s"  );
$config->define( "data_htotalh_descr=s"  );
$config->define( "data_htotall_hexcode=s"  );
$config->define( "data_htotall_multiply=s"  );
$config->define( "data_htotall_measure=s"  );
$config->define( "data_htotall_index=s"  );
$config->define( "data_htotall_descr=s"  );
$config->define( "data_mode_hexcode=s"  );
$config->define( "data_mode_multiply=s"  );
$config->define( "data_mode_measure=s"  );
$config->define( "data_mode_index=s"  );
$config->define( "data_mode_descr=s"  );
$config->define( "data_errgv_hexcode=s"  );
$config->define( "data_errgv_multiply=s"  );
$config->define( "data_errgv_measure=s"  );
$config->define( "data_errgv_index=s"  );
$config->define( "data_errgv_descr=s"  );
$config->define( "data_errgf_hexcode=s"  );
$config->define( "data_errgf_multiply=s"  );
$config->define( "data_errgf_measure=s"  );
$config->define( "data_errgf_index=s"  );
$config->define( "data_errgf_descr=s"  );
$config->define( "data_errgz_hexcode=s"  );
$config->define( "data_errgz_multiply=s"  );
$config->define( "data_errgz_measure=s"  );
$config->define( "data_errgz_index=s"  );
$config->define( "data_errgz_descr=s"  );
$config->define( "data_errtemp_hexcode=s"  );
$config->define( "data_errtemp_multiply=s"  );
$config->define( "data_errtemp_measure=s"  );
$config->define( "data_errtemp_index=s"  );
$config->define( "data_errtemp_descr=s"  );
$config->define( "data_errpv1_hexcode=s"  );
$config->define( "data_errpv1_multiply=s"  );
$config->define( "data_errpv1_measure=s"  );
$config->define( "data_errpv1_index=s"  );
$config->define( "data_errpv1_descr=s"  );
$config->define( "data_errgfc1_hexcode=s"  );
$config->define( "data_errgfc1_multiply=s"  );
$config->define( "data_errgfc1_measure=s"  );
$config->define( "data_errgfc1_index=s"  );
$config->define( "data_errgfc1_descr=s"  );
$config->define( "data_errmode_hexcode=s"  );
$config->define( "data_errmode_multiply=s"  );
$config->define( "data_errmode_measure=s"  );
$config->define( "data_errmode_index=s"  );
$config->define( "data_errmode_descr=s"  );

# fill variables by reading configuration file
$config->file( "config.ini" ) || die "FAILED to open and/or read config file: config.ini\n";

if ($config->flags_debug) {
  print "debug=" . $config->flags_debug ;
  print ", use_pvoutput=" . $config->flags_use_pvoutput ;
  print ", use_rrdtool=" . $config->flags_use_rrdtool ;
  print ", hex_serial_length=" . $config->hex_serial_length . "\n" ;
  print "time_start_poll=" . $config->time_start_poll ;
  print ", time_end_poll=" . $config->time_end_poll . "\n" ;
}

#
# inverter parameter format codes (hash of hashes)
#
%HoHparams = (
	'VPV-START' => {
                HEXCODE  => $config->param_vpvstart_hexcode,
                MULTIPLY => $config->param_vpvstart_multiply,
                MEAS     => $config->param_vpvstart_measure,
                INDEX    => $config->param_vpvstart_index,
                VALUE    => 0,
                DESCR    => $config->param_vpvstart_descr,
	},
	'T-START'   => {
                HEXCODE  => $config->param_tstart_hexcode,
                MULTIPLY => $config->param_tstart_multiply,
                MEAS     => $config->param_tstart_measure,
                INDEX    => $config->param_tstart_index,
                VALUE    => 0,
                DESCR    => $config->param_tstart_descr,
	},
	'VAC-MIN'   => {
                HEXCODE  => $config->param_vacmin_hexcode,
                MULTIPLY => $config->param_vacmin_multiply,
                MEAS     => $config->param_vacmin_measure,
                INDEX    => $config->param_vacmin_index,
                VALUE    => 0,
                DESCR    => $config->param_vacmin_descr,
	},
	'VAC-MAX'   => {
                HEXCODE  => $config->param_vacmax_hexcode,
                MULTIPLY => $config->param_vacmax_multiply,
                MEAS     => $config->param_vacmax_measure,
                INDEX    => $config->param_vacmax_index,
                VALUE    => 0,
                DESCR    => $config->param_vacmax_descr,
	},
	'FAC-MIN'   => {
                HEXCODE  => $config->param_facmin_hexcode,
                MULTIPLY => $config->param_facmin_multiply,
                MEAS     => $config->param_facmin_measure,
                INDEX    => $config->param_facmin_index,
                VALUE    => 0,
                DESCR    => $config->param_facmin_descr,
	},
	'FAC-MAX'   => {
                HEXCODE  => $config->param_facmax_hexcode,
                MULTIPLY => $config->param_facmax_multiply,
                MEAS     => $config->param_facmax_measure,
                INDEX    => $config->param_facmax_index,
                VALUE    => 0,
                DESCR    => $config->param_facmax_descr,
	},
	'ZAC-MAX'   => {
                HEXCODE  => $config->param_zacmax_hexcode,
                MULTIPLY => $config->param_zacmax_multiply,
                MEAS     => $config->param_zacmax_measure,
                INDEX    => $config->param_zacmax_index,
                VALUE    => 0,
                DESCR    => $config->param_zacmax_descr,
	},
	'DZAC'      => {
                HEXCODE  => $config->param_dzac_hexcode,
                MULTIPLY => $config->param_dzac_multiply,
                MEAS     => $config->param_dzac_measure,
                INDEX    => $config->param_dzac_index,
                VALUE    => 0,
                DESCR    => $config->param_dzac_descr,
	},
); #end %HoHparams

#
# inverter data format codes (hash of hashes)
#
%HoH = (
	TEMP   => {
                HEXCODE  => $config->data_temp_hexcode,
                MULTIPLY => $config->data_temp_multiply,
                MEAS     => $config->data_temp_measure,
                INDEX    => $config->data_temp_index,
                VALUE    => 0,
                DESCR    => $config->data_temp_descr,
	},
	VPV1   => {
                HEXCODE  => $config->data_vpv1_hexcode,
                MULTIPLY => $config->data_vpv1_multiply,
                MEAS     => $config->data_vpv1_measure,
                INDEX    => $config->data_vpv1_index,
                VALUE    => 0,
                DESCR    => $config->data_vpv1_descr,
	},
	VPV2   => {
                HEXCODE  => $config->data_vpv2_hexcode,
                MULTIPLY => $config->data_vpv2_multiply,
                MEAS     => $config->data_vpv2_measure,
                INDEX    => $config->data_vpv2_index,
                VALUE    => 0,
                DESCR    => $config->data_vpv2_descr,
	},
	VPV3   => {
                HEXCODE  => $config->data_vpv3_hexcode,
                MULTIPLY => $config->data_vpv3_multiply,
                MEAS     => $config->data_vpv3_measure,
                INDEX    => $config->data_vpv3_index,
                VALUE    => 0,
                DESCR    => $config->data_vpv3_descr,
	},
	IPV1   => {
                HEXCODE  => $config->data_ipv1_hexcode,
                MULTIPLY => $config->data_ipv1_multiply,
                MEAS     => $config->data_ipv1_measure,
                INDEX    => $config->data_ipv1_index,
                VALUE    => 0,
                DESCR    => $config->data_ipv1_descr,
	},
	IPV2   => {
                HEXCODE  => $config->data_ipv2_hexcode,
                MULTIPLY => $config->data_ipv2_multiply,
                MEAS     => $config->data_ipv2_measure,
                INDEX    => $config->data_ipv2_index,
                VALUE    => 0,
                DESCR    => $config->data_ipv2_descr,
	},
	IPV3   => {
                HEXCODE  => $config->data_ipv3_hexcode,
                MULTIPLY => $config->data_ipv3_multiply,
                MEAS     => $config->data_ipv3_measure,
                INDEX    => $config->data_ipv3_index,
                VALUE    => 0,
                DESCR    => $config->data_ipv3_descr,
	},
	ETODAY => {
                HEXCODE  => $config->data_etoday_hexcode,
                MULTIPLY => $config->data_etoday_multiply,
                MEAS     => $config->data_etoday_measure,
                INDEX    => $config->data_etoday_index,
                VALUE    => 0,
                DESCR    => $config->data_etoday_descr,
	},
	VPV    => {
                HEXCODE  => $config->data_vpv_hexcode,
                MULTIPLY => $config->data_vpv_multiply,
                MEAS     => $config->data_vpv_measure,
                INDEX    => $config->data_vpv_index,
                VALUE    => 0,
                DESCR    => $config->data_vpv_descr,
	},
	IAC    => {
                HEXCODE  => $config->data_iac_hexcode,
                MULTIPLY => $config->data_iac_multiply,
                MEAS     => $config->data_iac_measure,
                INDEX    => $config->data_iac_index,
                VALUE    => 0,
                DESCR    => $config->data_iac_descr,
	},
	VAC    => {
                HEXCODE  => $config->data_vac_hexcode,
                MULTIPLY => $config->data_vac_multiply,
                MEAS     => $config->data_vac_measure,
                INDEX    => $config->data_vac_index,
                VALUE    => 0,
                DESCR    => $config->data_vac_descr,
	},
	FAC    => {
                HEXCODE  => $config->data_fac_hexcode,
                MULTIPLY => $config->data_fac_multiply,
                MEAS     => $config->data_fac_measure,
                INDEX    => $config->data_fac_index,
                VALUE    => 0,
                DESCR    => $config->data_fac_descr,
	},
	PAC    => {
                HEXCODE  => $config->data_pac_hexcode,
                MULTIPLY => $config->data_pac_multiply,
                MEAS     => $config->data_pac_measure,
                INDEX    => $config->data_pac_index,
                VALUE    => 0,
                DESCR    => $config->data_pac_descr,
	},
	ZAC    => {
                HEXCODE  => $config->data_zac_hexcode,
                MULTIPLY => $config->data_zac_multiply,
                MEAS     => $config->data_zac_measure,
                INDEX    => $config->data_zac_index,
                VALUE    => 0,
                DESCR    => $config->data_zac_descr,
	},
	ETOTALH => {
                HEXCODE  => $config->data_etotalh_hexcode,
                MULTIPLY => $config->data_etotalh_multiply,
                MEAS     => $config->data_etotalh_measure,
                INDEX    => $config->data_etotalh_index,
                VALUE    => 0,
                DESCR    => $config->data_etotalh_descr,
	},
	ETOTALL => {
                HEXCODE  => $config->data_etotall_hexcode,
                MULTIPLY => $config->data_etotall_multiply,
                MEAS     => $config->data_etotall_measure,
                INDEX    => $config->data_etotall_index,
                VALUE    => 0,
                DESCR    => $config->data_etotall_descr,
	},
	HTOTALH => {
                HEXCODE  => $config->data_htotalh_hexcode,
                MULTIPLY => $config->data_htotalh_multiply,
                MEAS     => $config->data_htotalh_measure,
                INDEX    => $config->data_htotalh_index,
                VALUE    => $config->data_htotalh_index,
                DESCR    => $config->data_htotalh_descr,
	},
	HTOTALL => {
                HEXCODE  => $config->data_htotall_hexcode,
                MULTIPLY => $config->data_htotall_multiply,
                MEAS     => $config->data_htotall_measure,
                INDEX    => $config->data_htotall_index,
                VALUE    => 0,
                DESCR    => $config->data_htotall_descr,
	},
	MODE   => {
                HEXCODE  => $config->data_mode_hexcode,
                MULTIPLY => $config->data_mode_multiply,
                MEAS     => $config->data_mode_measure,
                INDEX    => $config->data_mode_index,
                VALUE    => 0,
                DESCR    => $config->data_mode_descr,
	},
	ERR_GV => {
                HEXCODE  => $config->data_errgv_hexcode,
                MULTIPLY => $config->data_errgv_multiply,
                MEAS     => $config->data_errgv_measure,
                INDEX    => $config->data_errgv_index,
                VALUE    => 0,
                DESCR    => $config->data_errgv_descr,
	},
	ERR_GF => {
                HEXCODE  => $config->data_errgf_hexcode,
                MULTIPLY => $config->data_errgf_multiply,
                MEAS     => $config->data_errgf_measure,
                INDEX    => $config->data_errgf_index,
                VALUE    => 0,
                DESCR    => $config->data_errgf_descr,
	},
	ERR_GZ => {
                HEXCODE  => $config->data_errgz_hexcode,
                MULTIPLY => $config->data_errgz_multiply,
                MEAS     => $config->data_errgz_measure,
                INDEX    => $config->data_errgz_index,
                VALUE    => 0,
                DESCR    => $config->data_errgz_descr,
	},
	ERR_TEMP => {
                HEXCODE  => $config->data_errtemp_hexcode,
                MULTIPLY => $config->data_errtemp_multiply,
                MEAS     => $config->data_errtemp_measure,
                INDEX    => $config->data_errtemp_index,
                VALUE    => 0,
                DESCR    => $config->data_errtemp_descr,
	},
	ERR_PV1 => {
                HEXCODE  => $config->data_errpv1_hexcode,
                MULTIPLY => $config->data_errpv1_multiply,
                MEAS     => $config->data_errpv1_measure,
                INDEX    => $config->data_errpv1_index,
                VALUE    => 0,
                DESCR    => $config->data_errpv1_descr,
	},
	ERR_GFC1 => {
                HEXCODE  => $config->data_errgfc1_hexcode,
                MULTIPLY => $config->data_errgfc1_multiply,
                MEAS     => $config->data_errgfc1_measure,
                INDEX    => $config->data_errgfc1_index,
                VALUE    => 0,
                DESCR    => $config->data_errgfc1_descr,
	},
	ERR_MODE => {
                HEXCODE  => $config->data_errmode_hexcode,
                MULTIPLY => $config->data_errmode_multiply,
                MEAS     => $config->data_errmode_measure,
                INDEX    => $config->data_errmode_index,
                VALUE    => 0,
                DESCR    => $config->data_errmode_descr,
	},
	UNK10  => {
		HEXCODE  => "7f",
		MULTIPLY => 1,
		MEAS     => "",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "Unknown",
	},
      # ---------------- UNKNOWN ----------------------
	UNK11  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "Unknown",
	},
	UNK12  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "Unknown",
	},
	UNK13  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "Unknown",
	},
	UNK14  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "Unknown",
	},
	IDC1  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	IDC2  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	IDC3  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	IAC1  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	VAC1  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "V",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	FAC1  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.01,
		MEAS     => "Hz",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	PDC1  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 1,
		MEAS     => "W",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	IAC2  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	VAC2  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "V",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	FAC2  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.01,
		MEAS     => "Hz",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	PDC2  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 1,
		MEAS     => "W",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	IAC3  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "A",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	VAC3  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.1,
		MEAS     => "V",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	FAC3  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 0.01,
		MEAS     => "Hz",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
	PDC3  => {
		HEXCODE  => "zz",		# unknown
		MULTIPLY => 1,
		MEAS     => "W",
		INDEX    => -1,
		VALUE    => 0,
		DESCR    => "",
	},
# ---------------- UNKNOWN ----------------------
# PVP1   "W",       "PV 1 voltage"
# PVP2   "W",       "PV 2 voltage"
# PVP3   "W",       "PV 3 voltage"
# IAC1   "A",       "PV 1 Grid current"
# IAC2   "A",       "PV 2 Grid current"
# IAC3   "A",       "PV 3 Grid current"
# VAC1   "V",       "PV 1 Grid voltage"
# VAC2   "V",       "PV 2 Grid voltage"
# VAC3   "V",       "PV 3 Grid voltage"
# TEMP1  "deg C",   "External temperature sensor 1"
# TEMP2  "deg C",   "External temperature sensor 2"
# RAD1   "W/m2",    "Irradiance sensor 1"
# RAD2   "W/m2",    "Irradiance sensor 2"
); #end %HoH


#
# inverter version information (hash)
#
%HASH = (
	CAPACITY => "",
	FIRMWARE => "",
	MODEL    => "",
	MANUF    => "",
	SERIAL   => "",
	OTHER    => "",
); #end %HASH

#######################################################################


#######################################################################
#
# Returns 1 (true) if Windows, 0 (false) if not (eg: Linux/Unix/Other)
#
sub isWindows() {
   if ( $^O eq 'cygwin' || $^O =~ /^MSWin/ ) {
      return 1;
   }
   return 0;
} #end isWindows

#######################################################################
#
# Open serial/usb/bluetooth port depending on Operating System
#
sub initialiseSerialPort() {

  print "Initialise Serial Port... ";
  if ( &isWindows() ) {      # Windows (ActivePerl)
    eval "use Win32::SerialPort";
    $port = $ARGV[0] || $config->serial_port_win;

    # Open the serial port
    $serial = Win32::SerialPort->new ($port, 0, '') || die "Can\'t open $port: $!";
  }
  else {				     # Unix/Linux/other
    eval "use Device::SerialPort";
    $port = $ARGV[0] || $config->serial_port_oth;

    # Open the serial port
    $serial = Device::SerialPort->new ($port, 0, '') || die "Can\'t open $port: $!";
  }
  print "port = $port\n";

  #
  # Open the serial port
  #
  $serial->error_msg(1); 		# use built-in hardware error messages like "Framing Error"
  $serial->user_msg(1);			# use built-in function messages like "Waiting for ..."
  $serial->baudrate($config->serial_baud) || die 'fail setting baudrate, try -b option';
  $serial->parity($config->serial_parity) || die 'fail setting parity';
  $serial->databits($config->serial_databits) || die 'fail setting databits';
  $serial->stopbits($config->serial_stopbits) || die 'fail setting stopbits';
  $serial->handshake($config->serial_handshake) || die 'fail setting handshake';
  $serial->datatype($config->serial_datatype) || die 'fail setting datatype';
  $serial->write_settings || die 'could not write settings';
  $serial->read_char_time(0);     	# don't wait for each character
  $serial->read_const_time(1000); 	# 1 second per unfulfilled "read" call
} #end initialiseSerialPort

#######################################################################
#
# Close serial/usb/bluetooth port
#
sub closeSerialPort() {
    $serial->close || warn "*** WARNING Close port failed, connection may have died.\n";
    undef $serial;
} #end closeSerialPort

#######################################################################
#
# Trim function to remove whitespace from start and end of a string
#
sub trim($) {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
} #end trim

#######################################################################
#
# Turn raw data from the inverter into a hex string
#
sub convRawToHex() {
  my $pstring = shift;
  my $hstring = unpack ("H*",$pstring);
  return $hstring;
} #end convRawToHex

#######################################################################
#
# Turn hex string into raw data for transmission to the inverter
#
sub convHexToRaw() {
  my $hstring = shift;
  my $pstring = pack (qq{H*},qq{$hstring});
  return $pstring;
} #end convHexToRaw

#######################################################################
#
# Return Date & Time in format: "DD/MM/YYYY HH:MM:SS"
#
sub getDateTime() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  return sprintf("%02d/%02d/%04d %02d:%02d:%02d", $dayOfMth, $monthOffset+1, $yearOffset+1900, $hour, $min, $sec);
} #end getDateTime

#######################################################################
#
# Return Date in format: "YYYYMMDD"
#
sub getDate_YYYYMMDD() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  return sprintf("%04d%02d%02d", $yearOffset+1900, $monthOffset+1, $dayOfMth);
} #end getDate_YYYYMMDD

#######################################################################
#
# Return Date in format: "YYYYMM"
#
sub getDate_YYYYMM() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  return sprintf("%04d%02d", $yearOffset+1900, $monthOffset+1);
} #end getDate_YYYYMM

#######################################################################
#
# Return Time in format: "HH:MM"
#
sub getTime_HHMM() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  return sprintf("%02d:%02d", $hour, $min);
} #end getTime_HHMM

#######################################################################
#
# Return Time in format: "HH:MM:SS"
#
sub getTime_HHMMSS() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  return sprintf("%02d:%02d:%02d", $hour, $min, $sec);
} #end getTime_HHMMSS

#######################################################################
#
# Set lastPollTime & nextPollTime
#
sub setPollTimes() {
  $lastPollTime = time;
  $nextPollTime = $lastPollTime + $config->secs_datapoll_freq;
} #end setPollTimes

#######################################################################
#
# Set lastPvoutputTime & nextPvoutputTime
#
sub setPvoutputTimes() {
  $lastPvoutputTime = time;
  $nextPvoutputTime = $lastPvoutputTime + $config->secs_pvoutput_freq;
} #end setPvoutputTimes

#######################################################################
#
# Sleep until nextPollTime 
#
sub sleepTilNextPoll() {
  my $seconds = $nextPollTime - time;
  if ( $seconds > 0 ) {
    print "Sleeping: $seconds secs as at " . &getDateTime() . " ...\n";
    sleep $seconds;
  }
} #end sleepTilNextPoll

#######################################################################
#
# Return 1 (true) if time now is within the valid (config) polling times, 0 (false) if not.
#
sub isValidPollTime() {
  local($sec,$min,$hour,$dayOfMth,$monthOffset,$yearOffset,$dayOfWk,$dayOfYr,$isDST) = localtime;
  my $strNow = sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $yearOffset+1900, $monthOffset+1, $dayOfMth, $hour, $min, $sec );
  my $strStart = sprintf( "%04d-%02d-%02d %s", $yearOffset+1900, $monthOffset+1, $dayOfMth, $config->time_start_poll );
  my $strEnd = sprintf( "%04d-%02d-%02d %s", $yearOffset+1900, $monthOffset+1, $dayOfMth, $config->time_end_poll );
  if ( $strStart le $strNow && $strNow le $strEnd ) {
    return 1;
  }
  return 0;
} #end isValidPollTime

#######################################################################
#
# Return 1 (true) if time for next pvoutput upload, 0 (false) if not.
#
sub isNextPvoutputDue() {
  if ( $lastPvoutputTime == 0 || $nextPvoutputTime <= time ) {
    return 1;
  }
  return 0;
} #end isNextPvoutputDue

#######################################################################
#
# Return LogFile Name: [path]/inverter_[serial#]_[yyyymmdd].csv
#
sub getLogFileName() {
  #
  # set path
  #
  my $logfile = $config->paths_other;                 # Unix/Linux/other
  if ( &isWindows() ) {                               # Windows
    $logfile = $config->paths_windows;
  }

  #
  # append filename
  #
  $logfile .= "/inverter_" . $HASH{SERIAL} . "_" . &getDate_YYYYMMDD() . ".csv";
  return $logfile;
} #end getLogFileName

#######################################################################
#
# Return ErrFile Name: [path]/inverter_err_[serial#]_[yyyymm].log
#
sub getErrFileName() {
  #
  # set path
  #
  my $errfile = $config->paths_other;                 # Unix/Linux/other
  if ( &isWindows() ) {                               # Windows
    $errfile = $config->paths_windows;
  }

  #
  # append filename
  #
  $errfile .= "/inverter_err_" . $HASH{SERIAL} . "_" . &getDate_YYYYMM() . ".log";
  return $errfile;
} #end getErrFileName

#######################################################################
#
# Return RRD File Name: [path]/inverter_[serial#].rrd
#
sub getRrdFileName() {
  #
  # set path
  #
  my $rrdfile = $config->paths_other;                 # Unix/Linux/other
  if ( &isWindows() ) {                               # Windows
     $rrdfile = $config->paths_windows;
  }

  #
  # append filename
  #
  $rrdfile .= "/inverter_" . $HASH{SERIAL} . ".rrd";
  return $rrdfile;
} #end getRrdFileName

#######################################################################
#
# Write to the port (the inverter is on) & warn if it fails
#
sub writeToPort() {
  my $writeStr = shift;
  my $countOut = $serial->write($writeStr);
  warn "*** write failed ( $countOut ) ***\n" unless ($countOut);
  warn "*** write incomplete ( $countOut ) ***\n" if ( $countOut != length($writeStr) );
  return $countOut;
} #end writeToPort

#######################################################################
#
# Write to serial port then read result from buffer
# until expected read response received or timeout exceeded
#
sub writeReadBuffer() {
  my $writeString = shift;
  my $readPattern = shift;
  my $chars=0;
  my $buffer="";
  my $buffer2="x";
  my $timeout = $config->secs_timeout;

  #
  # Check if within the valid (config) polling times, exit if not
  #
  if ( ! &isValidPollTime() ) {
    &closeSerialPort();
    die "Exiting, as " . &getTime_HHMMSS() . " is outside valid poll times: " . $config->time_start_poll . " to " . $config->time_end_poll . "\n";
  }

  if ($config->flags_debug) {
    print "writeReadBuffer: writeString=$writeString\n";
    print "writeReadBuffer: readPattern=$readPattern\n";
  }

  #
  # Write to (Serial) Port
  #
  &writeToPort(&convHexToRaw($writeString));

  # sleep for dodgy cables (eg beginner soldering or usb converters)
  # sleep 2;

  #
  # Read response from buffer until either expected response received or timeout reached
  #
  while ( $timeout > 0 ) {

    my ($countIn,$stringIn) = $serial->read(255); 		# will read _up to_ 255 chars
    if ($countIn > 0) {

      if ($config->flags_debug) {
        print "writeReadBuffer: saw..." . &convRawToHex($stringIn) . "\n";
      }

      $chars += $countIn;
      $buffer .= $stringIn;
      $hexBuffer = &convRawToHex($buffer);

      #
      # Check to see if expected read response is in the $buffer
      #
      if ( $hexBuffer =~ /$readPattern/ ) {
        ($buffer2) = ( $hexBuffer =~ /($readPattern.*$)/ );
        if ($config->flags_debug) {
          print "writeReadBuffer: found=$buffer2\n";
        }
        print "Recv <- $buffer2 \n";
        return $buffer2;
      }

    }
    else {
      $timeout--;
    }

  }	# end of while loop

  #
  # timeout was reached
  #
  $noTalks++;
  print "Waited " . $config->secs_timeout . " seconds and never saw $readPattern\n";
  print "noTalks=$noTalks, reInits=$reInits.\n";
  
  #
  # Reset number of noTalks & attempt ReInit
  #
  if ( $noTalks > 0 ) {
    &setPollTimes();
    &closeSerialPort();
    #
    # check if reinitialise port timeout was reached, if so die
    #
    if ($config->secs_reinit >= 0 && $reInits > $config->secs_reinit) {
      die "REINIT MAX exceeded, aborted.\n";
    }

    #
    # Sleep until next time data needs to be polled (per $config->secs_datapoll_freq)
    #
    &sleepTilNextPoll();

    #
    # Attempt to Re-initialise
    #
    $noTalks = 0;
    $reInits++;
    print "Re-Init attempt $reInits...\n";
    &main();
  }
  
  return "";
} #end writeReadBuffer

#######################################################################
#
# Prepare the REQUEST_CONF_SERIAL packet
# grab serial# from input data, use it to create the response packet, incl checksum in format:
# sendhex_conf_serial1 + $hexSerial + sendhex_conf_serial2 + $hexReqChkSum
#
sub calcReqConfSerial() {
  my $hexStr = shift;
  my $hexSerial = substr($hexStr, $config->hex_confserial_index, $config->hex_serial_length);
  $HASH{SERIAL} = pack ("H*", $hexSerial);
  my $hexReqRegex = $config->sendhex_conf_serial1 . $hexSerial . $config->sendhex_conf_serial2;

  if ($config->flags_debug) {
    print "hexSerial=$hexSerial\n";          # decimal string
    print "SERIAL=$HASH{SERIAL}\n";          # hexadecimal string, for pvoutput.org
  }

  #
  # calculate hex checksum for the request
  #
  my $rawReq = &convHexToRaw( $hexReqRegex );
  my $rawReqChkSum = unpack ( "%C*", $rawReq );
  my $hexReqChkSum = sprintf ( "%04x ", $rawReqChkSum );

  #
  # join it all together to create the request
  #
  my $reqConfSerial = $hexReqRegex . $hexReqChkSum;
  return($reqConfSerial);
} #end calcReqConfSerial

#######################################################################
#
# Initialise Inverter - handshake is done here
#
sub initialiseInverter() {
  #
  # step 1: Start initial handshake with inverter (reset network)
  #
  my $rawRequest = &convHexToRaw($config->sendhex_initialise);
  print "Send -> req init inverter: " . $config->sendhex_initialise . "\n";
  &writeToPort($rawRequest);

  #
  # step 2: request the serial number (query network)
  #
  print "Send -> req serial: " . $config->sendhex_serial . "\n";
  my $hexResponse = &writeReadBuffer($config->sendhex_serial,$config->recvhex_serial);

  #
  # step 3: confirm the serial number
  #
  if ( $hexResponse ne "" ) {
    my $confSerialRequest = &calcReqConfSerial($hexResponse);
    print "Send -> confirm serial: $confSerialRequest \n";
    my $hexResponse2 = &writeReadBuffer($confSerialRequest,$config->recvhex_conf_serial);
  }
} #end initialiseInverter

#######################################################################
#
# Parse Version/Firmware Data - store in %HASH
#
sub parseVersData() {
  print "* Version info:\n";
  my $hexData = shift;
  my $asciiVers = ( pack ("H*", $hexData) );
  my $hexLength = length($hexData);
  print "asciiVers=$asciiVers\n";

  #
  # convert portions of hex to ascii
  #
  if ( $config->hex_capacity_length > 0 && $config->hex_capacity_index + $config->hex_capacity_length < $hexLength ) {
    $HASH{CAPACITY} = &trim( pack ("H*", substr($hexData, $config->hex_capacity_index, $config->hex_capacity_length)) );
  }
  if ( $config->hex_firmware_length > 0 && $config->hex_firmware_index + $config->hex_firmware_length < $hexLength ) {
    $HASH{FIRMWARE} = &trim( pack ("H*", substr($hexData, $config->hex_firmware_index, $config->hex_firmware_length)) );
  }
  if ( $config->hex_model_length > 0 && $config->hex_model_index + $config->hex_model_length < $hexLength ) {
    $HASH{MODEL} = &trim( pack ("H*", substr($hexData, $config->hex_model_index, $config->hex_model_length)) );
  }
  if ( $config->hex_manuf_length > 0 && $config->hex_manuf_index + $config->hex_manuf_length < $hexLength ) {
    $HASH{MANUF} = &trim( pack ("H*", substr($hexData, $config->hex_manuf_index, $config->hex_manuf_length)) );
  }
  if ( $config->hex_serial_index > 0 && $config->hex_serial_index + $config->hex_serial_length < $hexLength ) {
    $HASH{SERIAL} = &trim( pack ("H*", substr($hexData, $config->hex_serial_index, $config->hex_serial_length)) );
  }
  if ( $config->hex_other_length > 0 && $config->hex_other_index + $config->hex_other_length < $hexLength ) {
    $HASH{OTHER} = &trim( pack ("H*", substr($hexData, $config->hex_other_index, $config->hex_other_length)) );
  }

  #
  # display version information (in sorted order)
  #
  for $key ( sort( keys ( %HASH ) ) ) {
     printf "%-8s : %s\n", $key, $HASH{$key};
  }
} #end parseVersData

#######################################################################
#
# Parse Parameter Format
# based on $HoHparams{HEXCODE} & store index/position in $HoHparams{INDEX}
#
sub parseParamFmt() {
  print "* Parameter Format:\n";
  my $hexData = shift;
  if ($hexData eq "") {
    print "n/a\n";
    return;
  }

  # split hex string into an array of 2char hex strings
  @d = ( $hexData =~ m/..?/g );

  my $dataOffset = $config->hex_data_to_follow_index + 1;
  my $dataToFollow = hex($d[$config->hex_data_to_follow_index]);
  print "dataToFollow = hex($d[$config->hex_data_to_follow_index]) = $dataToFollow\n";

  my $i = 0;
  for $x ($dataOffset .. $dataOffset + $dataToFollow - 1) {
    printf "%2s = %2s", $x, $d[$x] ;
    for $key ( keys ( %HoHparams ) ) {
      if ( $HoHparams{$key}{HEXCODE} eq $d[$x]) {
        $HoHparams{$key}{INDEX} = $i;
        printf " = %-10s = %2s = %s", $key, $HoHparams{$key}{INDEX}, $HoHparams{$key}{DESCR} ;
      }
    }
    print "\n";
    $i++;
  }
} #end parseParamFmt

#######################################################################
#
# Parse Parameters
# based on $HoHparams{INDEX} & store value in $HoHparams{VALUE}
#
sub parseParam() {
  print "* Parameters:\n";
  my $hexData = shift;
  my $dataToFollow = hex( substr( $hexData, $config->hex_data_to_follow_index*2, 2 ) );
  my $startIndex = ( $config->hex_data_to_follow_index + 1 )*2;
  my $numOfChars = $dataToFollow * 2;
  my $data = substr( $hexData, $startIndex, $numOfChars );

  # split hex string into an array of 4char hex strings
  @d = ( $data =~ m/..?.?.?/g );

  # display data values - sort %HoH by INDEX
  for $key ( sort {$HoHparams{$a}{INDEX} <=> $HoHparams{$b}{INDEX} } keys ( %HoHparams ) ) {
       if ( $HoHparams{$key}{INDEX} ne "-1" ) {
         $HoHparams{$key}{VALUE} = hex( $d[$HoHparams{$key}{INDEX}] ) * $HoHparams{$key}{MULTIPLY};
         printf "%-10s: %8s %-5s = %s \n", $key, $HoHparams{$key}{VALUE}, $HoHparams{$key}{MEAS}, $HoHparams{$key}{DESCR} ;
       }
  }
} #end parseParam

#######################################################################
#
# Set Data Format Manually - if not sure of REQUEST_DATAFMT response break-up yet
# eg: CMS 10000
#
sub setDataFmt2() {
  print "* Data Format2:\n";
  $HoH{TEMP}{INDEX} = 0;
  $HoH{VPV}{INDEX} = 1;
  $HoH{VPV2}{INDEX} = 2;
  $HoH{VPV3}{INDEX} = 3;
  $HoH{IDC1}{INDEX} = 4;
  $HoH{IDC2}{INDEX} = 5;
  $HoH{IDC3}{INDEX} = 6;
  $HoH{ETOTALH}{INDEX} = 7;
  $HoH{ETOTALL}{INDEX} = 8;
  $HoH{HTOTALH}{INDEX} = 9;
  $HoH{HTOTALL}{INDEX} = 10;
  $HoH{PAC}{INDEX} = 11;
  $HoH{MODE}{INDEX} = 12;
  $HoH{ETODAY}{INDEX} = 13;
  $HoH{ERR_GV}{INDEX} = 14;
  $HoH{ERR_GF}{INDEX} = 15;
  $HoH{ERR_GZ}{INDEX} = 16;
  $HoH{ERR_TEMP}{INDEX} = 17;
  $HoH{ERR_PV1}{INDEX} = 18;
  $HoH{ERR_GFC1}{INDEX} = 19;
  $HoH{ERR_MODE}{INDEX} = 20;
  $HoH{IAC1}{INDEX} = 21;
  $HoH{VAC1}{INDEX} = 22;
  $HoH{FAC1}{INDEX} = 23;
  $HoH{PDC1}{INDEX} = 24;
  $HoH{UNK10}{INDEX} = 25;
  $HoH{UNK11}{INDEX} = 26;
  $HoH{UNK12}{INDEX} = 27;
  $HoH{UNK13}{INDEX} = 28;
  $HoH{IAC2}{INDEX} = 29;
  $HoH{VAC2}{INDEX} = 30;
  $HoH{FAC2}{INDEX} = 31;
  $HoH{PDC2}{INDEX} = 32;
  $HoH{UNK14}{INDEX} = 33;

  #
  # display data format indexes - sort %HoH by INDEX
  #
  for $key ( sort {$HoH{$a}{INDEX} <=> $HoH{$b}{INDEX} } keys ( %HoH ) ) {
    if ( $HoH{$key}{INDEX} ne "-1" ) {
      printf "%-8s = %2s = %s\n", $key, $HoH{$key}{INDEX}, $HoH{$key}{DESCR} ;
    }
  }
} #end setDataFmt2

#######################################################################
#
# Parse Data Format
# based on $HoH{HEXCODE} & store index/position in $HoH{INDEX}
#
sub parseDataFmt() {
  print "* Data Format:\n";
  my $hexData = shift;
  if ($hexData eq "") {
    print "n/a\n";
    return;
  }

  # split hex string into an array of 2char hex strings
  @d = ( $hexData =~ m/..?/g );

  my $dataOffset = $config->hex_data_to_follow_index + 1;
  my $dataToFollow = hex($d[$config->hex_data_to_follow_index]);
  print "dataToFollow = hex($d[$config->hex_data_to_follow_index]) = $dataToFollow\n";

  if ($HASH{MODEL} eq "CMS 10000") {
    &setDataFmt2();	# temp: until get hold of CMS 10000 protocol & figure out hexcodes & keys
    return;
  }

  my $i = 0;
  for $x ($dataOffset .. $dataOffset + $dataToFollow - 1) {
    printf "%2s = %2s", $x, $d[$x] ;
    for $key ( keys ( %HoH ) ) {
      if ( $HoH{$key}{HEXCODE} eq $d[$x]) {
        $HoH{$key}{INDEX} = $i;
        printf " = %-8s = %2s = %s", $key, $HoH{$key}{INDEX}, $HoH{$key}{DESCR} ;
      }
    }
    print "\n";
    $i++;
  }
} #end parseDataFmt

#######################################################################
#
# Parse Data
# based on $HoH{INDEX} & store value in $HoH{VALUE}
#
sub parseData() {
  print "* Data:\n";
  my $hexData = shift;
  my $dataToFollow = hex( substr( $hexData, $config->hex_data_to_follow_index*2, 2 ) );
  my $startIndex = ( $config->hex_data_to_follow_index + 1 )*2;
  my $numOfChars = $dataToFollow * 2;
  my $data = substr( $hexData, $startIndex, $numOfChars );
  my $lastEtoday = $HoH{ETODAY}{VALUE};
  my $lastEtotal = ($HoH{ETOTALL}{VALUE} + $HoH{ETOTALH}{VALUE});
  my $lastHtotal = ($HoH{HTOTALL}{VALUE} + $HoH{HTOTALH}{VALUE});
  
  # split hex string into an array of 4char hex strings
  @d = ( $data =~ m/..?.?.?/g );

  # display data values - sort %HoH by INDEX
  for $key ( sort {$HoH{$a}{INDEX} <=> $HoH{$b}{INDEX} } keys ( %HoH ) ) {
       if ( $HoH{$key}{INDEX} ne "-1" ) {
         $HoH{$key}{VALUE} = hex( $d[$HoH{$key}{INDEX}] ) * $HoH{$key}{MULTIPLY};
         printf "%-8s: %8s %-5s = %s \n", $key, $HoH{$key}{VALUE}, $HoH{$key}{MEAS}, $HoH{$key}{DESCR} ;
       }
  }

  my $etotal = ($HoH{ETOTALL}{VALUE} + $HoH{ETOTALH}{VALUE});
  my $htotal = ($HoH{HTOTALL}{VALUE} + $HoH{HTOTALH}{VALUE});
  #
  # Sometimes CMS2000 inverter keeps yesterdays ETODAY for first 30mins or more each morning
  # hence some logic to use ZERO if hour < 9am and ETODAY > 1.0 kWh
  #
  if ($HASH{MODEL} eq "CMS 2000") {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
    if ($hour < 9 && $HoH{ETODAY}{VALUE} > 1.0) {

      #
      # open errfile in 'append' mode
      #
      my $errfile = &getErrFileName();
      if ( open(ERRFILE, ">>$errfile") ) {
        my $errLine = &getDateTime() . " - ETODAY=$HoH{ETODAY}{VALUE}, will use 0 instead, as not reset since yesterday. letod=$lastEtoday, letot=$lastEtotal, lhtot=$lastHtotal, etot=$etotal, htot=$htotal.";
        print "ERROR logged to: $errfile\n";
        print ERRFILE "$errLine\n";
        close (ERRFILE);
      }
      $HoH{ETODAY}{VALUE} = 0;
    }
  }
} #end parseData

#######################################################################
#
# Write certain inverter data to a csv file
#
sub writeToFile() {
  my $logfile = getLogFileName();
  my $rrdfile = getRrdFileName();

  #
  # open logfile in 'append' mode
  #
  if ( open(LOGFILE, ">>$logfile") ) {
    print "Logging to: $logfile\n";

    #
    # add file header to logfile (if file exists & is empty)
    #
    if ( -z $logfile ) {
#      print LOGFILE "DATE,TIMESTAMP,TEMP,VPV,IAC,VAC,FAC,PAC,ETOTAL,HTOTAL,MODE,ETODAY\n";
      print LOGFILE "DATE,TIMESTAMP,TEMP,VPV,IAC,VAC,FAC,PAC,ETOTAL,HTOTAL,MODE,ETODAY" .
                    ",ETOTALH,HTOTALH,ERR_GV,ERR_GF,ERR_GZ,ERR_TEMP,ERR_PV1,ERR_GFC1,ERR_MODE,UNK10\n";
    }

    my $etotal = ($HoH{ETOTALL}{VALUE} + $HoH{ETOTALH}{VALUE});
    my $htotal = ($HoH{HTOTALL}{VALUE} + $HoH{HTOTALH}{VALUE});
    if ($config->flags_debug) {
      print "etotal=$etotal   htotal=$htotal\n";
    }

    #
    # write data to logfile & close it
    #
    my $unixTimeStamp = time;                           # secs since epoch
    my $dateTimeStr = &getDateTime($unixTimeStamp);
    my $csvLine = "$dateTimeStr,"         .
                  "$unixTimeStamp,"       .
                  "$HoH{TEMP}{VALUE},"    .
                  "$HoH{VPV}{VALUE},"     .
                  "$HoH{IAC}{VALUE},"     .
                  "$HoH{VAC}{VALUE},"     .
                  "$HoH{FAC}{VALUE},"     .
                  "$HoH{PAC}{VALUE},"     .
                  "$etotal,"              .
                  "$htotal,"              .
                  "$HoH{MODE}{VALUE},"    .
                  "$HoH{ETODAY}{VALUE},"  .
                  "$HoH{ETOTALH}{VALUE},"  .
                  "$HoH{HTOTALH}{VALUE},"  .
                  "$HoH{ERR_GV}{VALUE},"   .
                  "$HoH{ERR_GF}{VALUE},"   .
                  "$HoH{ERR_GZ}{VALUE},"   .
                  "$HoH{ERR_TEMP}{VALUE}," .
                  "$HoH{ERR_PV1}{VALUE},"  .
                  "$HoH{ERR_GFC1}{VALUE}," .
                  "$HoH{ERR_MODE}{VALUE}," .
                  "$HoH{UNK10}{VALUE}";
    print LOGFILE "$csvLine\n";
    close (LOGFILE);

    #
    # write data to rrdtool for graphing
    #
    if ($config->flags_use_rrdtool) {

      my $rrdexe  = $config->scripts_rrdtool_exe_oth;     # Unix/Linux/other
      if ( &isWindows() ) {                               # Windows
         $rrdexe  = $config->scripts_rrdtool_exe_win;
      }

      #
      # create rrd file - if it doesn't exist
      #
      if ( ! -e $rrdfile ) {
        print "Ran: " . $config->scripts_create_rrd . " \"$rrdfile\" \"$rrdexe\"\n";
        system ($config->scripts_create_rrd . " \"$rrdfile\" \"$rrdexe\"" );
      }

      #
      # update rrd file
      #
      my $rrdLine = "$unixTimeStamp:"       .
                    "$HoH{TEMP}{VALUE}:"    .
                    "$HoH{VPV}{VALUE}:"     .
                    "$HoH{IAC}{VALUE}:"     .
                    "$HoH{VAC}{VALUE}:"     .
                    "$HoH{FAC}{VALUE}:"     .
                    "$HoH{PAC}{VALUE}:"     .
                    "$etotal:"              .
                    "$htotal:"              .
                    "$HoH{MODE}{VALUE}:"    .
                    "$HoH{ETODAY}{VALUE}";
      print "Ran: $rrdexe update $rrdfile $rrdLine\n";
      system( "$rrdexe update $rrdfile $rrdLine" );
    }

  }
  else {
    warn "*** WARNING Could not open logfile: $logfile\n";
  }
} #end writeToFile

#######################################################################
#
# MAIN METHOD
#
sub main() {
   print "Starting up at " . &getDateTime() . " running on $^O ...\n";

   #
   # Check if within the valid (config) polling times, exit if not
   #
   if ( ! &isValidPollTime() ) {
     die "Exiting, as " . &getTime_HHMMSS() . " is outside valid poll times: " . $config->time_start_poll . " to " . $config->time_end_poll . "\n";
   }
   
   #
   # Initialise Poll & Pvoutput times
   #
   &setPollTimes();
   &setPvoutputTimes();

   #
   # Initialise Serial Port & Inverter
   #
   &initialiseSerialPort();
   &initialiseInverter();

   #
   # Request Inverter Version Information
   #
   print "Send -> req version: " . $config->sendhex_version . "\n";
   $hexResponse = &writeReadBuffer($config->sendhex_version,$config->recvhex_version);
   &parseVersData($hexResponse) if ($hexResponse ne "");

   #
   # Request Inverter Parameter Format Information
   #
   if ( $config->sendhex_paramfmt ne " " ) {
     print "Send -> req param format: " . $config->sendhex_paramfmt . "\n";
     $hexResponse = &writeReadBuffer($config->sendhex_paramfmt,$config->recvhex_paramfmt);
     &parseParamFmt($hexResponse) if ($hexResponse ne "");
   }

   #
   # Request Inverter Parameter Information
   #
   print "Send -> req params: " . $config->sendhex_param . "\n";
   $hexResponse = &writeReadBuffer($config->sendhex_param,$config->recvhex_param);
   &parseParam($hexResponse) if ($hexResponse ne "");

   #
   # Request Inverter Data Format Information
   #
   if ( $config->sendhex_datafmt ne " " ) {
     print "Send -> req data format: " . $config->sendhex_datafmt . "\n";
     $hexResponse = &writeReadBuffer($config->sendhex_datafmt,$config->recvhex_datafmt);
     &parseDataFmt($hexResponse) if ($hexResponse ne "");
   }

   #
   # The main loop starts here
   #
   while (1) {

     #
     # Request Inverter Data (regular data poll)
     #
     print "Send -> req data as at " . &getDateTime() . " : " . $config->sendhex_data . "\n";
     &setPollTimes();
     $hexResponse = &writeReadBuffer($config->sendhex_data,$config->recvhex_data);
     &parseData($hexResponse) if ($hexResponse ne "");
     &writeToFile();

     #
     # Export data to http://pvoutput.org
     #
     if ($config->flags_use_pvoutput) {
       if ( &isNextPvoutputDue() ) {
         my $date = &getDate_YYYYMMDD();
         my $time = &getTime_HHMM();
         print "PVOUTPUT as at " . &getDateTime() . " ...\n";
         print "  ran: " . $config->scripts_pvoutput . " " . ($HoH{ETODAY}{VALUE} * 1000) . " $HoH{PAC}{VALUE} $date $time $HASH{SERIAL} $HoH{VPV1}{VALUE} $HoH{TEMP}{VALUE}\n";
         system ($config->scripts_pvoutput . " " . ($HoH{ETODAY}{VALUE} * 1000) . " $HoH{PAC}{VALUE} $date $time $HASH{SERIAL} $HoH{VPV1}{VALUE} $HoH{TEMP}{VALUE}" );
         &setPvoutputTimes();
       }
     }

     #
     # Sleep until next time data needs to be polled (per $config->secs_datapoll_freq)
     #
     &sleepTilNextPoll();

   } #end while
} #end main

#######################################################################

&main();

