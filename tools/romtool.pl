#! /usr/bin/perl
#########################################################################################################
##
## Name:            romtool.pl
## Created:         July 2018
## Author(s):       Philip Smart
## Description:     Sharp MZ series rom management tool.
##                  This script takes a set of roms and creates the necessary MIF image for embedding
##                  into the FPGA during compilation.
##                  It can also be used to create a binary image if needed for upload via the HPS.
##
## Credits:         
## Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
##
## History:         July 2018   - Initial script written.
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
$TITLE                  = "ROM Tool";
$VERSION                = "0.5";
$VERSIONDATE            = "12.10.2018";

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
$errorMailSubject       = "Rom tool patch Errors...";
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
        print STDOUT "                     --command=<64KRAM|MONROM|CGROM|KEYMAP>                |\n";
        print STDOUT "                     --binout=<file>                                       |\n";
        print STDOUT "                     --mifout=<file>                                       |\n";
        print STDOUT "                     --a_mrom=<file>                                       |\n";
        print STDOUT "                     --b_mrom=<file>                                       |\n";
        print STDOUT "                     --c_mrom=<file>                                       |\n";
        print STDOUT "                     --k_mrom=<file>                                       |\n";
        print STDOUT "                     --7_mrom=<file>                                       |\n";
        print STDOUT "                     --8_mrom=<file>                                       |\n";
        print STDOUT "                     --12_mrom=<file>                                      |\n";
        print STDOUT "                     --20_mrom=<file>                                      |\n";
        print STDOUT "                     --a_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --b_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --c_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --k_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --7_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --8_80c_mrom=<file>                                   |\n";
        print STDOUT "                     --12_80c_mrom=<file>                                  |\n";
        print STDOUT "                     --20_80c_mrom=<file>                                  |\n";
        print STDOUT "                     --a_userrom=<file>                                    |\n";
        print STDOUT "                     --b_userrom=<file>                                    |\n";
        print STDOUT "                     --c_userrom=<file>                                    |\n";
        print STDOUT "                     --k_userrom=<file>                                    |\n";
        print STDOUT "                     --7_userrom=<file>                                    |\n";
        print STDOUT "                     --8_userrom=<file>                                    |\n";
        print STDOUT "                     --12_userrom=<file>                                   |\n";
        print STDOUT "                     --20_userrom=<file>                                   |\n";
        print STDOUT "                     --a_fdcrom=<file>                                     |\n";
        print STDOUT "                     --b_fdcrom=<file>                                     |\n";
        print STDOUT "                     --c_fdcrom=<file>                                     |\n";
        print STDOUT "                     --k_fdcrom=<file>                                     |\n";
        print STDOUT "                     --7_fdcrom=<file>                                     |\n";
        print STDOUT "                     --8_fdcrom=<file>                                     |\n";
        print STDOUT "                     --12_fdcrom=<file>                                    |\n";
        print STDOUT "                     --20_fdcrom=<file>                                    |\n";
        print STDOUT "                     --mzffile=<file>                                      |\n";
        print STDOUT "                     --ramchecker=<file>                                   |\n";
        print STDOUT "                     --a_cgrom=<file>                                      |\n";
        print STDOUT "                     --b_cgrom=<file>                                      |\n";
        print STDOUT "                     --c_cgrom=<file>                                      |\n";
        print STDOUT "                     --k_cgrom=<file>                                      |\n";
        print STDOUT "                     --7_cgrom=<file>                                      |\n";
        print STDOUT "                     --12_cgrom=<file>                                     |\n";
        print STDOUT "                     --20_cgrom=<file>                                     |\n";
        print STDOUT "                     --a_keymap=<file>                                     |\n";
        print STDOUT "                     --b_keymap=<file>                                     |\n";
        print STDOUT "                     --c_keymap=<file>                                     |\n";
        print STDOUT "                     --k_keymap=<file>                                     |\n";
        print STDOUT "                     --7_keymap=<file>                                     |\n";
        print STDOUT "                     --8_keymap=<file>                                     |\n";
        print STDOUT "                     --12_keymap=<file>                                    |\n";
        print STDOUT "                     --20_keymap=<file>                                    |\n";
        print STDOUT "           options = --debug=<1=ON, 0=OFF>\n";
        print STDOUT "\n";
    }
    if($msg ne "")
    {
        print STDOUT "Error: $msg\n";
    }
    exit( $exitCode );
}

# Subroutine to create a Memory Initialization File.
#
sub createMIF
{
    local ($Memory, $OUTPUT) = @_;
#local @Memory = @{$_[0]};
#    local $OUTPUT = $_[1];

    $addr = 0x0000;
    $depth = scalar @$Memory;
    $width = 8;

    print $OUTPUT "DEPTH = $depth;\n";
    print $OUTPUT "WIDTH = $width;\n";
    print $OUTPUT "ADDRESS_RADIX = HEX;\n";
    print $OUTPUT "DATA_RADIX = HEX;\n";
    print $OUTPUT "CONTENT BEGIN\n";

    for($addr=0; $addr < $depth; $addr+=16)
    {
        my $thisLineCount = ($depth > $addr + 16) ? 16 : $depth - $addr;
        printf $OUTPUT "%04x: ", $addr;
        $line = "";
        for(my $byteaddr=0; $byteaddr < $thisLineCount; $byteaddr++)
        {
            if($byteaddr > 0) { $line .= " "; }
            $line .= unpack("H2", @$Memory[$byteaddr + $addr]);
        }
        print $OUTPUT "$line;\n";
    }

    print $OUTPUT "END;\n";
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
GetOptions( "debug=n"               => \$debugMode,            # Debug Mode?
            "command=s"             => \$command,              # Command to execute.
            "binout=s"              => \$outFile,              # Binary output file to be created.
            "mifout=s"              => \$mifoutFile,           # MIF output file to be created.
            "a_mrom=s"              => \$modelA_mromFile,      # MZ80A Monitor ROM file.
            "b_mrom=s"              => \$modelB_mromFile,      # MZ80B Monitor ROM file.
            "c_mrom=s"              => \$modelC_mromFile,      # MZ80C Monitor ROM file.
            "k_mrom=s"              => \$modelK_mromFile,      # MZ80K Monitor ROM file.
            "7_mrom=s"              => \$model7_mromFile,      # MZ700 Monitor ROM file.
            "8_mrom=s"              => \$model8_mromFile,      # MZ800 Monitor ROM file.
            "12_mrom=s"             => \$model12_mromFile,     # MZ1200 Monitor ROM file.
            "20_mrom=s"             => \$model20_mromFile,     # MZ2000 Monitor ROM file.
            "a_80c_mrom=s"          => \$modelA_80c_mromFile,  # MZ80A Monitor 80x25 Display ROM file.
            "b_80c_mrom=s"          => \$modelB_80c_mromFile,  # MZ80B Monitor 80x25 Display ROM file.
            "c_80c_mrom=s"          => \$modelC_80c_mromFile,  # MZ80C Monitor 80x25 Display ROM file.
            "k_80c_mrom=s"          => \$modelK_80c_mromFile,  # MZ80K Monitor 80x25 Display ROM file.
            "7_80c_mrom=s"          => \$model7_80c_mromFile,  # MZ700 Monitor 80x25 Display ROM file.
            "8_80c_mrom=s"          => \$model8_80c_mromFile,  # MZ800 Monitor 80x25 Display ROM file.
            "12_80c_mrom=s"         => \$model12_80c_mromFile, # MZ1200 Monitor 80x25 Display ROM file.
            "20_80c_mrom=s"         => \$model20_80c_mromFile, # MZ2000 Monitor 80x25 Display ROM file.
            "a_userrom=s"           => \$modelA_userromFile,   # MZ80A User ROM file.
            "b_userrom=s"           => \$modelB_userromFile,   # MZ80B User ROM file.
            "c_userrom=s"           => \$modelC_userromFile,   # MZ80C User ROM file.
            "k_userrom=s"           => \$modelK_userromFile,   # MZ80K User ROM file.
            "7_userrom=s"           => \$model7_userromFile,   # MZ700 User ROM file.
            "8_userrom=s"           => \$model8_userromFile,   # MZ800 User ROM file.
            "12_userrom=s"          => \$model12_userromFile,  # MZ1200 User ROM file.
            "20_userrom=s"          => \$model20_userromFile,  # MZ2000 User ROM file.
            "a_fdcrom=s"            => \$modelA_fdcromFile,    # MZ80A FDC ROM file.
            "b_fdcrom=s"            => \$modelB_fdcromFile,    # MZ80B FDC ROM file.
            "c_fdcrom=s"            => \$modelC_fdcromFile,    # MZ80C FDC ROM file.
            "k_fdcrom=s"            => \$modelK_fdcromFile,    # MZ80K FDC ROM file.
            "7_fdcrom=s"            => \$model7_fdcromFile,    # MZ700 FDC ROM file.
            "8_fdcrom=s"            => \$model8_fdcromFile,    # MZ800 FDC ROM file.
            "12_fdcrom=s"           => \$model12_fdcromFile,   # MZ1200 User ROM file.
            "20_fdcrom=s"           => \$model20_fdcromFile,   # MZ2000 User ROM file.
            "mzffile=s"             => \$mzfFile,              # MZF file.
            "ramchecker=s"          => \$ramcheckFile,         # Ram Tester program.
            "a_cgrom=s"             => \$modelA_CGFile,        # Model 80A CG Rom.
            "b_cgrom=s"             => \$modelB_CGFile,        # Model 80B CG Rom.
            "c_cgrom=s"             => \$modelC_CGFile,        # Model 80C CG Rom.
            "k_cgrom=s"             => \$modelK_CGFile,        # Model 80K CG Rom.
            "7_cgrom=s"             => \$model7_CGFile,        # Model 700 CG Rom.
            "8_cgrom=s"             => \$model8_CGFile,        # Model 800 CG Rom.
            "12_cgrom=s"            => \$model12_CGFile,       # Model 1200 CG Rom.
            "20_cgrom=s"            => \$model20_CGFile,       # Model 2000 CG Rom.
            "a_keymap=s"            => \$modelA_KeyFile,       # Model 80A Key Map File
            "b_keymap=s"            => \$modelB_KeyFile,       # Model 80B Key Map File
            "c_keymap=s"            => \$modelC_KeyFile,       # Model 80C Key Map File
            "k_keymap=s"            => \$modelK_KeyFile,       # Model 80K Key Map File
            "7_keymap=s"            => \$model7_KeyFile,       # Model 700 Key Map File
            "8_keymap=s"            => \$model8_KeyFile,       # Model 800 Key Map File
            "12_keymap=s"           => \$model12_KeyFile,      # Model 1200 Key Map File
            "20_keymap=s"           => \$model20_KeyFile,      # Model 2000 Key Map File
            "help"                  => \$help,                 # Help required on commands/options?
          );

# Help required?
#
if(defined($help))
{
    argOptions(1, "");
} 

# Verify command.
#
if($command eq "64KRAM" || $command eq "MONROM" || $command eq "CGROM" || $command eq "KEYMAP")
{
    logWrite("", "Creating binary output file for command:$command.");
}
else
{
    argOptions(1, "Illegal command given on command line:$command.\n",$ERR_BADARGUMENTS);
}

# Output file.
# #
if(defined($outFile) && $outFile ne "")
{
    # If defined, can we open it?
    #
    if( $outFile ne "" && ! open(OUTFILE, ">".$outFile) )
    {
        argOptions(1, "Cannot create output file: $outFile.\n",$ERR_BADFILENAME);
    }
} else
{
    argOptions(1, "No output file given.\n",$ERR_BADARGUMENTS);
}
binmode(OUTFILE);

# MIF Output file.
# #
if(defined($mifoutFile) && $mifoutFile ne "")
{
    # If defined, can we open it?
    #
    if( $mifoutFile ne "" && ! open(MIFOUTFILE, ">".$mifoutFile) )
    {
        argOptions(1, "Cannot create MIF output file: $mifoutFile.\n",$ERR_BADFILENAME);
    }
    $createMIF=1;
} else
{
    $createMIF=0;
}

# An MZF file is not mandatory, if it exists then we must be able to open and read, if it
# doesnt exist, zero's will be used in the initialization image.
#
if(defined($mzfFile) && $mzfFile ne "")
{
    # If defined, can we open it?
    #
    if( $mzfFile ne "" && ! open(MZFFILE, "<".$mzfFile) )
    {
        argOptions(1, "Cannot open MZF file: $mzfFile.\n",$ERR_BADFILENAME);
    }

    $mzfExists = 1;
} else
{
    $mzfExists = 0;
}

# A Ram Checker program loaded into high memory.
#
if(defined($ramcheckFile) && $ramcheckFile ne "")
{
    # If defined, can we open it?
    #
    if( $ramcheckFile ne "" && ! open(RAMCHECKFILE, "<".$ramcheckFile) )
    {
        argOptions(1, "Cannot open MZF file: $ramcheckFile.\n",$ERR_BADFILENAME);
    }

    $ramcheckExists = 1;
} else
{
    $ramcheckExists = 0;
}

# Verify all options, easier to use tool at a later stage when memory of the project fades!!
#
if(defined($modelA_mromFile) && $modelA_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_mromFile ne "" && ! open(A_MROMFILE, "<".$modelA_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $modelA_mromFile.\n",$ERR_BADFILENAME);
    }
    $a_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80A Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $a_mromExists = 0;
}
if(defined($modelB_mromFile) && $modelB_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_mromFile ne "" && ! open(B_MROMFILE, "<".$modelB_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $modelB_mromFile.\n",$ERR_BADFILENAME);
    }
    $b_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80B Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $b_mromExists = 0;
}
if(defined($modelC_mromFile) && $modelC_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_mromFile ne "" && ! open(C_MROMFILE, "<".$modelC_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $modelC_mromFile.\n",$ERR_BADFILENAME);
    }
    $c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80C Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $c_mromExists = 0;
}
if(defined($modelK_mromFile) && $modelK_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_mromFile ne "" && ! open(K_MROMFILE, "<".$modelK_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $modelK_mromFile.\n",$ERR_BADFILENAME);
    }
    $k_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80K Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $k_mromExists = 0;
}
if(defined($model7_mromFile) && $model7_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_mromFile ne "" && ! open(M7_MROMFILE, "<".$model7_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $model7_mromFile.\n",$ERR_BADFILENAME);
    }
    $m7_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ700 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m7_mromExists = 0;
}
if(defined($model8_mromFile) && $model8_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_mromFile ne "" && ! open(M8_MROMFILE, "<".$model8_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $model8_mromFile.\n",$ERR_BADFILENAME);
    }
    $m8_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ800 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m8_mromExists = 0;
}
if(defined($model12_mromFile) && $model12_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_mromFile ne "" && ! open(M12_MROMFILE, "<".$model12_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $model12_mromFile.\n",$ERR_BADFILENAME);
    }
    $m12_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ1200 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m12_mromExists = 0;
}
if(defined($model20_mromFile) && $model20_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_mromFile ne "" && ! open(M20_MROMFILE, "<".$model20_mromFile) )
    {
        argOptions(1, "Cannot open Monitor ROM file: $model20_mromFile.\n",$ERR_BADFILENAME);
    }
    $m20_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ2000 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m20_mromExists = 0;
}
#
if(defined($modelA_80c_mromFile) && $modelA_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_80c_mromFile ne "" && ! open(A_80C_MROMFILE, "<".$modelA_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $modelA_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $a_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80A 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $a_80c_mromExists = 0;
}
if(defined($modelB_80c_mromFile) && $modelB_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_80c_mromFile ne "" && ! open(B_80C_MROMFILE, "<".$modelB_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $modelB_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $b_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80B 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $b_80c_mromExists = 0;
}
if(defined($modelC_80c_mromFile) && $modelC_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_80c_mromFile ne "" && ! open(C_80C_MROMFILE, "<".$modelC_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $modelC_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $c_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80C 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $c_80c_mromExists = 0;
}
if(defined($modelK_80c_mromFile) && $modelK_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_80c_mromFile ne "" && ! open(K_80C_MROMFILE, "<".$modelK_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $modelK_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $k_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80K 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $k_80c_mromExists = 0;
}
if(defined($model7_80c_mromFile) && $model7_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_80c_mromFile ne "" && ! open(M7_80C_MROMFILE, "<".$model7_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $model7_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $m7_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ700 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m7_80c_mromExists = 0;
}
if(defined($model8_80c_mromFile) && $model8_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_80c_mromFile ne "" && ! open(M8_80C_MROMFILE, "<".$model8_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $model8_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $m8_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ700 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m8_80c_mromExists = 0;
}
if(defined($model12_80c_mromFile) && $model12_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_80c_mromFile ne "" && ! open(M12_80C_MROMFILE, "<".$model12_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $model12_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $m12_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ1200 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m12_80c_mromExists = 0;
}
if(defined($model20_80c_mromFile) && $model20_80c_mromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_80c_mromFile ne "" && ! open(M20_80C_MROMFILE, "<".$model20_80c_mromFile) )
    {
        argOptions(1, "Cannot open 80x25 Monitor ROM file: $model20_80c_mromFile.\n",$ERR_BADFILENAME);
    }
    $m20_80c_mromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ1200 80x25 Monitor ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m20_80c_mromExists = 0;
}
#
# User Rom
#
if(defined($modelA_userromFile) && $modelA_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_userromFile ne "" && ! open(A_USERROMFILE, "<".$modelA_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $modelA_userromFile.\n",$ERR_BADFILENAME);
    }
    $a_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80A User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $a_userromExists = 0;
}
if(defined($modelB_userromFile) && $modelB_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_userromFile ne "" && ! open(B_USERROMFILE, "<".$modelB_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $modelB_userromFile.\n",$ERR_BADFILENAME);
    }
    $b_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80B User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $b_userromExists = 0;
}
if(defined($modelC_userromFile) && $modelC_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_userromFile ne "" && ! open(C_USERROMFILE, "<".$modelC_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $modelC_userromFile.\n",$ERR_BADFILENAME);
    }
    $c_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80C User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $c_userromExists = 0;
}
if(defined($modelK_userromFile) && $modelK_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_userromFile ne "" && ! open(K_USERROMFILE, "<".$modelK_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $modelK_userromFile.\n",$ERR_BADFILENAME);
    }
    $k_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80K User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $k_userromExists = 0;
}
if(defined($model7_userromFile) && $model7_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_userromFile ne "" && ! open(M7_USERROMFILE, "<".$model7_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $model7_userromFile.\n",$ERR_BADFILENAME);
    }
    $m7_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ700 User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m7_userromExists = 0;
}
if(defined($model8_userromFile) && $model8_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_userromFile ne "" && ! open(M8_USERROMFILE, "<".$model8_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $model8_userromFile.\n",$ERR_BADFILENAME);
    }
    $m8_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ800 User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m8_userromExists = 0;
}
if(defined($model12_userromFile) && $model12_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_userromFile ne "" && ! open(M12_USERROMFILE, "<".$model12_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $model12_userromFile.\n",$ERR_BADFILENAME);
    }
    $m12_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ1200 User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m12_userromExists = 0;
}
if(defined($model20_userromFile) && $model20_userromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_userromFile ne "" && ! open(M20_USERROMFILE, "<".$model20_userromFile) )
    {
        argOptions(1, "Cannot open User ROM file: $model20_userromFile.\n",$ERR_BADFILENAME);
    }
    $m20_userromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ2000 User ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m20_userromExists = 0;
}
# 
# Floppy Disk Controller Rom
#
if(defined($modelA_fdcromFile) && $modelA_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_fdcromFile ne "" && ! open(A_FDCROMFILE, "<".$modelA_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $modelA_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $a_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80A FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $a_fdcromExists = 0;
}
if(defined($modelB_fdcromFile) && $modelB_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_fdcromFile ne "" && ! open(B_FDCROMFILE, "<".$modelB_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $modelB_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $b_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80B FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $b_fdcromExists = 0;
}
if(defined($modelC_fdcromFile) && $modelC_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_fdcromFile ne "" && ! open(C_FDCROMFILE, "<".$modelC_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $modelC_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $c_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80C FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $c_fdcromExists = 0;
}
if(defined($modelK_fdcromFile) && $modelK_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_fdcromFile ne "" && ! open(K_FDCROMFILE, "<".$modelK_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $modelK_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $k_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ80K FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $k_fdcromExists = 0;
}
if(defined($model7_fdcromFile) && $model7_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_fdcromFile ne "" && ! open(M7_FDCROMFILE, "<".$model7_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $model7_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $m7_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ700 FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m7_fdcromExists = 0;
}
if(defined($model8_fdcromFile) && $model8_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_fdcromFile ne "" && ! open(M8_FDCROMFILE, "<".$model8_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $model8_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $m8_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ800 FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m8_fdcromExists = 0;
}
if(defined($model12_fdcromFile) && $model12_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_fdcromFile ne "" && ! open(M12_FDCROMFILE, "<".$model12_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $model12_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $m12_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ1200 FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m12_fdcromExists = 0;
}
if(defined($model20_fdcromFile) && $model20_fdcromFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_fdcromFile ne "" && ! open(M20_FDCROMFILE, "<".$model20_fdcromFile) )
    {
        argOptions(1, "Cannot open FDC ROM file: $model20_fdcromFile.\n",$ERR_BADFILENAME);
    }
    $m20_fdcromExists = 1;
} else
{
    if($command eq "MONROM")
    {
        argOptions(1, "No MZ2000 FDC ROM file given.\n",$ERR_BADARGUMENTS);
    }
    $m20_fdcromExists = 0;
}
#
# Checks
#
if($command eq "64KRAM" && $a_mromExists == 0 && $b_mromExists && $c_mromExists && $k_mromExists && $m7_mromExists && $m8_mromExists && $m12_mromExists && $m20_mromExists &&
                           $a_80c_mromExists == 0 && $b_80c_mromExists && $c_80c_mromExists && $k_80c_mromExists && $m7_80c_mromExists && $m8_80c_mromExists && $m12_80c_mromExists && $m20_80c_mromExists &&
                           $a_userromExists == 0 && $b_userromExists && $c_userromExists && $k_userromExists && $m7_userromExists && $m8_userromExists && $m12_userromExists && $m20_userromExists &&
                           $a_fdcromExists == 0 && $b_fdcromExists && $c_fdcromExists && $k_fdcromExists && $m7_fdcromExists && $m8_fdcromExists && $m12_fdcromExists && $m20_fdcromExists
  )
{
    argOptions(1, "No Monitor ROM file given for 64K RAM mode..\n",$ERR_BADARGUMENTS);
}
#
if($command eq "64KRAM" && ($a_mromExists + $b_mromExists + $c_mromExists + $k_mromExists + $m7_mromExists + $m8_mromExists + $m12_mromExists + $m20_mromExists +
                            $a_80c_mromExists + $b_80c_mromExists + $c_80c_mromExists + $k_80c_mromExists + $m7_80c_mromExists + $m8_80c_mromExists + $m12_80c_mromExists + $m20_80c_mromExists
                           ) > 1)
{
    argOptions(1, "You must only specify one Monitor ROM for 64K RAM mode..\n",$ERR_BADARGUMENTS);
}
if($command eq "64KRAM" && ($a_userromExists + $b_userromExists + $c_userromExists + $k_userromExists + $m7_userromExists + $m8_userromExists + $m12_userromExists + $m20_userromExists
                           ) > 1)
{
    argOptions(1, "You must only specify one User ROM for 64K RAM mode..\n",$ERR_BADARGUMENTS);
}
if($command eq "64KRAM" && ($a_fdcromExists + $b_fdcromExists + $c_fdcromExists + $k_fdcromExists + $m7_fdcromExists + $m8_fdcromExists + $m12_fdcromExists + $m20_fdcromExists
                           ) > 1)
{
    argOptions(1, "You must only specify one FDC ROM for 64K RAM mode..\n",$ERR_BADARGUMENTS);
}

if(defined($modelA_CGFile) && $modelA_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_CGFile ne "" && ! open(A_CGFILE, "<".$modelA_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $modelA_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ80A CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelB_CGFile) && $modelB_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_CGFile ne "" && ! open(B_CGFILE, "<".$modelB_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $modelB_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ80B CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelC_CGFile) && $modelC_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_CGFile ne "" && ! open(C_CGFILE, "<".$modelC_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $modelC_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ80C CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelK_CGFile) && $modelK_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_CGFile ne "" && ! open(K_CGFILE, "<".$modelK_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $modelK_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ80K CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model7_CGFile) && $model7_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_CGFile ne "" && ! open(M7_CGFILE, "<".$model7_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $model7_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ700 CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model8_CGFile) && $model8_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_CGFile ne "" && ! open(M8_CGFILE, "<".$model8_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $model8_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ800 CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model12_CGFile) && $model12_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_CGFile ne "" && ! open(M12_CGFILE, "<".$model12_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $model12_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ1200 CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model20_CGFile) && $model20_CGFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_CGFile ne "" && ! open(M20_CGFILE, "<".$model20_CGFile) )
    {
        argOptions(1, "Cannot open CG ROM file: $model20_CGFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "CGROM")
    {
        argOptions(1, "No MZ2000 CG ROM file given.\n",$ERR_BADARGUMENTS);
    }
}

if(defined($modelA_KeyFile) && $modelA_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelA_KeyFile ne "" && ! open(A_KEYFILE, "<".$modelA_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $modelA_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ80A Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelB_KeyFile) && $modelB_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelB_KeyFile ne "" && ! open(B_KEYFILE, "<".$modelB_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $modelB_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ80B Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelC_KeyFile) && $modelC_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelC_KeyFile ne "" && ! open(C_KEYFILE, "<".$modelC_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $modelC_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ80C Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($modelK_KeyFile) && $modelK_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $modelK_KeyFile ne "" && ! open(K_KEYFILE, "<".$modelK_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $modelK_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ80K Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model7_KeyFile) && $model7_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $model7_KeyFile ne "" && ! open(M7_KEYFILE, "<".$model7_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $model7_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ700 Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model8_KeyFile) && $model8_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $model8_KeyFile ne "" && ! open(M8_KEYFILE, "<".$model8_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $model8_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ800 Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model12_KeyFile) && $model12_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $model12_KeyFile ne "" && ! open(M12_KEYFILE, "<".$model12_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $model12_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ1200 Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}
if(defined($model20_KeyFile) && $model20_KeyFile ne "")
{
    # If defined, can we open it?
    #
    if( $model20_KeyFile ne "" && ! open(M20_KEYFILE, "<".$model20_KeyFile) )
    {
        argOptions(1, "Cannot open Key Map file: $model20_KeyFile.\n",$ERR_BADFILENAME);
    }
} else
{
    if($command eq "KEYMAP")
    {
        argOptions(1, "No MZ2000 Key Map file given.\n",$ERR_BADARGUMENTS);
    }
}

##############################################################################################################
# Commands:
#           64KRAM = Create Image for 64K RAM initialisation. 
#                    MROM + MZF + ZERO
#           MONROM = Create Image for Monitor ROM initialisation.
#                    MROM(K) + MROM(C) + MROM(1200) + MROM(A) + MROM(700) + MROM(B)
#           CGROM  = Create Image for Character Generator ROM initialisation.
#                    CGROM(K) + CGROM(C) + CGROM(1200) + CGROM(A) + CGROM(700) + CGROM(B)
#           KEYMAP = Create Image for Key Map ROM initialization.
#                    KEYMAP(K) + KEYMAP(C) + KEYMAP(1200) + KEYMAP(A) + KEYMAP(700) + KEYMAP(B)
##############################################################################################################

# Read all opened files into memory, dirty but easier to process.
#
if($command eq "64KRAM" || $command eq "MONROM")
{
    # Read in MZF file if given.
    if($mzfExists == 1)
    {
        @A_MZF = ();
        binmode(MZFFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <MZFFILE> )
        {
            $A_MZF[$cnt] = $byte;
            $cnt++;
        }
        $A_MZF_SIZE = $cnt;
    }

    # Read in MZF file if given.
    if($ramcheckExists == 1)
    {
        @RAMCHECK = ();
        binmode(RAMCHECKFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <RAMCHECKFILE> )
        {
            $RAMCHECK[$cnt] = $byte;
            $cnt++;
        }
        $RAMCHECK_SIZE = $cnt;
    }

    if($a_mromExists == 1)
    {
        @A_MROM = ();
        binmode(A_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <A_MROMFILE> )
        {
            $A_MROM[$cnt] = $byte;
            $cnt++;
        }
        $A_MROM_SIZE = $cnt;
    }

    if($b_mromExists == 1)
    {
        @B_MROM = ();
        binmode(B_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <B_MROMFILE> )
        {
            $B_MROM[$cnt] = $byte;
            $cnt++;
        }
        $B_MROM_SIZE = $cnt;
    }

    if($c_mromExists == 1)
    {
        @C_MROM = ();
        binmode(C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <C_MROMFILE> )
        {
            $C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $C_MROM_SIZE = $cnt;
    }

    if($k_mromExists == 1)
    {
        @K_MROM = ();
        binmode(K_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <K_MROMFILE> )
        {
            $K_MROM[$cnt] = $byte;
            $cnt++;
        }
        $K_MROM_SIZE = $cnt;
    }

    if($m7_mromExists == 1)
    {
        @M7_MROM = ();
        binmode(M7_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M7_MROMFILE> )
        {
            $M7_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M7_MROM_SIZE = $cnt;
    }

    if($m8_mromExists == 1)
    {
        @M8_MROM = ();
        binmode(M8_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M8_MROMFILE> )
        {
            $M8_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M8_MROM_SIZE = $cnt;
    }

    if($m12_mromExists == 1)
    {
        @M12_MROM = ();
        binmode(M12_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M12_MROMFILE> )
        {
            $M12_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M12_MROM_SIZE = $cnt;
    }

    if($m20_mromExists == 1)
    {
        @M20_MROM = ();
        binmode(M20_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M20_MROMFILE> )
        {
            $M20_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M20_MROM_SIZE = $cnt;
    }

    if($a_80c_mromExists == 1)
    {
        @A_80C_MROM = ();
        binmode(A_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <A_80C_MROMFILE> )
        {
            $A_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $A_80C_MROM_SIZE = $cnt;
    }

    if($b_80c_mromExists == 1)
    {
        @B_80C_MROM = ();
        binmode(B_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <B_80C_MROMFILE> )
        {
            $B_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $B_80C_MROM_SIZE = $cnt;
    }

    if($c_80c_mromExists == 1)
    {
        @C_80C_MROM = ();
        binmode(C_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <C_80C_MROMFILE> )
        {
            $C_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $C_80C_MROM_SIZE = $cnt;
    }

    if($k_80c_mromExists == 1)
    {
        @K_80C_MROM = ();
        binmode(K_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <K_80C_MROMFILE> )
        {
            $K_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $K_80C_MROM_SIZE = $cnt;
    }

    if($m7_80c_mromExists == 1)
    {
        @M7_80C_MROM = ();
        binmode(M7_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M7_80C_MROMFILE> )
        {
            $M7_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M7_80C_MROM_SIZE = $cnt;
    }

    if($m8_80c_mromExists == 1)
    {
        @M8_80C_MROM = ();
        binmode(M8_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M8_80C_MROMFILE> )
        {
            $M8_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M8_80C_MROM_SIZE = $cnt;
    }

    if($m12_80c_mromExists == 1)
    {
        @M12_80C_MROM = ();
        binmode(M12_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M12_80C_MROMFILE> )
        {
            $M12_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M12_80C_MROM_SIZE = $cnt;
    }

    if($m20_80c_mromExists == 1)
    {
        @M20_80C_MROM = ();
        binmode(M20_80C_MROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M20_80C_MROMFILE> )
        {
            $M20_80C_MROM[$cnt] = $byte;
            $cnt++;
        }
        $M20_80C_MROM_SIZE = $cnt;
    }

    if($a_userromExists == 1)
    {
        @A_USERROM = ();
        binmode(A_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <A_USERROMFILE> )
        {
            $A_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $A_USERROM_SIZE = $cnt;
    }

    if($b_userromExists == 1)
    {
        @B_USERROM = ();
        binmode(B_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <B_USERROMFILE> )
        {
            $B_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $B_USERROM_SIZE = $cnt;
    }

    if($c_userromExists == 1)
    {
        @C_USERROM = ();
        binmode(C_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <C_USERROMFILE> )
        {
            $C_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $C_USERROM_SIZE = $cnt;
    }

    if($k_userromExists == 1)
    {
        @K_USERROM = ();
        binmode(K_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <K_USERROMFILE> )
        {
            $K_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $K_USERROM_SIZE = $cnt;
    }

    if($m7_userromExists == 1)
    {
        @M7_USERROM = ();
        binmode(M7_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M7_USERROMFILE> )
        {
            $M7_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $M7_USERROM_SIZE = $cnt;
    }

    if($m8_userromExists == 1)
    {
        @M8_USERROM = ();
        binmode(M8_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M8_USERROMFILE> )
        {
            $M8_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $M8_USERROM_SIZE = $cnt;
    }

    if($m12_userromExists == 1)
    {
        @M12_USERROM = ();
        binmode(M12_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M12_USERROMFILE> )
        {
            $M12_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $M12_USERROM_SIZE = $cnt;
    }

    if($m20_userromExists == 1)
    {
        @M20_USERROM = ();
        binmode(M20_USERROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M20_USERROMFILE> )
        {
            $M20_USERROM[$cnt] = $byte;
            $cnt++;
        }
        $M20_USERROM_SIZE = $cnt;
    }

    if($a_fdcromExists == 1)
    {
        @A_FDCROM = ();
        binmode(A_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <A_FDCROMFILE> )
        {
            $A_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $A_FDCROM_SIZE = $cnt;
    }

    if($b_fdcromExists == 1)
    {
        @B_FDCROM = ();
        binmode(B_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <B_FDCROMFILE> )
        {
            $B_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $B_FDCROM_SIZE = $cnt;
    }

    if($c_fdcromExists == 1)
    {
        @C_FDCROM = ();
        binmode(C_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <C_FDCROMFILE> )
        {
            $C_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $C_FDCROM_SIZE = $cnt;
    }

    if($k_fdcromExists == 1)
    {
        @K_FDCROM = ();
        binmode(K_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <K_FDCROMFILE> )
        {
            $K_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $K_FDCROM_SIZE = $cnt;
    }

    if($m7_fdcromExists == 1)
    {
        @M7_FDCROM = ();
        binmode(M7_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M7_FDCROMFILE> )
        {
            $M7_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $M7_FDCROM_SIZE = $cnt;
    }

    if($m8_fdcromExists == 1)
    {
        @M8_FDCROM = ();
        binmode(M8_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M8_FDCROMFILE> )
        {
            $M8_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $M8_FDCROM_SIZE = $cnt;
    }

    if($m12_fdcromExists == 1)
    {
        @M12_FDCROM = ();
        binmode(M12_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M12_FDCROMFILE> )
        {
            $M12_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $M12_FDCROM_SIZE = $cnt;
    }

    if($m20_fdcromExists == 1)
    {
        @M20_FDCROM = ();
        binmode(M20_FDCROMFILE); 
        local $/ = \1;
        $cnt = 0;
        $skip = 0;
        while ( my $byte = <M20_FDCROMFILE> )
        {
            $M20_FDCROM[$cnt] = $byte;
            $cnt++;
        }
        $M20_FDCROM_SIZE = $cnt;
    }
}

if($command eq "CGROM")
{
    @A_CGROM = ();
    binmode(A_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <A_CGFILE> )
    {
        $A_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $A_CGROM_SIZE = $cnt;

    @B_CGROM = ();
    binmode(B_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <B_CGFILE> )
    {
        $B_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $B_CGROM_SIZE = $cnt;

    @C_CGROM = ();
    binmode(C_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <C_CGFILE> )
    {
        $C_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $C_CGROM_SIZE = $cnt;

    @K_CGROM = ();
    binmode(K_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <K_CGFILE> )
    {
        $K_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $K_CGROM_SIZE = $cnt;

    @M7_CGROM = ();
    binmode(M7_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M7_CGFILE> )
    {
        $M7_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $M7_CGROM_SIZE = $cnt;

    @M8_CGROM = ();
    binmode(M8_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M8_CGFILE> )
    {
        $M8_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $M8_CGROM_SIZE = $cnt;

    @M12_CGROM = ();
    binmode(M12_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M12_CGFILE> )
    {
        $M12_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $M12_CGROM_SIZE = $cnt;

    @M20_CGROM = ();
    binmode(M20_CGFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M20_CGFILE> )
    {
        $M20_CGROM[$cnt] = $byte;
        $cnt++;
    }
    $M20_CGROM_SIZE = $cnt;
}

if($command eq "KEYMAP")
{
    @A_KEYMAP = ();
    binmode(A_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <A_KEYFILE> )
    {
        $A_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $A_KEYMAP_SIZE = $cnt;

    @B_KEYMAP = ();
    binmode(B_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <B_KEYFILE> )
    {
        $B_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $B_KEYMAP_SIZE = $cnt;

    @C_KEYMAP = ();
    binmode(C_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <C_KEYFILE> )
    {
        $C_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $C_KEYMAP_SIZE = $cnt;

    @K_KEYMAP = ();
    binmode(K_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <K_KEYFILE> )
    {
        $K_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $K_KEYMAP_SIZE = $cnt;

    @M7_KEYMAP = ();
    binmode(M7_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M7_KEYFILE> )
    {
        $M7_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $M7_KEYMAP_SIZE = $cnt;

    @M8_KEYMAP = ();
    binmode(M8_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M8_KEYFILE> )
    {
        $M8_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $M8_KEYMAP_SIZE = $cnt;

    @M12_KEYMAP = ();
    binmode(M12_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M12_KEYFILE> )
    {
        $M12_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $M12_KEYMAP_SIZE = $cnt;

    @M20_KEYMAP = ();
    binmode(M20_KEYFILE); 
    local $/ = \1;
    $cnt = 0;
    $skip = 0;
    while ( my $byte = <M20_KEYFILE> )
    {
        $M20_KEYMAP[$cnt] = $byte;
        $cnt++;
    }
    $M20_KEYMAP_SIZE = $cnt;
}

if($command eq "64KRAM")
{
    # Location    Loc. in    Location in    Length    Meaning
    # in tape    monitor's    S-BASIC        
    # header     work area    1Z-013B        
    # $00 (0)     $10F0       $0FFC           1      attribute of the file:
    #                                                 01 machine code program file
    #                                                 02 MZ-80 BASIC program file
    #                                                 03 MZ-80 data file
    #                                                 04 MZ-700 data file
    #                                                 05 MZ-700 BASIC program file
    # $01 (1)     $10F1       $0FFD           17     file name ( end = $0D )
    # $12 (18)    $1102       $100E           2      byte size of the file
    # $14 (20)    $1104       $1010           2      load address of a program file
    # $16 (22)    $1106       $1012           2      execution address of a program file
    # $18 (24)    $1108       $1014           104    comment

    # Initialize in memory image.
    @MainMemory = ();

    
    # First up, write out the Monitor ROM to output file.
    #
    if($a_mromExists == 1)       { $mrom_size = scalar @A_MROM;          foreach my $byte (@A_MROM)       { push @MainMemory, $byte; } };
    if($a_80c_mromExists == 1)   { $mrom_size = scalar @A_80C_MROM;      foreach my $byte (@A_80C_MROM)   { push @MainMemory, $byte; } };
    if($b_mromExists == 1)       { $mrom_size = scalar @B_MROM;          foreach my $byte (@B_MROM)       { push @MainMemory, $byte; } };
    if($b_80c_mromExists == 1)   { $mrom_size = scalar @B_80C_MROM;      foreach my $byte (@B_80C_MROM)   { push @MainMemory, $byte; } };
    if($c_mromExists == 1)       { $mrom_size = scalar @C_MROM;          foreach my $byte (@C_MROM)       { push @MainMemory, $byte; } };
    if($c_80c_mromExists == 1)   { $mrom_size = scalar @C_80C_MROM;      foreach my $byte (@C_80C_MROM)   { push @MainMemory, $byte; } };
    if($k_mromExists == 1)       { $mrom_size = scalar @K_MROM;          foreach my $byte (@K_MROM)       { push @MainMemory, $byte; } };
    if($k_80c_mromExists == 1)   { $mrom_size = scalar @K_80C_MROM;      foreach my $byte (@K_80C_MROM)   { push @MainMemory, $byte; } };
    if($m7_mromExists == 1)      { $mrom_size = scalar @M7_MROM;         foreach my $byte (@M7_MROM)      { push @MainMemory, $byte; } };
    if($m7_80c_mromExists == 1)  { $mrom_size = scalar @M7_80C_MROM;     foreach my $byte (@M7_80C_MROM)  { push @MainMemory, $byte; } };
    if($m8_mromExists == 1)      { $mrom_size = scalar @M8_MROM;         foreach my $byte (@M8_MROM)      { push @MainMemory, $byte; } };
    if($m8_80c_mromExists == 1)  { $mrom_size = scalar @M8_80C_MROM;     foreach my $byte (@M8_80C_MROM)  { push @MainMemory, $byte; } };
    if($m12_mromExists == 1)     { $mrom_size = scalar @M12_MROM;        foreach my $byte (@M12_MROM)     { push @MainMemory, $byte; } };
    if($m12_80c_mromExists == 1) { $mrom_size = scalar @M12_80C_MROM;    foreach my $byte (@M12_80C_MROM) { push @MainMemory, $byte; } };
    if($m20_mromExists == 1)     { $mrom_size = scalar @M20_MROM;        foreach my $byte (@M20_MROM)     { push @MainMemory, $byte; } };
    if($m20_80c_mromExists == 1) { $mrom_size = scalar @M20_80C_MROM;    foreach my $byte (@M20_80C_MROM) { push @MainMemory, $byte; } };


    # If a Tape Program has been provided, process it.
    #
    if($mzfExists == 1)
    {
        # Process the header to get key information.
        #
        $mzf_header = pack('a'x128, @A_MZF);
        ($mzf_type, $mzf_filename, $mzf_size, $mzf_loadaddr, $mzf_execaddr, $mzf_comment) = unpack 'c1 a17 v4 v4 v4 a104', $mzf_header;
        $mzf_filename =~ s/\r|\n//g;

        # Next, 1000 - 10EF as zero's (Monitor scratch area).
        for(my $idx=0; $idx < 240; $idx++) { push @MainMemory, "\x00"; };
    
        # Next, write out the Tape Header 10F0 - 116F.
        for(my $idx=0; $idx < 128; $idx++) { push @MainMemory, $A_MZF[$idx]; };
    
        # Next, write out zero's up until the load address.
        for(my $idx=0x1170; $idx < $mzf_loadaddr; $idx++) { push @MainMemory, "\x00";  };
        for(my $idx=128; $idx < $A_MZF_SIZE; $idx++) { push @MainMemory, $A_MZF[$idx]; };

        # Next, 1000 - 10EF as zero's (Monitor scratch area).
        # Positions for easy reference.
        $romStartPosition        = 0;
        $romEndPosition          = $mrom_size;
        $romScratchStartPosition = $mrom_size;
        $romScratchEndPosition   = 0x10EF;
        $tapeHeaderStartPosition = 0x10F0;
        $tapeHeaderEndPosition   = 0x116F;
        $romStackStartPosition   = 0x1170;
        $romStackEndPosition     = $mzf_loadaddr;
        $programStartPosition    = $mzf_loadaddr;
        $programEndPosition      = $mzf_loadaddr + $mzf_size;
        $lowerUsedMemoryPosition = scalar @MainMemory;
        $ramcheckMemoryPosition  = 0xCE00;
        $userrom_size            = 0x0000;
        $fdcrom_size             = 0x0000;
        $userRomMemoryPosition   = 0xE800;
        $fdcRomMemoryPosition    = 0xF000;
        $upperMemoryPosition     = 65536;

        # Next, write out zero's from scratch area to end of ramchecker or userrom.
        if($ramcheckExists == 1)
        {
            for(my $idx=$lowerUsedMemoryPosition; $idx < $ramcheckMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
            for(my $idx=0; $idx < $RAMCHECK_SIZE; $idx++) { push @MainMemory, $RAMCHECK[$idx]; };
            for(my $idx=$ramcheckMemoryPosition + $RAMCHECK_SIZE; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
        } else
        {
            for(my $idx=$lowerUsedMemoryPosition; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
        }
        
        # User Rom
        if($a_userromExists == 1)    { $userrom_size = scalar @A_USERROM;    foreach my $byte (@A_USERROM)    { push @MainMemory, $byte; } };
        if($b_userromExists == 1)    { $userrom_size = scalar @B_USERROM;    foreach my $byte (@B_USERROM)    { push @MainMemory, $byte; } };
        if($c_userromExists == 1)    { $userrom_size = scalar @C_USERROM;    foreach my $byte (@C_USERROM)    { push @MainMemory, $byte; } };
        if($k_userromExists == 1)    { $userrom_size = scalar @K_USERROM;    foreach my $byte (@K_USERROM)    { push @MainMemory, $byte; } };
        if($m7_userromExists == 1)   { $userrom_size = scalar @M7_USERROM;   foreach my $byte (@M7_USERROM)   { push @MainMemory, $byte; } };
        if($m8_userromExists == 1)   { $userrom_size = scalar @M8_USERROM;   foreach my $byte (@M8_USERROM)   { push @MainMemory, $byte; } };
        if($m12_userromExists == 1)  { $userrom_size = scalar @M12_USERROM;  foreach my $byte (@M12_USERROM)  { push @MainMemory, $byte; } };
        if($m20_userromExists == 1)  { $userrom_size = scalar @M20_USERROM;  foreach my $byte (@M20_USERROM)  { push @MainMemory, $byte; } };
        
        # Pad with zeros to end of block.
        for(my $idx=$userRomMemoryPosition + $userrom_size; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };

        # FDC Rom
        if($a_fdcromExists == 1)     { $fdcrom_size = scalar @A_FDCROM;      foreach my $byte (@A_FDCROM)     { push @MainMemory, $byte; } };
        if($b_fdcromExists == 1)     { $fdcrom_size = scalar @B_FDCROM;      foreach my $byte (@B_FDCROM)     { push @MainMemory, $byte; } };
        if($c_fdcromExists == 1)     { $fdcrom_size = scalar @C_FDCROM;      foreach my $byte (@C_FDCROM)     { push @MainMemory, $byte; } };
        if($k_fdcromExists == 1)     { $fdcrom_size = scalar @K_FDCROM;      foreach my $byte (@K_FDCROM)     { push @MainMemory, $byte; } };
        if($m7_fdcromExists == 1)    { $fdcrom_size = scalar @M7_FDCROM;     foreach my $byte (@M7_FDCROM)    { push @MainMemory, $byte; } };
        if($m8_fdcromExists == 1)    { $fdcrom_size = scalar @M8_FDCROM;     foreach my $byte (@M8_FDCROM)    { push @MainMemory, $byte; } };
        if($m12_fdcromExists == 1)   { $fdcrom_size = scalar @M12_FDCROM;    foreach my $byte (@M12_FDCROM)   { push @MainMemory, $byte; } };
        if($m20_fdcromExists == 1)   { $fdcrom_size = scalar @M20_FDCROM;    foreach my $byte (@M20_FDCROM)   { push @MainMemory, $byte; } };

        # Pad with zeros to end of block.
        for(my $idx=$fdcRomMemoryPosition + $fdcrom_size; $idx < $fdcRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
    } else
    {

        # Positions for easy reference.
        $romStartPosition        = 0;
        $romEndPosition          = $mrom_size;
        $romScratchStartPosition = $mrom_size;
        $romScratchEndPosition   = 0x116F;
        $tapeHeaderStartPosition = 0x0000;
        $tapeHeaderEndPosition   = 0x0000;
        $romStackStartPosition   = 0x1170;
        $romStackEndPosition     = 0x11FF;
        $programStartPosition    = 0x0000;
        $programEndPosition      = 0x0000;
        $lowerUsedMemoryPosition = scalar @MainMemory;
        $ramcheckMemoryPosition  = 0xCE00;
        $userrom_size            = 0x0000;
        $fdcrom_size             = 0x0000;
        $userRomMemoryPosition   = 0xE800;
        $fdcRomMemoryPosition    = 0xF000;
        $upperMemoryPosition     = 65536;

        # Next, write out zero's from scratch area to end of memory or ramchecker..
        if($ramcheckExists == 1)
        {
            for(my $idx=$lowerUsedMemoryPosition; $idx < $ramcheckMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
            for(my $idx=0; $idx < $RAMCHECK_SIZE; $idx++) { push @MainMemory, $RAMCHECK[$idx]; };
            for(my $idx=$ramcheckMemoryPosition + $RAMCHECK_SIZE; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
        } else
        {
            for(my $idx=$lowerUsedMemoryPosition; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
        }

        # User Rom
        if($a_userromExists == 1)    { $userrom_size = scalar @A_USERROM;    foreach my $byte (@A_USERROM)    { push @MainMemory, $byte; } };
        if($b_userromExists == 1)    { $userrom_size = scalar @B_USERROM;    foreach my $byte (@B_USERROM)    { push @MainMemory, $byte; } };
        if($c_userromExists == 1)    { $userrom_size = scalar @C_USERROM;    foreach my $byte (@C_USERROM)    { push @MainMemory, $byte; } };
        if($k_userromExists == 1)    { $userrom_size = scalar @K_USERROM;    foreach my $byte (@K_USERROM)    { push @MainMemory, $byte; } };
        if($m7_userromExists == 1)   { $userrom_size = scalar @M7_USERROM;   foreach my $byte (@M7_USERROM)   { push @MainMemory, $byte; } };
        if($m8_userromExists == 1)   { $userrom_size = scalar @M8_USERROM;   foreach my $byte (@M8_USERROM)   { push @MainMemory, $byte; } };
        if($m12_userromExists == 1)  { $userrom_size = scalar @M12_USERROM;  foreach my $byte (@M12_USERROM)  { push @MainMemory, $byte; } };
        if($m20_userromExists == 1)  { $userrom_size = scalar @M20_USERROM;  foreach my $byte (@M20_USERROM)  { push @MainMemory, $byte; } };
        
        # Pad with zeros to end of block.
        for(my $idx=$userRomMemoryPosition + $userrom_size; $idx < $userRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };

        # FDC Rom
        if($a_fdcromExists == 1)     { $fdcrom_size = scalar @A_FDCROM;      foreach my $byte (@A_FDCROM)     { push @MainMemory, $byte; } };
        if($b_fdcromExists == 1)     { $fdcrom_size = scalar @B_FDCROM;      foreach my $byte (@B_FDCROM)     { push @MainMemory, $byte; } };
        if($c_fdcromExists == 1)     { $fdcrom_size = scalar @C_FDCROM;      foreach my $byte (@C_FDCROM)     { push @MainMemory, $byte; } };
        if($k_fdcromExists == 1)     { $fdcrom_size = scalar @K_FDCROM;      foreach my $byte (@K_FDCROM)     { push @MainMemory, $byte; } };
        if($m7_fdcromExists == 1)    { $fdcrom_size = scalar @M7_FDCROM;     foreach my $byte (@M7_FDCROM)    { push @MainMemory, $byte; } };
        if($m8_fdcromExists == 1)    { $fdcrom_size = scalar @M8_FDCROM;     foreach my $byte (@M8_FDCROM)    { push @MainMemory, $byte; } };
        if($m12_fdcromExists == 1)   { $fdcrom_size = scalar @M12_FDCROM;    foreach my $byte (@M12_FDCROM)   { push @MainMemory, $byte; } };
        if($m20_fdcromExists == 1)   { $fdcrom_size = scalar @M20_FDCROM;    foreach my $byte (@M20_FDCROM)   { push @MainMemory, $byte; } };

        # Pad with zeros to end of block.
        for(my $idx=$fdcRomMemoryPosition + $fdcrom_size; $idx < $fdcRomMemoryPosition; $idx++) { push @MainMemory, "\x00"; };
    }

    # Finally, print out details for confirmation.
    #
    logWrite("", sprintf "Main Memory Map:\n");
    logWrite("", sprintf "                     MROM           = %04x:%04x %04x bytes", $romStartPosition,        $romEndPosition,        $romEndPosition - $romStartPosition);
    logWrite("", sprintf "                     MROM (Scratch) = %04x:%04x %04x bytes", $romScratchStartPosition, $romScratchEndPosition, $romScratchEndPosition - $romScratchStartPosition);
    logWrite("", sprintf "              Tape Header           = %04x:%04x %04x bytes", $tapeHeaderStartPosition, $tapeHeaderEndPosition, $tapeHeaderEndPosition - $tapeHeaderStartPosition,);
    logWrite("", sprintf "                     MROM (Stack)   = %04x:%04x %04x bytes", $romStackStartPosition,   $romStackEndPosition,   $romStackEndPosition - $romStackStartPosition);
    logWrite("", sprintf "                  Program           = %04x:%04x %04x bytes", $programStartPosition,    $programEndPosition,    $programEndPosition - $programStartPosition);
    if($ramcheckExists == 1)
    {
        logWrite("", sprintf "              Ram Checker           = %04x:%04x %04x bytes", $ramcheckMemoryPosition,    $ramcheckMemoryPosition + $RAMCHECK_SIZE,    $RAMCHECK_SIZE);
    }
    if($a_userromExists == 1 || $b_userromExists == 1 || $c_userromExists == 1 || $k_userromExists == 1 || $m7_userromExists == 1 || $m8_userromExists == 1 || $m12_userromExists == 1 || $m20_userromExists == 1)
    {
        logWrite("", sprintf "              User Rom              = %04x:%04x %04x bytes", $userRomMemoryPosition,    $userRomMemoryPosition + $userrom_size,    $userrom_size);
    }
    if($a_fdcromExists == 1 || $b_fdcromExists == 1 || $c_fdcromExists == 1 || $k_fdcromExists == 1 || $m7_fdcromExists == 1 || $m8_fdcromExists == 1 || $m12_fdcromExists == 1 || $m20_fdcromExists == 1)
    {
        logWrite("", sprintf "              FDC Rom               = %04x:%04x %04x bytes", $fdcRomMemoryPosition,    $fdcRomMemoryPosition + $fdcrom_size,    $fdcrom_size);
    }
    logWrite("", sprintf "End of Program Memory               = %04x", $programEndPosition);
}
elsif($command eq "MONROM")
{
    # Initialize in memory image.
    @MonitorMemory = ();

    # Max ROM Sizes.
    $A_MROM_MAX_SIZE        = 4096;
    $A_80C_MROM_MAX_SIZE    = 4096;
    $A_USERROM_MAX_SIZE     = 2048;
    $A_FDCROM_MAX_SIZE      = 4096;
    $K_MROM_MAX_SIZE        = 4096;
    $K_80C_MROM_MAX_SIZE    = 4096;
    $K_USERROM_MAX_SIZE     = 2048;
    $K_FDCROM_MAX_SIZE      = 4096;
    $C_MROM_MAX_SIZE        = 4096;
    $C_80C_MROM_MAX_SIZE    = 4096;
    $C_USERROM_MAX_SIZE     = 2048;
    $C_FDCROM_MAX_SIZE      = 4096;
    $M12_MROM_MAX_SIZE      = 4096;
    $M12_80C_MROM_MAX_SIZE  = 4096;
    $M12_USERROM_MAX_SIZE   = 2048;
    $M12_FDCROM_MAX_SIZE    = 4096;
    $M20_MROM_MAX_SIZE      = 2048;
    $M20_80C_MROM_MAX_SIZE  = 2048;
    $M20_USERROM_MAX_SIZE   = 2048;
    $M20_FDCROM_MAX_SIZE    = 4096;
    $M7_MROM_MAX_SIZE       = 4096;
    $M7_80C_MROM_MAX_SIZE   = 4096;
    $M7_USERROM_MAX_SIZE    = 2048;
    $M7_FDCROM_MAX_SIZE     = 4096;
    $M8_MROM_MAX_SIZE       = 4096;
    $M8_80C_MROM_MAX_SIZE   = 4096;
    $M8_USERROM_MAX_SIZE    = 2048;
    $M8_FDCROM_MAX_SIZE     = 4096;
    $B_MROM_MAX_SIZE        = 2048;
    $B_80C_MROM_MAX_SIZE    = 2048;
    $B_USERROM_MAX_SIZE     = 2048;
    $B_FDCROM_MAX_SIZE      = 4096;
    $M20_MROM_MAX_SIZE      = 2048;
    $M20_80C_MROM_MAX_SIZE  = 2048;
    $M20_USERROM_MAX_SIZE   = 2048;
    $M20_FDCROM_MAX_SIZE    = 4096;

    # Fill the memory image with equisize images, zero padding as necessary.
    foreach my $byte (@K_MROM)       { push @MonitorMemory, $byte; };  for(my $idx=$K_MROM_SIZE;       $idx < $K_MROM_MAX_SIZE; $idx++)       { push @MonitorMemory, "\x00"; };
    foreach my $byte (@K_80C_MROM)   { push @MonitorMemory, $byte; };  for(my $idx=$K_80C_MROM_SIZE;   $idx < $K_80C_MROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@K_USERROM)    { push @MonitorMemory, $byte; };  for(my $idx=$K_USERROM_SIZE;    $idx < $K_USERROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@K_FDCROM)     { push @MonitorMemory, $byte; };  for(my $idx=$K_FDCROM_SIZE;     $idx < $K_FDCROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@C_MROM)       { push @MonitorMemory, $byte; };  for(my $idx=$C_MROM_SIZE;       $idx < $C_MROM_MAX_SIZE; $idx++)       { push @MonitorMemory, "\x00"; };
    foreach my $byte (@C_80C_MROM)   { push @MonitorMemory, $byte; };  for(my $idx=$C_80C_MROM_SIZE;   $idx < $C_80C_MROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@C_USERROM)    { push @MonitorMemory, $byte; };  for(my $idx=$C_USERROM_SIZE;    $idx < $C_USERROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@C_FDCROM)     { push @MonitorMemory, $byte; };  for(my $idx=$C_FDCROM_SIZE;     $idx < $C_FDCROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M12_MROM)     { push @MonitorMemory, $byte; };  for(my $idx=$M12_MROM_SIZE;     $idx < $M12_MROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M12_80C_MROM) { push @MonitorMemory, $byte; };  for(my $idx=$M12_80C_MROM_SIZE; $idx < $M12_80C_MROM_MAX_SIZE; $idx++) { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M12_USERROM)  { push @MonitorMemory, $byte; };  for(my $idx=$M12_USERROM_SIZE;  $idx < $M12_USERROM_MAX_SIZE; $idx++)  { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M12_FDCROM)   { push @MonitorMemory, $byte; };  for(my $idx=$M12_FDCROM_SIZE;   $idx < $M12_FDCROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@A_MROM)       { push @MonitorMemory, $byte; };  for(my $idx=$A_MROM_SIZE;       $idx < $A_MROM_MAX_SIZE; $idx++)       { push @MonitorMemory, "\x00"; };
    foreach my $byte (@A_80C_MROM)   { push @MonitorMemory, $byte; };  for(my $idx=$A_80C_MROM_SIZE;   $idx < $A_80C_MROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@A_USERROM)    { push @MonitorMemory, $byte; };  for(my $idx=$A_USERROM_SIZE;    $idx < $A_USERROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@A_FDCROM)     { push @MonitorMemory, $byte; };  for(my $idx=$A_FDCROM_SIZE;     $idx < $A_FDCROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M7_MROM)      { push @MonitorMemory, $byte; };  for(my $idx=$M7_MROM_SIZE;      $idx < $M7_MROM_MAX_SIZE; $idx++)      { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M7_80C_MROM)  { push @MonitorMemory, $byte; };  for(my $idx=$M7_80C_MROM_SIZE;  $idx < $M7_80C_MROM_MAX_SIZE; $idx++)  { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M7_USERROM)   { push @MonitorMemory, $byte; };  for(my $idx=$M7_USERROM_SIZE;   $idx < $M7_USERROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M7_FDCROM)    { push @MonitorMemory, $byte; };  for(my $idx=$M7_FDCROM_SIZE;    $idx < $M7_FDCROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M8_MROM)      { push @MonitorMemory, $byte; };  for(my $idx=$M8_MROM_SIZE;      $idx < $M8_MROM_MAX_SIZE; $idx++)      { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M8_80C_MROM)  { push @MonitorMemory, $byte; };  for(my $idx=$M8_80C_MROM_SIZE;  $idx < $M8_80C_MROM_MAX_SIZE; $idx++)  { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M8_USERROM)   { push @MonitorMemory, $byte; };  for(my $idx=$M8_USERROM_SIZE;   $idx < $M8_USERROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M8_FDCROM)    { push @MonitorMemory, $byte; };  for(my $idx=$M8_FDCROM_SIZE;    $idx < $M8_FDCROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@B_MROM)       { push @MonitorMemory, $byte; };  for(my $idx=$B_MROM_SIZE;       $idx < $B_MROM_MAX_SIZE; $idx++)       { push @MonitorMemory, "\x00"; };
    foreach my $byte (@B_80C_MROM)   { push @MonitorMemory, $byte; };  for(my $idx=$B_80C_MROM_SIZE;   $idx < $B_80C_MROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };
    foreach my $byte (@B_USERROM)    { push @MonitorMemory, $byte; };  for(my $idx=$B_USERROM_SIZE;    $idx < $B_USERROM_MAX_SIZE; $idx++)    { push @MonitorMemory, "\x00"; };
    foreach my $byte (@B_FDCROM)     { push @MonitorMemory, $byte; };  for(my $idx=$B_FDCROM_SIZE;     $idx < $B_FDCROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M20_MROM)     { push @MonitorMemory, $byte; };  for(my $idx=$M20_MROM_SIZE;     $idx < $M20_MROM_MAX_SIZE; $idx++)     { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M20_80C_MROM) { push @MonitorMemory, $byte; };  for(my $idx=$M20_80C_MROM_SIZE; $idx < $M20_80C_MROM_MAX_SIZE; $idx++) { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M20_USERROM)  { push @MonitorMemory, $byte; };  for(my $idx=$M20_USERROM_SIZE;  $idx < $M20_USERROM_MAX_SIZE; $idx++)  { push @MonitorMemory, "\x00"; };
    foreach my $byte (@M20_FDCROM)   { push @MonitorMemory, $byte; };  for(my $idx=$M20_FDCROM_SIZE;   $idx < $M20_FDCROM_MAX_SIZE; $idx++)   { push @MonitorMemory, "\x00"; };

    # Positions for easy reference.
    $k_romStartPosition        = 0;
    $k_romEndPosition          = $K_MROM_MAX_SIZE -1;
    $k_romPadding              = $K_MROM_MAX_SIZE - $K_MROM_SIZE;
    $k_80c_romStartPosition    = $k_romEndPosition + 1;
    $k_80c_romEndPosition      = $k_80c_romStartPosition + $K_80C_MROM_MAX_SIZE -1;
    $k_80c_romPadding          = $K_80C_MROM_MAX_SIZE - $K_80C_MROM_SIZE;
    $k_userromStartPosition    = $k_80c_romEndPosition + 1;
    $k_userromEndPosition      = $k_userromStartPosition + $K_USERROM_MAX_SIZE -1;
    $k_userromPadding          = $K_USERROM_MAX_SIZE - $K_USERROM_SIZE;
    $k_fdcromStartPosition     = $k_userromEndPosition + 1;
    $k_fdcromEndPosition       = $k_fdcromStartPosition + $K_FDCROM_MAX_SIZE -1;
    $k_fdcromPadding           = $K_FDCROM_MAX_SIZE - $K_FDCROM_SIZE;
    $c_romStartPosition        = $k_fdcromEndPosition + 1;
    $c_romEndPosition          = $c_romStartPosition + $C_MROM_MAX_SIZE -1;
    $c_romPadding              = $C_MROM_MAX_SIZE - $C_MROM_SIZE;
    $c_80c_romStartPosition    = $c_romEndPosition + 1;
    $c_80c_romEndPosition      = $c_80c_romStartPosition + $C_80C_MROM_MAX_SIZE -1;
    $c_80c_romPadding          = $C_80C_MROM_MAX_SIZE - $C_80C_MROM_SIZE;
    $c_userromStartPosition    = $c_80c_romEndPosition + 1;
    $c_userromEndPosition      = $c_userromStartPosition + $C_USERROM_MAX_SIZE -1;
    $c_userromPadding          = $C_USERROM_MAX_SIZE - $C_USERROM_SIZE;
    $c_fdcromStartPosition     = $c_userromEndPosition + 1;
    $c_fdcromEndPosition       = $c_fdcromStartPosition + $C_FDCROM_MAX_SIZE -1;
    $c_fdcromPadding           = $C_FDCROM_MAX_SIZE - $C_FDCROM_SIZE;
    $m12_romStartPosition      = $c_fdcromEndPosition + 1;
    $m12_romEndPosition        = $m12_romStartPosition + $M12_MROM_MAX_SIZE -1;
    $m12_romPadding            = $M12_MROM_MAX_SIZE - $M12_MROM_SIZE;
    $m12_80c_romStartPosition  = $m12_romEndPosition + 1;
    $m12_80c_romEndPosition    = $m12_80c_romStartPosition + $M12_80C_MROM_MAX_SIZE -1;
    $m12_80c_romPadding        = $M12_80C_MROM_MAX_SIZE - $M12_80C_MROM_SIZE;
    $m12_userromStartPosition  = $m12_80c_romEndPosition + 1;
    $m12_userromEndPosition    = $m12_userromStartPosition + $M12_USERROM_MAX_SIZE -1;
    $m12_userromPadding        = $M12_USERROM_MAX_SIZE - $M12_USERROM_SIZE;
    $m12_fdcromStartPosition   = $m12_userromEndPosition + 1;
    $m12_fdcromEndPosition     = $m12_fdcromStartPosition + $M12_FDCROM_MAX_SIZE -1;
    $m12_fdcromPadding         = $M12_FDCROM_MAX_SIZE - $M12_FDCROM_SIZE;
    $a_romStartPosition        = $m12_fdcromEndPosition + 1;
    $a_romEndPosition          = $a_romStartPosition + $A_MROM_MAX_SIZE -1;
    $a_romPadding              = $A_MROM_MAX_SIZE - $A_MROM_SIZE;
    $a_80c_romStartPosition    = $a_romEndPosition + 1;
    $a_80c_romEndPosition      = $a_80c_romStartPosition + $A_80C_MROM_MAX_SIZE -1;
    $a_80c_romPadding          = $A_80C_MROM_MAX_SIZE - $A_80C_MROM_SIZE;
    $a_userromStartPosition    = $a_80c_romEndPosition + 1;
    $a_userromEndPosition      = $a_userromStartPosition + $A_USERROM_MAX_SIZE -1;
    $a_userromPadding          = $A_USERROM_MAX_SIZE - $A_USERROM_SIZE;
    $a_fdcromStartPosition     = $a_userromEndPosition + 1;
    $a_fdcromEndPosition       = $a_fdcromStartPosition + $A_FDCROM_MAX_SIZE -1;
    $a_fdcromPadding           = $A_FDCROM_MAX_SIZE - $A_FDCROM_SIZE;
    $m7_romStartPosition       = $a_fdcromEndPosition + 1;
    $m7_romEndPosition         = $m7_romStartPosition + $M7_MROM_MAX_SIZE -1;
    $m7_romPadding             = $M7_MROM_MAX_SIZE - $M7_MROM_SIZE;
    $m7_80c_romStartPosition   = $m7_romEndPosition + 1;
    $m7_80c_romEndPosition     = $m7_80c_romStartPosition + $M7_80C_MROM_MAX_SIZE -1;
    $m7_80c_romPadding         = $M7_80C_MROM_MAX_SIZE - $M7_80C_MROM_SIZE;
    $m7_userromStartPosition   = $m7_80c_romEndPosition + 1;
    $m7_userromEndPosition     = $m7_userromStartPosition + $M7_USERROM_MAX_SIZE -1;
    $m7_userromPadding         = $M7_USERROM_MAX_SIZE - $M7_USERROM_SIZE;
    $m7_fdcromStartPosition    = $m7_userromEndPosition + 1;
    $m7_fdcromEndPosition      = $m7_fdcromStartPosition + $M7_FDCROM_MAX_SIZE -1;
    $m7_fdcromPadding          = $M7_FDCROM_MAX_SIZE - $M7_FDCROM_SIZE;
    $m8_romStartPosition       = $m7_fdcromEndPosition + 1;
    $m8_romEndPosition         = $m8_romStartPosition + $M8_MROM_MAX_SIZE -1;
    $m8_romPadding             = $M8_MROM_MAX_SIZE - $M8_MROM_SIZE;
    $m8_80c_romStartPosition   = $m8_romEndPosition + 1;
    $m8_80c_romEndPosition     = $m8_80c_romStartPosition + $M8_80C_MROM_MAX_SIZE -1;
    $m8_80c_romPadding         = $M8_80C_MROM_MAX_SIZE - $M8_80C_MROM_SIZE;
    $m8_userromStartPosition   = $m8_80c_romEndPosition + 1;
    $m8_userromEndPosition     = $m8_userromStartPosition + $M8_USERROM_MAX_SIZE -1;
    $m8_userromPadding         = $M8_USERROM_MAX_SIZE - $M8_USERROM_SIZE;
    $m8_fdcromStartPosition    = $m8_userromEndPosition + 1;
    $m8_fdcromEndPosition      = $m8_fdcromStartPosition + $M8_FDCROM_MAX_SIZE -1;
    $m8_fdcromPadding          = $M8_FDCROM_MAX_SIZE - $M8_FDCROM_SIZE;
    $b_romStartPosition        = $m8_fdcromEndPosition + 1;
    $b_romEndPosition          = $b_romStartPosition + $B_MROM_MAX_SIZE -1;
    $b_romPadding              = $B_MROM_MAX_SIZE - $B_MROM_SIZE;
    $b_80c_romStartPosition    = $b_romEndPosition + 1;
    $b_80c_romEndPosition      = $b_80c_romStartPosition + $B_80C_MROM_MAX_SIZE -1;
    $b_80c_romPadding          = $B_80C_MROM_MAX_SIZE - $B_80C_MROM_SIZE;
    $b_userromStartPosition    = $b_80c_romEndPosition + 1;
    $b_userromEndPosition      = $b_userromStartPosition + $B_USERROM_MAX_SIZE -1;
    $b_userromPadding          = $B_USERROM_MAX_SIZE - $B_USERROM_SIZE;
    $b_fdcromStartPosition     = $b_userromEndPosition + 1;
    $b_fdcromEndPosition       = $b_fdcromStartPosition + $B_FDCROM_MAX_SIZE -1;
    $b_fdcromPadding           = $B_FDCROM_MAX_SIZE - $B_FDCROM_SIZE;
    $m20_romStartPosition      = $b_fdcromEndPosition + 1;
    $m20_romEndPosition        = $m20_romStartPosition + $M20_MROM_MAX_SIZE -1;
    $m20_romPadding            = $M20_MROM_MAX_SIZE - $M20_MROM_SIZE;
    $m20_80c_romStartPosition  = $m20_romEndPosition + 1;
    $m20_80c_romEndPosition    = $m20_80c_romStartPosition + $M20_80C_MROM_MAX_SIZE -1;
    $m20_80c_romPadding        = $M20_80C_MROM_MAX_SIZE - $M20_80C_MROM_SIZE;
    $m20_userromStartPosition  = $m20_80c_romEndPosition + 1;
    $m20_userromEndPosition    = $m20_userromStartPosition + $M20_USERROM_MAX_SIZE -1;
    $m20_userromPadding        = $M20_USERROM_MAX_SIZE - $M20_USERROM_SIZE;
    $m20_fdcromStartPosition   = $m20_userromEndPosition + 1;
    $m20_fdcromEndPosition     = $m20_fdcromStartPosition + $M20_FDCROM_MAX_SIZE -1;
    $m20_fdcromPadding         = $M20_FDCROM_MAX_SIZE - $M20_FDCROM_SIZE;
    for(my $idx=$m20_fdcromEndPosition; $idx < 131071; $idx++) { push @MonitorMemory, "\x00"; };

    # Finally, print out details for confirmation.
    #
    logWrite("", sprintf "Monitor ROM Map:\n");
    logWrite("", sprintf "                  80K MROM           =%04x:%04x %04x bytes padding", $k_romStartPosition,       $k_romEndPosition,       $k_romPadding);
    logWrite("", sprintf "           80x25  80K MROM           =%04x:%04x %04x bytes padding", $k_80c_romStartPosition,   $k_80c_romEndPosition,   $k_80c_romPadding);
    logWrite("", sprintf "            USER  80K  ROM           =%04x:%04x %04x bytes padding", $k_userromStartPosition,   $k_userromEndPosition,   $k_userromPadding);
    logWrite("", sprintf "            FDC   80K  ROM           =%04x:%04x %04x bytes padding", $k_fdcromStartPosition,    $k_fdcromEndPosition,    $k_fdcromPadding);
    logWrite("", sprintf "                  80C MROM           =%04x:%04x %04x bytes padding", $c_romStartPosition,       $c_romEndPosition,       $c_romPadding);
    logWrite("", sprintf "           80x25  80C MROM           =%04x:%04x %04x bytes padding", $c_80c_romStartPosition,   $c_80c_romEndPosition,   $c_80c_romPadding);
    logWrite("", sprintf "            USER  80C  ROM           =%04x:%04x %04x bytes padding", $c_userromStartPosition,   $c_userromEndPosition,   $c_userromPadding);
    logWrite("", sprintf "            FDC   80C  ROM           =%04x:%04x %04x bytes padding", $c_fdcromStartPosition,    $c_fdcromEndPosition,    $c_fdcromPadding);
    logWrite("", sprintf "                 1200 MROM           =%04x:%04x %04x bytes padding", $m12_romStartPosition,     $m12_romEndPosition,     $m12_romPadding);
    logWrite("", sprintf "           80x25 1200 MROM           =%04x:%04x %04x bytes padding", $m12_80c_romStartPosition, $m12_80c_romEndPosition, $m12_80c_romPadding);
    logWrite("", sprintf "            USER 1200  ROM           =%04x:%04x %04x bytes padding", $m12_userromStartPosition, $m12_userromEndPosition, $m12_userromPadding);
    logWrite("", sprintf "            FDC  1200  ROM           =%04x:%04x %04x bytes padding", $m12_fdcromStartPosition,  $m12_fdcromEndPosition,  $m12_fdcromPadding);
    logWrite("", sprintf "                  80A MROM           =%04x:%04x %04x bytes padding", $a_romStartPosition,       $a_romEndPosition,       $a_romPadding);
    logWrite("", sprintf "           80x25  80A MROM           =%04x:%04x %04x bytes padding", $a_80c_romStartPosition,   $a_80c_romEndPosition,   $a_80c_romPadding);
    logWrite("", sprintf "            USER  80A  ROM           =%04x:%04x %04x bytes padding", $a_userromStartPosition,   $a_userromEndPosition,   $a_userromPadding);
    logWrite("", sprintf "            FDC   80A  ROM           =%04x:%04x %04x bytes padding", $a_fdcromStartPosition,    $a_fdcromEndPosition,    $a_fdcromPadding);
    logWrite("", sprintf "                  700 MROM           =%04x:%04x %04x bytes padding", $m7_romStartPosition,      $m7_romEndPosition,      $m7_romPadding);
    logWrite("", sprintf "           80x25  700 MROM           =%04x:%04x %04x bytes padding", $m7_80c_romStartPosition,  $m7_80c_romEndPosition,  $m7_80c_romPadding);
    logWrite("", sprintf "            USER  700  ROM           =%04x:%04x %04x bytes padding", $m7_userromStartPosition,  $m7_userromEndPosition,  $m7_userromPadding);
    logWrite("", sprintf "            FDC   700  ROM           =%04x:%04x %04x bytes padding", $m7_fdcromStartPosition,   $m7_fdcromEndPosition,   $m7_fdcromPadding);
    logWrite("", sprintf "                  800 MROM           =%04x:%04x %04x bytes padding", $m8_romStartPosition,      $m8_romEndPosition,      $m8_romPadding);
    logWrite("", sprintf "           80x25  800 MROM           =%04x:%04x %04x bytes padding", $m8_80c_romStartPosition,  $m8_80c_romEndPosition,  $m8_80c_romPadding);
    logWrite("", sprintf "            USER  800  ROM           =%04x:%04x %04x bytes padding", $m8_userromStartPosition,  $m8_userromEndPosition,  $m8_userromPadding);
    logWrite("", sprintf "            FDC   800  ROM           =%04x:%04x %04x bytes padding", $m8_fdcromStartPosition,   $m8_fdcromEndPosition,   $m8_fdcromPadding);
    logWrite("", sprintf "                  80B MROM           =%04x:%04x %04x bytes padding", $b_romStartPosition,       $b_romEndPosition,       $b_romPadding);
    logWrite("", sprintf "           80x25  80B MROM           =%04x:%04x %04x bytes padding", $b_80c_romStartPosition,   $b_80c_romEndPosition,   $b_romPadding);
    logWrite("", sprintf "            USER  80B  ROM           =%04x:%04x %04x bytes padding", $b_userromStartPosition,   $b_userromEndPosition,   $b_userromPadding);
    logWrite("", sprintf "            FDC   80B  ROM           =%04x:%04x %04x bytes padding", $b_fdcromStartPosition,    $b_fdcromEndPosition,    $b_fdcromPadding);
    logWrite("", sprintf "                 2000 MROM           =%04x:%04x %04x bytes padding", $m20_romStartPosition,     $m20_romEndPosition,     $m20_romPadding);
    logWrite("", sprintf "           80x25 2000 MROM           =%04x:%04x %04x bytes padding", $m20_80c_romStartPosition, $m20_80c_romEndPosition, $m20_romPadding);
    logWrite("", sprintf "            USER 2000  ROM           =%04x:%04x %04x bytes padding", $m20_userromStartPosition, $m20_userromEndPosition, $m20_userromPadding);
    logWrite("", sprintf "            FDC  2000  ROM           =%04x:%04x %04x bytes padding", $m20_fdcromStartPosition,  $m20_fdcromEndPosition,  $m20_fdcromPadding);
}
elsif($command eq "CGROM")
{
    # Initialize in memory image.
    @CGMemory = ();

    # Fill the memory image with equisize images.=.
    foreach my $byte (@K_CGROM)   { push @CGMemory, $byte; };  
    foreach my $byte (@C_CGROM)   { push @CGMemory, $byte; };  
    foreach my $byte (@M12_CGROM) { push @CGMemory, $byte; }; 
    foreach my $byte (@A_CGROM)   { push @CGMemory, $byte; };  
    foreach my $byte (@M7_CGROM)  { push @CGMemory, $byte; }; 
    foreach my $byte (@M8_CGROM)  { push @CGMemory, $byte; }; 
    foreach my $byte (@B_CGROM)   { push @CGMemory, $byte; }; 
    foreach my $byte (@M20_CGROM) { push @CGMemory, $byte; }; 

    # Positions for easy reference.
    $k_romStartPosition        = 0;
    $k_romEndPosition          = $K_CGROM_SIZE -1;
    $c_romStartPosition        = $k_romEndPosition + 1;
    $c_romEndPosition          = $c_romStartPosition + $C_CGROM_SIZE -1;
    $m12_romStartPosition      = $c_romEndPosition + 1;
    $m12_romEndPosition        = $m12_romStartPosition + $M12_CGROM_SIZE -1;
    $a_romStartPosition        = $m12_romEndPosition + 1;
    $a_romEndPosition          = $a_romStartPosition + $A_CGROM_SIZE -1;
    $m7_romStartPosition       = $a_romEndPosition + 1;
    $m7_romEndPosition         = $m7_romStartPosition + $M7_CGROM_SIZE  -1;
    $m8_romStartPosition       = $m7_romEndPosition + 1;
    $m8_romEndPosition         = $m8_romStartPosition + $M8_CGROM_SIZE  -1;
    $b_romStartPosition        = $m8_romEndPosition + 1;
    $b_romEndPosition          = $b_romStartPosition + $B_CGROM_SIZE  -1;
    $m20_romStartPosition      = $b_romEndPosition + 1;
    $m20_romEndPosition        = $m20_romStartPosition + $M20_CGROM_SIZE  -1;

    # Finally, print out details for confirmation.
    #
    logWrite("", sprintf "Character Generator ROM Map:\n");
    logWrite("", sprintf "                 80K CGROM           =%04x:%04x", $k_romStartPosition,    $k_romEndPosition);
    logWrite("", sprintf "                 80C CGROM           =%04x:%04x", $c_romStartPosition,    $c_romEndPosition);
    logWrite("", sprintf "                1200 CGROM           =%04x:%04x", $m12_romStartPosition,  $m12_romEndPosition);
    logWrite("", sprintf "                 80A CGROM           =%04x:%04x", $a_romStartPosition,    $a_romEndPosition);
    logWrite("", sprintf "                 700 CGROM           =%04x:%04x", $m7_romStartPosition,   $m7_romEndPosition);
    logWrite("", sprintf "                 800 CGROM           =%04x:%04x", $m8_romStartPosition,   $m8_romEndPosition);
    logWrite("", sprintf "                 80B CGROM           =%04x:%04x", $b_romStartPosition,    $b_romEndPosition);
    logWrite("", sprintf "                2000 CGROM           =%04x:%04x", $m20_romStartPosition,  $m20_romEndPosition);
}
elsif($command eq "KEYMAP")
{
    # Initialize in memory image.
    @KeyMemory = ();

    $maxSize = $A_KEYMAP_SIZE;
    if($K_KEYMAP_SIZE > $maxSize)   { $maxSize = $K_KEYMAP_SIZE; }
    if($C_KEYMAP_SIZE > $maxSize)   { $maxSize = $C_KEYMAP_SIZE; }
    if($M12_KEYMAP_SIZE > $maxSize) { $maxSize = $M12_KEYMAP_SIZE; }
    if($M7_KEYMAP_SIZE > $maxSize)  { $maxSize = $M7_KEYMAP_SIZE; }
    if($M8_KEYMAP_SIZE > $maxSize)  { $maxSize = $M8_KEYMAP_SIZE; }
    if($B_KEYMAP_SIZE > $maxSize)   { $maxSize = $B_KEYMAP_SIZE; }
    if($M20_KEYMAP_SIZE > $maxSize) { $maxSize = $M20_KEYMAP_SIZE; }

    # Fill the memory image with equisize images, zero padding as necessary.
    foreach my $byte (@K_KEYMAP)   { push @KeyMemory, $byte; }; for(my $idx=$K_KEYMAP_SIZE; $idx < $maxSize; $idx++)   { push @KeyMemory, "\x00"; };
    foreach my $byte (@C_KEYMAP)   { push @KeyMemory, $byte; }; for(my $idx=$C_KEYMAP_SIZE; $idx < $maxSize; $idx++)   { push @KeyMemory, "\x00"; };
    foreach my $byte (@M12_KEYMAP) { push @KeyMemory, $byte; }; for(my $idx=$M12_KEYMAP_SIZE; $idx < $maxSize; $idx++) { push @KeyMemory, "\x00"; };
    foreach my $byte (@A_KEYMAP)   { push @KeyMemory, $byte; }; for(my $idx=$A_KEYMAP_SIZE; $idx < $maxSize; $idx++)   { push @KeyMemory, "\x00"; };
    foreach my $byte (@M7_KEYMAP)  { push @KeyMemory, $byte; }; for(my $idx=$M7_KEYMAP_SIZE; $idx < $maxSize; $idx++)  { push @KeyMemory, "\x00"; };
    foreach my $byte (@M8_KEYMAP)  { push @KeyMemory, $byte; }; for(my $idx=$M8_KEYMAP_SIZE; $idx < $maxSize; $idx++)  { push @KeyMemory, "\x00"; };
    foreach my $byte (@B_KEYMAP)   { push @KeyMemory, $byte; }; for(my $idx=$B_KEYMAP_SIZE; $idx < $maxSize; $idx++)   { push @KeyMemory, "\x00"; };
    foreach my $byte (@M20_KEYMAP) { push @KeyMemory, $byte; }; for(my $idx=$M20_KEYMAP_SIZE; $idx < $maxSize; $idx++) { push @KeyMemory, "\x00"; };

    # Positions for easy reference.
    $k_romStartPosition        = 0;
    $k_romEndPosition          = $K_KEYMAP_SIZE + ($maxSize - $K_KEYMAP_SIZE) -1;
    $k_romPadding              = $maxSize - $K_KEYMAP_SIZE;
    $c_romStartPosition        = $k_romEndPosition + 1;
    $c_romEndPosition          = $c_romStartPosition + $C_KEYMAP_SIZE + ($maxSize - $C_KEYMAP_SIZE) -1;
    $c_romPadding              = $maxSize - $C_KEYMAP_SIZE;
    $m12_romStartPosition      = $c_romEndPosition + 1;
    $m12_romEndPosition        = $m12_romStartPosition + $M12_KEYMAP_SIZE + ($maxSize - $M12_KEYMAP_SIZE) -1;
    $m12_romPadding            = $maxSize - $M12_KEYMAP_SIZE;
    $a_romStartPosition        = $m12_romEndPosition + 1;
    $a_romEndPosition          = $a_romStartPosition + $A_KEYMAP_SIZE + ($maxSize - $A_KEYMAP_SIZE) -1;
    $a_romPadding              = $maxSize - $A_KEYMAP_SIZE;
    $m7_romStartPosition       = $a_romEndPosition + 1;
    $m7_romEndPosition         = $m7_romStartPosition + $M7_KEYMAP_SIZE + ($maxSize - $M7_KEYMAP_SIZE) -1;
    $m7_romPadding             = $maxSize - $M7_KEYMAP_SIZE;
    $m8_romStartPosition       = $m7_romEndPosition + 1;
    $m8_romEndPosition         = $m8_romStartPosition + $M8_KEYMAP_SIZE + ($maxSize - $M8_KEYMAP_SIZE) -1;
    $m8_romPadding             = $maxSize - $M8_KEYMAP_SIZE;
    $b_romStartPosition        = $m7_romEndPosition + 1;
    $b_romEndPosition          = $b_romStartPosition + $B_KEYMAP_SIZE + ($maxSize - $B_KEYMAP_SIZE) -1;
    $b_romPadding              = $maxSize - $B_KEYMAP_SIZE;
    $m20_romStartPosition      = $b_romEndPosition + 1;
    $m20_romEndPosition        = $m20_romStartPosition + $M20_KEYMAP_SIZE + ($maxSize - $M20_KEYMAP_SIZE) -1;
    $m20_romPadding            = $maxSize - $M20_KEYMAP_SIZE;

    # Finally, print out details for confirmation.
    #
    logWrite("", sprintf "Key Mapping ROM Map:\n");
    logWrite("", sprintf "                80K KEYMAP           =%04x:%04x %04x bytes padding", $k_romStartPosition,   $k_romEndPosition,   $k_romPadding);
    logWrite("", sprintf "                80C KEYMAP           =%04x:%04x %04x bytes padding", $c_romStartPosition,   $c_romEndPosition,   $c_romPadding);
    logWrite("", sprintf "               1200 KEYMAP           =%04x:%04x %04x bytes padding", $m12_romStartPosition, $m12_romEndPosition, $m12_romPadding);
    logWrite("", sprintf "                80A KEYMAP           =%04x:%04x %04x bytes padding", $a_romStartPosition,   $a_romEndPosition,   $a_romPadding);
    logWrite("", sprintf "                700 KEYMAP           =%04x:%04x %04x bytes padding", $m7_romStartPosition,  $m7_romEndPosition,  $m7_romPadding);
    logWrite("", sprintf "                800 KEYMAP           =%04x:%04x %04x bytes padding", $m8_romStartPosition,  $m8_romEndPosition,  $m8_romPadding);
    logWrite("", sprintf "                80B KEYMAP           =%04x:%04x %04x bytes padding", $b_romStartPosition,   $b_romEndPosition,   $b_romPadding);
    logWrite("", sprintf "               2000 KEYMAP           =%04x:%04x %04x bytes padding", $m20_romStartPosition, $m20_romEndPosition, $m20_romPadding);
}
else
{
    argOptions(1, "Illegal command given on command line:$command.\n",$ERR_BADARGUMENTS);
}

# Output the memory image to the output file.
#
if   (scalar @MainMemory > 0)
{
    foreach my $byte (@MainMemory) { print OUTFILE $byte; }
}
elsif(scalar @MonitorMemory > 0)
{
    foreach my $byte (@MonitorMemory) { print OUTFILE $byte; }
}
elsif(scalar @CGMemory > 0)
{
    foreach my $byte (@CGMemory) { print OUTFILE $byte; }
}
elsif(scalar @KeyMemory > 0)
{
    foreach my $byte (@KeyMemory) { print OUTFILE $byte; }
}

# If a MIF file is required, create it.
#
if($createMIF == 1)
{
    if   (scalar @MainMemory > 0)
    {
        createMIF(\@MainMemory, MIFOUTFILE);
    }
    elsif(scalar @MonitorMemory > 0)
    {
        createMIF(\@MonitorMemory, MIFOUTFILE);
    }
    elsif(scalar @CGMemory > 0)
    {
        createMIF(\@CGMemory, MIFOUTFILE);
    }
    elsif(scalar @KeyMemory > 0)
    {
        createMIF(\@KeyMemory, MIFOUTFILE);
    }
}

exit 0;
