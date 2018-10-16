#!/usr/bin/perl
#
# Description
#
# Tivoli BAU tool
#
# Created by Jozsef Fekete
# 2017 October 30
#

use strict;
use warnings;
use threads;
use threads::shared;
use POSIX 'strftime';
use Config::IniFiles;
use File::KeePass;
use Data::Dumper qw(Dumper);
use File::Slurp;
use File::HomeDir;
use Net::SSH::Perl;
use Net::OpenSSH;
use Net::OpenSSH::ShellQuoter::POSIX;
use IO::Pty;
use Net::FTP;
use Cwd 'abs_path';
use Encode;
use Chart::Gnuplot;

#credentials
my $username : shared;
my $password : shared;
my $user_email : shared;
my $HUBTEMS : shared;
my $repository : shared;
my $packagerscript : shared;
my $packageDIR : shared;
my $tad4dresDIR : shared;
$tad4dresDIR = File::HomeDir->my_home . "/Desktop/TAD4DtoBRAVO";
my $tarfile : shared;
$tarfile = $tad4dresDIR . "/EUT4DIFIN.tar";
my $tmpdir : shared;
$tmpdir = $tad4dresDIR . "/tmp/";

my $command : shared;
my $deathflag : shared;
my @work_q : shared;
my @agent_info : shared;
my $tad4d_info : shared;
my $srm_info : shared;
my $stb_info : shared;
my $sit_info : shared;
my $stdout : shared;
my $stderr : shared;
my $exit : shared;
my $generate_list : shared;
my $fullfile : shared;

my $product : shared;
my $hosttype : shared;
my $custype : shared;
my @offacnt : shared;
my $isdone : shared;
my $latestver : shared;
my $uptod : shared;
my @uptod : shared;
my $uptodcnt : shared;
my $notuptod : shared;
my @notuptod : shared;
my $notuptodcnt : shared;
$isdone = 0;
$latestver = "06.30.07.00";

$deathflag = 0;
                       ################################################## COMMAND THREAD (work queue)##################################################
my $thread = threads->create (sub {
        while (! $deathflag) {
                if (@work_q) {
                        print "Logging in with: ". $username ."\n";
                        sleep 1;
                        my $host = $HUBTEMS;
                        #-- set up a new connection
                        my $ssh = Net::SSH::Perl->new($host);
                        #-- authenticate
                        $ssh->login($username, $password);
                        my $tacmdlogin = "/opt/IBM/ITM/bin/tacmd login -s localhost -u $username -p $password ";
                        ($stdout,$stderr) = $ssh->cmd("$tacmdlogin");
                        print $stdout."\n";
                        my $cmd = (shift @work_q);
                        print "Running command: ".$cmd."\n";
                        my $id = (shift @work_q);
                      if($id eq "lista"){
                            my $listfile = "./Servers.txt";
                            my $listfile2 = "./SharedSystems.txt";
                            open(my $fh2, '>', $listfile2) or die "Could not open file '$listfile2' $!";
                            open(my $fh, '>', $listfile) or die "Could not open file '$listfile' $!";
                            ($stdout,$stderr) = $ssh->cmd("$command");
                            my @agentlist = split /\n/, $stdout;
                            shift @agentlist;
                            for my $i (0 .. $#agentlist)
                            {
                              chomp $agentlist[$i];
                              print $fh2 "$agentlist[$i]\n";
                              $agentlist[$i] =~ s/..._//g;
                              $agentlist[$i] =~ s/:.*$//g;
                              print $fh "$agentlist[$i]\n";
                            }
                            close $fh2;
                            close $fh;
                        $generate_list = 0;
                        }
                      elsif($id eq "svr_info"){
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          my @lines = split /\n/, $stdout;
                          foreach my $line (@lines) {
                          my($agent, $version, $status) = $line =~ m/\s+(..)\s+([0-9]{2}[.][0-9]{2}[.][0-9]{2}[.]..)\s+(.)/g;
                          push @agent_info, $agent;
                          push @agent_info, $version;
                          push @agent_info, $status;
                          }
                          
                          print "Output: \n".$stdout."\n";
                        }
                      elsif($id eq "sit_info"){
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          $sit_info = $sit_info . $stdout;
                          print "Output: \n".$stdout."\n";
                        }
                      elsif($id eq "scp_tad4d"){
                          &scp_qlr();
                          print "Output: SCP done \n";
                          `tar -xvf $tarfile -C $tad4dresDIR`;
                          `chmod -R 777 $tmpdir`;
                        }
                      elsif($id eq "ftp_tad4d"){
                          my $fl1;

                          opendir(DH, "$tmpdir");
                          my @files1 = readdir(DH);
                          closedir(DH);

                          foreach my $fl (@files1)
                          {
                            next if($fl =~ /^\.$/);
                            next if($fl =~ /^\.\.$/);
                            $fl1 = $tmpdir . $fl;
                            print "Uploading " . $fl1 . " to bldgsa.ibm.com \n";
                            &ftp_upl("$fl1");
                          }

                          print "Output: FTP upload done. \n";
                        }
                      elsif($id eq "offacnt"){
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          @offacnt =  split /\n/, $stdout;
                          chomp @offacnt;
                      for (my $i = 0; $i < @offacnt; $i++) {
                          chomp $offacnt[$i];
                      }

                          ($stdout,$stderr) = $ssh->cmd("/opt/IBM/ITM/bin/tacmd listsystems -t NT LZ UX | awk '{if(\$3==\"$latestver\") print \$0}' ");
                          print $stdout."\n";
                          $uptod = $stdout;
                          @uptod =  split /\n/, $stdout;
                          $uptodcnt = scalar (@uptod);
                          chomp $uptodcnt;
                        
                          ($stdout,$stderr) = $ssh->cmd("/opt/IBM/ITM/bin/tacmd listsystems -t NT LZ UX | awk '{if(\$3!=\"$latestver\") print \$0}' ");
                          print $stdout."\n";
                          $notuptod = $stdout;
                          @notuptod =  split /\n/, $stdout;
                          $notuptodcnt = scalar (@notuptod);
                          chomp $notuptodcnt;
                         
                          $isdone = 1;
                        }
                      elsif($id eq "agent_pkg"){
                         if($hosttype eq "wix64"){
                           my $commandka = "cp /tivrepos/AgentPackager/AgentPackager/ITMPackages/"."$custype"."WIX64_Silent_Win.txt /tivrepos/AgentPackager/AgentPackager/ITMPackages/WIX64_Silent_Win.txt";
                          ($stdout,$stderr) = $ssh->cmd("/opt/IBM/ITM/bin/tacmd executecommand -m tfi_"."$HUBTEMS".":KUX -c \"$commandka\" -v -o -e");
                         }
                         if($hosttype eq "SLib"){
                           my $commandka2 = "cp /tivrepos/AgentPackager/AgentPackager/ITMPackages/"."$custype"."WINNT_Silent_Win.txt /tivrepos/AgentPackager/AgentPackager/ITMPackages/WINNT_Silent_Win.txt";
                          ($stdout,$stderr) = $ssh->cmd("/opt/IBM/ITM/bin/tacmd executecommand -m tfi_"."$HUBTEMS".":KUX -c \"$commandka2\" -v -o -e");
                         }
                          ($stdout,$stderr) = $ssh->cmd("echo $password | sudo -S /tivrepos/AgentPackager/AgentPackager/itm_create_agent_package.ksh -c $custype -p $product -t $hosttype");
                          print "Output: \n".$stdout."\n";
                          if ($stdout =~ /Package ([a-z]{3}_[a-z]{2}-[a-z]{3}_[0-9]{9}_.*?\.[a-z]{3}) created./) {
                              my $pkgname = $1;
                              print "Downloading $pkgname package...\n";
                          `sshpass -p $password scp $username\@$HUBTEMS:/tivrepos/RemoteDeployPackages/$pkgname ./packages/$pkgname`;
                          print "DONE \n";
                          }else{print "ERROR, package not found!";}
                        }
                      elsif($id eq "tad4d_info"){
                          $tad4d_info = "";
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          my @lines = split /\n/, $stdout;
                          foreach my $line (@lines) {
                              if ($line =~ /tlmagent version/) {
                                  my @fieldek = split /-/, $line;
                                  $tad4d_info = $fieldek[0]; 
                              }
                          }
                          print "Output: \n".$stdout."\n";
                        }
                      elsif($id eq "srm_info"){
                          $srm_info = "";
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          my $iostat = 0;
                          my $procdata = 0;
                          my $vmstat = 0;
                          my $netstat = 0;
                          my $srmagentexe = 0;
                          my $srmserviceexe = 0;
                          my @lines = split /\n/, $stdout;
                          foreach my $line (@lines) {
                              if ($line =~ /iostat/) {
                                  $iostat = 1;
                              }
                              if ($line =~ /procdata/) {
                                  $procdata = 1;
                              }
                              if ($line =~ /vmstat/) {
                                  $vmstat = 1;
                              }
                              if ($line =~ /netstat/) {
                                  $netstat = 1;
                              }
                              if ($line =~ /srmagent\.exe/) {
                                  $srmagentexe = 1;
                              }
                              if ($line =~ /srmservice\.exe/) {
                                  $srmserviceexe = 1;
                              }
                          }
                          if($iostat && $procdata && $vmstat && $netstat){
                          $srm_info = "All SRM processes running \n (iostat procdata vmstat netstat)";
                          }
                          elsif($srmagentexe && $srmserviceexe){
                          $srm_info = "All SRM processes running \n (srmagent.exe srmservice.exe)";
                          }
                          print "Output: \n".$stdout."\n";
                        }
                      elsif($id eq "upload"){
                          my ( $servername, $ffilename ) = split(':',$cmd);
                          my @filepatharray = split('/',$ffilename);
                          my $ufilename = pop @filepatharray;
                          my $ucommand = "";
                          my $iswin = 0;
                          my $isunix = 0;
                          my $shareddestinationserver = "";
                          my $base_pat = abs_path($1);
                          my $shrdfl_path = "/SharedSystems.txt";
                          my $fullshrdfl_path = $base_pat . $shrdfl_path;
                          if(-f $fullshrdfl_path){ #If shared server list file exist
                           my $sharedSystems = "./SharedSystems.txt";
                           my @allSharedAgents = read_file($sharedSystems);

                           my %sharedServers = map { my ( $key, $value ) = split ":"; ( $key, $value ) } @allSharedAgents;

                           for (grep /\Q$servername\E/, keys %sharedServers)
                           {
                              print "Found $_ server ($servername) \n";
                              if ($sharedServers{$_} =~ "KUX"){
                              	print "This is an AIX machine.";
                              	$isunix = 1;
                              }
                              if ($sharedServers{$_} =~ "NT"){
                              	print "This is a Windows machine.";
                              	$iswin = 1;
                              }
                              if ($sharedServers{$_} =~ "LZ"){
                              	print "This is a Linux machine.";
                              	$isunix = 1;
                              }
                              $shareddestinationserver = join (":", $_, $sharedServers{$_});
                              chomp $shareddestinationserver;
                              print "The OS agent is: $shareddestinationserver";
                           }
                           if ($shareddestinationserver eq ""){
                           print "Destination server not found in Shared environment!\n";
                           }
                           else{
                          	`sshpass -p $password scp $ffilename $username\@158.98.130.82:/tmp/$ufilename`;
	
                          	#doing copy in shared env
                              #-- set up a new connection
                              my $ssh = Net::SSH::Perl->new($host);
                              #-- authenticate
                              $ssh->login($username, $password);
                              #-- execute the command
                              #$tacmdlogin = "/opt/IBM/ITM/bin/tacmd login -s localhost -u $username -p $password ";
                              if ($isunix){
                              	$ucommand = "/opt/IBM/ITM/bin/tacmd putfile -m $shareddestinationserver -s \"/tmp/$ufilename\" -d \"/tmp/$ufilename\" -f ";
                              }
                              if ($iswin){
                                  $ucommand = "/opt/IBM/ITM/bin/tacmd putfile -m $shareddestinationserver -s \"/tmp/$ufilename\" -d \"C:\\Temp\\$ufilename\" -f ";	
                              }
    
                              ($stdout, $stderr, $exit) = $ssh->cmd("$ucommand");
                              print "$stdout";
                              my $cleaningcommand = "rm /tmp/$ufilename";
                              ($stdout, $stderr, $exit) = $ssh->cmd("$cleaningcommand");
                              print "\nPutfile done, please verify by running this command on HUBTEMS:\n";
                              if ($isunix){
                              print "tacmd executecommand -m $shareddestinationserver -c \"ls -ltr /tmp\" -v -o -e \n";}
                              if ($iswin){
                              print "tacmd executecommand -m $shareddestinationserver -c \"DIR C:\\Temp\" -v -o -e \n";}
                           }
                          }
                           else{print "$fullshrdfl_path file is missing, please generate it! \n";}
                          
                        }
                      else{
                          ($stdout,$stderr) = $ssh->cmd("$cmd");
                          print $stdout."\n";
                          print $stderr."\n";
                        }
                        print "Successful command count: ".(shift @work_q)."\n"; #This will hide the window away!
                } else {
                        threads->yield;
                }
        }
});                      ################################################## COMMAND THREAD END ##################################################
















use Glib;
use Glib 'TRUE', 'FALSE';
use Gtk3 '-init';

my $lastbusy = 0;
my $n = 0;
my $LOAD_WINDOW = &create_loading_window();
my $ABOUT_WINDOW = &create_about_window();
my $INFRA_WINDOW;
my $registered = 0;
my $KP_setup = 0;
my $key = 'TivBAUtoolbeta';
my $upload_filename = "";
my $servername = "";
my $iswin = 0;
my $isunix = 0;
my $shareddestinationserver = "";
my $listcreated = 0;
my $SRVINF_tad4d;
my $SRVINF_srm;
my $SRVINF_os;
my $SRVINF_bc;
my $SRVINF_stb;
my $SRVINF_sit;

#agent packager variables
my $assistant;
my %HostTypes;
my @HostTypekeys;
my %CusTypes;
my @CusTypekeys;
my $oscb;
my $cuscb;
my $label3;
my $cmdtext;
#########################

#Menu entries and action call###############################################################
my @entries = (
    [ "FileMenu",        undef, "_File" ],
    [ "PreferencesMenu", undef, "_Preferences" ],
    [ "HelpMenu",        undef, "_Help" ],

        [   "SendEmail",        'gtk-open', "_Open", "<control>O",
        "Send e-mail to TaskID", \&activate_action
        ],

    [ "GeneralConfig", 'gtk-genconf', "_General Configuration", "<control>E", "GenConfig", \&general_config ],
    [ "KPConnSettings", 'gtk-mKey', "_KeePass Connection Settings", "<control>p", "KPConnSet", \&keepass_config ],
    [ "AddUsefulLink", 'gtk-AddLink', "_Add Useful link", "<control>l", "AddLink", \&add_link ],
    [ "CreateLists", 'gtk-CreateList', "_Create Server List", "<control>l", "CreateList", \&create_list ],
    
    [ "Quit", 'gtk-quit', "_Quit", "<control>Q", "Quit", \&activate_action ],
    [ "About", undef, "_About", "<control>A", "About", \&about ],
    [ "TivBauLogo", "demo-gtk-logo", undef, undef, "Tivoli BAU Tool | Info", \&about ],
    );
############################################################################################


#Create application windows ################################################################
my $main_window;
my $GENCONF_WINDOW;
my $KPCONF_WINDOW;
my $ADDLINK_WINDOW;
my $SERVERINFO_WINDOW;
my $INFRASTATUS_WINDOW;
my $PACKAGE_WINDOW;
my $LINKS_WINDOW;

my $MasterKey_entry;
my $level;
                            ################################################## GUI THREAD ##################################################
Glib::Idle->add (sub {
        # touch the queue only once to avoid race conditions.
        my $thisbusy = @work_q;
        if (!$thisbusy){ $LOAD_WINDOW->hide(); }
        # print $thisbusy."\n";
        if ($thisbusy != $lastbusy) {
                $lastbusy = $thisbusy;
                if (!$thisbusy){ $LOAD_WINDOW->hide(); }
                if(@agent_info){
                my $limit = scalar (@agent_info) / 3;
                my $others = "Other agents on server \n \n";
                  for (my $i=0; $i < $limit; $i++) {
                      my $agent = (shift @agent_info);
                      my $version = (shift @agent_info);
                      my $status = (shift @agent_info);
                      if($agent eq "NT" || $agent eq "UX" || $agent eq "LZ" ){
                          $SRVINF_os->set_text( " <b>OS</b> ($agent) agent: ".&design_status($status)." \n Version: $version" );
                          $SRVINF_os->set_use_markup(1);
                      }
                      elsif($agent eq "06" || $agent eq "07" || $agent eq "08" ){
                          $SRVINF_bc->set_text( " <b>BC</b> ($agent) agent: ".&design_status($status)." \n Version: $version" );
                          $SRVINF_bc->set_use_markup(1);
                      }
                      else{
                          $others = $others . "<b>$agent</b> agent: ".&design_status($status)." \n Version: $version \n";
                      }
                  }
                  $SRVINF_stb->set_text( " $others" );
                  $SRVINF_stb->set_use_markup(1);
                }
              if($tad4d_info){
                 $SRVINF_tad4d->set_text( " <b>TAD4D</b> agent: ".&design_status("Y")." \n $tad4d_info" );
                 $SRVINF_tad4d->set_use_markup(1);
              }else{$SRVINF_tad4d->set_text( " <b>TAD4D</b> agent: <b>N/A</b>");$SRVINF_tad4d->set_use_markup(1);}
              if($srm_info){
                 $SRVINF_srm->set_text( " <b>SRM</b> agent: ".&design_status("Y")." \n $srm_info" );
                 $SRVINF_srm->set_use_markup(1);
              }else{$SRVINF_srm->set_text( " <b>SRM</b> agent: <b>N/A</b>");$SRVINF_srm->set_use_markup(1);}
              if($sit_info){
                 $SRVINF_sit->set_text( "Situations: \n $sit_info" );
              }
        }
        1;
});                           ############################################ GUI THREAD END ##################################################

do_appwindow();
create_assistant();
Gtk3->main();

############################################################################################

#GUI related functions Toolbar/Menubar/Icons ###############################################
sub register_stock_icons {
    if ( !$registered ) {

        $registered = 1;

        my $factory = Gtk3::IconFactory->new;
        $factory->add_default;

        my $pixbuf = undef;

        my $filename = "TivBau.png";
        if ($filename) {
            eval {
                $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($filename);

                my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );

                my $icon_set = Gtk3::IconSet->new_from_pixbuf($transparent);
                $factory->add( "demo-gtk-logo", $icon_set );
            };
            warn "failed to load GTK logo for toolbar"
                if $@;
        }
    }
}
sub get_ui {
    return "<ui>
	<menubar name='MenuBar'>
	<menu action='FileMenu'>
      <menuitem action='AddUsefulLink'/> 
      <menuitem action='CreateLists'/>
      <menuitem action='Quit'/>
    </menu>
    <menu action='PreferencesMenu'>
	<menuitem action='GeneralConfig'/>
	<menuitem action='KPConnSettings'/>    
    </menu>
    <menu action='HelpMenu'>
      <menuitem action='About'/>
    </menu>
  </menubar>
  <toolbar  name='ToolBar'>
    <toolitem action='SendEmail'/>
    <toolitem action='Quit'/>
    <separator/>
    <toolitem action='TivBauLogo'/>
  </toolbar>
</ui>";
}
############################################################################################

#Preferences menu functions #################################################################
sub general_config {

    $GENCONF_WINDOW = Gtk3::Window->new;
    $GENCONF_WINDOW->set_title('General/Infrastructure Configuration');
    $GENCONF_WINDOW->set_default_size( 400, 300 );

    my $GENconf_table = Gtk3::Grid->new;
    $GENCONF_WINDOW->add($GENconf_table);
#asd customer code for hubtems fiels (tfi_)

    my $email_label = Gtk3::Label->new("         Your email address:");
    my $email_entry = Gtk3::Entry->new;
    my $ip_label = Gtk3::Label->new("      HUBTEMS hostname or IP:");
    my $ip_entry = Gtk3::Entry->new;
    my $depo_label = Gtk3::Label->new("         ITM repository path:");
    my $depo_entry = Gtk3::Entry->new;
    my $apacksc_label = Gtk3::Label->new("     Agent packager script path:");
    my $apacksc_entry = Gtk3::Entry->new;
    my $pack_label = Gtk3::Label->new("  Agent packages directory path: ");
    my $pack_entry = Gtk3::Entry->new;
    my $setGEN_btn = Gtk3::Button->new_from_stock('gtk-setGEN');
    $setGEN_btn->set_size_request( 120, 50 );
    $setGEN_btn->set_label("Apply");
    $setGEN_btn->signal_connect( "clicked" => sub {
                                                   if (!(-e "./genconf.ini")){`touch genconf.ini`;`echo \"[GeneralConfiguration]\n email=defaultValue\n IPorHOST=defaultValue\n RepositoryPath=defaultValue\n AgentPackagerScript=defaultValue\n AgentPackagesDir=defaultValue\" > genconf.ini`;}
                                                   my $section = 'GeneralConfiguration';
                                                   my $email_param = 'email';
                                                   my $IP_param = 'IPorHOST';
                                                   my $repo_param = 'RepositoryPath';
                                                   my $packagerSC_param = 'AgentPackagerScript';
                                                   my $packageDIR_param = 'AgentPackagesDir';
                                                   #Getting the values from the filled out fields
                                                   my $email = $email_entry->get_text;
                                                   my $IP = $ip_entry->get_text;
                                                   my $repo = $depo_entry->get_text;
                                                   my $packagerSC = $apacksc_entry->get_text;
                                                   my $packageDIR = $pack_entry->get_text;
                                                   #Setting values in .kpconf.ini
                                                   my $cfg = Config::IniFiles->new( -file => "./genconf.ini" );
                                                   $cfg->setval($section, $email_param, "$email");
                                                   $cfg->setval($section, $IP_param, "$IP");
                                                   $cfg->setval($section, $repo_param, "$repo");
                                                   $cfg->setval($section, $packagerSC_param, "$packagerSC");
                                                   $cfg->setval($section, $packageDIR_param, "$packageDIR");
                                                   $cfg->WriteConfig('./genconf.ini', -delta=>1);
                                                   #Close window
                                                   $GENCONF_WINDOW->destroy;
                                                   } );

    $GENconf_table->attach( $email_label, 0, 0, 1, 1 );
    $GENconf_table->attach( $email_entry, 1, 0, 1, 1 );
    $GENconf_table->attach( $ip_label, 0, 1, 1, 1 );
    $GENconf_table->attach( $ip_entry, 1, 1, 1, 1 );
    $GENconf_table->attach( $depo_label, 0, 2, 1, 1 );
    $GENconf_table->attach( $depo_entry, 1, 2, 1, 1 );
    $GENconf_table->attach( $apacksc_label, 0, 3, 1, 1 );
    $GENconf_table->attach( $apacksc_entry, 1, 3, 2, 1 );
    $GENconf_table->attach( $pack_label, 0, 4, 1, 1 );
    $GENconf_table->attach( $pack_entry, 1, 4, 2, 1 );
    $GENconf_table->attach( $setGEN_btn, 2, 5, 1, 1 );
    #TODO general configuration menu
    #email address, HUB IP/name, ITMDEPO on hub, agent package directory

    $GENCONF_WINDOW->set_border_width(50);    
    $GENCONF_WINDOW->show_all;
    return;
}
#-------------------------------------------------------------------------------------------
sub keepass_config {

    $KPCONF_WINDOW = Gtk3::Window->new;
    $KPCONF_WINDOW->set_title('KeePass Connection Settings');
    $KPCONF_WINDOW->set_default_size( 400, 250 );
    my $KPconf_table = Gtk3::Grid->new;
    $KPCONF_WINDOW->add($KPconf_table);

  my $buffer = Gtk3::EntryBuffer->new( undef, -1 );
  $buffer->signal_connect( 'inserted-text' => \&handler );
  $buffer->set_max_length( 20 );

    my $DBpath_entry = Gtk3::Entry->new;
    my $HUBtitle_entry = Gtk3::Entry->new;
    $MasterKey_entry = Gtk3::Entry->new_with_buffer( $buffer );

  my $checkbutton = Gtk3::CheckButton->new_with_label( 'Show Master Key characters' );
  $checkbutton->signal_connect(
      toggled => sub {
          if ( $checkbutton->get_active() ) {
              $MasterKey_entry->set_visibility( 1 );
          } else {
              $MasterKey_entry->set_visibility( 0 );
          }
      }
  );
  $level = Gtk3::LevelBar->new;

    $MasterKey_entry->set_visibility(0);
    my $DBpath_label = Gtk3::Label->new("  Path to KeePass Database:");
    my $HUBtitle_label = Gtk3::Label->new("  Title of HUBTEMS entry:");
    my $MasterKey_label = Gtk3::Label->new("  Master Key for KeePass DB: ");
    my $strength_label = Gtk3::Label->new("  Master Key strength");
    my $setKP_btn = Gtk3::Button->new_from_stock('gtk-setKP');
    $setKP_btn->set_size_request( 120, 50 );
    $setKP_btn->set_label("Apply");
    $setKP_btn->signal_connect( "clicked" => sub {
                                                   if (!(-e "./.kpconf.ini")){`touch genconf.ini`;`echo \"[KPconfiguration]\n DBpath=defaultValue\n HUBentrytitle=defaultValue\n MasterKey=defaultValue\" > .kpconf.ini`;}
                                                   my $section = 'KPconfiguration';
                                                   my $DBpath_param = 'DBpath';
                                                   my $HUBtitle_param = 'HUBentrytitle';
                                                   my $MasterKey_param = 'MasterKey';
                                                   #Getting the values from the filled out fields
                                                   my $DBpath = $DBpath_entry->get_text;
                                                   my $HUBtitle = $HUBtitle_entry->get_text;
                                                   my $pass = $MasterKey_entry->get_text;
                                                   my $encoded = xor_encode($pass,$key);
                                                   #Setting values in .kpconf.ini
                                                   my $cfg = Config::IniFiles->new( -file => "./.kpconf.ini" );
                                                   $cfg->setval($section, $DBpath_param, "$DBpath");
                                                   $cfg->setval($section, $HUBtitle_param, "$HUBtitle");
                                                   $cfg->setval($section, $MasterKey_param, "$encoded");
                                                   $cfg->WriteConfig('./.kpconf.ini', -delta=>1);
                                                   #Close window
                                                   $KPCONF_WINDOW->destroy;
                                                   } );

    $KPconf_table->attach( $DBpath_label, 0, 0, 1, 1 );
    $KPconf_table->attach( $DBpath_entry, 1, 0, 2, 1 );
    $KPconf_table->attach( $HUBtitle_label, 0, 1, 1, 1 );
    $KPconf_table->attach( $HUBtitle_entry, 1, 1, 1, 1 );
    $KPconf_table->attach( $MasterKey_label, 0, 2, 1, 1 );
    $KPconf_table->attach( $MasterKey_entry, 1, 2, 2, 1 );
    $KPconf_table->attach( $checkbutton, 0, 3, 1, 1 );
    $KPconf_table->attach( $level, 0, 4, 3, 1 );
    $KPconf_table->attach( $strength_label, 0, 5, 3, 1 );
    $KPconf_table->attach( $setKP_btn, 2, 6, 1, 1 );
    $KPCONF_WINDOW->set_border_width(50);
    $KPCONF_WINDOW->show_all;
    return;
}
sub xor_encode {
    my ($str, $key) = @_;
    my $enc_str = '';
    for my $char (split //, $str){
        my $decode = chop $key;
        $enc_str .= chr(ord($char) ^ ord($decode));
        $key = $decode . $key;
    }
   return $enc_str;
}
sub handler {
    my ( $position, $char, $num_of_chars ) = @_;

    my ( $upper, $lower, $digits, $special ) = ( 0 ) x 4;

    my $percent = 0;

    my $pass = $MasterKey_entry->get_text;

    for my $t ( split //, $pass ) {
        if ( $t =~ /[a-z]/ ) {
            $lower++;
        } elsif ( $t =~ /[A-Z]/ ) {
            $upper++;
        } elsif ( $t =~ /[0-9]/ ) {
            $digits++;
        } else {
            $special++;
        }
    }

    $percent += .25 if ( $lower > 1 );
    $percent += .25 if ( $upper > 1 );
    $percent += .25 if ( $digits > 1 );
    $percent += .25 if ( $special > 1 );

    $level->set_value( $percent );

    return 1;
}
#--------------------------------------------------------------------------------------------------
sub add_link {

    $ADDLINK_WINDOW = Gtk3::Window->new;
    $ADDLINK_WINDOW->set_title('Add Useful Link');
    $ADDLINK_WINDOW->set_default_size( 400, 200 );

    my $linktable = Gtk3::Grid->new;
    $ADDLINK_WINDOW->add($linktable);

    my $name_entry = Gtk3::Entry->new;
    my $url_entry = Gtk3::Entry->new;
    my $desc_entry = Gtk3::Entry->new;
    my $name_label = Gtk3::Label->new("  Name of link:");
    my $url_label = Gtk3::Label->new("  URL of link:");
    my $desc_label = Gtk3::Label->new("  Description of link:");
    my $addlink_btn = Gtk3::Button->new_from_stock('gtk-addlink');
    $addlink_btn->set_size_request( 250, 50 );
    $addlink_btn->set_label("Add Link");
    $addlink_btn->signal_connect( "clicked" => sub {my $name = $name_entry->get_text;
                                                    my $url = $url_entry->get_text;
                                                    my $desc = $desc_entry->get_text;
                                                    my $stringresult = $url . "====" . $desc . "====" . $name;
                                                    my $filename = 'ulinks';
                                                    open(my $fh, '>>', $filename) or die "Could not open file '$filename' $!";
                                                    print $fh "$stringresult \n";
                                                    close $fh;
                                                    $ADDLINK_WINDOW->destroy;
                                                   } );

    $linktable->attach( $name_label, 0, 0, 1, 1 );
    $linktable->attach( $name_entry, 1, 0, 1, 1 );
    $linktable->attach( $url_label, 0, 1, 1, 1 );
    $linktable->attach( $url_entry, 1, 1, 2, 1 );
    $linktable->attach( $desc_label, 0, 2, 1, 1 );
    $linktable->attach( $desc_entry, 1, 2, 2, 1 );
    $linktable->attach( $addlink_btn, 2, 3, 1, 1 );
    $ADDLINK_WINDOW->set_border_width(50);
    $ADDLINK_WINDOW->show_all;
    return;
}
sub create_list {
    check_KPconf();
  if (!$KP_setup){
    my $dialog = Gtk3::MessageDialog->new( $main_window, 'destroy', 'info',
        'close', " Unable to connect to KeePass! \n Please set up Keepass Connection Settings from preferences menu!" );
    $dialog->signal_connect( response => sub { $dialog->destroy } );
    $dialog->show();
    }
  else{
        if(!$listcreated){
                                                    $command = "/opt/IBM/ITM/bin/tacmd listsystems -t NT UX LZ | awk \'{print \$1}\'";
                                                    $LOAD_WINDOW->show_all();
                                                    set_HUBcredentials();
                                                    $generate_list = 1;
                                                    push @work_q, $command;
                                                    push @work_q, "lista";
                                                    push @work_q, ++$n;

        $listcreated = 1;
        }
        else{
        err_dialog("You already have an up to date serverlist! \n Please don't create load on the HUB unnecessarily!");
        }
    }
}
#############################################################################################

#KeePass related functions ##################################################################
sub check_KPconf {
  my $base_path = "./.kpconf.ini";
  if (-e $base_path) {
  my $cfg = Config::IniFiles->new( -file => "./.kpconf.ini" );
  my $str = "";
  $str = $cfg->val( 'KPconfiguration', 'DBpath' );
    if ($str){
    $KP_setup = 1;
    }
    else{
    $KP_setup = 0;
    }
  }
  else{
  $KP_setup = 0;
  }
}
sub set_HUBcredentials {
    #TODO get HUBTEMS IP or hostname from ini file!!!
    my $gencfg = Config::IniFiles->new( -file => "./genconf.ini" );
    my $gensection = 'GeneralConfiguration';
    my $email_param = 'email';
    my $IP_param = 'IPorHOST';
    my $repo_param = 'RepositoryPath';
    my $packagerSC_param = 'AgentPackagerScript';
    my $packageDIR_param = 'AgentPackagesDir';
    $HUBTEMS = $gencfg->val( $gensection, $IP_param );
    $user_email = $gencfg->val( $gensection, $email_param );
    $repository = $gencfg->val( $gensection, $repo_param );
    $packagerscript = $gencfg->val( $gensection, $packagerSC_param );
    $packageDIR = $gencfg->val( $gensection, $packageDIR_param );
    #Connect to Keepass Database
    my $cfg = Config::IniFiles->new( -file => "./.kpconf.ini" );
    my $file = "";
    my $HUBentry_title = "";
    my $encoded_master_pass = "";
    my $section = 'KPconfiguration';
    my $MKparam = 'MasterKey';
    my $DBparam = 'DBpath';
    my $titleparam = 'HUBentrytitle';
    $file = $cfg->val( $section, $DBparam );
    $encoded_master_pass = $cfg->val( $section, $MKparam );
    $HUBentry_title = $cfg->val( $section, $titleparam);
    my $decoded = xor_encode($encoded_master_pass,$key);

    my $k = File::KeePass->new;
    if (! eval { $k->load_db($file, $decoded) }) {
        die "Couldn't load the file $file: $@";
    }
    #set up credentials for HUB
    $k->unlock;
    my @entries = $k->find_entries({title => "$HUBentry_title"});

    $username =  "$entries[0]->{username}";
    $password =  "$entries[0]->{password}";

    #Check if username begins with HU this check is optional.
    my $lower_uname = lc $username;
    my $letter = substr($lower_uname, 0, 2);
    if ($letter eq "hu") {
    return 1;
    }
    else{
    return 0;
    }
}
#############################################################################################

#Button functions ###########################################################################
sub server_info { 
    check_KPconf();
    if (!$KP_setup){
    err_dialog("Unable to connect to KeePass! \n Please set up Keepass Connection Settings, from preferences menu!");
    }
    else{
    set_HUBcredentials();
    ########################################################################################################################################################
    #$LOAD_WINDOW->set_title ("Test loading..");
    #$LOAD_WINDOW->show_all();                        #loading_window("Test loading...", "write message function called..."); TODO Replace the 3 line code...
    ########################################################################################################################################################
      my $flname = "Servers.txt";
      if (-z $flname){
      err_dialog("The file $flname is empty \n Please generate server list, from File menu!");
      }
      else{
      $SERVERINFO_WINDOW->show_all;
      }
    }
}
sub infra_status { 
    check_KPconf();
    if (!$KP_setup){
    err_dialog("Unable to connect to KeePass! \n Please set up Keepass Connection Settings, from preferences menu!");
    }
    else{
    set_HUBcredentials();
    my $command = "tail -n 31 /tivrepos/offacnt.txt";
    push @work_q, $command;
    push @work_q, "offacnt";
    push @work_q, ++$n;
    do{
      print "Fetching data from HUB...\n";
      sleep 3;
    } until($isdone);
    $isdone = 0;
    create_plot();
    my $INFRA_WINDOW = &create_infstatus_window();
    $INFRA_WINDOW->show_all();
    }
}
sub agent_package { 
    check_KPconf();
    if (!$KP_setup){
    err_dialog("Unable to connect to KeePass! \n Please set up Keepass Connection Settings, from preferences menu!"); 
    }
    else{
    $assistant->show_all();    
    }
}
sub useful_links { 
  $LINKS_WINDOW = Gtk3::Window->new('toplevel');
  $LINKS_WINDOW->set_title('Useful Links');
  $LINKS_WINDOW->set_default_size( 300, 750 );
  $LINKS_WINDOW->set_border_width(12);
  my $string = "";

  my $filename = 'ulinks';
  open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";
 
  while (my $row = <$fh>) {
    chomp $row;
    my @words = split /====/, $row;
    my $retstring = create_link( $words[2], $words[0], $words[1] );
    $string = $string . $retstring;
  }


  my $label = Gtk3::Label->new($string);
  $label->set_use_markup(1);
  $label->signal_connect(
    'activate-link' => \&activate_link,
    $LINKS_WINDOW
    );
  $LINKS_WINDOW->add($label);
  $label->show();

    my $icon = 'TivBau.png';
    if ( -e $icon ) {
      my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
      my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
      $LINKS_WINDOW->set_icon($transparent);
    }

  $LINKS_WINDOW->show_all();
}

sub create_link{
    my ( $name, $url, $desc ) = @_;
    my $string = "";
    my $string1 = "<a href=\"$url\"";
    my $string2 = "title=\"$desc\">$name</a> \n";

    $string = $string1 . $string2;
    return $string;
}


#############################################################################################



#Default functions ##########################################################################
sub activate_action {
    my $action = shift;
    
    my $name = $action->get_name;

    if ( $name eq 'Quit' ) {
                if (@work_q) {
                        print "can't quit, busy...\n";
                } else {
                        Gtk3->main_quit;
                        $deathflag = 1;
                }

                return 1;
    }
    else{
    err_dialog("This \"$name\" function is not working yet.");
    }
}
sub design_status{
    my $stat = shift;
    if($stat eq "Y"){
    $stat = "<span color=\"#00FF00\">Online</span>";
    }
    elsif($stat eq "N"){
    $stat = "<span color=\"#FF0000\">Offline</span>";
    }
    else{$stat = "<b>N/A</b>";}
    return $stat;
}
sub get_os_agentname {
    my $servername = shift;
    my $agentname = "";
                          my $base_pat = abs_path($1);
                          my $shrdfl_path = "/SharedSystems.txt";
                          my $fullshrdfl_path = $base_pat . $shrdfl_path;
                          if(-f $fullshrdfl_path){ #If shared server list file exist
                           my $sharedSystems = "./SharedSystems.txt";
                           my @allSharedAgents = read_file($sharedSystems);

                           my %sharedServers = map { my ( $key, $value ) = split ":"; ( $key, $value ) } @allSharedAgents;

                           for (grep /\Q$servername\E/, keys %sharedServers)
                           {
                              print "Found $_ server ($servername) \n";
                              if ($sharedServers{$_} =~ "KUX"){
                              	print "This is an AIX machine.";
                              	$isunix = 1;
                              }
                              if ($sharedServers{$_} =~ "NT"){
                              	print "This is a Windows machine.";
                              	$iswin = 1;
                              }
                              if ($sharedServers{$_} =~ "LZ"){
                              	print "This is a Linux machine.";
                              	$isunix = 1;
                              }
                              $agentname = join (":", $_, $sharedServers{$_});
                              chomp $agentname;
                              print "The OS agent is: $agentname";
                            }
                           }
    return $agentname;
}
sub get_bc_agentname {
    my $servername = shift;
    my $agentname = "";
                          my $base_pat = abs_path($1);
                          my $shrdfl_path = "/SharedSystems.txt";
                          my $fullshrdfl_path = $base_pat . $shrdfl_path;
                          if(-f $fullshrdfl_path){ #If shared server list file exist
                           my $sharedSystems = "./SharedSystems.txt";
                           my @allSharedAgents = read_file($sharedSystems);

                           my %sharedServers = map { my ( $key, $value ) = split ":"; ( $key, $value ) } @allSharedAgents;

                           for (grep /\Q$servername\E/, keys %sharedServers)
                           {
                              print "Found $_ server ($servername) \n";
                              if ($sharedServers{$_} =~ "KUX"){
                              	$sharedServers{$_} = "07";
                              }
                              if ($sharedServers{$_} =~ "NT"){
                         	$sharedServers{$_} = "06";
                              }
                              if ($sharedServers{$_} =~ "LZ"){
                              	$sharedServers{$_} = "08";
                              }
                              $agentname = join (":", $_, $sharedServers{$_});
                              chomp $agentname;
                              print "The BC agent is: $agentname";
                            }
                           }
    return $agentname;
}
sub write_log {
  my $text = shift;
  if($text){
  my $date = strftime '%Y%m%d', localtime;
  my $time = `date`;
  my $filename = "TivBauLog_$date.txt";
  open(my $fh, '>>', $filename) or die "Could not open file '$filename' $!";
  print $fh "############################################################################################\n";
  print $fh "$time";
  print $fh "$text\n";
  print $fh "############################################################################################\n";
  close $fh;
  print "done\n";
  }
}
sub create_loading_window{
    my $loading_window = Gtk3::Window->new('toplevel');
    $loading_window->set_title ("Loading...");
    $loading_window->set_default_size (340, 280);
    $loading_window->signal_connect('delete_event' =>  \&Gtk3::Widget::hide_on_delete); 
    my $grid=Gtk3::Grid->new();
    $loading_window->add($grid);
    my $file = 'TivBauLoading1.gif';
    my $scrolled = Gtk3::ScrolledWindow->new();
    $scrolled->set_hexpand(1);
    $scrolled->set_vexpand(1);
    my $message = Gtk3::Label->new();
    $message->set_text( "Working on HUBTEMS. Please wait!" );
    $grid->attach($scrolled, 0, 0, 1, 1);
    $grid->attach($message, 0, 1, 1, 1);
    my $image = Gtk3::Image->new();
    $image->set_from_file($file);
    $scrolled->add_with_viewport($image);

    my $icon = 'TivBau.png';
    if ( -e $icon ) {
      my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
      my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
      $loading_window->set_icon($transparent);
    }

    return $loading_window;
}
sub create_about_window{
    my $about_window = Gtk3::Window->new('toplevel');
    $about_window->set_title ("About TivBAU");
    $about_window->set_default_size (600, 400);
    $about_window->signal_connect('delete_event' =>  \&Gtk3::Widget::hide_on_delete);
    my $grid=Gtk3::Grid->new();
    $about_window->add($grid);
    my $file = 'TivBauCloud.gif';
    my $scrolled = Gtk3::ScrolledWindow->new();
    $scrolled->set_hexpand(1);
    $scrolled->set_vexpand(1);
    my $message = Gtk3::Label->new();
    $message->set_text( "Tivoli BAU tool version 1.0.1 \n  Created by Jozsef Fekete." );
    $grid->attach($scrolled, 0, 0, 1, 1);
    $grid->attach($message, 0, 1, 1, 1);
    my $image = Gtk3::Image->new();
    $image->set_from_file($file);
    $scrolled->add_with_viewport($image);
    my $icon = 'TivBau.png';
    if ( -e $icon ) {
      my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
      my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
      $about_window->set_icon($transparent);
    }

    return $about_window;
}
sub about{
    $ABOUT_WINDOW->show_all();
}
sub create_infstatus_window{
    my $inf_window = Gtk3::Window->new('toplevel');
    $inf_window->set_title ("Infrasctructure Status");
    $inf_window->set_default_size (600, 400);
    $inf_window->signal_connect('delete_event' =>  sub {$inf_window->destroy;});
    $inf_window->set_border_width(15);
    
    my $grid=Gtk3::Grid->new();
    $inf_window->add($grid);
    my $file = 'offagent_plot.png';
    my $scrolled = Gtk3::ScrolledWindow->new();
    my $textview = Gtk3::Label->new("$notuptod");
    $scrolled->add($textview);
    my $message = Gtk3::Label->new();
    my $date = `date`;
    $message->set_text( "Offline agent statistics generated on $date" );
    my $image = Gtk3::Image->new();
    $image->set_from_file($file);
    my $vbox = Gtk3::Box->new( 'vertical', 0 );
    my $val = pop @offacnt;
    my $offacnt_label = Gtk3::Label->new("  The <span color=\"#FF0000\">red</span> line on the plot shows the varying offline agent count for the last 30 days.\n  The <span color=\"#0000FF\">blue</span> line is the baseline which is 1% of all agent count.\n  Todays offline agent count: <span color=\"#FF0000\">$val</span>\n\n  There are <span color=\"#00FF00\">$uptodcnt</span> OS agents on latest fixpack version ($latestver).\n  There are <span color=\"#FF0000\">$notuptodcnt</span> OS agents, that are NOT up to date. \n\n\n\n Not up to date agents: ");
    $offacnt_label->set_use_markup(1);
    $vbox->pack_start( $offacnt_label, TRUE, TRUE, 0 );
    $vbox->pack_start( $scrolled, TRUE, TRUE, 0 );
    my $button = Gtk3::Button->new_with_label('Update OS agents');
    $button->signal_connect( clicked => sub { err_dialog("Update agent function is not working yet!");  } );
    $grid->attach($image, 0, 0, 1, 1);
    $grid->attach($message, 0, 1, 1, 1);
    $grid->attach($vbox, 1, 0, 1, 1);
    $grid->attach($button, 1, 1, 1, 1);
    $grid->attach($scrolled, 1, 2, 1, 1);
    my $icon = 'TivBau.png';
    if ( -e $icon ) {
      my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
      my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
      $inf_window->set_icon($transparent);
    }
    
    
    return $inf_window;
}
sub create_plot{
  my @baseline;
  for (my $i=0; $i<31; $i++){
    push @baseline, 52;
  }
  my @baseline0;
  for (my $i=0; $i<31; $i++){
    push @baseline0, 0;
  }
  my @x = (0 .. 30);
  #my @offacnt = map { rand } ( 0..30 );
  my $chart = Chart::Gnuplot->new(
    output => "offagent_plot.png",
    title   => "Offline agents plot.",
    xlabel  => "Last 30 days",
    ylabel  => "Offline Agent count",
    terminal => "png",
  );
  my @dataSets;
  my $dataSet1 = Chart::Gnuplot::DataSet->new(
     xdata => \@x,
     ydata => \@offacnt,
     width => 3,
     style => "lines",
     color => "red",
  );
  my $baseline = Chart::Gnuplot::DataSet->new(
    xdata => \@x,
    ydata => \@baseline,
    width => 5,
    style => "lines",
    color => "blue",
  );
  my $baseline0 = Chart::Gnuplot::DataSet->new(
    xdata => \@x,
    ydata => \@baseline0,
    width => 1,
    style => "lines",
    color => "black",
  );
  $dataSets[0] = $dataSet1;
  $dataSets[1] = $baseline;
  $dataSets[2] = $baseline0;
  $chart->plot2d(@dataSets);
}

sub err_dialog{
    my $text = shift;
    my $dialog = Gtk3::Dialog->new();
    $dialog->set_transient_for($main_window);
    $dialog->set_title('TivBAU Error');
    $dialog->set_position("mouse");
    $dialog->set_modal(1);
    $dialog->set_destroy_with_parent(0);

    my $hbox = Gtk3::Box->new( 'horizontal', 8 );
    $hbox->set_border_width(8);
    $dialog->get_content_area()->add($hbox);

    my $stock = Gtk3::Image->new_from_stock( 'gtk-dialog-error', 6 );
    $hbox->pack_start( $stock, 0, 0, 0 );

    my $table = Gtk3::Grid->new();
    $table->set_row_spacing(4);
    $table->set_column_spacing(4);
    $hbox->pack_start( $table, 1, 1, 0 );

    my $label = Gtk3::Label->new_with_mnemonic("_ $text");
    $table->attach( $label, 0, 0, 1, 1 );

    $hbox->show_all();
    $dialog->run;
}
sub write_message {
        my $msg_label = shift;
        my $text = shift;
	$msg_label->set_text( "$text" );
}

sub create_srvinf_window {
  my $twin = Gtk3::Window->new('toplevel');
  $twin->set_title('Server Information');
  $twin->set_border_width(10);
  #Only hides window if u click on X
  $twin->signal_connect (delete_event => \&Gtk3::Widget::hide_on_delete);

  my $box = Gtk3::Box->new( 'vertical', 0 );
  $box->set_homogeneous(0);
  $twin->add($box);
  #Create Server frame
  my $server_frame = Gtk3::Frame->new('Server');
  $box->pack_start( $server_frame, 1, 1, 10 );
  #add box to frame
  my $vbox = Gtk3::Box->new( 'vertical', 0 );
  $vbox->set_border_width(10);
  $vbox->set_homogeneous(0);
  $server_frame->add($vbox);
  my $srv_entry = Gtk3::Entry->new;
  #create button to download server informations from HUBTEMS
  my $chksrv_button = Gtk3::Button->new_from_stock('gtk-chksrv');
  $chksrv_button->set_label("Server Information");
  $chksrv_button->signal_connect( "clicked" => sub {
                                                    if($srv_entry->get_text){
                                                    my $svrneve = $srv_entry->get_text;
                                                    $command = "/opt/IBM/ITM/bin/tacmd listsystems | grep -i $svrneve";
                                                    $LOAD_WINDOW->show_all();
                                                    set_HUBcredentials();
                                                    push @work_q, $command;
                                                    push @work_q, "svr_info";
                                                    push @work_q, ++$n;
                                                    my $agentneve = &get_os_agentname($svrneve);
                                                    if($agentneve =~ "UX"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve -c \"/opt/itlm/tlmagent -v\" -v -o -e";
                                                    }
                                                    elsif($agentneve =~ "NT"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve -c \"C:\\windows\\itlm\\tlmagent -v\" -v -o -e";
                                                    }
                                                    elsif($agentneve =~ "LZ"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve -c \"/var/itlm/tlmagent -v\" -v -o -e";
                                                    }
                                                    push @work_q, $command;
                                                    push @work_q, "tad4d_info";
                                                    push @work_q, ++$n;
                                                    my $agentneve2 = &get_os_agentname($svrneve);
                                                    if($agentneve2 =~ "UX"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve2 -c \"ps -ef | grep -i srm\" -v -o -e";
                                                    }
                                                    elsif($agentneve2 =~ "NT"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve2 -c \"tasklist\" -v -o -e";
                                                    }
                                                    elsif($agentneve2 =~ "LZ"){
                                                    $command = "/opt/IBM/ITM/bin/tacmd executecommand -m $agentneve2 -c \"ps -ef | grep -i srm\" -v -o -e";
                                                    }
                                                    push @work_q, $command;
                                                    push @work_q, "srm_info";
                                                    push @work_q, ++$n;
                                                    }else{err_dialog("No server selected! \n Please select a server from which you need information!");}
                                                   });
  $vbox->pack_start($srv_entry, 1, 1, 0);
  $vbox->add( $chksrv_button );
  #setup search icon on text entry
  my $stock_id = undef;
  $stock_id = Gtk3::STOCK_FIND;
  $srv_entry->set_icon_from_stock('secondary', $stock_id);
  #Setup server name autocomplete
  my $completion = Gtk3::EntryCompletion->new();
  $srv_entry->set_completion($completion);
  my $completion_model = create_completion_model();
  $completion->set_model($completion_model);
  $completion->set_text_column(0);

  #create Mon. info frame
  my $frame_vert = Gtk3::Frame->new('Monitoring information');
  $box->pack_start( $frame_vert, 1, 1, 10 );
  my $hbox = Gtk3::Box->new( 'horizontal', 0 );
  $hbox->set_border_width(10);
  $hbox->set_homogeneous(0);
  $frame_vert->add($hbox);
  my $agnt_box = Gtk3::ButtonBox->new('vertical');
  $agnt_box->set_border_width(10);
  my $frame = Gtk3::Frame->new("Agent Info");
  $frame->add($agnt_box);
  $agnt_box->set_layout("spread");
  #$agnt_box->set_spacing(1);

  my $os_label = Gtk3::Label->new("OS agent: <b>N/A</b>");
  $os_label->set_use_markup(1);
  my $bc_label = Gtk3::Label->new("BC agent: <b>N/A</b>");
  $bc_label->set_use_markup(1);
  my $tad4d_label = Gtk3::Label->new("TAD4D: <b>N/A</b>");
  $tad4d_label->set_use_markup(1);
  my $srm_label = Gtk3::Label->new("SRM agent: <b>N/A</b>");
  $srm_label->set_use_markup(1);
  my $stbinfo_label = Gtk3::Label->new("");
  my $sitinfo_label = Gtk3::Label->new("");
  my $scrolled = Gtk3::ScrolledWindow->new;
  $scrolled->add( $sitinfo_label );
  #$scrolled->set_hexpand(1);
  #$scrolled->set_vexpand(1);
  #$scrolled->set_size_request (500, 200);
  $box->pack_start( $scrolled, 1, 1, 10 );

  $agnt_box->add($os_label);
  $agnt_box->add($bc_label);
  $agnt_box->add($tad4d_label);
  $agnt_box->add($srm_label);
  &set_up_srvinf_labels($os_label, $bc_label, $tad4d_label, $srm_label, $stbinfo_label, $sitinfo_label);
  
  my $upl_box = Gtk3::ButtonBox->new('vertical');
  $upl_box->set_border_width(10);
  my $frame2 = Gtk3::Frame->new("Features");
  $frame2->add($upl_box);
  $upl_box->set_layout("spread");
  $upl_box->set_spacing(10);
  my $browse_button = Gtk3::Button->new_from_stock('gtk-browsefile');
  $browse_button->set_label("Browse File");
  $browse_button->signal_connect('clicked' => \&open_callback);
  my $upload_button = Gtk3::Button->new_from_stock('gtk-uplfile');
  $upload_button->set_label("Upload");
  $upload_button->signal_connect( "clicked" => sub {
                                                    if($srv_entry->get_text && $fullfile){
                                                    my $svrneve = $srv_entry->get_text;
                                                    $command = "$svrneve".":"."$fullfile";
                                                    $LOAD_WINDOW->show_all();
                                                    set_HUBcredentials();
                                                    push @work_q, $command;
                                                    push @work_q, "upload";
                                                    push @work_q, ++$n;
                                                    }else{err_dialog("No server or file selected! \n Please select a server, and then a file to upload!");}
                                                   });

  my $adm_button = Gtk3::Button->new_from_stock('gtk-srminst');
  $adm_button->set_label("Create Admin user");
  $adm_button->signal_connect( "clicked" => \&srm_install); #TODO
  #my $update_button = Gtk3::Button->new_from_stock('gtk-updagent');
  #$update_button->set_label("Update Agents");
  #$update_button->signal_connect( "clicked" => \&update); #TODO
  my $situations_button = Gtk3::Button->new_from_stock('gtk-situations');
  $situations_button->set_label("Monitoring Situations");
  $situations_button->signal_connect( "clicked" => sub {
                                                    if($srv_entry->get_text){
                                                    $scrolled->set_size_request (500, 200);
                                                    $sit_info="";
                                                    $LOAD_WINDOW->show_all();
                                                    set_HUBcredentials();
                                                    my $svrneve = $srv_entry->get_text;
                                                    my $agentneve1 = &get_os_agentname($svrneve);
                                                    my $agentneve2 = &get_bc_agentname($svrneve);
                                                    my $command = "/opt/IBM/ITM/bin/tacmd listsit -m $agentneve1";
                                                    push @work_q, $command;
                                                    push @work_q, "sit_info";
                                                    push @work_q, ++$n;
                                                    $command = "/opt/IBM/ITM/bin/tacmd listsit -m $agentneve2";
                                                    push @work_q, $command;
                                                    push @work_q, "sit_info";
                                                    push @work_q, ++$n;
                                                    }else{err_dialog("ERROR, invalid server name !!!");}
                                                   });

  $upl_box->add( $browse_button );
  $upl_box->add( $upload_button );
  $upl_box->add( $situations_button );
  $upl_box->add($adm_button);
  #$upl_box->add($update_button);

  $hbox->pack_start( $frame, 1, 1, 10 );
  $hbox->pack_start( $stbinfo_label, 1, 1, 10 );
  $hbox->pack_start( $frame2, 1, 1, 10 );

   my $icon = 'TivBau.png';
    if ( -e $icon ) {
      my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
      my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
      $twin->set_icon($transparent);
    }

  return $twin;
}
sub open_callback {
	my $open_dialog = Gtk3::FileChooserDialog->new('Pick a file', 
						$main_window,
						'open',
						('gtk-cancel', 'cancel', 
						'gtk-open', 'accept'));
	$open_dialog->set_local_only(0);
	$open_dialog->set_modal(1);
	$open_dialog->signal_connect('response' => \&open_response_cb);
	$open_dialog->show();
}
sub open_response_cb {
	my ($dialog, $response_id) = @_;
	my $open_dialog = $dialog;
	if ($response_id eq 'accept') {
		print "accept was clicked \n";		
		$fullfile = $open_dialog->get_filename();
		print "Selected $fullfile file to be uploaded.";
		print "\n";
                $dialog->destroy();
        }
	elsif ($response_id eq 'cancel') {
		print "cancelled: Gtk3::FileChooserAction::OPEN \n";
		$dialog->destroy();
	}
}

sub set_up_srvinf_labels {
  my $os = shift;
  my $bc = shift;
  my $tad = shift;
  my $srm = shift;
  my $stb = shift;
  my $sit = shift;
  $SRVINF_tad4d = $tad;
  $SRVINF_srm = $srm;
  $SRVINF_os = $os;
  $SRVINF_bc = $bc;
  $SRVINF_stb = $stb;
  $SRVINF_sit = $sit;
}

sub create_completion_model {
  my $liststore = Gtk3::ListStore->new('Glib::String');
  my $iter = $liststore->append;
  my $flname = "./Servers.txt";
  if (!(-e $flname)){
  `touch Servers.txt`;
  }
  open( my $flh => $flname) || die "Cannot open $flname: $!";
  while(my $line = <$flh>) {
    chomp $line;
    $iter = $liststore->append;
    $liststore->set( $iter, 0, "$line" );
  }
  close($flh);
  
  return $liststore;
}
############################################################################################

#Agent packager Assistant related subs######################################################
sub on_apply_clicked
{
    set_HUBcredentials();
    $LOAD_WINDOW->show_all();
    push @work_q, $cmdtext;
    push @work_q, "agent_pkg";
    push @work_q, ++$n;

    print "The 'Apply' button has been clicked.\n Now command will run on hub. \n";
}

sub populate_box {
    my @words;
    my $filename = 'HostType.txt';
    open(my $fh, '<:encoding(UTF-8)', $filename)
      or die "Could not open file '$filename' $!";
     
    while (my $row = <$fh>) {
      chomp $row;
      push (@words, $row);
    }
    foreach my $item(@words) {
      my ($i,$j)= split(/\|/, $item);
      $HostTypes{$i} = $j;
    }
    #print Dumper \%HostTypes;
    @HostTypekeys = keys %HostTypes;
    @HostTypekeys = sort @HostTypekeys;
    foreach my $key(@HostTypekeys) {
      $oscb->append_text( $key );
    }
}
sub create_assistant{
  $assistant = Gtk3::Assistant->new();
  $assistant->set_title('Assistant');
  $assistant->set_default_size(450, -1);
  $assistant->signal_connect('apply' => sub {on_apply_clicked});
  $assistant->signal_connect('cancel' =>  \&Gtk3::Widget::hide_on_delete);
  $assistant->signal_connect('close' =>  \&Gtk3::Widget::hide_on_delete);
  $assistant->signal_connect('delete_event' =>  \&Gtk3::Widget::hide_on_delete);

  my $box = Gtk3::Box->new('vertical', 0);
  $assistant->append_page($box);
  $assistant->set_page_type($box, 'intro');
  $assistant->set_page_title($box, "Introduction");
  my $label = Gtk3::Label->new("We will guide you trough the steps of creating an OS agent package. This version of TivBAU tool only provides OS+BC agent packages. Later on, support will be added to provide package for all agent types.");
  $label->set_line_wrap(1);
  $box->pack_start($label, 1, 1, 0);
  $assistant->set_page_complete($box, 1);

  my $box2 = Gtk3::Box->new('vertical', 0);
  $assistant->append_page($box2);
  $assistant->set_page_type($box2, 'content');
  $assistant->set_page_title($box2, "Customer Selection");
  my $label1 = Gtk3::Label->new("Select a customer! \nIf the customer is not in the list contact jfekete1\@hu.ibm.com for support.");
  $label1->set_line_wrap(1);
  $cuscb = Gtk3::ComboBoxText->new;
  %CusTypes = (
        "Samlink Ab Oy"  => "sml",
        "Mela (Maatalousyrittajien elakelaitos)" => "mel",
        "Alko Inc"  => "alk",
        "Algol Chemicals Oy"  => "alg",
        "IBM"  => "ibm",
        "Itella (Logistics Finland)"  => "itj",
        "Finnair Oyj"  => "fin",
        "Vaasan and Vaasan"  => "vnv",
        "Yap Solutions"  => "yap",
        "Elisa Oyj"  => "eli",
        "Berner Oy"  => "ber",
        "SUOMEN VILJAVA"  => "svl",
        "Lemminkainen Oy"  => "lem",
        "Metso Automation"  => "mea",
        "SLO Oy"  => "slo",
        "Helsingin Kaupunki"  => "hki",
  );
  @CusTypekeys = keys %CusTypes;
  @CusTypekeys = sort @CusTypekeys;
  foreach my $kiy(@CusTypekeys) {
    $cuscb->append_text( $kiy );
  }
  $cuscb->signal_connect(
    changed => sub {
        my $text = $cuscb->get_active_text;
        $custype = $CusTypes{$text};
        return unless ( $text );
        print "$custype";
        print "\n";
        $assistant->set_page_complete($box2, 1);
    }
  );

  $box2->pack_start($label1, 1, 1, 0);
  $box2->pack_start($cuscb, 1, 1, 0);
  $assistant->set_page_complete($box2, 0);

  my $complete = Gtk3::Box->new('vertical', 0);
  $assistant->append_page($complete);
  $assistant->set_page_type($complete, 'content');
  $assistant->set_page_title($complete, "Select OS type");
  my $label2 = Gtk3::Label->new("Select Operating system type! \nIf the OS type is not in the list contact jfekete1\@hu.ibm.com for support.");
  $label2->set_line_wrap(1);
  $oscb = Gtk3::ComboBoxText->new;
  populate_box();
  $oscb->signal_connect(
    changed => sub {
        my $text = $oscb->get_active_text;
        $hosttype = $HostTypes{$text};
        if($text=~"AIX" || $text=~"UX"){$product = "ux-aix";}
        if($text=~"Linux"){$product = "lz-lin";}
        if($text=~"Windows" || $text=~"WINNT"){$product = "nt-win";}
        return unless ( $text );
        print $HostTypes{$text};
        print "\n";
        $cmdtext = "/tivrepos/AgentPackager/AgentPackager/itm_create_agent_package.ksh -c $custype -p $product -t $hosttype";
        $label3->set_text( "Are you sure you want to run the following command on HUBTEMS? \n\n $cmdtext \n " );
        $assistant->set_page_complete($complete, 1);
    }
  );
  $complete->pack_start($label2, 1, 1, 0);
  $complete->pack_start($oscb, 1, 1, 0);

  my $box3 = Gtk3::Box->new('vertical', 0);
  $assistant->append_page($box3);
  $assistant->set_page_type($box3, 'confirm');
  $assistant->set_page_title($box3, "Confirm");
  $label3 = Gtk3::Label->new("Are you sure you want to run the following command on HUBTEMS? \n./itm_create_agent_package.ksh -c unknown -p unknown -t unknown \n ");
  $label3->set_line_wrap(1);
  $box3->pack_start($label3, 1, 1, 0);
  $assistant->set_page_complete($box3, 1);

  my $box4 = Gtk3::Box->new('vertical', 0);
  $assistant->append_page($box4);
  $assistant->set_page_type($box4, 'summary');
  $assistant->set_page_title($box4, "Download Package");
  my $label4 = Gtk3::Label->new("Check ./packages directory for the downloaded agent package.");
  $label4->set_line_wrap(1);
  $box4->pack_start($label4, 1, 1, 0);
  $assistant->set_page_complete($box4, 1);

  my $icon = 'TivBau.png';
  if ( -e $icon ) {
    my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
    my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
    $assistant->set_icon($transparent);
  }
}
############################################################################################


#Main function to create main menu #########################################################
sub scp_qlr {
  my $qlr = "158.98.130.3";
  my $ssh = Net::OpenSSH->new($qlr, user => $username, password => $password);
  $ssh->scp_get({glob => 1}, '/home/huh94608/EUT4DIFIN.tar', "$tarfile")
    or die "scp failed: " . $ssh->error;
}
sub ftp_upl {

  my $flname = shift;
  my $fnm;
  my @fileptharray = split('/',$flname);
  $fnm = pop @fileptharray;

        my $ftp = Net::FTP->new("bldgsa.ibm.com", Debug => 0)
          or die "Cannot connect to some.host.name: $@";
        $ftp->login("anonymous",'-anonymous@')
          or die "Cannot login ", $ftp->message;
        $ftp->cwd("/projects/s/swdata/ftp/disconnected")
          or die "Cannot change working directory ", $ftp->message;
        $ftp->put("$flname", "$fnm")
          or die "get failed ", $ftp->message;
        $ftp->quit;
}

sub do_appwindow {
  register_stock_icons();

  $main_window = Gtk3::Window->new;
  $main_window->set_title('Tivoli BAU tool for Fi Shared');
  #$main_window->signal_connect( destroy => sub { Gtk3->main_quit } );
  $main_window->signal_connect (delete_event => sub {
                if (@work_q) {
                        print "can't quit, busy...\n";
                } else {
                        Gtk3->main_quit;
                        $deathflag = 1;
                }
                # either way, don't destroy the window -- we'll do that
                # by hand below.
                return 1;
        });
  $main_window->set_default_size( 640, 480 );


  my $table = Gtk3::Grid->new;
        $main_window->add($table);

        # Create the menubar and toolbar Open helyett SEND MAIL TO TASKID!!!

        my $action_group = Gtk3::ActionGroup->new('AppWindowActions');
        my $open_action  = Gtk3::Action->new(
            [ 'Open', '_Open', 'Open a file', 'gtk-open' ] );
        $action_group->add_action($open_action);
        $action_group->add_actions( \@entries, undef );

        my $ui = Gtk3::UIManager->new();
        $ui->insert_action_group( $action_group, 0 );
        $main_window->add_accel_group( $ui->get_accel_group );
        my $ui_info = get_ui();
        $ui->add_ui_from_string( $ui_info, length($ui_info) );

  # Create main screen buttons and add functions
  my $button1 = Gtk3::Button->new_from_stock('gtk-serverinfo');
  $button1->set_size_request( 300, 50 );
  $button1->set_label("Server Information");
  $button1->signal_connect( "clicked" => \&server_info);


  my $button2 = Gtk3::Button->new_from_stock('gtk-infrastatus');
  $button2->set_size_request( 300, 50 );
  $button2->set_label("Infrastructure Status");
  $button2->signal_connect( "clicked" => \&infra_status);#sub{$LOAD_WINDOW->show_all();infra_status();});


  my $button3 = Gtk3::Button->new_from_stock('gtk-agentpackage');
  $button3->set_size_request( 300, 50 );
  $button3->set_label("Create Agent Package");
  $button3->signal_connect( "clicked" => \&agent_package); #sub{agent_package$assistant->show_all();});


  my $button4 = Gtk3::Button->new_from_stock('gtk-usefullinks');
  $button4->set_size_request( 300, 50 );
  $button4->set_label("Useful links");
  $button4->signal_connect( "clicked" => \&useful_links);

  my $button5 = Gtk3::Button->new_from_stock('gtk-tad4dbravo');
  $button5->set_size_request( 300, 50 );
  $button5->set_label("Upload TAD4D results to Bravo");
  $button5->signal_connect( "clicked" => sub {
                                                    #create dir if doesn't exist
                                                    if (-d $tad4dresDIR) {
                                                        print "$tad4dresDIR exists";
                                                    } else {
                                                        mkdir $tad4dresDIR;
                                                    }
                                                    my $tad4d_agent = "";
                                                    my $parancs1 = "/opt/IBM/ITM/bin/tacmd executecommand -m $tad4d_agent -c \"rm -f /tmp/*EU*\" -v -o -e";
                                                    my $parancs2 = "/opt/IBM/ITM/bin/tacmd executecommand -m $tad4d_agent -c \"/usr/bin/perl /home/huh94608/Tad4dreport.pl\" -v -o -e";
                                                    my $parancs3 = "/opt/IBM/ITM/bin/tacmd executecommand -m $tad4d_agent -c \"tar -cvf /home/huh94608/EUT4DIFIN.tar /tmp/EUT4DIFIN_*\" -v -o -e";
                                                    my $parancs4 = "/opt/IBM/ITM/bin/tacmd executecommand -m $tad4d_agent -c \"chown  huh94608:staff /home/huh94608/EUT4DIFIN.tar\" -v -o -e";
                                                    my $parancs5 = "download tad4d with scp...";
                                                    my $parancs6 = "uploading tad4d results with trough FTP...";
                                                    
                                                    $LOAD_WINDOW->show_all();
                                                    set_HUBcredentials();
                                                    push @work_q, $parancs1;
                                                    push @work_q, "tad4dbravo";
                                                    push @work_q, ++$n;
                                                    push @work_q, $parancs2;
                                                    push @work_q, "tad4dbravo2";
                                                    push @work_q, ++$n;
                                                    push @work_q, $parancs3;
                                                    push @work_q, "tad4dbravo3";
                                                    push @work_q, ++$n;
                                                    push @work_q, $parancs4;
                                                    push @work_q, "tad4dbravo4";
                                                    push @work_q, ++$n;
                                                    push @work_q, $parancs5;
                                                    push @work_q, "scp_tad4d";
                                                    push @work_q, ++$n;
                                                    push @work_q, $parancs6;
                                                    push @work_q, "ftp_tad4d";
                                                    push @work_q, ++$n;
                                              });


  #Attach widgets to main panel
      $table->attach( $ui->get_widget('/MenuBar'), 0, 0, 1, 1 ); 
      $table->attach( $ui->get_widget('/ToolBar'), 0, 1, 1, 1 );
      $table->attach( $button1, 1, 2, 1, 1 );
      $table->attach( $button2, 1, 3, 1, 1 );
      $table->attach( $button3, 1, 4, 1, 1 );
      $table->attach( $button4, 1, 5, 1, 1 );
      $table->attach( $button5, 1, 6, 1, 1 );

  #Set icon
  my $icon = 'TivBau.png';
  if ( -e $icon ) {
    my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($icon);
    my $transparent = $pixbuf->add_alpha( 1, 0xff, 0xff, 0xff );
    $main_window->set_icon($transparent);
  }

  $SERVERINFO_WINDOW = &create_srvinf_window();

  $main_window->show_all;
}
############################################################################################



$main_window->destroy;
$thread->join;
