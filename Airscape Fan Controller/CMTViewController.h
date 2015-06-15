//
//  CMTViewController.h
//  Airscape Fan Controller
//
//  Created by Jesse Walter Vanderwerf on 8/7/14.
//  Copyright (c) 2014 Jesse Walter Vanderwerf. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Reachability.h"

@interface CMTViewController : UIViewController<UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate, NSURLConnectionDelegate>
{
    NSMutableData *_responseData;
    NSString *_responseString;
    UIAlertView *statusAlert;
    NSOperationQueue *operationQueue;
    NSOperation *refreshOps;
    NSOperation *verifyOps;
    Reachability *reach;
}

@property (nonatomic,strong) NSManagedObjectContext *managedObjectContext;


@property (weak, nonatomic) IBOutlet UIButton *menu;

@property (weak, nonatomic) IBOutlet UIButton *FanDrop;
@property (weak, nonatomic) IBOutlet UIButton *Rename;
@property (weak, nonatomic) IBOutlet UIButton *scan;
@property (weak, nonatomic) IBOutlet UIPickerView *DevicePicker;
@property (weak, nonatomic) IBOutlet UIView *DeviceBox;

@property (weak, nonatomic) IBOutlet UIView *RenameBox;
@property (weak, nonatomic) IBOutlet UITextField *RenameField;
@property (weak, nonatomic) IBOutlet UIButton *TFCancel;
@property (weak, nonatomic) IBOutlet UIButton *TFSave;

@property (weak, nonatomic) IBOutlet UIButton *Accept;
@property (weak, nonatomic) IBOutlet UIButton *Cancel;
@property (weak, nonatomic) IBOutlet UIButton *Modify;

@property (strong) UIActivityIndicatorView *mySpinner;
@property (weak, nonatomic) IBOutlet UILabel *topLabel;
@property (weak, nonatomic) IBOutlet UIButton *Refresh;

@property (weak, nonatomic) IBOutlet UILabel *SpeedLabel;
@property (weak, nonatomic) IBOutlet UILabel *SpeedValue;
@property (weak, nonatomic) IBOutlet UILabel *AirflowValue;
@property (weak, nonatomic) IBOutlet UILabel *RoomTemp;
@property (weak, nonatomic) IBOutlet UILabel *OAtemp;
@property (weak, nonatomic) IBOutlet UILabel *AtticTemp;
@property (weak, nonatomic) IBOutlet UILabel *Timer;
@property (weak, nonatomic) IBOutlet UILabel *Power;
@property (weak, nonatomic) IBOutlet UILabel *CFMpWatt;
@property (weak, nonatomic) IBOutlet UILabel *CoolPw;
@property (weak, nonatomic) IBOutlet UILabel *EER;
@property (weak, nonatomic) IBOutlet UILabel *IPAddress;
@property (weak, nonatomic) IBOutlet UILabel *MAC;
@property (weak, nonatomic) IBOutlet UILabel *PrimDNS;
@property (weak, nonatomic) IBOutlet UILabel *SoftwareVs;

@property (weak, nonatomic) IBOutlet UIView *interlockBox;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *interlockTop;


@property (weak, nonatomic) IBOutlet UIView *bottomLine;


@property (weak, nonatomic) IBOutlet UILabel *interlockStar;
@property (weak, nonatomic) IBOutlet UIView *scanDialog;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *scanSpinner;



@end
