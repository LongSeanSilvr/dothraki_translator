# Subroutines for syntactic transfer
#
# Author:     George Wilson - gwilson@computer.org
# Copyright:  George Wilson 2011
# Last Modified: December 2011

use strict;

use POSIX qw(locale_h);
setlocale(LC_CTYPE, "es");
use locale;
use Cwd 'abs_path';

chdir abs_path($0);

package      SynTransfer;
use vars     qw(@ISA @EXPORT @EXPORT_OK $VERSION);
require      Exporter;
@ISA       = qw(Exporter);
@EXPORT    = qw($GrammarFile $LexiconFile $TransferFile
		$SourceLangName $TargetLangName
                $ST_ExternalPreprocessor
                $ST_ExternalPostprocessor
		$ST_DEBUG   $ST_QUIET
                $ST_DisplayFeatures
		$PCPATR_EXE $ST_CodePage
		InitializeAll FinalCleanup
		StatusMessage
		ST_ParseOnly
		ST_Translate);
@EXPORT_OK = qw(%TransferRules %TR_Constraints
                %WorkingLexicon
		ShowTree);
our($VERSION) = 0.99;
our($Rev)     = "7C";

##############  End Header  ##############

## Global variables
our($GrammarFile,     $LexiconFile, $TransferFile);
our($BogusGramFile,   $BogusLexFile);
our($BogusExternalProcessing);
our($CurrentGramFile, $CurrentLexFile);
our(%TransferRules,   @PreProcPatterns, @PostProcPatterns);
our(@MorphRules,      @OOVRules); 
our(%WorkingLexicon, %AllPOS);
our($SourceLangName, $TargetLangName);
our($LexSize);
our($ST_DEBUG, $ST_QUIET);
our(%InsertWords);
our($PCPATR_EXE);
our($ST_ExternalPreprocessor, $ST_ExternalPostprocessor);
our($ST_CodePage) = 1252;
our($ST_DisplayFeatures) = 0;

$BogusGramFile = "BogusTempGrammar.txt";
$BogusLexFile  = "BogusTempLexicon.txt";
$BogusExternalProcessing = "BogusExternalProcessing";

$ST_DEBUG = 0;
$ST_QUIET = 0;
$ST_ExternalPreprocessor = "";
$ST_ExternalPostprocessor = "";

if((-e "pcpatr32.exe") && (-x "pcpatr32.exe")) {
    $PCPATR_EXE = "pcpatr32.exe"; }
elsif((-e "./pcpatr") && (-x "./pcpatr")) {
    $PCPATR_EXE = "./pcpatr"; }


###################################
#  sub InitializeAll
#  Initialize Grammatical Elements
###################################
sub InitializeAll {
    my($TempRule, $pos);

    &LoadLexicon;

    LoadRules($TransferFile);

    ## Create Bogus Grammar for word transfer
    unlink($BogusGramFile);
    open(BGF, ">$BogusGramFile") ||
	die "Unable to create temporary grammar file\n";
    print BGF "Rule  S  -> W / {W S_1}\n\n";
    $TempRule = "Rule  W -> ";
    foreach $pos (keys %AllPOS) { $TempRule .= "$pos / "; }
    $TempRule =~ s/\/\s*\Z//;
    print BGF "$TempRule\n\n";
    close(BGF);

    ## Create Bogus Lexicon to handle OOV
    unlink($BogusLexFile);
    open(BLF, ">$BogusLexFile") || 
	die "Unable to create temporary lexicon file\n";
    open(LF, $LexiconFile) ||
	die "Unable to open lexicon file: $LexiconFile\n";
    while(<LF>) { print BLF; }
    print BLF "\n\n\n\;\; Automatically generated entries\n\n";
    close(BLF);
    close(LF);
    $CurrentLexFile = $BogusLexFile;

}  ## End of InitializeAll


###################################
#  sub FinalCleanup
#  Get rid of temporary files
###################################
sub FinalCleanup {
    # print STDERR "Performing final cleanup\n";
    unlink($BogusGramFile);
    unlink($BogusLexFile);
} ## End of FinalCleanup


###################################
#  sub StatusMessage
#  Generate a status message for display
###################################
sub StatusMessage {
    my($Message) = "";
    my($temp);

    $Message .= "SyntacticTransfer          Version $VERSION Rev $Rev\n";
    $Message .= "Grammar File:              $GrammarFile\n";
    $Message .= "Lexicon File:              $LexiconFile\n";
    $Message .= "Lexical Entries:           $LexSize\n";
    $temp     = scalar(keys %TransferRules);
    $Message .= "Transfer Rules File:       $TransferFile\n";
    $Message .= "Transfer Rules:            $temp\n";
    $temp     = scalar(@MorphRules);
    $Message .= "Morphological Rules:       $temp\n";
    $temp     = scalar(@OOVRules);
    $Message .= "OOV Rules:                 $temp\n";
    $temp     = scalar(@PreProcPatterns);
    $Message .= "PreProcessing Patterns:    $temp\n";
    $temp     = scalar(@PostProcPatterns);
    $Message .= "PostProcessing Patterns:   $temp\n";

    if($SourceLangName && $TargetLangName) {
	$Message .= "\nTranslating from $SourceLangName to $TargetLangName\n";}
    if($ST_DEBUG) { $Message .= "Debug is ON\n"; }
    if($Message)  { $Message .= "\n"; }

    return($Message);
} ## End of StatusMessage


#################################
#  sub LoadRules
#  Load transfer rules from file
#################################
sub LoadRules {
    my($TRFile);
    ($TRFile) = @_;

    my($SaveDelim);
    my($Source, $Target, $Constraints);
    my($temp, $Targ2, $GoodTarget, $Missed, @Targ2Elements);
    my($Find, $Replace, $Context);
    my(@MRule, $i);
    my(@Labels, $l);
    my($SList, $TList);
    my($TempC);

    $SaveDelim = $/;

    ## open transfer file for processing
    open(TRF, $TRFile) ||
	die "Unable to open transfer rules: $TRFile\n";

    ## Check for language names
    seek(TRF, 0, 0);
    $/ = "";
    while(<TRF>) {
	s/\n[;\#].*//g;
	if(/<SourceLanguageName>\s*(.*\S)\s*<\/SourceLanguageName>/msi) {
	    $SourceLangName = $1; }
	if(/<TargetLanguageName>\s*(.*\S)\s*<\/TargetLanguageName>/msi) {
	    $TargetLangName = $1; }
    }

    ## Load transfer rules
    undef %TransferRules;
    $/ = "</TRule>";
    seek(TRF, 0, 0);
    while(<TRF>) {
	s/\n[;\#].*//g;
	if(/<TRule[^>]*>(.*)/ms) { $_ = $&; }
	else { next; }
	s/->/ -> /g;
	s/\s\s+/ /msg;

	undef($Source);
	undef($Target);
	if(/<Source[^>]*>\s*(\S+\s*->\s*.*)<\/Source>/msi) {
	    $Source = $1;
	    $Source =~ s/\s*\Z//; }

	if(/<Target[^>]*>\s*(.*)<\/Target>/msi) {
	    $Target = $1;
	    while($Target =~ s/(\[[^\s\]]*)\s+(.*?\])/$1$2/) { 1; }
	    $Target =~ s/\s*\Z//; 
        }

	unless(defined $Source) {
	    print STDERR "Bad transfer rule - No Source (Rule ignored):\n$_\n";
	    next; }	
	unless(defined $Target) {
	    print STDERR "Bad transfer rule - No Target (Rule ignored):\n$_\n";
	    next; }

	## Test that components of target are in source
	$Targ2 = $Target;
	$Targ2 =~ s/\[.*?\]//g;
	$Targ2 =~ s/[\(\)]//g;
	$Targ2 =~ s/\A\s+//;
	$Targ2 =~ s/\s+\Z//;
	@Targ2Elements = split(/\s+/, $Targ2);
	$GoodTarget = 1;
	foreach $temp (@Targ2Elements) {
	    $temp = quotemeta($temp);
	    unless($Source =~ /\b$temp\b/) { 
		print STDERR "** Bad transfer rule. RULE IGNORED\n";
		print STDERR "**    Target contains $temp missing from source. \n";
		$GoodTarget = 0; 
		last; }
	}
	unless($GoodTarget) { next; }
	## check format of added words
	while($Target =~ /\[(.*?)\]/g) {
	    $temp = $1;
	    unless($temp =~ /\S\s*,\s*\S/) {
		print STDERR "** Bad transfer rule. RULE IGNORED\n";
		print STDERR "**   Target contains incorrectly formatted insertion [$temp]\n";
		$GoodTarget = 0;
		last; }
	}
	unless($GoodTarget) { next; }

	## Add in constraints 
	$Constraints = "";
	while(/<Constraint[^>]*>\s*(.*?)<\/Constraint>/gmsi) {
	    $TempC = $1;
	    $TempC =~ s/\s*=\s*/=/g;
	    $TempC =~ s/\s*\Z//;
	    # $TempC = quotemeta($TempC);
	    $Constraints .= " \|\:\| $TempC"; }

	## Add in constant terms 
	@Labels = split(/\s+/, $Target);
	foreach $l (@Labels) {
	    if($l =~ /\[(\w+),(.+?)\]/) {
		my(@Temp) = (1, $1, "<cat>=$1 \|\:\| <gloss>=$2 \|\:\| lex=Inserted");
		$InsertWords{$l} = \@Temp; }
	}

	if($Source =~ /\(\S+\)/) { 
	    ($SList, $TList) =  ExpandTRules($Source, $Target);
	    for($i=0; $i<scalar(@{$SList}); $i++) {
		if(${$SList}[$i] =~ /->\s*(.+)/) {
		    $temp = $1;
		    if($temp eq ${$TList}[$i]) {
			next; }
		}
		while(${$SList}[$i] =~ /(\S+)_1\b/g) {
		    $temp = $1;
		    unless(${$SList}[$i] =~ /\b${temp}_2/) {
			${$SList}[$i] =~ s/\b${temp}_1\b/$temp/g; 
			${$TList}[$i] =~ s/\b${temp}_1\b/$temp/g;  }
		}
		push(@{$TransferRules{${$SList}[$i]}}, ${$TList}[$i] . $Constraints); }
	} else {
	    push(@{$TransferRules{$Source}}, $Target . $Constraints);
	}
    }

    ## Load PostProcessing rules
    $/ = "</PostProc>";
    seek(TRF, 0, 0);
    undef @PostProcPatterns;
    while(<TRF>) {
	s/\n[;\#].*//g;
	if(/<PostProc[^>]*>(.*)/ms) { $_ = $&; }
	else { next; }
	s/\s\s+/ /msg;

	undef($Find);
	undef($Replace);
	if(/<Find[^>]*>(.*)<\/Find>/msi) {
	    $Find = $1; }
	if(/<Replace[^>]*>(.*)<\/Replace>/msi) {
	    $Replace = $1; }
	unless((defined $Find) && (defined $Replace)) {
	    print STDERR "Bad PostProcessing rule:\n$_\n";
	    exit; }
	push(@PostProcPatterns, [$Find, $Replace]);
    }

    ## Load PreProcessing rules
    $/ = "</PreProc>";
    seek(TRF, 0, 0);
    undef @PreProcPatterns;
    while(<TRF>) {
	s/\n[;\#].*//g;
	if(/<PreProc[^>]*>(.*)/ms) { $_ = $&; }
	else { next; }
	s/\s\s+/ /msg;

	undef($Find);
	undef($Replace);
	$Context = "";
	if(/<Find[^>]*>(.*?)<\/Find>/msi) {
	    $Find = $1; }
	if(/<Replace[^>]*>(.*?)<\/Replace>/msi) {
	    $Replace = $1; }
	if(/<Context[^>]*>(.*?)<\/Context>/msi) {
	    $Context = $1; }
	unless((defined $Find) && (defined $Replace)) {
	    print STDERR "Bad PreProcessing rule:\n$_\n";
	    exit; }
	if($Find &&  $Replace) {
	    push(@PreProcPatterns, [$Find, $Replace, $Context]); }
	else {
	    print STDERR "Ill-formed PreProcessing Rule:\n$_\n"; }
    }

    ## Load morphological rules (for known roots)
    undef @MorphRules;
    $/ = "</Morph>";
    seek(TRF, 0, 0);
    while(<TRF>) {
	s/\n[;\#].*//g;
	if(/<Morph[^>]*>\s*(.*)/ms) { $_ = $1; }
	else { next; }
	s/<\/Morph>//;
	s/\s\s+/ /msg;

	@MRule = split(/\s*,\s*/, $_);
	for($i=0; $i<8; $i++) {
	    unless($MRule[$i]) { $MRule[$i] = ""; }
	    $MRule[$i] =~ s/\"(.*)\"/$1/; }
	push(@MorphRules, 
	     [ $MRule[0], $MRule[1], $MRule[2], $MRule[3],
	       $MRule[4], $MRule[5], $MRule[6], $MRule[7]]);
    }

    ## Load morphological rules (for OOV)
    $/ = "</OOV>";
    seek(TRF, 0, 0);
    undef @OOVRules;
    while(<TRF>) {
	s/\n[\;\#].*//g;
	if(/<OOV[^>]*>\s*(\S.*?)<\/OOV>/ms) { $_ = $1; }
	else { next; }
	s/\s\s+/ /msg;

	@MRule = split(/\s*,\s*/, $_);
	for($i=0; $i<4; $i++) {
	    unless($MRule[$i]) { $MRule[$i] = ""; }
	    $MRule[$i] =~ s/\"(.*)\"/$1/; }
	push(@OOVRules, [$MRule[0], $MRule[1], $MRule[2]]);
    }
    close(TRF);

    $/ = $SaveDelim;
    return(1);
}  ## End of LoadRules


#################################
#  sub ExpandTRules 
# Handle optional tokens in transfer rules
#################################
sub ExpandTRules {
    my($source, $target);
    ($source, $target) = @_;
    my(@SList, @TList, $sl, $tl);
    my($source1, $target1, $source2, $target2);
    my($Optional);

    if($source =~ /\((\S+)\)/) {
	$Optional = $1;

	$source1 = $source;
	$source1 =~ s/\($Optional\)//;
	$source1 =~ s/\s+/ /g;
	$source1 =~ s/\s+\Z//;
	$target1 = $target;
	$target1 =~ s/\($Optional\)//;
	$target1 =~ s/\s+/ /g;
	$target1 =~ s/\s+\Z//;
	$target1 =~ s/\A\s+//;

	$source2 = $source;
	$source2 =~ s/\($Optional\)/$Optional/;
	$target2 = $target;
	$target2 =~ s/\($Optional\)/$Optional/;

	($sl, $tl) = ExpandTRules($source1, $target1);
	push(@SList, @{$sl});
	push(@TList, @{$tl});
	($sl, $tl) = ExpandTRules($source2, $target2);
	push(@SList, @{$sl});
	push(@TList, @{$tl});
    } else {
	push(@SList, $source);
	push(@TList, $target);
    }
    
    return(\@SList, \@TList);

}  ## End of ExpandTRules



#################################
#  sub LoadLexicon
#  Load PC-PATR Lexicon
#  Intended for word transfer
#  as a backup strategy         
#################################
sub LoadLexicon {
    my($word, $class, $gloss, $entry);
    my($SaveDelim) = $/;
    $/ = "";
    undef %AllPOS;

    open(ST_LEX, $LexiconFile) ||
	die "Unable to open Lexicon: $LexiconFile\n";
    undef %WorkingLexicon;
    $LexSize = 0;
    while(<ST_LEX>) {
	$entry = $_;
	while(s/\A\;.*\n//) { 1; }
	s/\s+/ /msg;
	$word = $class = $gloss = "";
	if(/\A\s*\\w\s+(\S[^\\]*)/ms)  { 
	    $word = $1; 
	    $word =~ s/\s+\Z//; }
	if(/\\c\s+(\S+)/ms)       { $class = $1; }    
	if(/\\g\s+(\S[^\\]*)/ms) { 
	    $gloss = $1; 
	    $gloss =~ s/\s+\Z//;
	    if($gloss =~ /\s*\\[cfw]/msi) { $gloss = $`; }
	}
	if($word && $class) {
            unless($gloss) { $gloss = " "; }
	    $LexSize++;
	    $AllPOS{$class}++;
	    $WorkingLexicon{$word}{"entry"} .= "$entry\n"; 
	    $WorkingLexicon{$word}{$class} = $gloss; }
    }
    close(ST_LEX);
    $/ = $SaveDelim;
}  ## End of LoadLexicon


###################################
#  sub EnhanceLexicon
#  Add OOV to Lexicon
###################################
sub EnhanceLexicon {
    my($w, $i, $k, $lcw, $temp, $UseCount, $rule, $pref, $stem, $gloss);
    my($DefPOS, $DefFeat);
    my(@Words) = split(/\P{Alnum}+/, $_[0]);

    $DefPOS  = "";
    $DefFeat = "";

    ## Create Bogus Lexicon to handle OOV
    open(BLF, ">>$BogusLexFile");
    foreach $w (@Words) {
	unless($w =~ /\w/) { next; }
	if($WorkingLexicon{$w}) { next; }
	if($WorkingLexicon{lc($w)}) { 
	    $lcw = lc($w);
	    $temp = $WorkingLexicon{$lcw}{"entry"};
	    $temp =~ s/w\s+$lcw\b/w $w/gms;
	    print BLF $temp;
	    foreach $k (keys %{$WorkingLexicon{$lcw}}) {
		$WorkingLexicon{$w}{$k} = $WorkingLexicon{$lcw}{$k}; }
	    next; }

	if($ST_DEBUG) { print STDERR "Adding unknown word: \"$w\"\n"; }
	$WorkingLexicon{$w}{"INSERTED"} = "  ";
	$UseCount = 0;

	## Morphology with known roots
	for($i = 0; $i <= $#MorphRules; $i++) {
	    if($w =~ /$MorphRules[$i][0]\Z/i) {
		$stem = $`;
		if($WorkingLexicon{$stem . $MorphRules[$i][1]} &&
		   $WorkingLexicon{$stem . $MorphRules[$i][1]}{$MorphRules[$i][2]}) {
		    $gloss = $WorkingLexicon{$stem . $MorphRules[$i][1]}{$MorphRules[$i][2]};
		    if($MorphRules[$i][4]) {
			unless($gloss =~ /$MorphRules[$i][4]\Z/) { next; }}
		    $gloss =~ s/$MorphRules[$i][4]\Z//;
		    $gloss = $MorphRules[$i][5] . $gloss . $MorphRules[$i][6];
		    
		    $UseCount++;
		    print BLF "\\w $w\n\\c $MorphRules[$i][3]\n";
		    print BLF "\\g $gloss\n\\f $MorphRules[$i][7]\n\n"; 
		}
	    }
	}
	if($UseCount) { next; }

	## Morphology without known roots
	for($i = 0; $i <= $#OOVRules; $i++) {
	    if($OOVRules[$i][0] eq "DEFAULT") {
		$DefPOS  = $OOVRules[$i][1];
		$DefFeat = $OOVRules[$i][2]; 
		next; }
	    if($w =~ /$OOVRules[$i][0]/i) {
		$UseCount++;
		print BLF "\\w $w\n\\c $OOVRules[$i][1]\n";
		print BLF "\\f $OOVRules[$i][2]\n\\g $w\n\n"; }
	}
	unless($UseCount) {
	    if($DefPOS) {
		print BLF "\\w $w\n\\c $DefPOS\n";
		print BLF "\\g $w\n\\f $DefFeat\n\n"; }
	}
    }
    close(BLF);

}  ## End of EnhanceLexicon


##################################
#  sub PCP_Parse                 #
#  Use PC-PATR to get parse tree #
##################################
sub PCP_Parse {
    my($Sentence, $Result, $SaveRS);
    ($Sentence)   = @_;
    my($TempFile) = "TempPCPATR_CommandFile.tak"; 
    my($LogFile)  = "TempPCPATR_LogFile.txt";
    my($Junk)     = "DeletableJunk.txt";

    unlink($TempFile);
    unlink($LogFile);
    open(CMD, ">$TempFile");
    print CMD "set warn off\n";
    print CMD "set tree XML\n";
    print CMD "load grammar $CurrentGramFile\n";
    print CMD "load lexicon $CurrentLexFile\n";
    print CMD "log $LogFile\n";
    print CMD "parse $Sentence\n";
    print CMD "close\n";
    print CMD "exit\n";
    close(CMD);
    `wine $PCPATR_EXE -q -t $TempFile 2> $Junk`;
    unlink($TempFile);
    unlink($Junk);

    $SaveRS = $/;
    undef $/;
    if(open(RESULT, $LogFile)) {
	$Result = <RESULT>;
	close(RESULT); 
	}
    else { 
	$Result = "Error_1\: Unable to access PC-PATR - $PCPATR_EXE"; 
        return($Result);
    }
    $/ = $SaveRS;
    unlink($LogFile);

    if($Result =~ /<Parse>.*<\/Parse>/ims)   { $Result = $&; }
    else { $Result = ""; }
    return($Result);
}  ## End of PCP_Parse

########################################
# sub Proc_PCP_XML                     #
# Input  PCP XML tree                  #
# Output Array of parses               #
########################################
sub Proc_PCP_XML {
    my($String) = @_;
    my(@Parses);
    my($PString);
    my($Tail, $P);
    
    while($String =~ /<Parse[^>]*>\s*(.*?)<\/Parse>(.*)/msi) {
	$PString = $1;
	$String  = $2;
	($Tail, $P) = XML2TreeObj($PString);
	push(@Parses, $P);
    }
    return(@Parses);
}  ## End of sub Proc_PCP_XML


##################################################
# sub XML2TreeObj                                #
# Input:  XML Parse from PCPatr                  #
# Output: Parse Tree Object                      #
#                                                #
# Object format: TERM CAT FEATURES CONTENT       #
# For a leaf, there is no content                #
# For a node, the content is an array of objects #
##################################################
sub XML2TreeObj {
    my($String) = @_;
    my(@Node);
    my($Rest, $R2);
    my($Label, $Label2, $Desc, $Content);
    my($SubNode);

    if($String =~ /<(\S+)\s*([^>]*)>(.*)/msi) {
	$Label = $1;
	$Desc  = $2;
	$Rest  = $3;

	if($Label =~ /\ALeaf\Z/i) {
	    if($Rest =~ /\A(.*?)<\/Leaf>(.*)/msi) {
		$Content = $1;
		$Rest    = $2;
		$Node[0] = 1;

		if($Content =~ /<FS>(.*?)<\/FS>(.*)/msi) {
		    $Node[2] = XML2FS($1); }
		else { $Node[2] = ""; }
		
		if($Node[2] =~ /<cat>=(.*?) \|\:\|/i) {
		    $Node[1] = $1; }
	    }
	}
	elsif($Label =~ /\ANode\Z/i) {
	    $Node[0] = 0;
	    if($Desc =~ /cat=\"(.*?)\"/msi) { $Node[1] = $1; }
	    else { $Node[1] = ""; }

	    ## Get features
	    if($Rest =~ /<FS>(.*?)<\/FS>(.*)/msi) {
		$Rest = $2;
		$Node[2] = XML2FS($1); }
	    else { $Node[2] = ""; }

	    ## Get rest of node structure
	    while($Rest =~ /<([^\s>]+)[^>]*>(.*)/msi) {
		$Label2 = $1;
		$R2     = $2;
		
		if($Label2 =~ /\A\/Node/i) { $Rest = $R2; last; }
		else { 
		    ($Rest, $SubNode) = XML2TreeObj($Rest);
		    push(@Node, $SubNode); }
	    }
	}
    }

    return($Rest, \@Node);
}    ## End of sub XML2TreeObj


##############################################
# sub XML2FS                                 #
# Input:  XML Feature List                   #
# Output: Feature String                     #
##############################################
sub XML2FS {
    my($String)   = @_;
    my($FName, $FContent);
    my($FSString) = "";

    while($String =~ /<F\s+name=\"(.*?)\">(.*?)<\/F>(.*)/msi) {
	$FName    = $1;
	$FContent = $2;
	$String   = $3;
	if($FContent =~ /<Str>(.*?)<\/Str>(.*)/msi) {
	    $FSString .= "<$FName>=$1 \|\:\| "; }
    }
    $FSString =~ s/\s+\|\:\|\s+\Z//;
    $FSString =~ s/\s*=\s*/=/g;
    return($FSString);
}  ## End of sub XML2FS



###################################################
#  sub AddSeqNums
#  Add Sequence numbers to tokens in transfer rules
###################################################
sub AddSeqNums {
    my($rule);
    ($rule) = @_;

    my(@Tokens, $t, $temp, $TCount);
    my($Head, $Expansion, $E2);
    
    if($rule =~ /\s*->\s*(.*)/) {
	$Head = $` . $&;
	$Expansion = $1; }
    else {
	$Head = "";
	$Expansion = $rule; }
    
    @Tokens = split(/\s+/, $Expansion);
    $E2 = "";
    $TCount = 0;
    while($rule =~ /_(\d+)\b/g) {
	if($1 > $TCount) { $TCount = $1; } }
    foreach $t (@Tokens) {
	unless($t =~ /_\d+\b/) { 
	    $TCount++; 
	    if($t =~ /\A\[\w+,.*\]\Z/) {
		$temp = "_$TCount"; 
		$t =~ s/\A(\[\w+)(,.*\])\Z/$1$temp$2/; }
	    else { $t .= "_$TCount"; }
	}
	$E2 .= " $t";
    }
    $E2 =~ s/\A\s+//;
    return("$Head$E2");
}  ## End of AddSeqNums


###################################
#  sub BuildSent                  #
#  Construct transferred sentence #
# Object format: TERM CAT FEATURES CONTENT #
###################################
sub BuildSent {
    my($Tree) = @_;
    my(@TArray, $gloss, $obj, @OBJ, $Sent);
    
    @TArray = @{$Tree};

    $Sent = "";
    if($TArray[0]) { 
	if($TArray[2] =~ /<gloss>=(.*)/) { 
	    $gloss = $1;
	    if($gloss =~ / \|\:\|/) { $gloss = $`; }
	    unless($gloss =~ /\S/)  { $gloss = ""; }	
	    if($gloss) { $Sent .= " $gloss"; }
	}
    }
    else {
	shift(@TArray);
	shift(@TArray);
	shift(@TArray);
	foreach $obj (@TArray) { $Sent .= BuildSent($obj); }
    }
    return($Sent);
}  ## End of BuildSent


#######################
#  sub ShowTree       #
#  Display parse tree #
# Object format: TERM CAT FEATURES CONTENT #
#######################
sub ShowTree {
    my($Pad, $Tree, $FeatureFlag) = @_;
    my($Pad2, @TArray, $obj, @OBJ);
    my($Label);
    
    $Pad2 = $Pad . "   ";

    @TArray = @{$Tree};
    if($TArray[0]) {
	if($FeatureFlag) {
	    print "$Pad$TArray[1] $TArray[2]\n"; }
	else {
	    $FeatureFlag = 0;
	    if($TArray[2] =~ /<lex>=(.*)/) {
		$Label = $1;
		if($Label =~ / \|\:\|/) { $Label = $`; }}
	    if($TArray[2] =~ /<gloss>=(.*)/) {
		$Label = $1;
		if($Label =~ / \|\:\|/) { $Label = $`; }}
	    print "$Pad$TArray[1] $Label\n"; }
    } else {
	print "$Pad$TArray[1]\n";
	shift(@TArray);
	shift(@TArray);
	shift(@TArray);
	foreach $obj (@TArray) {
	    ShowTree($Pad2, $obj, $FeatureFlag); }
    }
}  ## End of ShowTree

#####################################
#  sub TransferTree                 #
#  Use rules to transfer structure  #
# Object: TERM CAT FEATURES CONTENT #
#####################################
sub TransferTree {
    my($SA) = @_;
    my(@Labels, @SArray, @TArray, %LabeledObjects);
    my($i, $l, $qml, $SourceRule);
    my($PhraseType, $TagSeq, $Counter, $sub);
    my($Target, $MeetsConstraints);
    my($c, $copy, $Tag, $TR);
    my(@LabeledConstraints, @Constraints);
    my($TreeTransferred);
    my($RuleApplied) = 0;

    unless($SA) { return; }

    @SArray = @{$SA};
    $TArray[0] = $SArray[0];
    $TArray[1] = $SArray[1];
    $TArray[2] = $SArray[2];
    
    if($SArray[0]) { return($SA); }
    else {
	$SourceRule = "$SArray[1] ->";
	for($i=3; $i<= $#SArray; $i++) {
	    $SourceRule .= " $SArray[$i][1]"; 
	}
    }

    ## Remove structure numbers and flags for non-unique parses
    while($SourceRule =~ s/\b(\S+)_\d+\+?(\s|\Z)/$1$2/) { 1; }

    ## Check to see if Source tree needs to be numbered
    $SourceRule =~ /\s*->\s+(.*)/ms;
    $PhraseType = $`;
    $TagSeq     = $1;
    @Labels = split(/\s+/, $TagSeq);

    foreach $l (@Labels) {
	$qml = quotemeta($l);
	if($TagSeq =~ /\b$qml\b.*\b$qml\b/) {
	    $Counter = 1;
	    $sub = "${qml}_1";
	    while($TagSeq =~ s/\b$qml\b/$sub/) { 
		$Counter++; $sub = "${qml}_$Counter"; }
	}
    }
    $SourceRule = "$PhraseType -> $TagSeq";


    if($TransferRules{$SourceRule}) {
	$TreeTransferred = 0;
	
	foreach $TR (@{$TransferRules{$SourceRule}}) {
	    if($TR =~ /\s+\|\:\|\s+(.*)/) {
		$Target = $`;
		@Constraints = split(/\s*\|\:\|\s*/, $1); }
	    else {
		$Target = $TR;
		@Constraints = (); }

	    $SourceRule =~ /->\s+(.*)/;
	    @Labels = split(/\s+/, $1);
	    
	    ## Store source objects with labels
	    for($i=3; $i<=$#SArray; $i++) {
		$LabeledObjects{$Labels[$i-3]} = $SArray[$i]; }
	    
	    ## Test constraints
	    $MeetsConstraints = 1;
	    foreach $c (@Constraints) {
		$copy = $c;
		$copy =~ s/\s+\Z//;
		if($copy =~ s/<(\S+)\s+(\S+>=.*)/<$2/) { 
		    $Tag = $1; }
		else { next; }
		unless($LabeledObjects{$Tag}[2] && 
		       ($LabeledObjects{$Tag}[2] =~ /$copy(\s|\Z)/i)) {
		    $MeetsConstraints = 0; last;}
	    }
	    
	    if($MeetsConstraints) {
		if($ST_DEBUG) {
		    print STDERR "Using TransRule: $SourceRule  =>  $Target\n"; }
		$RuleApplied = 1;

		## Move nodes around
		@Labels = split(/\s+/, $Target);
		foreach $l (@Labels) {
		    if($l =~ /\[(\w+),(.+?)\]/) {
			push(@TArray, $InsertWords{$l}); }
		    else {
			push(@TArray, TransferTree($LabeledObjects{$l})); }
		}
		$TreeTransferred = 1; 
		last;
	    } 
	}
	unless($TreeTransferred) {
	    for($i=3; $i<= $#SArray; $i++) {
		$TArray[$i] =  TransferTree($SArray[$i]); }
	}
    }
    else {
	for($i=3; $i<= $#SArray; $i++) {
	    $TArray[$i] =  TransferTree($SArray[$i]); }
    }

    ## Allow repeated application
    if($RuleApplied) {
	return(TransferTree(\@TArray)); }
    else { 
	return(\@TArray); }

}  ## End of TransferTree


###########################################
#  sub PreProcessSent
#  Apply specialized transformation rules
###########################################
sub PreProcessSent {
    my($Sent) = @_;
    my($i, $code,$Sent2);
    unless($Sent) { return ""; }

    if($ST_ExternalPreprocessor) {
	open(BTPF, ">$BogusExternalProcessing");
	print BTPF $Sent;
	close(BTPF);
	$Sent2 = `$ST_ExternalPreprocessor $BogusExternalProcessing`;
	unlink($BogusExternalProcessing);
	if($Sent2) { $Sent = $Sent2; }
    }

    for($i=0; $i<=$#PreProcPatterns; $i++) {
	unless($PreProcPatterns[$i][2] && 
	       ($Sent !~ /$PreProcPatterns[$i][2]/i)) {
	    $code = "\$Sent =~ s/$PreProcPatterns[$i][0]/$PreProcPatterns[$i][1]/migs;";
	    eval($code); }
    }
    
    $Sent =~ s/\s+/ /g;
    return($Sent);
}  ## End of sub PreProcessSent


###########################################
#  sub PostProcessSent
#  Apply specialized transformation rules
###########################################
sub PostProcessSent {
    my($Sent) = @_;
    my($i, $code, $Sent2);

    if($ST_ExternalPostprocessor) {
	open(BTPF, ">$BogusExternalProcessing");
	print BTPF $Sent;
	close(BTPF);
	$Sent2 = `$ST_ExternalPostprocessor $BogusExternalProcessing`;
	unlink($BogusExternalProcessing);
	if($Sent2) { $Sent = $Sent2; }
    }

    for($i=0; $i<=$#PostProcPatterns; $i++) {
	$code = "\$Sent =~ s/$PostProcPatterns[$i][0]/$PostProcPatterns[$i][1]/migs;";
	eval($code); }
    
    $Sent =~ s/\s+/ /g;
    return($Sent);
}  ## End of sub PostProcessSent


##########################
#  sub ST_Translate      #
#  Translate Sentence    #
##########################
sub ST_Translate {
    my($Sent);
    ($Sent) = @_;

    my($Parsed, $Tree, $Translated);
    my(@Trees);

    ## Use main Grammar
    $CurrentGramFile = $GrammarFile;

    ## Add OOV to lexicon
    $Sent = PreProcessSent($Sent);

    if($ST_DEBUG && (scalar(@PreProcPatterns) || $ST_ExternalPreprocessor)) {
	print STDERR "After PreProcessing: $Sent\n"; }
    unless($Sent =~ /\S/) { return(""); }

    EnhanceLexicon($Sent);
    
    $Parsed = PCP_Parse($Sent);
    if($Parsed) {
	if($Parsed =~ /\AError_\d+:/) { 
	    $Translated = $Parsed; }
	else {
	    @Trees= Proc_PCP_XML($Parsed);

	    if((scalar(@Trees) > 1) && $ST_DEBUG) {
		print STDERR "   ", scalar(@Trees), " parses found\n"; }
	    if($ST_DEBUG) { print ShowTree("", $Trees[0], $ST_DisplayFeatures); }

	    $Tree = TransferTree($Trees[0]);
	    if($ST_DEBUG) { 
		print "\nTransferred:\n"; 
		print ShowTree("", $Tree, $ST_DisplayFeatures), "\n"; }
	    $Translated = PostProcessSent(BuildSent($Tree));
	}
    } else {
	## No parse, use word transfer
	## print STDERR "Trying word transfer\n";
	$CurrentGramFile = $BogusGramFile;
	$Parsed = PCP_Parse($Sent);
	if($Parsed) {
	    @Trees = Proc_PCP_XML($Parsed);
	    $Tree = TransferTree($Trees[0]);
	    $Translated = "* " . PostProcessSent(BuildSent($Tree)); } 
	else { $Translated = ""; }
    }

    return($Translated);
} ## End of sub ST_Translate


############################
#  sub ST_ParseOnly        #
#  Parse using morphology  #
#  and preprocessing       #
############################
sub ST_ParseOnly {
    my($Sent);
    ($Sent) = @_;

    my($Parsed, $LeftOver, $Tree, $Translated);

    ## Use main Grammar
    $CurrentGramFile = $GrammarFile;

    ## Add OOV to lexicon
    $Sent = PreProcessSent($Sent);
    EnhanceLexicon($Sent);

    $Parsed = PCP_Parse($Sent);
    return($Parsed);
} ## End of sub ST_ParseOnly


1;
##############  End Code  ##############
__END__


=pod Perl Documentation Begins

=head1  Module SynTransfer

 Title:          Syntactic Transfer
 Author:         Dr. George Wilson
 Email:          gwilson@computer.org
 Version:        0.99 Rev 7C
 Last Modified:  December 2011

=head1 Copyright Notice

This work is copywritten material, owned by the author.
You may use it freely for non-commercial purposes.
Any commercial use requires an agreement with the author.
Copyright 2011  George Wilson

=head1 Contents

=item  ST_Translate
    
    Translate using syntactic transfer

You will have to wait for real documentation

=cut
    
