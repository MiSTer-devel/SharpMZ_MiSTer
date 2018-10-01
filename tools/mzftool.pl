#! /usr/bin/perl
#########################################################################################################
##
## Name:            mzftool.pl
## Created:         August 2018
## Author(s):       Philip Smart
## Description:     Sharp MZ series MZF (Sharp Tape File)  management tool.
##                  This script identifies the type of MZF file and can add or delete headers as required.
##                  Useful for seperating MZF compilations into Basic/Pascal/Machine Code etc.
##                  Also useful to add headers to homegrow machine code programs.
##
## Credits:         
## Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
##
## History:         August 2018   - Initial script written.
##
#########################################################################################################
## This source file is free software: you can redistribute it and#or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This source file is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################################################

# Title and Versioning.
#
$TITLE                  = "MZF Tool";
$VERSION                = "0.1";
$VERSIONDATE            = "25.09.2018";

# Global Modules.
#
#use strict
use Getopt::Long;
use IO::File;
use File::stat;
use File::Copy;
use Time::localtime;
use POSIX qw(tmpnam);
use Env qw(KPLUSHOME3 SYBASE SYBASE_OCS DSQUERY);
use sigtrap qw(die normal-signals);

# Error return codes.
#
$ERR_BADFILENAME        = 1;
$ERR_BADFILEDATA        = 2;
$ERR_BADFILECREATE      = 3;
$ERR_BADFUNCARGS        = 4;
$ERR_BADSYSCALL         = 5;
$ERR_BADCHECK           = 6;
$ERR_BADENV             = 7;
$ERR_SYBSERVER          = 8;
$ERR_BADARGUMENTS       = 9;

# Run-time constants.
#
$PROGNAME               = $0;

# Run-time globals. Although in Perl you can just specify variables, keeping with most
# high-order languages it is good practise to  specify non-local variables in a global header
# which aids visual variable tracking etc.
#
$dbh                    = 0;                        # Handle to a Sybase object.
$logh                   = 0;                        # Handle to open log file.
$logName                = "";                       # Temporary name of log file.
$logMode                = "terminal";               # Default logging mode for logger.


# Configurables!!
#
$SENDMAIL               = "/usr/lib/sendmail -t";
@errorMailRecipients    = ( "philip.smart\@net2net.org" );
$errorMailFrom          = "error\@localhost";
$errorMailSubject       = "MZF Tool Errors...";
$PERL                   = "perl";
$PERLFLAGS              = "";


##################################################################################
# GENERIC SUB-ROUTINES
##################################################################################

# Sub-routine to close the log file and email its contents to required participants.
#
sub logClose
{
    # Locals.
    local( $idx, $line, @mailRecipients, $mailFrom, $mailSubject, $mailHeader );

    # No point closing log if one wasnt created!!
    #
    if($logName eq "" || $sendEmail == 0)
    {
        return;
    }

    # Back to beginning of file, to copy into email.
    #
    seek($logh, 0, 0);

    # Build up an email to required recipients and send.
    #
    open(SENDMAIL, "|$SENDMAIL") or die "Cannot open $SENDMAIL: $!";
    for($idx=0; $idx < @errorMailRecipients; $idx++)
    {
        print SENDMAIL "To: $errorMailRecipients[$idx]\n";
    }
    print SENDMAIL "Reply-to: $errorMailFrom\n";
    print SENDMAIL "From: $errorMailFrom\n";
    print SENDMAIL "Subject: $errorMailSubject\n";
    print SENDMAIL "Content-type: text/plain\n\n";
    while( $line = <$logh> )
    {
        chomp($line);
        print SENDMAIL "$line\n";
    }
    close(SENDMAIL);

    # Delete the logfile, not needed.
    #
    unlink($logName) or die "Couldn't unlink Error File $logName : $!";
}

# Function to write a message into a log file. The logfile is a temporary buffer, used
# to store all messages until program end. Upon completion, the buffer is emailed to required
# participants.
#
sub logWrite
{
    # Get parameters, define locals.
    local( $mode, $text ) = @_;
    local( $date );

    # Get current date and time for timestamping the log message.
    #
    $date = `date +'%Y.%m.%d %H:%M:%S'`;
    chomp($date);

    # In terminal mode (=interactive mode), always log to STDOUT.
    #
    if($logMode eq "terminal")
    {
        if(index($mode, "ND") == -1)
        {
            print "$date ";
        }
        print "$text";
        if(index($mode, "NR") == -1)
        {
            print "\n";
        }

        # Die if required.
        #
        if (index($mode, 'die') != -1)
        {
            print "$date Terminating at program request.\n";
            exit 1;
        }
        return;
    }

    # If the logfile hasnt been opened, open it.
    #
    if($logName eq "")
    {
        # Try new temporary filenames until we get one that doesnt already exist.
        do {
            $logName = tmpnam();
        } until $logh = IO::File->new($logName, O_RDWR|O_CREAT|O_EXCL);

        # Automatically flush out log.
        $logh->autoflush(1);

        # Only send email if we explicitly die.
        #
        $sendEmail = 0;

        # Install an atexit-style handler so that when we exit or die,
        # we automatically dispatch the log.
        END { logClose($logh, $logName); }
    }

    # Print to log with date and time stamp.
    #
    print $logh "$date $text\n";

    # Print to stdout for user view if in debug mode.
    #
    if($debugMode > 0)
    {
        print "$date $text\n";
    }

    # If requested, log termination message and abort program.
    #
    if (index($mode, 'die') != -1)
    {
        print $logh "$date Terminating at program request.\n";
        $sendEmail = 1;
        exit 1;
    }
}

# Sub-routine to truncate whitespace at the front (left) of a string, returning the
# truncated string.
#
sub cutWhiteSpace
{
    local( $srcString ) = @_;
    local( $c, $dstString, $idx );
    $dstString = "";

    for($idx=0; $idx < length($srcString); $idx++)
    {
        # If the character is a space or tab, delete.
        #
        $c = substr($srcString, $idx, 1);
        if(length($dstString) == 0)
        {
            if($c ne " " && $c ne "\t")
            {
                $dstString = $dstString . $c;
            }
        } else
        {
            $dstString = $dstString . $c;
        }
    }
    return($dstString);
}

# Perl trim function to remove whitespace from the start and end of the string
#
sub trim($)
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

# Left trim function to remove leading whitespace
#
sub ltrim($)
{
    my $string = shift;
    $string =~ s/^\s+//;
    return $string;
}

# Right trim function to remove trailing whitespace
#
sub rtrim($)
{
    my $string = shift;
    $string =~ s/\s+$//;
    return $string;
}

# Sub-routine to test if a string is empty, and if so, replace
# with an alternative string. The case of the returned string
# can be adjusted according to the $convertCase parameter.
#
sub trString
{
    local( $tstString, $replaceString, $convertCase ) = @_;
    local( $dstString );

    $tstString=cutWhitespace($tstString);
    $replaceString=cutWhitespace($replaceString);
    if($tstString eq "")
    {
        $dstString = $replaceString;
    } else
    {
        $dstString = $tstString;
    }

    # Convert to Lower Case?
    #
    if($convertCase == 1)
    {
        $dstString =~ lc($dstString);
    }
    # Convert to Upper Case?
    #
    elsif($convertCase == 2)
    {
        $dstString =~ uc($dstString);
    }
    return($dstString);
}

# Sub-routine to test if a numeric is empty, and if so, set to a
# given value.
#
sub trNumeric
{
    local( $tstNumber, $replaceNumber ) = @_;
    local( $dstNumber );

    if(!defined($tstNumber) || $tstNumber eq "" || cutWhitespace($tstNumber) eq "")
    {
        $dstNumber = $replaceNumber;
    } else
    {
        $dstNumber = $tstNumber;
    }

    return($dstNumber);
}

# Function to look at a string and decide wether its contents
# indicate Yes or No. If the subroutine cannot determine a Yes,
# then it defaults to No.
#
sub yesNo
{
    local( $srcString ) = @_;
    local( $dstString, $yesNo );
    $yesNo = "N";

    $dstString=lc(cutWhiteSpace($srcString));
    if($dstString eq "y" || $dstString eq "yes" || $dstString eq "ye")
    {
        $yesNo = "Y";
    }
    return( $yesNo );
}

# Sub-routine to encrypt an input string, typically a password,
# using the Collateral Management Encrypt utility.
#
sub encrypt
{
    local( $srcPasswd ) = @_;
    local( $encPasswd );
    $encPasswd="";

    # Call external function to perform the encryption.
    #
    if($srcPasswd ne "")
    {
        $encPasswd=`$PROG_ENCRYPT -p $srcPasswd 2>&1`;
        chomp($encPasswd);
    }
    return($encPasswd);
}

# Sub-routine to test if a string is empty, and if so, replace
# with an alternative string. The case of the returned string
# can be adjusted according to the $convertCase parameter.
#
sub testAndReplace
{
    local( $tstString, $replaceString, $convertCase ) = @_;
    local( $dstString );
#printf("Input:$tstString,$replaceString\n");
    $tstString=cutWhiteSpace($tstString);
    $replaceString=cutWhiteSpace($replaceString);
    if($tstString eq "")
    {
        $dstString = $replaceString;
    } else
    {
        $dstString = $tstString;
    }

    # Convert to Lower Case?
    #
    if($convertCase == 1)
    {
        $dstString =~ lc($dstString);
    }
    # Convert to Upper Case?
    #
    elsif($convertCase == 2)
    {
        $dstString =~ uc($dstString);
    }
#printf("Output:$dstString:\n");
    return($dstString);
}

# Subroutine to generate a unique name by adding 2 digits onto the end of it. A hash of existing
# names is given to compare the new value against.
#
sub getUniqueName
{
    local( $cnt, $uniqueName ) = ( 0, "" );
    local( $startName, $maxLen, $usedNames ) = @_;

    # Go through looping, adding a unique number onto the end of the string, then looking it
    # up to see if it already exists.
    #
    $uniqueName = substr($startName, 0, $maxLen);
    while(defined($$usedNames{$uniqueName}))
    {
        $uniqueName = substr($uniqueName, 0, $maxLen-2) . sprintf("%02d", $cnt);
        $cnt++;
        if($cnt > 99)
        {
            logWrite("die", "Unique identifier > 99: $uniqueName");
        }
    }

    # Return unique name.
    #
    return($uniqueName);
}

# Sub-routine to process command line arguments. New style POSIX argument format used.
#
sub argOptions
{
    local ( $writeUsage, $msg, $exitCode ) = @_;

    if( $writeUsage == 1 )
    {
        print STDOUT "Usage: $PROGNAME <commands> [<options>]                                     \n";
        print STDOUT "           commands= --help                                                |\n";
        print STDOUT "                     --verbose                                             |\n";
        print STDOUT "                     --command=<IDENT|ADDHEADER|DELHEADER>                 |\n";
        print STDOUT "                     --mzffile=<file>          {IDENT|ADDHEADER|DELHEADER} |\n";
        print STDOUT "                     --srcfile=<file>                        {ADDHEADER}   |\n";
        print STDOUT "                     --dstfile=<file>                        {DELHEADER}   |\n";
        print STDOUT "                     --filename=<name of tape file>          (ADDHEADER}   |\n";
        print STDOUT "                     --loadaddr=<addr tape should load @>    (ADDHEADER}   |\n";
        print STDOUT "                     --execaddr=<auto exec addr>             (ADDHEADER}   |\n";
        print STDOUT "                     --tapetype=<1 byte type value>          (ADDHEADER}   |\n";
        print STDOUT "                     --comment=<comment string>              (ADDHEADER}   |\n";
        print STDOUT "           options = --debug=<1=ON, 0=OFF>\n";
        print STDOUT "\n";
    }
    if($msg ne "")
    {
        print STDOUT "Error: $msg\n";
    }
    exit( $exitCode );
}


##################################################################################
# END OF GENERIC SUB-ROUTINES
##################################################################################


##################################################################################
#
# MAIN PROGRAM
#
##################################################################################

# Locals.
#
local( $time, $date, $mzfExists, $a_mromExists, $b_mromExists, $k_mromExists, $m7_mromExists, $m8_mromExists, $m12_mromExists, $m20_mromExists,
       $a_80c_mromExists, $b_80c_mromExists, $k_80c_mromExists, $m7_80c_mromExists, $m8_80c_mromExists, $m12_80c_mromExists, $m20_80c_mromExists,
       $mzf_type, $mzf_filename, $mzf_size, $mzf_loadaddr, $mzf_execaddr, $mzf_comment);

# Get current time and date.
#
$time = `date +'%H:%M:%S'`;
$date = `date +'%d.%m.%Y'`;
chomp($time);
chomp($date);

# Sign-on.
#
print STDOUT "$TITLE (v$VERSION) \@ ${VERSIONDATE}\n\n";

# Parse arguments and put into required variables.
#
$verbose = 0;
$fileName = "";
$s_loadAddr = "";
$s_execAddr = "";
$s_tapeType = "";
$comment = "";
GetOptions( "debug=n"               => \$debugMode,            # Debug Mode?
            "verbose"               => \$verbose,              # Show details?
            "mzffile=s"             => \$mzfFile,              # MZF file.
            "dstfile=s"             => \$dstFile,              # Destination file (for header removal).
            "srcfile=s"             => \$srcFile,              # Source file (for header adding).
            "filename=s"            => \$fileName,             # Filename to insert into header.
            "loadaddr=s"            => \$s_loadAddr,           # Tape load address.
            "execaddr=s"            => \$s_execAddr,           # Tape execution address.
            "tapetype=s"            => \$s_tapeType,           # Tape type (ie. 01 = Machine Code).
            "comment=s"             => \$comment,              # Tape comment string.
            "command=s"             => \$command,              # Command to execute.
            "help"                  => \$help,                 # Help required on commands/options?
          );

# Help required?
#
if(defined($help))
{
    argOptions(1, "");
} 

# Convert number arguments from string to decimal.
#
if($s_loadAddr ne "")
{
    $loadAddr = oct($s_loadAddr);
}
if($s_execAddr ne "")
{
    $execAddr = oct($s_execAddr);
}
if($s_tapeType ne "")
{
    $tapeType = oct($s_tapeType);
}

# Verify command.
#
if($command eq "IDENT" || $command eq "ADDHEADER" || $command eq "DELHEADER")
{
    1;
}
else
{
    argOptions(1, "Illegal command given on command line:$command.\n",$ERR_BADARGUMENTS);
}

# Check that the additional parameters have been provided for the ADDHEADER command.
if($command eq "ADDHEADER" && ($fileName eq "" || !defined($loadAddr) || !defined($execAddr) || !defined($tapeType)) )
{
    argOptions(3, "ADDHEADER command requires the following parameters to be provided: --filename, --loadaddr, --execaddr, --tapetype\n",$ERR_BADARGUMENTS);
}

# For ident or delete header commands, we need to open and read the mzf file.
#
if(($command eq "IDENT" || $command eq "DELHEADER") && defined($mzfFile) && $mzfFile ne "")
{
    # If defined, can we open it?
    #
    if( ! open(MZFFILE, "<".$mzfFile) )
    {
        argOptions(1, "Cannot open MZF file: $mzfFile.\n",$ERR_BADFILENAME);
    }

    @MZF = ();
    binmode(MZFFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <MZFFILE> )
    {
        $MZF[$cnt] = $byte;
        $cnt++;
    }
    $MZF_SIZE = $cnt;

    # Once the MZF is in memory, analyse the details and output.
    #
    $mzf_header = pack('a'x128, @MZF);
    ($mzf_type, $mzf_filename, $mzf_size, $mzf_loadaddr, $mzf_execaddr, $mzf_comment) = unpack 'c1 a17 v4 v4 v4 a104', $mzf_header;
    $mzf_filename =~ s/\r|\n//g;

    # Output detail if requested.
    #
    if($verbose)
    {
        printf STDOUT "File Name          : %s\n",   $mzf_filename;
        printf STDOUT "File Type          : %02x\n", $mzf_type;
        printf STDOUT "File Size          : %04x\n", $mzf_size;
        printf STDOUT "File Load Address  : %04x\n", $mzf_loadaddr;
        printf STDOUT "File Exec Address  : %04x\n", $mzf_execaddr;
        printf STDOUT "Comment            : %s\n",   $mzf_comment;
    }

    # For the DELHEADER command, a destination needs to be provided and opened.
    if($command eq "DELHEADER" && defined($dstFile) && $dstFile ne "")
    {
        if( ! open(DSTFILE, ">".$dstFile) )
        {
            argOptions(1, "Cannot open the destination file: $dstFile.\n",$ERR_BADFILENAME);
        }
    }
} 
elsif($command eq "ADDHEADER" && defined($mzfFile) && $mzfFile ne "") 
{
    # If defined, can we create it?
    #
    if( ! open(MZFFILE, ">".$mzfFile) )
    {
        argOptions(1, "Cannot create MZF file: $mzfFile.\n",$ERR_BADFILENAME);
    }

    # For this command, a source file needs to exist and opened.
    if(defined($srcFile) && $srcFile ne "")
    {
        if( ! open(SRCFILE, "<".$srcFile) )
        {
            argOptions(1, "Cannot open the source file: $srcFile.\n",$ERR_BADFILENAME);
        }

        @SRC = ();
        binmode(SRCFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <SRCFILE> )
        {
            $SRC[$cnt] = $byte;
            $cnt++;
        }
        $SRC_SIZE = $cnt;
    }
}
else
{
    argOptions(2, "No MZF file given, use --mzffile=<file>.\n");
}

# Process command as necessary.
#
if($command eq "ADDHEADER")
{
    # Build the header based on given information and size of src file.
    $mzf_size = scalar @SRC;
    $mzf_type = $tapeType; # For exit code.
    $mzf_header  = pack('c1 a17 v v v', $tapeType, $fileName, $mzf_size, $loadAddr, $execAddr);
    $mzf_header .=  pack('a104', $comment) ;

    # Store in file.
    print MZFFILE $mzf_header;
    
    # Now add the source data.
    foreach my $byte (@SRC) { print MZFFILE $byte; }

    # All done.
    close MZFFILE;

    # Output detail if requested.
    #
    if($verbose)
    {
        printf STDOUT "File Name          : %s\n",   $fileName;
        printf STDOUT "File Type          : %02x\n", $tapeType;
        printf STDOUT "File Size          : %04x\n", $mzf_size;
        printf STDOUT "File Load Address  : %04x\n", $loadAddr;
        printf STDOUT "File Exec Address  : %04x\n", $execAddr;
        printf STDOUT "Comment            : %s\n",   $comment;
    }
}
# For delete, simply write out the tape contents less the header (first 128 bytes).
elsif($command eq "DELHEADER")
{
    my $cnt = 0;
    foreach my $byte (@MZF) { if($cnt++ >= 128) { print DSTFILE $byte; } }
    close DSTFILE;
}

# Exit code is the type of MZF file.
exit $mzf_type;
