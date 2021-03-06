#!/usr/bin/env perl

use strict;
use File::Basename;
use Capture::Tiny ':all';

my %apps = ();

my $expectedTemplate = 
  "%s: valid on disk\n"
  . "%s: satisfies its Designated Requirement\n"
  . "%s: explicit requirement satisfied\n";

my $notSignedTemplate = 
  "%s: code object is not signed at all\nIn architecture: x86_64\n";

my @launchd = getLaunchdFiles();

my $OSVersion = getOSVersion();

foreach my $plist (@launchd)
  {
  my $path = $plist->{path};
  my $label = $plist->{label};
  my $program = $plist->{program};
  my $programArguments = $plist->{programArguments};
  my $signature = $plist->{signature};
  
  printf("      <key>$path</key>\n");
  printf("      <dict>\n");
  printf("        <key>label</key>\n");
  printf("        <string>$label</string>\n");
  printf("        <key>program</key>\n");
  printf("        <string>$program</string>\n");
  printf("        <key>programArguments</key>\n");
  printf("        <array>\n");
  
  for my $argument (@{$programArguments})
    {
    $argument =~ s/^\s+//;
    $argument =~ s/\s+$//;
    
    printf("          <string>$argument</string>\n");
    }
    
  printf("        </array>\n");
  printf("        <key>signature</key>\n");
  printf("        <string>$signature</string>\n");
  printf("      </dict>\n");
  }
    
sub verify
  {
  my $bundle = shift;
  my $anchor = shift;
  my $expectedResult = shift;
  
  my ($data, $exit) = 
    capture_merged 
      {
      # Don't forget to add --no-strict for 10.9.5 and 10.10 only.
      my $hack = '';
      
      $hack = '--no-strict'
        if ($hack eq '10.9.5') || ($hack =~ /^10.10/);
        
      system(qq{/usr/bin/codesign -vv -R="anchor $anchor" $hack "$bundle"});
      };

  return $expectedResult
    if $data eq sprintf($expectedTemplate, $bundle, $bundle, $bundle);
    
  return "signaturemissing"
    if $data eq sprintf($notSignedTemplate, $ bundle);
    
  return "signaturenotvalid";
  }

sub checkSignature
  {
  my $bundle = shift;
  
  my $shell = $bundle =~ /\.(pl|cgi|d|py|rb|sh)$/;
  
  my $result = 'signaturenotvalid';
  
  if($shell)
    {
    $result = 'signatureshell';
    }
  else
    {  
    $result = verify($bundle, 'apple', 'signatureapple');
  
    if($result eq 'signatureapple')
      {
      $result = 'signatureapple';
      }
    else
      {  
      $result = verify($bundle, 'apple generic', 'signaturevalid');
      }
    }

  return $result;
  }
  
sub getOSVersion
  {
  my ($stdout, $stderr, $exit) = 
    capture 
      {
      # Don't forget to add --no-strict for 10.9.5 and 10.10 only.
      system(qq{system_profiler SPSoftwareDataType});
      };
  
  my ($version) = $stdout =~ /System Version: OS X (\S+) \(.+\)/;
  
  return $version;
  }
  
sub getLaunchdFiles
  {
  my @systemLaunchDaemons = 
    `find /System/Library/LaunchDaemons -type f 2> /dev/null`;
  my @systemLaunchAgents = 
    `find /System/Library/LaunchAgents -type f 2> /dev/null`;
  my @launchDaemons = 
    `find /Library/LaunchDaemons -type f 2> /dev/null`;
  my @launchAgents = 
    `find /Library/LaunchAgents -type f 2> /dev/null`;
  my @userLaunchAgents = 
    `find ~/Library/LaunchAgents -type f 2> /dev/null`;

  my @files = ();
  
  foreach 
    my $plist 
    (@systemLaunchDaemons, 
    @systemLaunchAgents, 
    @launchDaemons, 
    @launchAgents, 
    @userLaunchAgents)
    {
    chomp $plist;
        
    next
      if $plist =~ m|\.DS_Store$|;
    
    my $entries = 
      '-c "Print :Label" -c "Print :Program" -c "Print :ProgramArguments"';
    
    my ($stdout, $stderr, $exit) = 
      capture 
        {
        system(qq{/usr/libexec/PlistBuddy $entries "$plist"});
        };
       
    my %missing;
    
    my (@errors) = split(/\n/, $stderr);
    
    foreach my $error (@errors)
      {
      # This should never happen.
      $missing{label} = 1
        if $error eq 'Print: Entry, ":Label", Does Not Exist';

      $missing{program} = 1 
        if $error eq 'Print: Entry, ":Program", Does Not Exist';
      
      $missing{programArguments} = 1
        if $error eq 'Print: Entry, ":ProgramArguments", Does Not Exist';
      }
      
    # Don't bother.
    next
      if $missing{label};
      
    my $label;
    my $program;
    my @programArguments;
    
    my (@lines) = split(/\n/, $stdout);

    $label = trim(shift(@lines));
    
    $program = trim(shift(@lines))
      if not $missing{program};
      
    @programArguments = @lines
      if not $missing{programArguments};
    
    shift(@programArguments)
      if $programArguments[0] eq 'Array {';
    
    pop(@programArguments)
      if $programArguments[$#programArguments] eq '}';
          
    $program = trim($programArguments[0])
      if not $program;
      
    my $bundle = $program;
      
    my $parent = dirname($program);
    
    if($parent =~ m|(.+)/Contents/MacOS|)
      {
      $bundle = $1;
      }
      
    push 
      @files, 
        {
        path => $plist,
        label => $label,
        program => $program,
        programArguments => \@programArguments,
        signature => checkSignature($bundle)
        }
    }
    
  return @files;
  }
  
sub trim
  {
  my $value = shift;
  
  $value =~ s/^\s+//;
  $value =~ s/\s+$//;
  
  return $value;
  }  