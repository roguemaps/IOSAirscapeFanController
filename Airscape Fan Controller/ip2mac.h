//
//  ip2mac.h
//  netScan
//
//  Created by Jesse Walter Vanderwerf on 10/24/14.
//  Copyright (c) 2014 Jesse Walter Vanderwerf. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ip2mac : NSObject


-(NSString*)ip2mac:(in_addr_t)addr;

-(NSString*)Stip2mac: (char*) ip;

@end
