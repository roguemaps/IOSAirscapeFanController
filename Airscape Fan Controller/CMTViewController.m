//
//  CMTViewController.m
//  Airscape Fan Controller
//
//  Created by Jesse Walter Vanderwerf on 8/7/14.
//  Copyright (c) 2014 Jesse Walter Vanderwerf. All rights reserved.
//

#import "CMTViewController.h"
#import "AFHTTPRequestOperationManager.h"

#import "SimplePing.h"
#import "ip2mac.h"
#include <arpa/inet.h>
#import "WifiInfo.h"
#import <CoreData/CoreData.h>
#import <dispatch/dispatch.h>
#include "SimplePinger.h"


@interface CMTViewController ()
{
    NSMutableArray *_pickerData;
}

@property (strong) NSMutableArray *devices;
@property (strong) NSString *ActiveDevice;
@property (strong) NSString *phoneIp;
@property (strong) NSString *checkIp;
@property (strong) UIAlertView *httpErr;
@property bool isAlert;
@end
NSString *curSSID;
int loopCount;
UIView *_currentView;

@implementation CMTViewController

- (NSManagedObjectContext *)managedObjectContext
{
    NSManagedObjectContext *context = nil;
    id delegate = [[UIApplication sharedApplication] delegate];
    if ([delegate performSelector:@selector(managedObjectContext)]) {
        context = [delegate managedObjectContext];
    }
    return context;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    _ActiveDevice = [[NSString alloc]init];
    
    // Connect data
    self.DevicePicker.dataSource = self;
    self.DevicePicker.delegate = self;
    
    //connect Delegate to Rename Field
    self.RenameField.delegate = self;
    
    //load the manual Entry option
    if ([self deviceCount] == 0) {
        [self saveToCoreData:@"ManualEntry" :@"00.00.00.00" :@"manual" :@"ssid"];
    }
    
    // Create a new NSOperationQueue instance.
    operationQueue = [NSOperationQueue new];
    
    [self setWifiVars];

    // check for internet connection
    reach = [Reachability reachabilityWithHostname:_checkIp];
    reach.reachableOnWWAN = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkWifi) name:kReachabilityChangedNotification object:nil];
    
    [reach connectionRequired];
    [reach startNotifier];
    
    //load up the data array used for pickerView (DevicePicker)
    [self printFromCoreData];
    
    //pick the first item in the fan dropdown and select it.
    [_DevicePicker selectRow:0 inComponent:0 animated:NO];
    [_Accept sendActionsForControlEvents: UIControlEventTouchUpInside];
    if ([self wifiCheck:_checkIp]) {
        [self verifyInBg];
    }else{
        //throw warning message
        NSString *msg = @"Your Wifi is not connecting. Please check your Wifi settings and verify that your Wifi is on and you are connected to your home network";
        NSString *cbut = @"okay";
        [self alertMessage:[NSArray arrayWithObjects:msg, cbut, nil, nil]];
    }
    
    
}
- (void)applicationDidEnterBackground:(UIApplication *)application{
    [operationQueue cancelAllOperations];
    [operationQueue waitUntilAllOperationsAreFinished];
}

-(void)applicationDidEnterForeground:(UIApplication *)application{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kReachabilityChangedNotification" object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    [operationQueue cancelAllOperations];
    [operationQueue waitUntilAllOperationsAreFinished];
}


#pragma mark - Automation background methods
-(void)verifyInBg{
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(verifyData)object:nil];
    
    if (![verifyOps isCancelled]) {
        if(![[operationQueue operations] containsObject:verifyOps]){
           
            verifyOps = operation;
            if (![verifyOps isCancelled]) {
                [operationQueue addOperation:verifyOps];
            }
        }else{
           // NSLog(@"verifyOps is already in que let it finish?");
            //[verifyOps cancel];
            //[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(verifyInBg) object:nil];
        }
        
        if (![verifyOps isCancelled]) {
           // [self verifyInBg];
            [self performSelector:@selector(verifyInBg) withObject:nil afterDelay:15];
        }else{
            //NSLog(@"VerifyOpsWas Cancelled");
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(verifyInBg) object:nil];
        }

    }else{
       // NSLog(@"VerifyOpsWas Cancelled");
    }
}

-(void)verifyData{
    NSString *msg = @"One or more of your fans is missing. Would you like to scan the network to locate them?";
    NSString *cbut = @"No";
    NSString *obut = @"Yes";
    
    if (![self verifyCoreData]) {
       // NSLog(@"We hit the missing device section. Replace this with a alert and 2 buttons");
        if (![verifyOps isCancelled]) {
            [self performSelectorOnMainThread:@selector(alertMessage:) withObject:[NSArray arrayWithObjects:msg, cbut, obut, nil] waitUntilDone:NO];
        }
    }
}

-(void)refreshScreenData{
    loopCount++;
    //here is the operation
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        if (![refreshOps isCancelled]) {
            //send refresh signal
            if (![_ActiveDevice isEqualToString:@"00.00.00.00"]) {
                NSString *url = [NSString stringWithFormat:@"http://%@/fanspd.cgi", _ActiveDevice];
                [self sendAutoRefresh:url];
            }
            
        }else{
          //  NSLog(@"refreshOps was cancelled");
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshScreenData) object:nil];
        }
    }];
    
    if(![[operationQueue operations] containsObject:refreshOps]){
        refreshOps = operation;
        if (![refreshOps isCancelled]) {
           [operationQueue addOperation:refreshOps];
           // NSLog(@"refresh = %d", [refreshOps isCancelled]);
        }else{
           // NSLog(@"Cannot add refreshOps to que it was still cancelled");
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshScreenData) object:nil];
        }
    }else{
      //  NSLog(@"RefreshOps is in the queue");
    }
    
}

//same method used to send all http but this one is used specific for the automated refresh method.
-(void)sendAutoRefresh:(NSString*)_url{
    
    if (![self wifiCheck:_checkIp]) {
        //put wifi error message here
    }else{
        AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
        manager.responseSerializer = [AFHTTPResponseSerializer serializer];
        [manager GET:_url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseString) {
            [self handleResponse:responseString];
            if (![refreshOps isCancelled] && (loopCount < 8)) {
                [self performSelector:@selector(refreshScreenData) withObject:nil afterDelay:15];
            }else{
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshScreenData) object:nil];
                loopCount = 8;
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            //NSLog(@"Error: %@", error);
            //pop-up a timed error message stating error connecting to fan @ ip
            [self performSelectorOnMainThread:@selector(handleHTTPerror) withObject:nil waitUntilDone:YES];
        }];
    }
    
}

-(void)checkWifi{
    // called after network status changes
    
    NetworkStatus internetStatus = [reach currentReachabilityStatus];
    
    NSString *msg = @"Your Wifi is not connecting. Please check your Wifi settings and verify that your Wifi is on and you are connected to your home network";
    NSString *cbut = @"okay";
    
    if (internetStatus != ReachableViaWiFi) {
        //cancel all ops in the queue.
        [operationQueue cancelAllOperations];
        [operationQueue waitUntilAllOperationsAreFinished];
        
        //stop the timers used for recusion.
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(verifyInBg) object:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshScreenData) object:nil];
        [self alertMessage:[NSArray arrayWithObjects:msg, cbut, nil, nil]];
    }else{
        if (![[operationQueue operations] containsObject:verifyOps]) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(verifyInBg) object:nil];
            [self verifyInBg];
        }
        //set local global's used for wificheck
        [self setWifiVars];
    }
}

//sets all the global's used in WifiCheck
-(void)setWifiVars{
    WifiInfo *wi = [[WifiInfo alloc] init];
    _phoneIp = [wi getIPAddress:true];
    _checkIp  = [wi getMinIp:_phoneIp];
    NSDictionary *dict = [wi fetchSSIDInfo];
    int tmpIp = [wi StrIp2UnsignedInt:_checkIp];
    tmpIp = tmpIp + 2;
    _checkIp = [wi unsignedInt2StrIp:tmpIp];
    curSSID = dict[@"SSID"];
}

#pragma mark - PickerView Delegate methods
// The number of columns of data
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

// The number of rows of data
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return _pickerData.count;
}

// The data to return for the row and component (column) that's being passed in
- (NSString*)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    //return _pickerData[row];
    return [_pickerData objectAtIndex:row];
}


#pragma mark - View Controller Methods

- (IBAction)menu:(id)sender{
    NSArray *menuMessage = @[@"About: Please direct any questions regarding app functions to Airscape Fans, email - experts@airscapefans.com, phone - 1.866.448.4187, Author - Jesse Vanderwerf, App Version - 1.01", @"Ok"];
    
    [self alertMessage:menuMessage];
}

-(IBAction)myButtonAction:(id)sender {
    
    if (![_ActiveDevice  isEqual: @""] && [self wifiCheck:_checkIp]) {
        NSString *url = @"";
        switch ([sender tag]) {
            case 0: // default case Don't do a thing
               // NSLog(@"Wrong button tag:%ld", (long)[sender tag]);
                break;
            case 1://Turn fan up 1 unit
                url = [NSString stringWithFormat:@"http://%@/fanspd.cgi?dir=1", _ActiveDevice];
                [self httpRequest:url];
                break;
            case 2://turn fan down 1 unit
                url = [NSString stringWithFormat:@"http://%@/fanspd.cgi?dir=3", _ActiveDevice];
                [self httpRequest:url];
                break;
            case 3: //Add 60 mins to timer
                url = [NSString stringWithFormat:@"http://%@/fanspd.cgi?dir=2", _ActiveDevice];
                [self httpRequest:url];
                break;
            case 4://Stop Fan and Clear Timer
                url = [NSString stringWithFormat:@"http://%@/fanspd.cgi?dir=4", _ActiveDevice];
                [self httpRequest:url];
                break;
            case 5://Get results from Fan
                url = [NSString stringWithFormat:@"http://%@/fanspd.cgi", _ActiveDevice];
                [self httpRequest:url];
                break;
            default:
               // NSLog(@"Default Message here");
                break;
        }
        loopCount = 0;
        [self refreshScreenData];
    }else{
       // NSLog(@"There was an error with ActiveDevice String");
    }
    
}

- (IBAction)scan:(id)sender {
    //code for Scan goes here
    if (_scanDialog.hidden == YES) {
        _scanDialog.hidden = NO;
    }
    [_scanSpinner startAnimating];
    //[_scan setEnabled:NO];
    //_scan.backgroundColor = [UIColor grayColor];
    //[self performSelector:@selector(enableScanButton) withObject:nil afterDelay:30];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0 ), ^{
        [self scanWifi];
    });
}

- (IBAction)FanDrop:(id)sender {
    [self printFromCoreData];
    [self.DevicePicker reloadAllComponents];
    if (_DeviceBox) _DeviceBox.hidden = !_DeviceBox.hidden;
}

- (IBAction)Cancel:(id)sender {
    if (_DeviceBox) _DeviceBox.hidden = !_DeviceBox.hidden;
}

-(IBAction)Accept:(id)sender{
    NSInteger row;
    
    if (_DeviceBox.hidden == NO) {
        [_DeviceBox setHidden:YES];
    }
    
    row = [_DevicePicker selectedRowInComponent:0];
    NSString *tmp = [_pickerData objectAtIndex:row];
    NSArray *array = [tmp componentsSeparatedByString:@" "];
    _ActiveDevice = array[1];
    
    //send a call to refresh data.
    NSString *url = [NSString stringWithFormat:@"http://%@/fanspd.cgi", _ActiveDevice];
    [self httpRequest:url];

    //set the title for the fandropdown to reflect the current fan and ip.
    [_FanDrop setTitle: tmp forState: UIControlStateNormal];
    
    //change the Rename button text for ManualEntry and not manual Entry
    if ([array[0] isEqualToString:@"ManualEntry"] ) {
        //set button text to Modify IP
        [_Rename setTitle:@"Modify IP" forState:UIControlStateNormal];
    }else{
        [_Rename setTitle:@"Rename" forState:UIControlStateNormal];
    }
    loopCount = 0;
    [self refreshScreenData];
}

- (IBAction)Rename:(id)sender {
    if (![_ActiveDevice isEqualToString:@""]) {
        if (_RenameBox) _RenameBox.hidden = !_RenameBox.hidden;
    }else{
        //pop-up quick message recommending select from dropdown
        [self showStatus:@"You need to select a fan from the dropdown." timeout:2.5];
    }
    
}
- (IBAction)PvRename:(id)sender {
    if (_RenameBox) _RenameBox.hidden = !_RenameBox.hidden;
    //hide dropdown buttons
    _Accept.hidden = YES;
    _Cancel.hidden = YES;
    _Modify.hidden = YES;
}

- (IBAction)TFCancel:(id)sender{
    if (_RenameBox) _RenameBox.hidden = !_RenameBox.hidden;
    [_RenameBox endEditing:YES];
    
    //hide dropdown buttons
    _Accept.hidden = NO;
    _Cancel.hidden = NO;
    _Modify.hidden = NO;
}

- (IBAction)TFSave:(id)sender{
   
    [self textFieldShouldReturn:_RenameField];
    
}

- (IBAction)scanDialogOK:(id)sender {
    
    if (_scanDialog.hidden == NO) {
        _scanDialog.hidden = YES;
    }
    [_scanSpinner stopAnimating];
}


#pragma mark - Helper functions
//check if Wifi is reachable
-(int)wifiCheck:(NSString *)ip{
    int wifiOk = 0;
    Reachability *locReach;
    locReach = [Reachability reachabilityWithHostname:ip];
    locReach.reachableOnWWAN = NO;
    NetworkStatus netStatus = [locReach currentReachabilityStatus];
    
    if (netStatus == ReachableViaWiFi)
        wifiOk = 1;
    else
        wifiOk = 0;
    
    return wifiOk;
}

-(void)enableScanButton{
    [_scan setEnabled:YES];
    _scan.backgroundColor = [UIColor blackColor];
}

//A scan function ping in the bg all available IPs
//assumes wifi connectivity. Be sure to check that your device is connected before running this.
-(void)scanWifi{
    WifiInfo *wi = [[WifiInfo alloc] init];
    
    
    NSString *phoneIp = [wi getIPAddress:true];
    NSString *maxIp = [wi getBroadcastIp:phoneIp];
    NSString *minIp = [wi getMinIp:phoneIp];
    
    unsigned long ULmaxIp = [wi StrIp2UnsignedLong:maxIp];
    unsigned long ULminIp = [wi StrIp2UnsignedLong:minIp];
    ULminIp ++;
    
    unsigned long iterateIp = ULminIp;
    unsigned long Range = ULmaxIp - ULminIp;
    
    if (![self wifiCheck:_checkIp]) {
       // NSLog(@"oops looks like Internet Connection error");
        
        //throw Error message regarding Wifi NOT connected
        NSString *msg = @"Your Wifi is not connecting. Please check your Wifi settings and verify that your Wifi is on and you are connected to your home network";
        NSString *cbut = @"okay";
        //[self alertMessage:[NSArray arrayWithObjects:msg, cbut, nil, nil]];
        [self performSelectorOnMainThread:@selector(alertMessage:) withObject:[NSArray arrayWithObjects:msg, cbut, nil, nil] waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(stopSpinner) withObject:nil waitUntilDone:NO];
    }else{
        //Do the actual work needed
        NSString *strIps [Range];
        [self verifyCoreData];
        
        for (int i = 0; i < Range; i++) {
            strIps[i] = [wi unsignedInt2StrIp:iterateIp];
            iterateIp ++;
        }
        
        //verify the Devices already in the database
        [self verifyCoreData];
        
        double StartTime = CACurrentMediaTime();
        while (CACurrentMediaTime() <= StartTime+5) {
            
            for (int i=0; i < Range; i++) {
                SimplePinger *p = [SimplePinger alloc];
                [p runWithHostName:strIps[i]];
            }
            
            ip2mac *i2m = [[ip2mac alloc] init];
            
            int successcount = 0;
            for (int i = 0; i < Range; i++) {
                char *chIp = (char *)[strIps[i] UTF8String];
                NSString *mac = [[i2m Stip2mac:chIp]uppercaseString];
                
                
                if([mac hasPrefix:@"60:CB:FB"]) {
                    //Save the devices to the database.
                    successcount++;
                    NSString *name = [NSString stringWithFormat:@"%@%d", @"WHF", successcount];
                   // [self performSelectorInBackground:@selector(saveHelper:) withObject:[NSArray arrayWithObjects:name, strIps[i], mac, curSSID, nil]];
                    [self saveToCoreData:name :strIps[i] :mac :curSSID];
                }
            }
        }
        
    }
    [self performSelectorOnMainThread:@selector(stopSpinner) withObject:nil waitUntilDone:NO];
    [self performSelectorInBackground:@selector(printFromCoreData) withObject:nil];
}

-(void)stopSpinner{
    [_scanSpinner stopAnimating];
    _scanDialog.hidden = YES;
    //[self printFromCoreData];
    
    //pick the first item in the fan dropdown and select it.
    [_DevicePicker selectRow:0 inComponent:0 animated:NO];
    [_Accept sendActionsForControlEvents: UIControlEventTouchUpInside];
}

-(void)saveHelper:(NSArray *) vals{
    [self saveToCoreData:vals[0] :vals[1] :vals[2] :vals[3]];
}

-(void)refreshData{
    NSString *url = [NSString stringWithFormat:@"http://%@/fanspd.cgi", _ActiveDevice];
    [self httpRequest:url];
}

- (void)httpRequest:(NSString*)_url{
    
    if (![self wifiCheck:_checkIp]) {
        //put wifi error message here
    }else{
        AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
        manager.responseSerializer = [AFHTTPResponseSerializer serializer];
        [manager GET:_url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseString) {
            [self handleResponse:responseString];
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
           // NSLog(@"Error: %@", error);
            //pop-up a timed error message stating error connecting to fan @ ip
            [self performSelectorOnMainThread:@selector(handleHTTPerror) withObject:nil waitUntilDone:YES];
        }];
    }
}

-(void)handleHTTPerror{
    [self resetStats];
    [refreshOps cancel];
    loopCount = 8;
    
    NSString *message = [NSString stringWithFormat:@"%1$@ %2$@ %3$@", @"The Fan @", _ActiveDevice, @"is not showing results"];
    //here is the message pop-up call
    _httpErr = [[UIAlertView alloc] initWithTitle:nil
                                             message:message
                                            delegate:self
                                   cancelButtonTitle:@"OK"
                                   otherButtonTitles:nil];
    if (!self.isAlert) {
        [_httpErr show];
        _isAlert = true;
    }
}

- (void)handleResponse:(NSData*)response{
    NSString *responseString = [[NSString alloc]initWithData:response encoding:NSASCIIStringEncoding];
    //NSArray *Parsed = [responseString componentsSeparatedByString:@"\n"];
    
    NSString *pasingString = responseString;
    
    NSRegularExpression *testExpression = [NSRegularExpression regularExpressionWithPattern:@"<.+>(.*)</.+>" options:NSRegularExpressionCaseInsensitive error:nil];
    
    NSArray *myArray = [testExpression matchesInString:pasingString options:0 range:NSMakeRange(0, [pasingString length])];
    
    NSMutableArray *matches = [NSMutableArray arrayWithCapacity:[myArray count]];
    
    for (NSTextCheckingResult *match in myArray) {
        NSRange matchRange = [match rangeAtIndex:1];
        [matches addObject:[pasingString substringWithRange:matchRange]];
    }
    
    NSString *primDNS = [self getDNS];
    
    //Assign some variables to important switches
    
    //put the code to update text on screen.
    //First check the length (this will tell us wich fan version
    //lenght 10 = 1.0 lenth 18 = more current
    if ([matches count] > 10) {
        if ([matches[1] isEqualToString:@"1"] || [matches[7] isEqualToString:@"1"] || [matches[8] isEqualToString:@"1"])
        {
            if ([matches[1] isEqualToString:@"1"]) {
                //set refresh button text loop call refresh again
                //NSLog(@"The door is opening");
                
                [_Refresh setTitle:@"Waiting for Doors to Open" forState:UIControlStateNormal];
                [_Refresh setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                
                //if interlock is showing make it dissappear at this point.
                if (_interlockTop.constant < 256) {
                    
                    [UIView animateWithDuration:3
                                     animations:^{
                                         _interlockTop.constant = 430;
                                         [self.view layoutIfNeeded];
                                     }];
                }
            }
            if ([matches[7] isEqualToString:@"1"]) {
                //Here we set a block of text at the middle and bottem of screen
                [self resetStats];
                _interlockStar.text = @"** Fan Interlock Control means that an external switch (smoke detector, other controls) is not allowing the whole house fan to operate. Reset the external interlock and then resume normal operation.";
                [_Refresh setTitle:@"Disabled by Fan Interlock" forState:UIControlStateNormal];
                [_Refresh setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                
                _SpeedValue.textColor = [UIColor redColor];
                _SpeedValue.text = [NSString stringWithFormat:@"%1$@%2$@", matches[0], @"**"];
                
                if (_interlockTop.constant >= 256) {
                    
                    [UIView animateWithDuration:3
                                     animations:^{
                                         
                                         _interlockTop.constant = -200;
                                         [self.view layoutIfNeeded];
                                     }];
                }
            }
            if ([matches[8] isEqualToString:@"1"]) {
                //Here we do the same as before but it is for interlock 2
                [self resetStats];
                _interlockStar.text = @"* Disabled by SafeSpeed means that the differential pressure switch has determined that your house pressure is too low. Open more windows and reset by clicking the fan-speed-up button.";
                
                [_Refresh setTitle:@"Disabled by SafeSpeed" forState:UIControlStateNormal];
                [_Refresh setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                _SpeedValue.textColor = [UIColor redColor];
                _SpeedValue.text = [NSString stringWithFormat:@"%1$@%2$@", matches[0], @"*"];
                
                if (_interlockTop.constant >= 256) {
                    
                    [UIView animateWithDuration:3
                                     animations:^{
                                         _interlockTop.constant = -200;
                                         [self.view layoutIfNeeded];
                                     }];
                }
            }
            //update stats
            [self updateStats:matches];
            
            //loop back again, unless the power stat is at 0.
            if (![_SpeedValue.text isEqualToString:@"0*"] && ![_SpeedValue.text isEqualToString:@"0**"]) {
                [self performSelector:@selector(refreshData) withObject:nil afterDelay:5];
            }
            
        }else{
            //reset any text changed for interlocks or doors opening.
            [_Refresh setTitle:@"Refresh" forState:UIControlStateNormal];
            [_Refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            _SpeedValue.textColor = [UIColor blackColor];
            if (_interlockTop.constant < 256) {
                
                [UIView animateWithDuration:3
                                 animations:^{
                                     _interlockTop.constant = 430;
                                     [self.view layoutIfNeeded];
                                 }];
            }
            
            //run the regular update
            _SpeedValue.text = matches[0];
            [self updateStats:matches];
        }
    }else{
        if ([matches count] == 10) {
            //load what is there for version 1.0 type
            if ([matches[1] isEqualToString:@"1"] || [matches[7] isEqualToString:@"1"])
            {
                if ([matches[1] isEqualToString:@"1"]) {
                    //set refresh button text loop call refresh again
                   // NSLog(@"The door is opening");
                    NSString *local_url = [NSString stringWithFormat:@"http://%@/fanspd.cgi", _ActiveDevice];
                    [self httpRequest:local_url];
                    [_Refresh setTitle:@"Waiting for Doors to Open" forState:UIControlStateNormal];
                    [_Refresh setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                }
                if ([matches[7] isEqualToString:@"1"]) {
                    //Here we set a block of text at the middle and bottem of
                    [self resetStats];
                    _interlockStar.text = @"** Fan Interlock Control means that an external switch (smoke detector, other controls) is not allowing the whole house fan to operate. Reset the external interlock and then resume normal operation.";
                    
                    if (_interlockTop.constant >= 256) {
                        
                        [UIView animateWithDuration:3
                                         animations:^{
                                             _interlockTop.constant = -200;
                                             [self.view layoutIfNeeded];
                                         }];
                    }
                }
            }else{
                //reset any text changed for interlocks or doors opening.
                [_Refresh setTitle:@"Refresh" forState:UIControlStateNormal];
                [_Refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                _SpeedValue.textColor = [UIColor blackColor];
                
                //reset anything used for interlock
                if (_interlockTop.constant < 256) {
                    
                    [UIView animateWithDuration:3
                                     animations:^{
                                         _interlockTop.constant = 430;
                                         [self.view layoutIfNeeded];
                                     }];
                }
                
                //then update the rest of the stats
                _SpeedValue.text = matches[0];
                [self updateStats:matches];
            }
        }
    }
}

-(void)updateStats: (NSArray*)matches{
    
    NSString *primDNS = [self getDNS];
    
    //all new devices first
    if ([matches count]> 10) {
        
        _topLabel.text = matches[5];
        
        _AirflowValue.text = [NSString stringWithFormat:@"%1$@ %2$@", matches[9], @"CFM"];
        
        //handle temps that might not be hooked up properly
        if([matches[11] integerValue] > -50){
            _RoomTemp.text = [NSString stringWithFormat:@"%1$@%2$@", matches[11], @"\u00B0 F"] ;
        }else{
            _RoomTemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
        }
        
        //handle temps that might not be hooked up properly
        if ([matches[14] integerValue] > -50) {
            _OAtemp.text = [NSString stringWithFormat:@"%1$@%2$@", matches[14], @"\u00B0 F"];
        }else{
            _OAtemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
        }
        
        //handle temps that might not be hooked up properly
        if ([matches [13] integerValue] > -50) {
            _AtticTemp.text = [NSString stringWithFormat:@"%1$@%2$@", matches[13], @"\u00B0 F"];
        }else{
            _AtticTemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
        }
        
        int hrs = floor([matches[2] integerValue]/60);
        int mins = [matches[2] integerValue]%60;
        _Timer.text = [NSString stringWithFormat:@"%1$d hrs %2$d mins", hrs, mins];
        
        _Power.text = [NSString stringWithFormat:@"%1$@ %2$@", matches[10], @"Watts"];
        
        if ([matches[10] integerValue] > 0) {
            int tmp = floor([matches[9] integerValue]/[matches[10] integerValue]);
            _CFMpWatt.text = [NSString stringWithFormat:@"%1$d %2$@", tmp, @"CFM/Watt"];
        }else{
            _CFMpWatt.text = [NSString stringWithFormat:@"%1$@ %2$@", @"0", @"CFM/Watt"];
        }
        
        int coolpwr = (([matches[11] integerValue] - [matches[14] integerValue])*1.08)*[matches[9] integerValue];
        _CoolPw.text = [NSString stringWithFormat:@"%d %2@", coolpwr, @"BTUh"];
        
        if ([matches[10] integerValue] > 0) {
            int eer = coolpwr/[matches[10] integerValue];
            _EER.text = [NSString stringWithFormat:@"%d", eer];
        }else{
            _EER.text = @"0";
        }
        
        _IPAddress.text = matches[4];
        _MAC.text = matches[3];
        _PrimDNS.text = primDNS;
        _SoftwareVs.text = matches[6];
        
    }else{
        //check to make sure it is an old device
        if ([matches count] == 10) {
            _topLabel.text = matches[5];
            _SpeedValue.text = matches[0];
            _AirflowValue.text = [NSString stringWithFormat:@"%1$@ %2$@", matches[8], @"CFM"];
            
            int hrs = floor([matches[2] integerValue]/60);
            int mins = [matches[2] integerValue]%60;
            _Timer.text = [NSString stringWithFormat:@"%1$d hrs %2$d mins", hrs, mins];
            _Power.text = [NSString stringWithFormat:@"%1$@ %2$@", matches[9], @"Watts"];
            
            if ([matches[9] integerValue] > 0) {
                int tmp = floor([matches[8] integerValue]/[matches[9] integerValue]);
                _CFMpWatt.text = [NSString stringWithFormat:@"%1$d %2$@", tmp, @"CFM/Watt"];
            }else{
                _CFMpWatt.text = [NSString stringWithFormat:@"%1$@, %2$@", @"0", @"CFM/Watt"];
            }
            
            _IPAddress.text = matches[4];
            _MAC.text = matches[3];
            _PrimDNS.text = primDNS;
            _SoftwareVs.text = matches[6];
        }
    }
}

-(NSString *)getDNS{
    WifiInfo *wi = [[WifiInfo alloc] init];
    NSString *phoneIp = [wi getIPAddress:true];
    NSString *primDNS = [wi getMinIp:phoneIp];
    int ulDNS = (int)[wi StrIp2UnsignedLong:primDNS];
    ulDNS ++;
    primDNS = [wi unsignedInt2StrIp:ulDNS];
    
    return primDNS;
}

-(void)resetStats{
    [_Refresh setTitle:@"Refresh" forState:UIControlStateNormal];
    [_Refresh setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _SpeedValue.text = @"0";
    _AirflowValue.text = @"0 CFM";
    _RoomTemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
    _OAtemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
    _AtticTemp.text = [NSString stringWithFormat:@"%1$@%2$@", @"-", @"\u00B0 F"];
    _Timer.text = @"0 Min 0 Sec";
    _Power.text = @"0 Watts";
    _CFMpWatt.text = [NSString stringWithFormat:@"%1$@ %2$@", @"0", @"CFM/Watt"];
    _CoolPw.text = @"0.00 Btu";
    _EER.text = @"0";
    _IPAddress.text = @"00.00.00.00";
    _MAC.text = @"00:00:00:00:00:00";
    _PrimDNS.text = @"00.00.00.00";
    _SoftwareVs.text = @"0.0";
}

-(void)resetFanDrop{
    [_FanDrop setTitle: @"Fans" forState: UIControlStateNormal];
}

//send a refresh string and returun 1 if we get a result otherwise return 0
-(int)doubleCheckIp:(NSString*)ip{
    
    __block int check = 1;
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0 ), ^{
        double StartTime = CACurrentMediaTime();
        
        while (CACurrentMediaTime() <= StartTime+5) {
            SimplePinger *p = [SimplePinger alloc];
            [p runWithHostName:ip];
            
            ip2mac *i2m = [[ip2mac alloc] init];
            
            char *chIp;
            NSString *mac;
            
            //ip2mac on the ip address
            chIp = (char *)[ip UTF8String];
            mac= [[i2m Stip2mac:chIp]uppercaseString];
            
            //check the mac address
            if (![mac hasPrefix:@"60:CB:FB"]) {
                check = 0;
            }else{
                check = 1;
            }
            [NSThread sleepForTimeInterval:1];
        }
    });
    
    return check;
}


#pragma mark - Core Data stack
-(void)saveToCoreData:(NSString*)name :(NSString*)ip :(NSString*)mac :(NSString*)ssid {
    NSManagedObjectContext *context = [self managedObjectContext];
    
    // Create a new managed object
    NSManagedObject *newDevice = [self uniqueDevice:ip :mac inManagedObjectContext:context];
    
    
    if ([[newDevice valueForKey:@"name"] hasPrefix: @"AirScapeFan"]  || [[newDevice valueForKey:@"name"] length] == 0)
    {
        [newDevice setValue:name forKey:@"name"];
    }else{
       // NSLog(@"Here is the name %@", [newDevice valueForKey:@"name"]);
    }
    [newDevice setValue:ip forKey:@"ipAddress"];
    [newDevice setValue:mac forKey:@"macAddress"];
    [newDevice setValue:ssid forKey:@"ssid"];
    
    NSError *error = nil;
    // Save the object to persistent store
    if (![context save:&error]) {
       // NSLog(@"Can't Save! %@ %@", error, [error localizedDescription]);
    }
}

//Save our finds to the core Data
-(void)updateToCoreData:(NSString*)name :(NSString*)ip :(NSString*)mac :(NSString*)ssid{
    NSManagedObjectContext *context = [self managedObjectContext];
    
    //First Check if mac address is in Database
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"DeviceData"];
    
    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"macAddress CONTAINS %@", mac];
    [request setPredicate:predicate];
    
    if ([results count] > 0){
        NSManagedObject* favoritsGrabbed = [results objectAtIndex:0];
        [favoritsGrabbed setValue:name forKey:@"name"];
        [favoritsGrabbed setValue:ip forKey:@"ipAddress"];
        [favoritsGrabbed setValue:mac forKey:@"macAddress"];
        [favoritsGrabbed setValue:ssid forKey:@"ssid"];
    }
    
    //save update to persistant store
    if (![context save:&error]) {
       // NSLog(@"Can't Save! %@ %@", error, [error localizedDescription]);
    }
}

-(void)updateName:(NSString*)name :(NSString*)locmac{
    NSManagedObjectContext *context = [self managedObjectContext];
    
    //First Check if ip address is in Database
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"DeviceData"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"macAddress = %@", locmac];
    [request setPredicate:predicate];
    
    NSError *error = nil;
    NSArray *results = [context executeFetchRequest:request error:&error];
    
    
    
    //there should be only one
    if ([results count] > 0){
        
        NSManagedObject* favoritsGrabbed = [results objectAtIndex:0];
        [favoritsGrabbed setValue:name forKey:@"name"];
        
        //save update to persistant store
        if (![context save:&error]) {
           // NSLog(@"Can't Save! %@ %@", error, [error localizedDescription]);
        }
    }
}

//Print the entries in Core Data to Log. Could be repurposed to print elsewhere :)
-(void)printFromCoreData{
    NSMutableArray *tmp = [[NSMutableArray alloc] init];
    NSString *tmpDevice;

    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"DeviceData"];
    self.devices = [[managedObjectContext executeFetchRequest:fetchRequest error:nil] mutableCopy];
    int count = 0;
    
    for (NSManagedObject *info in _devices) {
        
        
        NSString *item = [NSString stringWithFormat:@"%1$@ %2$@",[info valueForKey:@"name"], [info valueForKey:@"ipAddress"]];
        
        if (![tmp containsObject:item]) {
            NSString *locIp = [info valueForKey:@"ipAddress"];
            NSString *locname = [info valueForKey:@"name"];
            NSString *locmac = [info valueForKey:@"macAddress"];
            NSString *locSSID = [info valueForKey:@"ssid"];
            
            //&& ![locmac isEqualToString:@"manual"]
            
            if ([locIp rangeOfString:@"00.00.00.00"].location == NSNotFound && [locSSID isEqualToString:curSSID]) {
                [tmp addObject:item];
            }
            if ([locname rangeOfString:@"ManualEntry"].location != NSNotFound && [locmac rangeOfString:@"manual"].location != NSNotFound) {
                tmpDevice = item;
            }
            if (count == [_devices count]-1) {
                if (tmpDevice != nil) {
                    [tmp addObject:tmpDevice];
                }
            }
        }
        count ++;
    }
    
    
    if (tmp.count > 0) {
        _pickerData = tmp;
        [self performSelectorOnMainThread:@selector(reloadDeviceDropDown) withObject:nil waitUntilDone:NO];
    }
    
}

//helper method to allow pickerview dropdown of devices to load in forground despite all else in background
-(void)reloadDeviceDropDown{
    [self.DevicePicker reloadAllComponents];
}

//assumes you already have connection to wifi
-(int)verifyCoreData{
    
    //create boolean to return false if there is a missing device
    int foundDevice = 1;
    
    NSError *error = nil;
    
    //get all objects from data
    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"DeviceData"];
    self.devices = [[managedObjectContext executeFetchRequest:fetchRequest error:nil] mutableCopy];
    
    
    //ping all objects from data
    for (NSManagedObject *item in _devices) {
        SimplePinger *p = [SimplePinger alloc];
        [p runWithHostName:[item valueForKey:@"ipAddress"]];
        [NSThread sleepForTimeInterval:.01];
    }
    
    ip2mac *i2m = [[ip2mac alloc] init];
    
    //Compare mac addresses. if not good set ip to 00.00.00.00
    for (NSManagedObject *info in _devices) {
        //load variables
        NSString *dbMac = [info valueForKey:@"macAddress"];
        NSString *dbIp  = [info valueForKey:@"ipAddress"];
        NSString *dbNam = [info valueForKey:@"name"];
        NSString *dbSSID = [info valueForKey:@"ssid"];
        char *chIp;
        NSString *mac;
        
        if (![dbMac isEqualToString:@"manual"]) {
            //ip2mac on the ip addresses
            chIp = (char *)[[info valueForKey:@"ipAddress"] UTF8String];
            mac= [[i2m Stip2mac:chIp]uppercaseString];
        }
        //
        if (![dbMac isEqualToString:@"manual"] && [dbSSID isEqualToString:curSSID]) {
            if (![mac hasPrefix:@"60:CB:FB"]){
                if (![self doubleCheckIp:dbIp]) {
                    
                    NSString *currTitle = [_FanDrop currentTitle];
                    NSArray *fanTitle = [currTitle componentsSeparatedByString:@" "];
                    
                    if ([dbNam isEqualToString:fanTitle[0]]) {
                        [self performSelectorOnMainThread:@selector(resetFanDrop) withObject:nil waitUntilDone:NO];
                    }
                    
                    if (![dbIp isEqualToString:@"00.00.00.00"]) {
                        
                        foundDevice = 0;
                        [info setValue:@"00.00.00.00" forKey:@"ipAddress"];
                        
                        //save update to persistant store
                        if (![managedObjectContext save:&error]) {
                          //  NSLog(@"Can't Save! %@ %@", error, [error localizedDescription]);
                        }
                    }
               }
            }
        }
    }
   // NSLog(@"Here is foundDevice %d", foundDevice);
    
    return foundDevice;
}

-(NSManagedObject *)uniqueDevice:(NSString*)locIp :(NSString *)locMac inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSManagedObject *device = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    
    request.entity = [NSEntityDescription entityForName:@"DeviceData" inManagedObjectContext:context];
    request.predicate = [NSPredicate predicateWithFormat:@"macAddress = %@", locMac];
    NSError *executeFetchError = nil;
    device = [[context executeFetchRequest:request error:&executeFetchError] lastObject];
    
    if (executeFetchError) {
      //  NSLog(@"Error looking in deviceExistinData");
    } else if (!device) {
        device = [NSEntityDescription insertNewObjectForEntityForName:@"DeviceData" inManagedObjectContext:context];
    }else{
        NSString *locName = [device valueForKey:@"name"];
        [device setValue:locIp forKey:@"ipAddress"];
        [device setValue:locName forKey:@"name"];
    }
    
    return device;
}

-(NSManagedObject *)getDevicebyName: (NSString*)locname{
    NSManagedObjectContext *_context = [self managedObjectContext];
    NSManagedObject *device = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    
    request.entity = [NSEntityDescription entityForName:@"DeviceData" inManagedObjectContext:_context];
    request.predicate = [NSPredicate predicateWithFormat:@"name = %@", locname];
    NSError *executeFetchError = nil;
    
    device = [[_context executeFetchRequest:request error:&executeFetchError] lastObject];
    
    if (executeFetchError) {
       // NSLog(@"Error looking in getDevicebyName");
    }else if (!device){
       // NSLog(@"Could not find device with name %@", locname);
    }
    
    return device;
    
}

-(unsigned long)deviceCount{
    NSManagedObjectContext *_context = [self managedObjectContext];
    
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"DeviceData" inManagedObjectContext:_context];
    [request setEntity:entity];
    
    NSError *error = nil;
    unsigned long count = [_context countForFetchRequest:request error:&error];
    
    
    if (!error){
        return count;
    }else{
        return 0;
    }
}

#pragma mark - Text-Field Delegates

- (void)textFieldDidBeginEditing:(UITextField *)textField{
   // NSLog(@"textFieldDidBeginEditing");
    textField.text = @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (![_RenameField.text  isEqual: @""] && ![_RenameField.text  isEqual: @" "] && ![_ActiveDevice  isEqual: @" "]){
        
        if (_RenameBox) _RenameBox.hidden = !_RenameBox.hidden;
        
        NSString *newName = nil;
        NSString *txtfield = _RenameField.text;
        txtfield = [txtfield stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        newName = [txtfield stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        NSString *title = nil;
        
        NSString *Regexp = @"\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}";
        NSPredicate *myTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", Regexp];
        
        if (_DeviceBox.hidden){
            //This is for renaming after selection has been made
            NSString *tmp = [_FanDrop currentTitle];
            NSArray *fanDropSplit = [tmp componentsSeparatedByString:@" "];
            NSString *oldName = fanDropSplit[0];
            //NSString *oldIp = fanDropSplit[1];
            
            NSManagedObject *device = [self getDevicebyName:oldName];
            NSString *locmac = [device valueForKey:@"macAddress"];
            
            if ([oldName isEqualToString:@"ManualEntry"]) {
                
                if ([locmac isEqualToString:@"manual"]) {
                    //make sure the entry is a mac address
                    if ([myTest evaluateWithObject:newName]) {
                        title = [NSString stringWithFormat:@"%1$@ %2$@", oldName, newName];
                        [self updateToCoreData:@"ManualEntry" :newName :@"manual" :@"ssid"];
                        //update fandrop button text
                        [_FanDrop setTitle:title forState: UIControlStateNormal];
                        _ActiveDevice = newName;
                    }else{
                        //put error message to label must be IP
                       // NSLog(@"you must put a string IP address. like ###.###.###");
                        NSString *msg = @"You must use a valid IP address like 192.168.68.5";
                        NSString *button = @"Ok";
                        NSArray *alertArray = @[msg, button];
                        [self alertMessage:alertArray];
                    }
                }else{
                    //all devies in list ManualEntry entry but not THE manual entry
                    title = [NSString stringWithFormat:@"%1$@ %2$@", newName, _ActiveDevice];
                    [self updateName:newName :locmac];
                    //update fandrop button text
                    [_FanDrop setTitle:title forState: UIControlStateNormal];
                }
            }else{
                title = [NSString stringWithFormat:@"%1$@ %2$@", newName, _ActiveDevice];
                [self updateName:newName :locmac];
                //update fandrop button text
                [_FanDrop setTitle:title forState: UIControlStateNormal];
            }
            
        }else{
          //DeviceBox is visible
            
            //Device box is showing
            
            //start the renaming part here
            NSInteger row;
            row = [_DevicePicker selectedRowInComponent:0];
            NSString *tmp = [_pickerData objectAtIndex:row];
            NSArray *rowContent = [tmp componentsSeparatedByString:@" "];
            
            NSString *devName = rowContent[0];
            //NSString *devIp = rowContent[1];
            
            NSManagedObject *device = [self getDevicebyName:devName];
            NSString *locmac = [device valueForKey:@"macAddress"];
            
            
            if ([devName isEqualToString:@"ManualEntry"]) {
                
                if ([locmac isEqualToString:@"manual"]) {
                    //make sure the entry is a mac address
                    if ([myTest evaluateWithObject:newName]) {
                        //title = [NSString stringWithFormat:@"%1$@ %2$@", devName, newName];
                        [self updateToCoreData:devName :newName :locmac :@"ssid"];
                    }else{
                        //put error message to label must be IP
                       // NSLog(@"you must put a string IP address. like ###.###.###");
                        NSString *msg = @"You must use a valid IP address like 192.168.68.5";
                        NSString *button = @"Ok";
                        NSArray *alertArray = @[msg, button];
                        [self alertMessage:alertArray];
                    }
                }else{
                    //all devies in list ManualEntry entry but not THE manual entry
                    [self updateName:newName :locmac];
                }
            }else{
                //all other not ManualEntry devices
                [self updateName:newName :locmac];
            }
            [self printFromCoreData];
        }
        [_RenameBox endEditing:YES];
        
        //show dropdown buttons
        _Accept.hidden = NO;
        _Cancel.hidden = NO;
        _Modify.hidden = NO;
    }else{
        //set error window to launch here.
       // NSLog(@"You Canna Save an Empty string Name, String Bean!!");
        NSString *msg = @"Name not saved. You should use something more interesting than an empty space";
        NSString *button = @"Ok";
        NSArray *alertArray = @[msg, button];
        [self alertMessage:alertArray];
    }
    
    return YES;
}


#pragma mark NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // We have a response initialize repsonse
    _responseData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // Append the new data to the instance variable you declared
    [_responseData appendData:data];
    
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse*)cachedResponse {
    // Return nil to indicate not necessary to store a cached response for this connection
    return nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    //This is where I will call handle response.
    [self handleResponse: _responseData];
    //NSLog(@"Here is the resopnseData %@", _responseData);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    NSLog(@"The Request failed with error %@", error);
}

#pragma mark AlertView Delegate Methods

- (void)showStatus:(NSString *)message timeout:(double)timeout {
    statusAlert = [[UIAlertView alloc] initWithTitle:nil
                                             message:message
                                            delegate:nil
                                   cancelButtonTitle:@"Ok"
                                   otherButtonTitles:nil];
    
    if (!statusAlert.visible) {
        
        [statusAlert show];
        [NSTimer scheduledTimerWithTimeInterval:timeout
                                         target:self
                                       selector:@selector(timerExpired:)
                                       userInfo:nil
                                        repeats:NO];
    }
    
}

//first in the array is message. Second in Array is Cancel. Third is other button title
- (void)alertMessage:(NSArray*)array{
    if ([array count] == 3) {
        statusAlert = [[UIAlertView alloc] initWithTitle:nil
                                                 message:array[0]
                                                delegate:self
                                       cancelButtonTitle:array[1]
                                       otherButtonTitles:array[2], nil];
    }else{
        statusAlert = [[UIAlertView alloc] initWithTitle:nil
                                                 message:array[0]
                                                delegate:self
                                       cancelButtonTitle:array[1]
                                       otherButtonTitles:nil];
    }
    
    if (!statusAlert.isVisible) {
        [statusAlert show];
    }
}

- (void)timerExpired:(NSTimer *)timer {
    [statusAlert dismissWithClickedButtonIndex:0 animated:YES];
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == [alertView firstOtherButtonIndex]) {
        if (_scanDialog.hidden == YES) {
            _scanDialog.hidden = NO;
        }
        [_scanSpinner startAnimating];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0 ), ^{
            [self scanWifi];
        });
    }
    _isAlert = false;
}

@end
