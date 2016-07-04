/***********************************************************************
 ** Etresoft
 ** John Daniel
 ** Copyright (c) 2016. All rights reserved.
 **********************************************************************/

#import "UnknownFilesManager.h"
#import "Model.h"
#import "NSMutableAttributedString+Etresoft.h"
#import "Utilities.h"
#import "TTTLocalizedPluralString.h"
#import "LaunchdCollector.h"
#import "SubProcess.h"

#define kRemove @"remove"
#define kWhitelist @"whitelist"
#define kPath @"path"

#define kRemoveColumnIndex 0
#define kWhitelistColumnIndex 1

@interface UninstallManager ()

// Show the window with content.
- (void) show: (NSString *) content;

// Verify removal of files.
- (void) verifyRemoveFiles: (NSMutableArray *) files;

// Tell the user that EtreCheck is too old.
- (BOOL) reportOldEtreCheckVersion;

// Tell the user that the EtreCheck version is unverified.
- (BOOL) reportUnverifiedEtreCheckVersion;

@end

@implementation UnknownFilesManager

@synthesize whitelistDescription = myWhitelistDescription;
@synthesize removeButton = myRemoveButton;

// Can I remove files?
- (BOOL) canRemoveFiles
  {
  int removeCount = 0;
  int whitelistCount = 0;
  BOOL disallow = NO;

  for(NSDictionary * item in self.filesToRemove)
    {
    if([[item objectForKey: kRemove] boolValue])
      ++removeCount;
    else if([[item objectForKey: kWhitelist] boolValue])
      ++whitelistCount;
    else
      disallow = YES;
    }
    
  if((whitelistCount > 0) && (removeCount == 0))
    [self.removeButton setTitle: NSLocalizedString(@"Report", NULL)];
  else
    [self.removeButton setTitle: NSLocalizedString(@"Remove", NULL)];

  if(disallow)
    return NO;
    
  return (removeCount > 0) || (whitelistCount > 0);
  }

// Constructor.
- (id) init
  {
  if(self = [super init])
    {
    myWhitelistDescription = [NSAttributedString new];
    }
    
  return self;
  }

// Destructor.
- (void) dealloc
  {
  [super dealloc];
  
  self.whitelistDescription = nil;
  }

// Show the window.
- (void) show
  {
  [super show: NSLocalizedString(@"unknownfiles", NULL)];
  
  [self willChangeValueForKey: @"canRemoveFiles"];
  
  self.filesRemoved = NO;
  
  NSMutableDictionary * filesToRemove = [NSMutableDictionary new];
  
  for(NSString * path in [[Model model] unknownLaunchdFiles])
    {
    NSDictionary * info = [[[Model model] launchdFiles] objectForKey: path];
    
    if(info != nil)
      {
      NSMutableDictionary * item = [NSMutableDictionary new];
      
      [item setObject: path forKey: kPath];
      [item setObject: info forKey: kLaunchdTask];
      
      [filesToRemove setObject: item forKey: path];
      
      [item release];
      }
    }
    
  NSArray * adwareFiles =
    [[filesToRemove allKeys] sortedArrayUsingSelector: @selector(compare:)];
  
  for(NSString * adwareFile in adwareFiles)
    {
    NSMutableDictionary * item = [filesToRemove objectForKey: adwareFile];
    
    if(item)
      [self.filesToRemove addObject: item];
    }
  
  [filesToRemove release];
  
  [self.tableView reloadData];

  [self didChangeValueForKey: @"canRemoveFiles"];
  }

// Close the window.
- (IBAction) close: (id) sender
  {
  self.whitelistDescription = nil;

  [super close: sender];
  }

// Remove the files.
- (IBAction) removeFiles: (id) sender
  {
  if([super canRemoveFiles])
    [super removeFiles: sender];
  }

// Verify removal of files.
- (void) verifyRemoveFiles: (NSMutableArray *) files
  {
  [super verifyRemoveFiles: files];

  NSMutableArray * filesNotRemoved = [NSMutableArray new];
  
  for(NSDictionary * item in files)
    if([[item objectForKey: kFileDeleted] boolValue])
      self.filesRemoved = YES;
    else
      [filesNotRemoved addObject: item];
  
  [self willChangeValueForKey: @"canRemoveFiles"];
  
  [files setArray: filesNotRemoved];
  
  [filesNotRemoved release];
  
  [self.tableView reloadData];

  [self didChangeValueForKey: @"canRemoveFiles"];
  }

// Contact Etresoft to add to whitelist.
- (IBAction) report: (id) sender
  {
  if([[Model model] oldEtreCheckVersion])
    {
    [self reportOldEtreCheckVersion];
    return;
    }
    
  if(![[Model model] verifiedEtreCheckVersion])
    {
    [self reportUnverifiedEtreCheckVersion];
    return;
    }
    
  NSMutableString * json = [NSMutableString string];
  
  [json appendString: @"{\"action\":\"report\","];
  [json appendString: @"\"files\":["];
  
  bool first = YES;

  for(NSDictionary * item in self.filesToRemove)
    {
    NSString * path = [item objectForKey: kPath];
    
    if(!path)
      continue;
      
    NSDictionary * info = [item objectForKey: kLaunchdTask];
    
    if(!info)
      continue;
      
    NSString * cmd =
      [path length] > 0
        ? [info objectForKey: path]
        : @"";
    
    path =
      [path stringByReplacingOccurrencesOfString: @"\"" withString: @"'"];
      
    NSString * name = [path lastPathComponent];
    
    if(!first)
      [json appendString: @","];
      
    first = NO;
    
    [json appendString: @"{"];
    
    [json
      appendFormat: @"\"known\":\"%@\",", [item objectForKey: kWhitelist]];
    
    [json appendFormat: @"\"name\":\"%@\",", name];
    [json appendFormat: @"\"path\":\"%@\",", path];
    [json appendFormat: @"\"cmd\":\"%@\"", cmd];
      
    [json appendString: @"}"];
    }
    
  [json appendString: @"],"];
  [json
    appendFormat:
      @"\"description\":\"%@\"}",
      [[self.whitelistDescription string]
        stringByReplacingOccurrencesOfString: @"\"" withString: @"'"]];
  
  NSString * server = @"https://etrecheck.com/server/adware_detection.php";
  
  NSArray * args =
    @[
      @"-s",
      @"--data",
      json,
      server
    ];

  SubProcess * subProcess = [[SubProcess alloc] init];
  
  if([subProcess execute: @"/usr/bin/curl" arguments: args])
    {
    NSString * status =
      [[NSString alloc]
        initWithData: subProcess.standardOutput
        encoding: NSUTF8StringEncoding];
      
    if([status isEqualToString: @"OK"])
      [self thanksForSubmission];
    else
      [self submissionFallbackToEmail];
      
    [status release];
    }
    
  [subProcess release];
  }

// Thank the user for their submission.
- (void) thanksForSubmission
  {
  NSAlert * alert = [[NSAlert alloc] init];

  [alert
    setMessageText: NSLocalizedString(@"Thanks for your submission", NULL)];
    
  [alert setAlertStyle: NSInformationalAlertStyle];

  [alert
    setInformativeText: NSLocalizedString(@"thanksforsubmission", NULL)];

  // This is the rightmost, first, default button.
  [alert addButtonWithTitle: NSLocalizedString(@"OK", NULL)];

  [alert runModal];

  [alert release];
  }

// Allow the user to submit an update via e-mail.
- (void) submissionFallbackToEmail
  {
  NSAlert * alert = [[NSAlert alloc] init];

  [alert
    setMessageText: NSLocalizedString(@"Submission failed", NULL)];
    
  [alert setAlertStyle: NSInformationalAlertStyle];

  [alert
    setInformativeText: NSLocalizedString(@"submissionfailed", NULL)];

  // This is the rightmost, first, default button.
  [alert
    addButtonWithTitle: NSLocalizedString(@"Yes - Send via e-mail", NULL)];

  [alert addButtonWithTitle: NSLocalizedString(@"No", NULL)];

  NSInteger result = [alert runModal];

  if(result == NSAlertFirstButtonReturn)
    {
    NSMutableString * content = [NSMutableString string];
    
    [content
      appendString: @"EtreCheck found the following unknown files:\n\n"];

    for(NSDictionary * item in self.filesToRemove)
      {
      NSString * path = [item objectForKey: kPath];
    
      if([path length] > 0)
        [content
          appendString:
            [NSString
              stringWithFormat:
                @"%@ %@\n",
                [[item objectForKey: kWhitelist] boolValue]
                  ? @"Known" : @"Unknown",
                path]];
      }
      
    [content appendString: @"\n\n"];
    [content appendString: [self.whitelistDescription string]];
    [content appendString: @"\n"];
      
    [Utilities
      sendEmailTo: @"info@etresoft.com"
      withSubject: @"Unknown files report"
      content: content];
    }

  [alert release];
  }

#pragma mark - NSTableViewDataSource

- (NSInteger) numberOfRowsInTableView: (NSTableView *) aTableView
  {
  return self.filesToRemove.count;
  }

- (id) tableView: (NSTableView *) aTableView
  objectValueForTableColumn: (NSTableColumn *) aTableColumn
  row: (NSInteger) rowIndex
  {
  if(rowIndex >= self.filesToRemove.count)
    return nil;

  NSMutableDictionary * item = [self.filesToRemove objectAtIndex: rowIndex];
  
  if([[aTableColumn identifier] isEqualToString: kWhitelist])
    return [item objectForKey: kWhitelist];

  if([[aTableColumn identifier] isEqualToString: kRemove])
    return [item objectForKey: kRemove];

  if([[aTableColumn identifier] isEqualToString: kPath])
    return [item objectForKey: kPath];
    
  return nil;
  }

- (void) tableView: (NSTableView *) tableView
  setObjectValue: (id) object
  forTableColumn: (NSTableColumn *) tableColumn
  row: (NSInteger) row
  {
  if(row >= self.filesToRemove.count)
    return;
    
  [self willChangeValueForKey: @"canRemoveFiles"];
    
  NSMutableDictionary * item = [self.filesToRemove objectAtIndex: row];
    
  if([[tableColumn identifier] isEqualToString: kWhitelist])
    {
    [item setObject: object forKey: kWhitelist];
    
    if([object boolValue])
      [item setObject: [NSNumber numberWithBool: NO] forKey: kRemove];

    [tableView
      reloadDataForRowIndexes: [NSIndexSet indexSetWithIndex: row]
      columnIndexes: [NSIndexSet indexSetWithIndex: kRemoveColumnIndex]];
    }
  else if([[tableColumn identifier] isEqualToString: kRemove])
    {
    [item setObject: object forKey: kRemove];
    
    if([object boolValue])
      [item setObject: [NSNumber numberWithBool: NO] forKey: kWhitelist];

    [tableView
      reloadDataForRowIndexes: [NSIndexSet indexSetWithIndex: row]
      columnIndexes: [NSIndexSet indexSetWithIndex: kWhitelistColumnIndex]];
    }

  [self didChangeValueForKey: @"canRemoveFiles"];
  }

#pragma mark - NSTableViewDelegate

@end
