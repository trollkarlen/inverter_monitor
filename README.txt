---------------------------------------------------------
  Inverter Monitor Installation - as at 08Mar2012
---------------------------------------------------------

1) Download files from solarfreaks & put them in a folder 
   such as c:/solar/scripts (Windows) or /tmp/solar/scripts (Unix/Linux)
   * config.ini 	    	- copy configs/config_*.ini for your inverter to config.ini
   * create_rrd.pl  		- if use_rrdtool  in config.ini is set to 1
   * inverter.pl
   * MonitorInverter.bat	- Windows only
   * pvoutput.pl	    	- if use_pvoutput in config.ini is set to 1
   * README.txt
   * VersionInfo.txt

2) Download and Install Perl 
   eg: ActivePerl via http://www.activestate.com/activeperl/downloads 
   * Windows users: make sure the version you download contains Win32::SerialPort 
     http://code.activestate.com/ppm/Win32-SerialPort/
   * Other users:   make sure the version you download contains Device::SerialPort 
     http://code.activestate.com/ppm/Device-SerialPort/

3) Install Required Perl Modules
   You may also need to install these, see 'Required Perl Modules' below:
   a) AppConfig
   b) Win32::SerialPort  (Windows)
   c) Device::SerialPort (Unix/Linux/Other) 
   eg:  http://docs.activestate.com/activeperl/5.12/faq/ActivePerl-faq2.html

4) Download and Install rrdtool if 'use_rrdtool' is set to 1:
   http://oss.oetiker.ch/rrdtool/download.en.html

5) Setup your pvoutput settings per http://pvoutput.org/help.html#api

6) Open pvoutput.pl in notepad and enter your details for SERIAL_NUM, API_KEY & SYSTEM_ID 
   per your pvoutput settings in step 3.

7) Open the configuration settings file (config.ini) and edit it *IF REQUIRED*
   but be careful to leave it in the SAME format.

8) Run the script, eg for Windows:
   * Double click MonitorInverter.bat to run it   
   or  
   * Start > Run > cmd > cd c:/solar/scripts > perl inverter.pl "COM1"

9) Set up a Windows Scheduled Task (or a Linux/Unix Cronjob), eg:
   * For Linux 
      crontab -e
      Add row: */5 3-22 * * * pgrep -f "\./inverter.pl" > /dev/null || ( cd /tmp/solar/solar && ./inverter.pl >> inverter.pl.cronout 2>&1 )

   * For Windows
   * Start (or My Computer) -> Control Panel -> Scheduled Tasks -> Add Scheduled Task ... etc 
   or
   * Start -> All Programs -> Administrative Tools -> Task Scheduler -> Action -> New Task -> 
       General (tab) -> 
          Name: SolarInverterMonitor
          Description: Attempt to fire up the solar inverter monitor.
          Select 'Run whether user is logged on or not' and 'Do not store password.'
          Select 'Run with highest privileges.'
       Triggers (tab) -> New -> 
          Begin the task: 'On a schedule'
          Settings: 'Daily' '5:00:00 AM'. Recur every: 1 days.
          Repeat task every: '5 minutes' for a duration of: '1 day' (or 'Indefinitely')
          'Enabled'
          -> OK.
       Actions (tab) -> New -> 
          Action: 'Start a program' 
          Program/script: InverterMonitor.bat
          Start in: C:\solar\scripts
          -> OK.
       Conditions (tab) -> 
          choose your own options.
       Settings (tab) -> 
          'Allow task to be run on demand'
	  'Stop the task if it runs longer than: '3 days'
          If the task is already running, then the following rule applies: 'Do not start a new instance'
          -> OK

   NOTE: If you need to kill the process manually: open Task Manager > Processes > Tick 'Show Processes from all users' > right click 'perl.exe' > select 'End Process'.

   Links:
   * http://www.iopus.com/guides/winscheduler.htm
   * http://lifehacker.com/153089/hack-attack-using-windows-scheduled-tasks
   * http://windows.microsoft.com/en-US/windows-vista/Schedule-a-task


---------------------------------------------------------
  Output Filenames
---------------------------------------------------------

* inverter_[serial#]_YYYYMMDD.csv
* inverter_err_[serial#]_YYYYMM.csv
* inverter_[serial#].rrd


---------------------------------------------------------
  Basic Perl Commands - on the Command Line
---------------------------------------------------------

You can run perl commands in a 'command/dos' window, eg: Start > Run > cmd (Windows)
* Get Perl version:	perl -v
* Check file's syntax:	perl -wc perltest.pl
* Run a script:		perl perltest.pl


---------------------------------------------------------
  Required Perl Modules
---------------------------------------------------------

Windows:
  * install any missing modules if required
    - using ActivePerl Package Manager: 
        Start > All Programs > ActivePerl > Perl Package Manager > View > All Packages > 
        right click 'AppConfig' > Install
        right click 'Win32-SerialPort' > Install
        File > Run Marked Actions > OK
        File > Exit
    OR
    - manually:
      * check if modules already installed:
          perl -MAppconfig -e "print 'OK'"
          perl -MWin32::SerialPort -e "print 'OK'"
      * install them if not already:
          ppm.bat install AppConfig
          ppm.bat install Win32-SerialPort

Unix/Linux/Other:
  * install any missing modules if required
    - using ActivePerl Package Manager: 
        Type 'ppm' on the command line to launch it's GUI eg:
        http://docs.activestate.com/activeperl/5.12/faq/ActivePerl-faq2.html#ppm_gui
    OR
    - manually:
        sudo apt-get install libappconfig-perl
        sudo apt-get install libdevice-serialport-perl


---------------------------------------------------------
  Sample Output
---------------------------------------------------------

The hex serial number in this output has been replaced with "00112233445566778899"
and the serial number has been replaced with "0123456789". :)

C:\Windows\system32>cd c:\solar\scripts

c:\solar\scripts>perl inverter.pl "COM1"
Starting up at 21/05/2011 09:57:19 running on MSWin32 ...
Initialise Serial Port... port = COM1
Send -> req init inverter: aaaa010000000004000159
Send -> req serial: aaaa010000000000000155
Recv <- aaaa0000010000800a001122334455667788990409
Send -> confirm serial: aaaa0100000000010b001122334455667788993301038c
Recv <- aaaa000101000081010601de
Send -> req version: aaaa01000001010300015a
Recv <- aaaa000101000183403120203230303041412e303020202020434d532032303030202020
2050484f454e495854454320202020202000112233445566778899000000000000333630300dcc
* Version info:
asciiVers=¬¬ ?? ?â@1  2000AA.00    CMS 2000    PHOENIXTEC      0123456789      3
¦00
CAPACITY : 2000
FIRMWARE : AA.00
MANUF    : PHOENIXTEC
MODEL    : CMS 2000
OTHER    : 3600
SERIAL   : 0123456789
Send -> req param format: aaaa010000010101000158
Recv <- aaaa000101000181064041444546470375
* Parameter Format:
dataToFollow = hex(06) = 6
 9 = 40 = VPV-START  =  0 = PV Start-up voltage
10 = 41 = T-START    =  1 = Time to connect grid
11 = 44 = VAC-MIN    =  2 = Minimum operational grid voltage
12 = 45 = VAC-MAX    =  3 = Maximum operational grid voltage
13 = 46 = FAC-MIN    =  4 = Minimum operational frequency
14 = 47 = FAC-MAX    =  5 = Maximum operational frequency
Send -> req params: aaaa01000001010400015b
Recv <- aaaa0001010001840c05dc003c080c0a5012c014b4050c
* Parameters:
VPV-START :      150 V     = PV Start-up voltage
T-START   :       60 Sec   = Time to connect grid
VAC-MIN   :      206 V     = Minimum operational grid voltage
VAC-MAX   :      264 V     = Maximum operational grid voltage
FAC-MIN   :       48 Hz    = Minimum operational frequency
FAC-MAX   :       53 Hz    = Maximum operational frequency
Send -> req data format: aaaa010000010100000157
Recv <- aaaa00010100018015000d4041424344454748494a4c78797a7b7c7d7e7f08d2
* Data Format:
dataToFollow = hex(15) = 21
 9 = 00 = TEMP     =  0 = Internal Temperature
10 = 0d = ETODAY   =  1 = Accumulated Energy Today
11 = 40 = VPV      =  2 = Panel Voltage
12 = 41 = IAC      =  3 = Grid Current
13 = 42 = VAC      =  4 = Grid Voltage
14 = 43 = FAC      =  5 = Grid Frequency
15 = 44 = PAC      =  6 = Output Power
16 = 45 = ZAC      =  7 = Grid Impedance
17 = 47 = ETOTALH  =  8 = Accumulated Energy (high bit)
18 = 48 = ETOTALL  =  9 = Accumulated Energy (low bit)
19 = 49 = HTOTALH  = 10 = Working Hours (high bit)
20 = 4a = HTOTALL  = 11 = Working Hours (low bit)
21 = 4c = MODE     = 12 = Operating Mode
22 = 78 = ERR_GV   = 13 = Error message: GV fault value
23 = 79 = ERR_GF   = 14 = Error message: GF fault value
24 = 7a = ERR_GZ   = 15 = Error message: GZ fault value
25 = 7b = ERR_TEMP = 16 = Error message: Tmp fault value
26 = 7c = ERR_PV1  = 17 = Error message: PV1 fault value
27 = 7d = ERR_GFC1 = 18 = Error message: GFC1 fault value
28 = 7e = ERR_MODE = 19 = Error mode
29 = 7f = UNK10    = 20 = Unknown
Send -> req data as at 21/05/2011 09:57:27 : aaaa010000010102000159
Recv <- aaaa0001010001822a012d003a0c77001e09c01392030affff00001e5b00000635000100
000000000000000000000000000000073a
* Data:
TEMP    :     30.1 deg C = Internal Temperature
ETODAY  :     0.58 kWh   = Accumulated Energy Today
VPV     :    319.1 V     = Panel Voltage
IAC     :        3 A     = Grid Current
VAC     :    249.6 V     = Grid Voltage
FAC     :     50.1 Hz    = Grid Frequency
PAC     :      778 W     = Output Power
ZAC     :    65535 mOhm  = Grid Impedance
ETOTALH :        0 kWh   = Accumulated Energy (high bit)
ETOTALL :    777.1 kWh   = Accumulated Energy (low bit)
HTOTALH :        0 hrs   = Working Hours (high bit)
HTOTALL :     1589 hrs   = Working Hours (low bit)
MODE    :        1       = Operating Mode
ERR_GV  :        0       = Error message: GV fault value
ERR_GF  :        0       = Error message: GF fault value
ERR_GZ  :        0       = Error message: GZ fault value
ERR_TEMP:        0       = Error message: Tmp fault value
ERR_PV1 :        0       = Error message: PV1 fault value
ERR_GFC1:        0       = Error message: GFC1 fault value
ERR_MODE:        0       = Error mode
UNK10   :        0       = Unknown
Logging to: C:/solar/inverter_0123456789_20110521.csv
Ran: C:/rrdtool/rrdtool update C:/solar/inverter_0123456789.rrd 1305935848:30.1:
319.1:3:249.6:50.1:778:777.1:1589:1:0.58
PVOUTPUT as at 21/05/2011 09:57:29 ...
  ran: perl pvoutput.pl 580 778 20110521 09:57 0123456789
Sending to PVOUTPUT [ d => 20110521, t => 09:57, v1 => 580, v2 => 778 ]


---------------------------------------------------------
  Serial Communication Protocol files - to help reverse engineer protocols for other inverters
---------------------------------------------------------

Free program from HHD software: http://www.serial-port-monitor.com/ 
Runs in parallel with the Inverter Control software (eg: ProControl or SunEzy Control, etc).

Start the monitor program first, then the Inverter Control software, log some stuff, close the Inverter Control program, close the monitor program. 
Just copy paste from 'output' window in the monitor program & paste it into your own text file (Notepad) & save it.
