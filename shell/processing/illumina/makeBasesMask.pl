#!/usr/bin/perl

use strict;
use warnings;

my $sample_sheet=$ARGV[0];
my $run_info_xml=$ARGV[1];
my $lane=$ARGV[2];
my $mixedIndex=$ARGV[3];

#parse RunInfo.xml
my $flowcell_id=-1;
my $length_read1=-1;
my $length_idx_read1=-1;
my $length_idx_read2=-1;
my $length_read2=-1;

#parse run info
open(RI, "<$run_info_xml") or die "Unable to open RunInfo file $run_info_xml: $!\n";

while(<RI>){

	
	if(/<Flowcell>(.*?)<\/Flowcell>/){
	    
		$flowcell_id=$1;	
		#print "$flowcell_id\n";
		
	}
	
	
	my $match = 0;
	my $read_number=-1;
	my $cycles=-1;
	my $is_index=-1;

	#HiSeq RunInfo.xml
	if(/<Read Number="(\d)" NumCycles="(\d*?)" IsIndexedRead="([Y|N])"/){

		$read_number=$1;
		$cycles=$2;
		$is_index=$3;

	#MiSeq RunInfo.xml
	} elsif (/<Read NumCycles="(\d*?)" Number="(\d)" IsIndexedRead="([Y|N])"/) {
		
		$read_number=$2;
		$cycles=$1;
		$is_index=$3;

	}

	if($read_number == 1 && $is_index eq "N"){
		$length_read1=$cycles;
	}

	if($read_number == 2 && $is_index eq "N"){
		$length_read2=$cycles;
	}
		
	if($read_number == 2 && $is_index eq "Y"){
		$length_idx_read1=$cycles;
	}
		
	if($read_number == 3 && $is_index eq "N"){
		$length_read2=$cycles;
	}	
		
	if($read_number == 3 && $is_index eq "Y"){
		$length_idx_read2=$cycles;
	}
		
	if($read_number == 4 && $is_index eq "N"){
		$length_read2=$cycles;
	} 
	
}

close(RI);

#print "$length_read1\n";
#print "$length_idx_read1\n";
#print "$length_idx_read2\n";
#print "$length_read2\n";

#parse sample sheet
open(IN, "<$sample_sheet") or die "Unable to open sample sheet $sample_sheet: $!\n";


my $lane_idx = -1;
my $index_idx = -1;

my %lengths_idx1;
my %lengths_idx2;

while(<IN>){
	#my $header_line = <IN>; 
	#chomp($header_line);
	chomp;
			
	#get column indexes
	#my @column_names = split(',', $header_line);
	my @column_names = split(',');
		
		
	my $idx = 0;
	foreach my $name (@column_names){
	
		if($name =~ /Lane/){
			$lane_idx=$idx;
		}
		if($name =~ /Index/){
			$index_idx=$idx;
		}
		$idx++;
	}

	while(<IN>){
	
		chomp;
		my @tokens = split(',');	
		my $token_count=@tokens;
		my $current_lane=$tokens[$lane_idx];

	
		if($current_lane == $lane){
				
			#idx
			if($index_idx != -1 && $tokens[$index_idx] ne ""){
				
				my $seq=$tokens[$index_idx];
				my $idx1="";
				my $idx2="";
				($idx1, $idx2) = split('-',$seq);
				my $length=length($idx1);
				$lengths_idx1{$length}="";
			#print " +++++++++++++++++++++++++++++++++ IDX1 $idx1\n";
			#print " +++++++++++++++++++++++++++++++++ IDX1 $length\n";
				my $lenght=0;
				if($idx2 ne ""){
					my $length=length($idx2);
					$lengths_idx2{$length}="";
					#print " +++++++++++++++++++++++++++++++++ IDX2 index $idx2\n";
					#print " +++++++++++++++++++++++++++++++++ IDX2 lenght $length\n";
				}else
				{
					$lengths_idx2{0}="";
				}
			
			}
			
		}

	} #end of while(<IN>)

	
} #end of while(<IN>)



#get lengths of indexes
my @keys_idx1 = sort {$a<=>$b} keys %lengths_idx1;
my @keys_idx2 = sort {$a<=>$b} keys %lengths_idx2;

my $length_idx1 = get_shortest_index_length(\@keys_idx1, 1);
my $length_idx2 = get_shortest_index_length(\@keys_idx2, 2);

sub get_shortest_index_length {

	my $ref_len = shift;
	my @len = @{$ref_len};
	my $idx_no = shift;
	my $retval = -1;

	#get shortest length
	if(@len != 0){
		$retval = $len[0];
	}

	#warn if there are more than one index length
#	if(@len > 1){
#		
#		print "WARNING: Different lengths index $idx_no @len in lane $lane. Shorter index length ($retval) will be used to generate bases mask.\n";
#
#	} 
		
	return $retval;
			 
}

#generate bases mask

if ($length_idx1==0 && $length_idx2==0){
	$length_idx1=$length_idx_read1;
	$length_idx2=$length_idx_read2;
}

#read 1
my $bases_mask="y".($length_read1-1)."n";

#index read 1
if($length_idx_read1 != -1){
	$bases_mask=$bases_mask.",i".$length_idx1;
	for(my $i = 0; $i < $length_idx_read1 - $length_idx1; $i++){
		$bases_mask=$bases_mask."n";
	}
}

#index read 2
#XXXXXX if mixedIndex && paired-end just skip second index (change the mask)
#if($mixedIndex == 1 && $length_read2 != -1){
#	 $bases_mask=$bases_mask.",n*";
#} else {
	if($length_idx_read2 != -1){
		#$bases_mask=$bases_mask.",i".$length_idx_read2;
		$bases_mask=$bases_mask.",i".$length_idx2;
		for(my $i = 0; $i < $length_idx_read2 - $length_idx2; $i++){
			$bases_mask=$bases_mask."n";
		}
	}
#}

#read 2
if($length_read2 != -1){
	$bases_mask=$bases_mask.",y".($length_read2-1)."n";
}

print "$bases_mask\n";

